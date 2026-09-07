import Foundation
import os

@MainActor
protocol ModelUsageControlling: AnyObject {
    var state: ModelUsageViewState { get }
    var onChange: (@MainActor (ModelUsageViewState) -> Void)? { get set }

    func start()
    func stop()
    func refresh()
}

@MainActor
final class ModelUsageService: ModelUsageControlling {
    static let refreshInterval: Duration = .seconds(120)

    private let logger = Logger(
        subsystem: "com.lipe.notchcapture",
        category: "ModelUsage"
    )

    private let credentials: any ModelUsageCredentialReading
    private let client: any ModelUsageFetching
    private let now: @Sendable () -> Date
    private let refreshInterval: Duration

    private(set) var state: ModelUsageViewState {
        didSet {
            guard state != oldValue else { return }
            onChange?(state)
        }
    }

    var onChange: (@MainActor (ModelUsageViewState) -> Void)?
    private var refreshTask: Task<Void, Never>?
    private var isStarted = false

    init(
        credentials: any ModelUsageCredentialReading = ModelUsageCredentialStore(),
        client: any ModelUsageFetching = ModelUsageClient(),
        now: @escaping @Sendable () -> Date = { .now },
        refreshInterval: Duration = ModelUsageService.refreshInterval,
        initialState: ModelUsageViewState = .empty
    ) {
        self.credentials = credentials
        self.client = client
        self.now = now
        self.refreshInterval = refreshInterval
        self.state = initialState
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while let self, self.isStarted, !Task.isCancelled {
                await self.refreshOnce()
                do {
                    try await Task.sleep(for: self.refreshInterval)
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        isStarted = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() {
        Task { [weak self] in
            await self?.refreshOnce()
        }
    }

    func refreshNow() async {
        await refreshOnce()
    }

    private func refreshOnce() async {
        await refresh(provider: .openAI)
        await refresh(provider: .cursor)
    }

    private func refresh(provider: ModelUsageProvider) async {
        guard let resolution = credentials.resolve(provider) else {
            update(provider, connection: .notSignedIn, isRefreshing: false)
            return
        }

        let hadSnapshot = state[provider].connection.snapshot != nil
        if hadSnapshot {
            update(provider, isRefreshing: true)
        } else {
            update(provider, connection: .loading, isRefreshing: true)
        }

        do {
            let snapshot = try await client.fetchSnapshot(
                for: provider,
                credential: resolution.credential,
                now: now()
            )
            update(provider, connection: .loaded(snapshot), isRefreshing: false)
        } catch let error as ModelUsageFetchError {
            logger.error("\(provider.displayName, privacy: .public) usage failed: \(error.statusText(for: provider), privacy: .public)")
            update(
                provider,
                connection: .failed(error.statusText(for: provider)),
                isRefreshing: false
            )
        } catch {
            logger.error("\(provider.displayName, privacy: .public) usage failed: \(error.localizedDescription, privacy: .public)")
            update(
                provider,
                connection: .failed(ModelUsageFetchError.unavailable.statusText(for: provider)),
                isRefreshing: false
            )
        }
    }

    private func update(
        _ provider: ModelUsageProvider,
        connection: ModelUsageConnectionState? = nil,
        isRefreshing: Bool? = nil
    ) {
        var next = state[provider]
        if let connection {
            next.connection = connection
        }
        if let isRefreshing {
            next.isRefreshing = isRefreshing
        }
        state[provider] = next
    }
}
