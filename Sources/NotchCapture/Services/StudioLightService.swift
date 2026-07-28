@preconcurrency import CoreBluetooth
import Foundation
import os

@MainActor
protocol StudioLightControlling: AnyObject {
    var state: StudioLightViewState { get }
    var onChange: (@MainActor (StudioLightViewState) -> Void)? { get set }

    func start()
    func stop()
    func startPairing()
    func cancelPairing()
    func pair(deviceID: UUID)
    func retry()
    func forget()
    func refresh()
    func setPower(_ isOn: Bool)
    func setBrightness(_ brightness: Double, final: Bool)
    func setColorTemperature(_ colorTemperature: Int, final: Bool)
}

enum StudioLightReconnectPolicy {
    static func delay(forAttempt attempt: Int) -> Duration {
        let seconds = min(10, 1 << min(4, max(0, attempt - 1)))
        return .seconds(seconds)
    }
}

@MainActor
final class StudioLightService: NSObject, StudioLightControlling {
    static let peripheralIDDefaultsKey = "studioLight.molusG60.peripheralID"
    static let peripheralNameDefaultsKey = "studioLight.molusG60.peripheralName"

    private let logger = Logger(
        subsystem: "com.lipe.notchcapture",
        category: "StudioLight"
    )

    private struct QueuedWrite {
        let data: Data
    }

    private enum MeshMode: Equatable {
        case unknown
        case unprovisioned
        case proxy
    }

    private let defaults: UserDefaults
    private let onAccessPrompt: () -> Void
    private let serviceUUID = CBUUID(string: MolusG60Protocol.serviceUUID)
    private let writeUUID = CBUUID(string: MolusG60Protocol.writeCharacteristicUUID)
    private let notifyUUID = CBUUID(string: MolusG60Protocol.notifyCharacteristicUUID)
    private let meshProvisioningUUID = CBUUID(string: "1827")
    private let meshProxyUUID = CBUUID(string: "1828")

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var pairingCandidate: StudioLightDevice?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var meshMode = MeshMode.unknown
    private var deviceNumber: UInt16?
    private var attemptedDirectRegistration = false
    private var writeType: CBCharacteristicWriteType = .withResponse
    private var supportsWriteWithoutResponse = false
    private var retriedInitialReadWithoutResponse = false
    private var writeQueue: [QueuedWrite] = []
    private var isWaitingForWriteResponse = false
    private var nextSequence: UInt16 = 1
    private var initialReads: [UInt16: MolusG60Command] = [:]
    private var initialReadQueue: [MolusG60Command] = []
    private var confirmedSnapshot = StudioLightSnapshot.initial
    private var isRunning = false
    private var pairingRequested = false
    private var scanningForConfiguredDevice = false
    private var suppressNextDisconnect = false
    private var reconnectAttempt = 0
    private var scanTimeoutTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var responseTimeoutTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var brightnessWriteTask: Task<Void, Never>?
    private var temperatureWriteTask: Task<Void, Never>?
    private var pendingBrightness: Double?
    private var pendingColorTemperature: Int?

    private(set) var state: StudioLightViewState {
        didSet {
            guard state != oldValue else { return }
            onChange?(state)
        }
    }

    var onChange: (@MainActor (StudioLightViewState) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        onAccessPrompt: @escaping () -> Void = {}
    ) {
        self.defaults = defaults
        self.onAccessPrompt = onAccessPrompt
        if let identifier = defaults.string(forKey: Self.peripheralIDDefaultsKey),
           let id = UUID(uuidString: identifier) {
            let name = defaults.string(forKey: Self.peripheralNameDefaultsKey)
                ?? "MOLUS G60"
            self.state = StudioLightViewState(
                connection: .disconnected("Ready to connect"),
                configuredDevice: StudioLightDevice(id: id, name: name),
                discoveredDevices: [],
                snapshot: .initial
            )
        } else {
            self.state = .empty
        }
        super.init()
    }

    deinit {
        scanTimeoutTask?.cancel()
        connectionTimeoutTask?.cancel()
        responseTimeoutTask?.cancel()
        reconnectTask?.cancel()
        brightnessWriteTask?.cancel()
        temperatureWriteTask?.cancel()
    }

    func start() {
        guard state.isConfigured else { return }
        isRunning = true
        prepareCentralManager(requestingPermission: false)
        if centralManager?.state == .poweredOn {
            connectConfiguredDevice()
        }
    }

