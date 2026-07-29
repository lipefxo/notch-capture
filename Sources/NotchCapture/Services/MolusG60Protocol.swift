import Foundation

enum MolusG60Command: UInt16, CaseIterable, Sendable {
    case registration = 0x0006
    case brightness = 0x1001
    case colorTemperature = 0x1002
    case power = 0x1008
    case deviceID = 0x2005

    static let stateCommands: [MolusG60Command] = [
        .power,
        .brightness,
        .colorTemperature,
    ]
}

struct MolusG60Frame: Equatable, Sendable {
    let messageType: UInt16
    let sequence: UInt16
    let command: MolusG60Command
    let payload: Data
}

enum MolusG60Value: Equatable, Sendable {
    case registration
    case power(Bool)
    case brightness(Double)
    case colorTemperature(Int)
    case deviceNumber(UInt16)
}

enum MolusG60ProtocolError: LocalizedError, Equatable {
    case frameTooShort(Int)
    case invalidMagic(UInt16)
    case invalidLength(expected: Int, actual: Int)
    case invalidCRC(expected: UInt16, actual: UInt16)
    case unknownCommand(UInt16)
    case invalidPayload(command: MolusG60Command, length: Int)

    var errorDescription: String? {
        switch self {
        case let .frameTooShort(length):
            "The light returned a frame that was too short (\(length) bytes)."
        case let .invalidMagic(value):
            String(format: "The light returned an invalid frame marker (0x%04X).", value)
        case let .invalidLength(expected, actual):
            "The light returned \(actual) bytes; \(expected) were expected."
        case let .invalidCRC(expected, actual):
            String(
                format: "The light returned an invalid checksum (expected 0x%04X, received 0x%04X).",
                expected,
                actual
            )
        case let .unknownCommand(command):
            String(format: "The light returned an unknown command (0x%04X).", command)
        case let .invalidPayload(command, length):
            String(
                format: "The light returned an invalid 0x%04X payload (%d bytes).",
                command.rawValue,
                length
            )
        }
    }
}

enum MolusG60Protocol {
    static let serviceUUID = "0000FEE9-0000-1000-8000-00805F9B34FB"
    static let writeCharacteristicUUID = "D44BC439-ABFD-45A2-B575-925416129600"
    static let notifyCharacteristicUUID = "D44BC439-ABFD-45A2-B575-925416129601"
    static let brightnessRange = 0.0...100.0
    static let colorTemperatureRange = 2_700...6_500

    private static let magic: UInt16 = 0x3C24
    private static let messageType: UInt16 = 0x0100
    private static let readMode: UInt8 = 0
    private static let writeMode: UInt8 = 1

    static func nextSequence(after sequence: UInt16) -> UInt16 {
        sequence == .max ? 1 : max(1, sequence + 1)
    }

    static func clampedBrightness(_ value: Double) -> Double {
        guard value.isFinite else { return brightnessRange.lowerBound }
        return min(brightnessRange.upperBound, max(brightnessRange.lowerBound, value))
    }

    static func clampedColorTemperature(_ value: Int) -> Int {
        min(colorTemperatureRange.upperBound, max(colorTemperatureRange.lowerBound, value))
    }

    static func power(
        _ isOn: Bool,
        deviceNumber: UInt16,
        sequence: UInt16
    ) -> Data {
        scopedFrame(
            command: .power,
            deviceNumber: deviceNumber,
            mode: writeMode,
            value: Data([isOn ? 1 : 0]),
            sequence: sequence
        )
    }

    static func brightness(
        _ value: Double,
        deviceNumber: UInt16,
        sequence: UInt16
    ) -> Data {
        let value = Float32(clampedBrightness(value))
        return scopedFrame(
            command: .brightness,
            deviceNumber: deviceNumber,
            mode: writeMode,
            value: littleEndian(value.bitPattern),
            sequence: sequence
        )
    }

    static func colorTemperature(
        _ value: Int,
        deviceNumber: UInt16,
        sequence: UInt16
    ) -> Data {
        scopedFrame(
            command: .colorTemperature,
            deviceNumber: deviceNumber,
            mode: writeMode,
            value: littleEndian(UInt16(clampedColorTemperature(value))),
            sequence: sequence
        )
    }

    static func readDeviceNumber(sequence: UInt16) -> Data {
        encode(command: .deviceID, payload: Data(), sequence: sequence)
    }

    static func register(
        deviceNumber: UInt16,
        sequence: UInt16
    ) -> Data {
        var payload = littleEndian(deviceNumber)
        payload.append(littleEndian(UInt16(0)))
        return encode(
            command: .registration,
            payload: payload,
            sequence: sequence
        )
    }