    func stop() {
        isRunning = false
        pairingRequested = false
        cancelTasks()
        centralManager?.stopScan()
        disconnectCurrentPeripheral(suppressingCallback: true)
        clearConnectionResources()
        if state.isConfigured {
            state.connection = .disconnected("Ready to connect")
        } else {
            state = .empty
        }
    }

    func startPairing() {
        isRunning = true
        pairingRequested = true
        scanningForConfiguredDevice = false
        state.discoveredDevices = []
        prepareCentralManager(requestingPermission: true)
        if centralManager?.state == .poweredOn {
            beginPairingScan()
        }
    }

    func cancelPairing() {
        guard pairingRequested, pairingCandidate == nil else { return }
        pairingRequested = false
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        centralManager?.stopScan()
        state.connection = state.isConfigured
            ? .disconnected("Ready to connect")
            : .notConfigured
    }

    func pair(deviceID: UUID) {
        guard pairingRequested,
              let target = state.discoveredDevices.first(where: { $0.id == deviceID }),
              let peripheral = discoveredPeripherals[deviceID] else { return }
        pairingCandidate = target
        pairingRequested = false
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        centralManager?.stopScan()
        connect(peripheral)
    }

    func retry() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        guard state.isConfigured else {
            startPairing()
            return
        }
        isRunning = true
        prepareCentralManager(requestingPermission: false)
        if centralManager?.state == .poweredOn {
            connectConfiguredDevice()
        }
    }

    func forget() {
        pairingRequested = false
        pairingCandidate = nil
        cancelTasks()
        centralManager?.stopScan()
        disconnectCurrentPeripheral(suppressingCallback: true)
        clearConnectionResources()
        defaults.removeObject(forKey: Self.peripheralIDDefaultsKey)
        defaults.removeObject(forKey: Self.peripheralNameDefaultsKey)
        state = .empty
    }

    func refresh() {
        guard state.connection.isConnected else { return }
        requestCurrentValues()
    }

    func setPower(_ isOn: Bool) {
        guard state.controlsEnabled, let deviceNumber else { return }
        state.snapshot.isOn = isOn
        enqueue(
            MolusG60Protocol.power(
                isOn,
                deviceNumber: deviceNumber,
                sequence: takeSequence()
            )
        )
        scheduleReconciliation(for: .power)
    }

    func setBrightness(_ brightness: Double, final: Bool) {
        guard state.controlsEnabled else { return }
        let clamped = MolusG60Protocol.clampedBrightness(brightness)
        state.snapshot.brightness = clamped
        pendingBrightness = clamped
        brightnessWriteTask?.cancel()
        if final {
            brightnessWriteTask = nil
            sendPendingBrightness()
            scheduleReconciliation(for: .brightness)
        } else {
            brightnessWriteTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self?.sendPendingBrightness()
            }
        }
    }

    func setColorTemperature(_ colorTemperature: Int, final: Bool) {
        guard state.controlsEnabled else { return }
        let clamped = MolusG60Protocol.clampedColorTemperature(colorTemperature)
        state.snapshot.colorTemperature = clamped
        pendingColorTemperature = clamped
        temperatureWriteTask?.cancel()
        if final {
            temperatureWriteTask = nil
            sendPendingColorTemperature()
            scheduleReconciliation(for: .colorTemperature)
        } else {
            temperatureWriteTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self?.sendPendingColorTemperature()
            }
        }
    }

    private func prepareCentralManager(requestingPermission: Bool) {
        guard centralManager == nil else { return }
        if requestingPermission { onAccessPrompt() }
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    private func beginPairingScan() {
        guard let centralManager, centralManager.state == .poweredOn else { return }
        connectionTimeoutTask?.cancel()
        responseTimeoutTask?.cancel()
        discoveredPeripherals.removeAll()
        state.discoveredDevices = []
        state.connection = .scanning
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        startScanTimeout()
    }

    private func connectConfiguredDevice() {
        guard let centralManager,
              centralManager.state == .poweredOn,
              let configured = state.configuredDevice else { return }
        pairingCandidate = nil
        scanningForConfiguredDevice = false
        scanTimeoutTask?.cancel()
        centralManager.stopScan()

        if let known = centralManager.retrievePeripherals(withIdentifiers: [configured.id]).first {
            connect(known)
            return
        }

        scanningForConfiguredDevice = true
        state.connection = .connecting
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        startScanTimeout()
    }

    private func connect(_ peripheral: CBPeripheral) {
        guard let centralManager, centralManager.state == .poweredOn else { return }
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        centralManager.stopScan()
        scanningForConfiguredDevice = false
        disconnectCurrentPeripheral(suppressingCallback: true)
        clearConnectionResources(keepingPeripheral: true)
        self.peripheral = peripheral
        peripheral.delegate = self
        state.connection = .connecting
        centralManager.connect(peripheral, options: nil)

        let identifier = peripheral.identifier
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled,
                  let self,
                  self.peripheral?.identifier == identifier,
                  self.state.connection == .connecting else { return }
            self.failConnection(
                "Connection timed out. Close ZY Vega and try again.",
                shouldRetry: self.state.isConfigured
            )
        }
    }

    private func discoverRequiredService(on peripheral: CBPeripheral) {
        // The mesh service tells us whether a reset G60 still needs
        // provisioning. FEE9 remains the service used for light commands.
        peripheral.discoverServices(nil)
    }

    private func configureCharacteristics(in service: CBService, on peripheral: CBPeripheral) {
        peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
    }

    private func enableNotifications() {
        guard let peripheral, let notifyCharacteristic else { return }
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    private func beginInitialSynchronization() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        initialReads.removeAll()
        initialReadQueue = MolusG60Command.stateCommands
        deviceNumber = nil
        attemptedDirectRegistration = false
        requestDeviceNumber()
    }

    private func requestDeviceNumber() {
        let sequence = takeSequence()
        initialReads = [sequence: .deviceID]
        enqueue(MolusG60Protocol.readDeviceNumber(sequence: sequence))
        startInitialResponseTimeout()
    }

    private func registerFreshDevice() {
        let sequence = takeSequence()
        initialReads = [sequence: .registration]
        enqueue(
            MolusG60Protocol.register(
                deviceNumber: 0x8000,
                sequence: sequence
            )
        )
        responseTimeoutTask?.cancel()
        responseTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.initialReads.removeAll()
            self.requestDeviceNumber()
        }
    }

    private func requestNextInitialValue() {
        guard let command = initialReadQueue.first else {
            finishInitialSynchronization()
            return
        }
        guard let deviceNumber else {
            requestDeviceNumber()
            return
        }
        let sequence = takeSequence()
        initialReads = [sequence: command]
        enqueue(
            MolusG60Protocol.read(
                command,
                deviceNumber: deviceNumber,
                sequence: sequence
            )
        )
        startInitialResponseTimeout()
    }

    private func startInitialResponseTimeout() {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, !self.initialReads.isEmpty else { return }
            if self.writeType == .withResponse,
               self.supportsWriteWithoutResponse,
               !self.retriedInitialReadWithoutResponse {
                self.logger.notice(
                    "G60 did not answer a write-with-response read; retrying without response"
                )
                self.retriedInitialReadWithoutResponse = true
                self.writeType = .withoutResponse
                self.writeQueue.removeAll()
                self.isWaitingForWriteResponse = false
                self.beginInitialSynchronization()
                return
            }
            let message = switch self.meshMode {
            case .unprovisioned:
                """
                This G60 is in Bluetooth setup mode. Add it once in ZY Vega, \
                close ZY Vega, then try Pair again.
                """
            case .proxy:
                """
                The G60 connected but did not identify itself. Make sure ZY Vega \
                is closed, then try again.
                """
            case .unknown:
                """
                The G60 connected but did not return its device identity. Close \
                ZY Vega and try again.
                """
            }
            self.logger.error("G60 identity/state synchronization failed: \(message, privacy: .public)")
            self.failConnection(
                message,
                unsupported: self.meshMode == .unprovisioned,
                shouldRetry: false
            )
        }
    }

    private func requestCurrentValues() {
        guard let deviceNumber else { return }
        for command in MolusG60Command.stateCommands {
            let sequence = takeSequence()
            enqueue(
                MolusG60Protocol.read(
                    command,
                    deviceNumber: deviceNumber,
                    sequence: sequence
                )
            )
        }
    }

    private func finishInitialSynchronization() {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        confirmedSnapshot = state.snapshot
        reconnectAttempt = 0

        if let pairingCandidate {
            state.configuredDevice = pairingCandidate
            defaults.set(
                pairingCandidate.id.uuidString,
                forKey: Self.peripheralIDDefaultsKey
            )
            defaults.set(
                pairingCandidate.name,
                forKey: Self.peripheralNameDefaultsKey
            )
            self.pairingCandidate = nil
        }
        state.discoveredDevices = []
        state.connection = .connected
    }

    private func apply(_ value: MolusG60Value) {
        switch value {
        case .registration:
            break
        case let .deviceNumber(value):
            deviceNumber = value
        case let .power(isOn):
            state.snapshot.isOn = isOn
            confirmedSnapshot.isOn = isOn
        case let .brightness(brightness):
            state.snapshot.brightness = brightness
            confirmedSnapshot.brightness = brightness
        case let .colorTemperature(colorTemperature):
            state.snapshot.colorTemperature = colorTemperature
            confirmedSnapshot.colorTemperature = colorTemperature
        }
    }

    private func sendPendingBrightness() {
        guard let value = pendingBrightness, let deviceNumber else { return }
        pendingBrightness = nil
        enqueue(
            MolusG60Protocol.brightness(
                value,
                deviceNumber: deviceNumber,
                sequence: takeSequence()
            )
        )
    }

    private func sendPendingColorTemperature() {
        guard let value = pendingColorTemperature, let deviceNumber else { return }
        pendingColorTemperature = nil
        enqueue(
            MolusG60Protocol.colorTemperature(
                value,
                deviceNumber: deviceNumber,
                sequence: takeSequence()
            )
        )
    }

    private func scheduleReconciliation(for command: MolusG60Command) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self,
                  self.state.controlsEnabled,
                  let deviceNumber = self.deviceNumber else { return }
            self.enqueue(
                MolusG60Protocol.read(
                    command,
                    deviceNumber: deviceNumber,
                    sequence: self.takeSequence()
                )
            )
        }
    }

    private func enqueue(_ data: Data) {
        guard writeCharacteristic != nil, peripheral != nil else {
            rollbackAfterWriteFailure("The light is no longer connected.")
            return
        }
        logger.debug("Queued G60 frame: \(data.hexString, privacy: .public)")
        writeQueue.append(QueuedWrite(data: data))
        flushWriteQueue()
    }

    private func flushWriteQueue() {
        guard let peripheral, let writeCharacteristic else { return }
        if writeType == .withResponse {
            guard !isWaitingForWriteResponse, !writeQueue.isEmpty else { return }
            let next = writeQueue.removeFirst()
            isWaitingForWriteResponse = true
            logger.debug("Writing G60 frame with response: \(next.data.hexString, privacy: .public)")
            peripheral.writeValue(next.data, for: writeCharacteristic, type: .withResponse)
            return
        }

        while !writeQueue.isEmpty, peripheral.canSendWriteWithoutResponse {
            let next = writeQueue.removeFirst()
            logger.debug("Writing G60 frame without response: \(next.data.hexString, privacy: .public)")
            peripheral.writeValue(next.data, for: writeCharacteristic, type: .withoutResponse)
        }
    }

    private func takeSequence() -> UInt16 {
        let sequence = nextSequence
        nextSequence = MolusG60Protocol.nextSequence(after: nextSequence)
        return sequence
    }

    private func startScanTimeout() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            self.centralManager?.stopScan()
            if self.pairingRequested {
                self.state.connection = .notFound
            } else if self.scanningForConfiguredDevice {
                self.scanningForConfiguredDevice = false
                self.state.connection = .notFound
                self.scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        guard isRunning, state.isConfigured, reconnectTask == nil else { return }
        reconnectAttempt += 1
        let delay = StudioLightReconnectPolicy.delay(forAttempt: reconnectAttempt)
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            guard self.isRunning,
                  self.centralManager?.state == .poweredOn else { return }
            self.connectConfiguredDevice()
        }
    }

    private func failConnection(
        _ message: String,
        unsupported: Bool = false,
        shouldRetry: Bool
    ) {
        connectionTimeoutTask?.cancel()
        responseTimeoutTask?.cancel()
        scanTimeoutTask?.cancel()
        centralManager?.stopScan()
        state.snapshot = confirmedSnapshot
        state.connection = unsupported
            ? .unsupported(message)
            : .disconnected(message)
        disconnectCurrentPeripheral(suppressingCallback: true)
        clearConnectionResources()
        pairingCandidate = nil
        if shouldRetry { scheduleReconnect() }
    }

    private func rollbackAfterWriteFailure(_ message: String) {
        state.snapshot = confirmedSnapshot
        failConnection(message, shouldRetry: state.isConfigured)
    }

    private func disconnectCurrentPeripheral(suppressingCallback: Bool) {
        guard let centralManager, let peripheral else { return }
        if peripheral.state != .disconnected {
            suppressNextDisconnect = suppressingCallback
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    private func clearConnectionResources(keepingPeripheral: Bool = false) {
        if !keepingPeripheral { peripheral = nil }
        writeCharacteristic = nil
        notifyCharacteristic = nil
        meshMode = .unknown
        deviceNumber = nil
        attemptedDirectRegistration = false
        supportsWriteWithoutResponse = false
        retriedInitialReadWithoutResponse = false
        writeQueue.removeAll()
        initialReads.removeAll()
        initialReadQueue.removeAll()
        isWaitingForWriteResponse = false
        pendingBrightness = nil
        pendingColorTemperature = nil
    }

    private func cancelTasks() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        brightnessWriteTask?.cancel()
        brightnessWriteTask = nil
        temperatureWriteTask?.cancel()
        temperatureWriteTask = nil
    }
}

extension StudioLightService: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if pairingRequested {
                beginPairingScan()
            } else if isRunning, state.isConfigured {
                connectConfiguredDevice()
            }
        case .poweredOff:
            cancelTasks()
            central.stopScan()
            state.snapshot = confirmedSnapshot
            state.connection = .bluetoothOff
        case .unauthorized:
            cancelTasks()
            central.stopScan()
            state.snapshot = confirmedSnapshot
            state.connection = .permissionDenied
        case .unsupported:
            cancelTasks()
            state.connection = .unsupported("Bluetooth Low Energy is unavailable")
        case .resetting:
            state.connection = .disconnected("Bluetooth is restarting")
        case .unknown:
            break
        @unknown default:
            state.connection = .disconnected("Bluetooth is unavailable")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        if scanningForConfiguredDevice,
           peripheral.identifier == state.configuredDevice?.id {
            connect(peripheral)
            return
        }

        guard pairingRequested else { return }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisedServiceUUIDs = [
            CBAdvertisementDataServiceUUIDsKey,
            CBAdvertisementDataOverflowServiceUUIDsKey,
            CBAdvertisementDataSolicitedServiceUUIDsKey,
        ].flatMap {
            advertisementData[$0] as? [CBUUID] ?? []
        }
        guard StudioLightDiscoveryPolicy.matches(
            advertisedName: advertisedName,
            peripheralName: peripheral.name,
            serviceUUIDs: advertisedServiceUUIDs.map(\.uuidString)
        ) else { return }
        let name = StudioLightDiscoveryPolicy.displayName(
            advertisedName: advertisedName,
            peripheralName: peripheral.name
        )
        let manufacturerData = advertisementData[
            CBAdvertisementDataManufacturerDataKey
        ] as? Data
        logger.notice(
            """
            Discovered G60 candidate \(name, privacy: .public); services \
            \(advertisedServiceUUIDs.map(\.uuidString).joined(separator: ","), privacy: .public); \
            manufacturer data \(manufacturerData?.hexString ?? "none", privacy: .private)
            """
        )
        discoveredPeripherals[peripheral.identifier] = peripheral
        let device = StudioLightDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue
        )
        if let index = state.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            state.discoveredDevices[index] = device
        } else {
            state.discoveredDevices.append(device)
            state.discoveredDevices.sort {
                ($0.rssi ?? .min) > ($1.rssi ?? .min)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        suppressNextDisconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        discoverRequiredService(on: peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        failConnection(
            error?.localizedDescription
                ?? "Could not connect. Close ZY Vega and try again.",
            shouldRetry: state.isConfigured
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        if suppressNextDisconnect {
            suppressNextDisconnect = false
            return
        }
        clearConnectionResources()
        self.peripheral = nil
        state.snapshot = confirmedSnapshot
        if central.state == .poweredOff {
            state.connection = .bluetoothOff
            return
        }
        if central.state == .unauthorized {
            state.connection = .permissionDenied
            return
        }
        state.connection = .disconnected(
            error?.localizedDescription ?? "Light disconnected"
        )
        scheduleReconnect()
    }
}

extension StudioLightService: @preconcurrency CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        if let error {
            failConnection(error.localizedDescription, shouldRetry: state.isConfigured)
            return
        }
        let services = peripheral.services ?? []
        let serviceNames = services.map(\.uuid.uuidString).joined(separator: ",")
        logger.notice("G60 services discovered: \(serviceNames, privacy: .public)")
        if services.contains(where: { $0.uuid == meshProxyUUID }) {
            meshMode = .proxy
        } else if services.contains(where: { $0.uuid == meshProvisioningUUID }) {
            meshMode = .unprovisioned
        } else {
            meshMode = .unknown
        }
        guard let service = services.first(where: {
            $0.uuid == serviceUUID
        }) else {
            failConnection(
                "This device does not expose the expected G60 Bluetooth service.",
                unsupported: true,
                shouldRetry: false
            )
            return
        }
        configureCharacteristics(in: service, on: peripheral)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        if let error {
            failConnection(error.localizedDescription, shouldRetry: state.isConfigured)
            return
        }
        writeCharacteristic = service.characteristics?.first { $0.uuid == writeUUID }
        notifyCharacteristic = service.characteristics?.first { $0.uuid == notifyUUID }
        guard let writeCharacteristic, let notifyCharacteristic else {
            failConnection(
                "This G60 firmware does not expose the expected controls.",
                unsupported: true,
                shouldRetry: false
            )
            return
        }
        logger.notice(
            """
            G60 characteristics ready. Write properties: \
            \(String(describing: writeCharacteristic.properties), privacy: .public); \
            notify properties: \
            \(String(describing: notifyCharacteristic.properties), privacy: .public)
            """
        )
        supportsWriteWithoutResponse = writeCharacteristic.properties.contains(
            .writeWithoutResponse
        )
        if writeCharacteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else if writeCharacteristic.properties.contains(.write) {
            writeType = .withResponse
        } else {
            failConnection(
                "The G60 control characteristic is not writable.",
                unsupported: true,
                shouldRetry: false
            )
            return
        }
        guard notifyCharacteristic.properties.contains(.notify)
                || notifyCharacteristic.properties.contains(.indicate) else {
            failConnection(
                "The G60 response characteristic does not support notifications.",
                unsupported: true,
                shouldRetry: false
            )
            return
        }
        enableNotifications()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier,
              characteristic.uuid == notifyUUID else { return }
        if let error {
            failConnection(error.localizedDescription, shouldRetry: state.isConfigured)
            return
        }
        guard characteristic.isNotifying else {
            failConnection(
                "The G60 did not enable Bluetooth notifications.",
                shouldRetry: state.isConfigured
            )
            return
        }
        beginInitialSynchronization()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier,
              characteristic.uuid == notifyUUID else { return }
        if let error {
            logger.error("G60 notification failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let data = characteristic.value else {
            logger.error("G60 notification did not contain data")
            return
        }
        logger.notice("Received G60 notification: \(data.hexString, privacy: .public)")
        let frame: MolusG60Frame
        let value: MolusG60Value
        do {
            frame = try MolusG60Protocol.decode(data)
            value = try MolusG60Protocol.value(from: frame)
        } catch {
            logger.error("Could not decode G60 notification: \(error.localizedDescription, privacy: .public)")
            return
        }
        logger.notice(
            "Decoded G60 command \(String(format: "0x%04X", frame.command.rawValue), privacy: .public), sequence \(frame.sequence)"
        )
        let valueToApply = value
        if case let .deviceNumber(number) = value {
            if number == 0,
               meshMode == .unprovisioned,
               !attemptedDirectRegistration {
                responseTimeoutTask?.cancel()
                responseTimeoutTask = nil
                initialReads.removeAll()
                attemptedDirectRegistration = true
                logger.notice(
                    "Unregistered G60 reported device zero; attempting direct registration as 0x8000"
                )
                registerFreshDevice()
                return
            } else if number == 0 || number == .max {
                failConnection(
                    """
                    This G60 has not finished Bluetooth setup. Add it once in ZY \
                    Vega, close ZY Vega, then try Pair again.
                    """,
                    unsupported: true,
                    shouldRetry: false
                )
                return
            }
            if case let .deviceNumber(activeNumber) = valueToApply {
                logger.notice(
                    "G60 using device number \(String(format: "0x%04X", activeNumber), privacy: .public)"
                )
            }
        }
        apply(valueToApply)
        if initialReads[frame.sequence] == frame.command {
            initialReads.removeValue(forKey: frame.sequence)
            if frame.command == .registration {
                responseTimeoutTask?.cancel()
                responseTimeoutTask = nil
                requestDeviceNumber()
            } else if frame.command == .deviceID {
                requestNextInitialValue()
            } else if initialReadQueue.first == frame.command {
                initialReadQueue.removeFirst()
                requestNextInitialValue()
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier,
              characteristic.uuid == writeUUID else { return }
        isWaitingForWriteResponse = false
        if let error {
            rollbackAfterWriteFailure(error.localizedDescription)
            return
        }
        flushWriteQueue()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        flushWriteQueue()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