    static func read(
        _ command: MolusG60Command,
        deviceNumber: UInt16,
        sequence: UInt16
    ) -> Data {
        let valueLength = switch command {
        case .registration: 0
        case .brightness: 4
        case .colorTemperature: 2
        case .power: 1
        case .deviceID: 0
        }
        return scopedFrame(
            command: command,
            deviceNumber: deviceNumber,
            mode: readMode,
            value: Data(repeating: 0, count: valueLength),
            sequence: sequence
        )
    }

    static func encode(
        command: MolusG60Command,
        payload: Data,
        sequence: UInt16,
        frameMessageType: UInt16 = messageType
    ) -> Data {
        var body = Data()
        body.append(littleEndian(frameMessageType))
        body.append(littleEndian(sequence))
        body.append(littleEndian(command.rawValue))
        body.append(payload)

        var frame = Data()
        frame.append(littleEndian(magic))
        frame.append(littleEndian(UInt16(body.count)))
        frame.append(body)
        frame.append(littleEndian(crc16Xmodem(body)))
        return frame
    }

    static func decode(_ data: Data) throws -> MolusG60Frame {
        guard data.count >= 12 else {
            throw MolusG60ProtocolError.frameTooShort(data.count)
        }

        let frameMagic = uint16(in: data, at: 0)
        guard frameMagic == magic else {
            throw MolusG60ProtocolError.invalidMagic(frameMagic)
        }

        let bodyLength = Int(uint16(in: data, at: 2))
        let expectedLength = bodyLength + 6
        guard data.count == expectedLength else {
            throw MolusG60ProtocolError.invalidLength(
                expected: expectedLength,
                actual: data.count
            )
        }

        let body = data.subdata(in: 4..<(data.count - 2))
        let actualCRC = uint16(in: data, at: data.count - 2)
        let expectedCRC = crc16Xmodem(body)
        guard actualCRC == expectedCRC else {
            throw MolusG60ProtocolError.invalidCRC(
                expected: expectedCRC,
                actual: actualCRC
            )
        }

        let rawCommand = uint16(in: data, at: 8)
        guard let command = MolusG60Command(rawValue: rawCommand) else {
            throw MolusG60ProtocolError.unknownCommand(rawCommand)
        }
        return MolusG60Frame(
            messageType: uint16(in: data, at: 4),
            sequence: uint16(in: data, at: 6),
            command: command,
            payload: data.subdata(in: 10..<(data.count - 2))
        )
    }

    static func value(from frame: MolusG60Frame) throws -> MolusG60Value {
        let payload = frame.payload
        switch frame.command {
        case .registration:
            return .registration
        case .deviceID:
            guard payload.count >= 2 else {
                throw MolusG60ProtocolError.invalidPayload(
                    command: frame.command,
                    length: payload.count
                )
            }
            return .deviceNumber(uint16(in: payload, at: 0))
        case .brightness:
            guard payload.count >= 7 else {
                throw MolusG60ProtocolError.invalidPayload(
                    command: frame.command,
                    length: payload.count
                )
            }
            let bits = uint32(in: payload, at: 3)
            return .brightness(clampedBrightness(Double(Float32(bitPattern: bits))))
        case .colorTemperature:
            guard payload.count >= 5 else {
                throw MolusG60ProtocolError.invalidPayload(
                    command: frame.command,
                    length: payload.count
                )
            }
            return .colorTemperature(
                clampedColorTemperature(Int(uint16(in: payload, at: 3)))
            )
        case .power:
            guard payload.count >= 4 else {
                throw MolusG60ProtocolError.invalidPayload(
                    command: frame.command,
                    length: payload.count
                )
            }
            return .power(payload[3] == 1)
        }
    }

    static func crc16Xmodem(_ data: Data, seed: UInt16 = 0) -> UInt16 {
        var crc = seed
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0
                    ? (crc << 1) ^ 0x1021
                    : crc << 1
            }
        }
        return crc
    }

    private static func scopedFrame(
        command: MolusG60Command,
        deviceNumber: UInt16,
        mode: UInt8,
        value: Data,
        sequence: UInt16
    ) -> Data {
        var payload = Data()
        payload.append(littleEndian(deviceNumber))
        payload.append(mode)
        payload.append(value)
        return encode(command: command, payload: payload, sequence: sequence)
    }

    private static func littleEndian(_ value: UInt16) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
        ])
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24),
        ])
    }

    private static func uint16(in data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func uint32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
