import Foundation

enum ModelUsageProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .cursor: "Cursor"
        }
    }

    var symbolName: String {
        switch self {
        case .openAI: "sparkles"
        case .cursor: "chevron.left.forwardslash.chevron.right"
        }
    }

    var logoResourceName: String {
        switch self {
        case .openAI: "openai"
        case .cursor: "cursor"
        }
    }

    var signInHint: String {
        switch self {
        case .openAI:
            "Sign in with Codex to see remaining ChatGPT usage"
        case .cursor:
            "Sign in to Cursor to see remaining plan usage"
        }
    }
}

enum ModelUsageConnectionState: Equatable, Sendable {
    case notSignedIn
    case loading
    case loaded(ModelUsageSnapshot)
    case failed(String)

    var statusText: String {
        switch self {
        case .notSignedIn:
            "Not signed in"
        case .loading:
            "Checking remaining usage…"
        case let .loaded(snapshot):
            snapshot.statusText
        case let .failed(message):
            message
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .failed:
            true
        default:
            false
        }
    }

    var snapshot: ModelUsageSnapshot? {
        if case let .loaded(snapshot) = self { return snapshot }
        return nil
    }
}

struct ModelUsageMeter: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    /// Remaining quota in 0...1 when a percentage is known.
    var remainingFraction: Double?
    var usedText: String?
    var remainingText: String
    var resetsText: String?

    var usedFraction: Double? {
        remainingFraction.map { min(1, max(0, 1 - $0)) }
    }
}

struct ModelUsageSnapshot: Equatable, Sendable {
    var planName: String?
    var headline: String
    var detail: String
    var remainingFraction: Double?
    var meters: [ModelUsageMeter]
    var fetchedAt: Date

    var statusText: String {
        if let planName, !planName.isEmpty {
            return "\(planName) · \(headline)"
        }
        return headline
    }

    var compactText: String {
        if let remainingFraction {
            return "\(ModelUsageFormatting.formattedPercent(remainingFraction * 100))%"
        }
        return headline
    }
}

struct ModelUsageProviderState: Equatable, Sendable {
    var connection: ModelUsageConnectionState
    var isRefreshing: Bool

    static let empty = ModelUsageProviderState(connection: .notSignedIn, isRefreshing: false)

    var statusText: String { connection.statusText }
    var isBusy: Bool {
        isRefreshing || connection == .loading
    }
}

struct ModelUsageViewState: Equatable, Sendable {
    var openAI: ModelUsageProviderState
    var cursor: ModelUsageProviderState

    static let empty = ModelUsageViewState(openAI: .empty, cursor: .empty)

    subscript(provider: ModelUsageProvider) -> ModelUsageProviderState {
        get {
            switch provider {
            case .openAI: openAI
            case .cursor: cursor
            }
        }
        set {
            switch provider {
            case .openAI: openAI = newValue
            case .cursor: cursor = newValue
            }
        }
    }

    var compactSummaries: [String] {
        ModelUsageProvider.allCases.compactMap { provider in
            guard let snapshot = self[provider].connection.snapshot else { return nil }
            return "\(provider.displayName) \(snapshot.compactText)"
        }
    }

    var compactSummary: String? {
        let summaries = compactSummaries
        guard !summaries.isEmpty else { return nil }
        return summaries.joined(separator: " · ")
    }

    var showsUtilityMeters: Bool {
        ModelUsageProvider.allCases.contains { provider in
            switch self[provider].connection {
            case .notSignedIn:
                false
            case .loading, .loaded, .failed:
                true
            }
        }
    }

    static let preview = ModelUsageViewState(
        openAI: ModelUsageProviderState(
            connection: .loaded(
                ModelUsageSnapshot(
                    planName: "Plus",
                    headline: "68% left this session",
                    detail: "Weekly 76% left · resets Thursday",
                    remainingFraction: 0.68,
                    meters: [
                        ModelUsageMeter(
                            id: "session",
                            title: "5h",
                            remainingFraction: 0.68,
                            usedText: "32% used",
                            remainingText: "68% left",
                            resetsText: "Resets in 2h"
                        ),
                        ModelUsageMeter(
                            id: "weekly",
                            title: "Weekly",
                            remainingFraction: 0.76,
                            usedText: "24% used",
                            remainingText: "76% left",
                            resetsText: "Resets Thursday"
                        ),
                    ],
                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ),
            isRefreshing: false
        ),
        cursor: ModelUsageProviderState(
            connection: .loaded(
                ModelUsageSnapshot(
                    planName: "Pro",
                    headline: "38% left",
                    detail: "Resets Sep 14",
                    remainingFraction: 0.38,
                    meters: [
                        ModelUsageMeter(
                            id: "plan",
                            title: "Plan",
                            remainingFraction: 0.38,
                            usedText: "1,240 of 2,000",
                            remainingText: "760 left",
                            resetsText: "Resets Sep 14"
                        ),
                        ModelUsageMeter(
                            id: "auto",
                            title: "Cursor Models",
                            remainingFraction: 0.42,
                            usedText: nil,
                            remainingText: "42% left",
                            resetsText: nil
                        ),
                        ModelUsageMeter(
                            id: "api",
                            title: "Other Models",
                            remainingFraction: 0.31,
                            usedText: nil,
                            remainingText: "31% left",
                            resetsText: nil
                        ),
                    ],
                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ),
            isRefreshing: false
        )
    )
}

enum ModelUsageFormatting {
    static func remainingPercentText(_ usedPercent: Double) -> String {
        let remaining = remainingPercent(fromUsedPercent: usedPercent)
        return "\(formattedPercent(remaining))% left"
    }

    static func usedPercentText(_ usedPercent: Double) -> String {
        "\(formattedPercent(usedPercent))% used"
    }

    static func remainingPercent(fromUsedPercent usedPercent: Double) -> Double {
        min(100, max(0, 100 - usedPercent))
    }

    static func remainingFraction(fromUsedPercent usedPercent: Double) -> Double {
        remainingPercent(fromUsedPercent: usedPercent) / 100
    }

    static func formattedPercent(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(Int(value.rounded()))
        }
        return String(format: "%g", (value * 10).rounded() / 10)
    }

    static func formattedCount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = abs(value.rounded() - value) < 0.05 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%g", value)
    }

    static func formattedCurrency(_ cents: Double) -> String {
        let dollars = cents / 100
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = dollars >= 10 && abs(dollars.rounded() - dollars) < 0.005 ? 0 : 2
        return formatter.string(from: NSNumber(value: dollars)) ?? String(format: "$%.2f", dollars)
    }

    static func windowTitle(limitWindowSeconds: Double?) -> String {
        guard let limitWindowSeconds, limitWindowSeconds > 0 else { return "Usage" }
        if abs(limitWindowSeconds - 18_000) < 60 {
            return "5h"
        }
        if abs(limitWindowSeconds - 604_800) < 3_600 {
            return "Weekly"
        }
        if limitWindowSeconds < 3_600 {
            return "\(Int((limitWindowSeconds / 60).rounded()))m"
        }
        if limitWindowSeconds < 86_400 {
            let hours = (limitWindowSeconds / 3_600).rounded()
            return "\(Int(hours))h"
        }
        let days = (limitWindowSeconds / 86_400).rounded()
        return "\(Int(days))d"
    }

    static func resetsText(at date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 {
            return "Resets soon"
        }
        if remaining < 3_600 {
            let minutes = max(1, Int((remaining / 60).rounded()))
            return "Resets in \(minutes)m"
        }
        if remaining < 86_400 {
            let hours = Int(remaining / 3_600)
            let minutes = Int(remaining.truncatingRemainder(dividingBy: 3_600) / 60)
            if minutes == 0 {
                return "Resets in \(hours)h"
            }
            return "Resets in \(hours)h \(minutes)m"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "Resets \(formatter.string(from: date))"
    }

    static func planDisplayName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.lowercased().capitalized(with: Locale(identifier: "en_US"))
    }
}

enum ModelUsageSnapshotBuilder {
    static func openAI(
        from data: Data,
        now: Date = .now
    ) throws -> ModelUsageSnapshot {
        let payload = try JSONDecoder().decode(OpenAIUsagePayload.self, from: data)
        return openAI(from: payload, now: now)
    }

    static func cursor(
        from data: Data,
        now: Date = .now
    ) throws -> ModelUsageSnapshot {
        let payload = try JSONDecoder().decode(CursorUsagePayload.self, from: data)
        return cursor(from: payload, now: now)
    }

    static func openAI(
        from payload: OpenAIUsagePayload,
        now: Date = .now
    ) -> ModelUsageSnapshot {
        let planName = ModelUsageFormatting.planDisplayName(payload.planType)
        var meters: [ModelUsageMeter] = []

        if let window = payload.rateLimit?.primaryWindow {
            meters.append(meter(from: window, id: "session", now: now))
        }
        if let window = payload.rateLimit?.secondaryWindow {
            meters.append(meter(from: window, id: "weekly", now: now))
        }

        if let credits = payload.credits, credits.hasCredits == true || credits.balance != nil {
            if credits.unlimited == true {
                meters.append(
                    ModelUsageMeter(
                        id: "credits",
                        title: "Credits",
                        remainingFraction: 1,
                        usedText: nil,
                        remainingText: "Unlimited",
                        resetsText: nil
                    )
                )
            } else if let balance = credits.balance {
                meters.append(
                    ModelUsageMeter(
                        id: "credits",
                        title: "Credits",
                        remainingFraction: nil,
                        usedText: nil,
                        remainingText: "\(formattedOpenAICreditBalance(balance)) left",
                        resetsText: nil
                    )
                )
            }
        }

        let headlineMeter = meters.first
        let headline = headlineMeter?.remainingText ?? "Usage available"
        var detailParts: [String] = []
        if meters.count > 1 {
            let secondary = meters[1]
            detailParts.append("\(secondary.title) \(secondary.remainingText)")
        }
        if let resets = headlineMeter?.resetsText {
            detailParts.append(resets.lowercased())
        }

        return ModelUsageSnapshot(
            planName: planName,
            headline: headlineMeter?.id == "session"
                ? "\(headline) this session"
                : headline,
            detail: detailParts.isEmpty ? (planName ?? "ChatGPT") : detailParts.joined(separator: " · "),
            remainingFraction: headlineMeter?.remainingFraction,
            meters: meters,
            fetchedAt: now
        )
    }

    static func cursor(
        from payload: CursorUsagePayload,
        now: Date = .now
    ) -> ModelUsageSnapshot {
        let planName = ModelUsageFormatting.planDisplayName(payload.membershipType)
        let resets = ModelUsageFormatting.resetsText(at: payload.billingCycleEndDate, now: now)
        var meters: [ModelUsageMeter] = []

        if payload.isUnlimited == true {
            meters.append(
                ModelUsageMeter(
                    id: "plan",
                    title: "Plan",
                    remainingFraction: 1,
                    usedText: nil,
                    remainingText: "Unlimited",
                    resetsText: resets
                )
            )
        } else if let plan = payload.individualUsage?.plan, plan.enabled != false {
            meters.append(planMeter(from: plan, resetsText: resets))
            if let autoPercent = plan.autoPercentUsed {
                meters.append(
                    percentMeter(
                        id: "auto",
                        title: "Cursor Models",
                        usedPercent: autoPercent
                    )
                )
            }
            if let apiPercent = plan.apiPercentUsed {
                meters.append(
                    percentMeter(
                        id: "api",
                        title: "Other Models",
                        usedPercent: apiPercent
                    )
                )
            }
        }

        if let onDemand = payload.individualUsage?.onDemand ?? payload.teamUsage?.onDemand,
           onDemand.enabled == true {
            meters.append(onDemandMeter(from: onDemand))
        }

        if meters.isEmpty, let overall = payload.individualUsage?.overall {
            meters.append(planMeter(from: overall, id: "overall", title: "Usage", resetsText: resets))
        }

        let headlineMeter = meters.first
        let headline = headlineMeter?.remainingText ?? "Usage available"
        let detail = [planName, resets].compactMap { $0 }.joined(separator: " · ")

        return ModelUsageSnapshot(
            planName: planName,
            headline: headline,
            detail: detail.isEmpty ? "Cursor" : detail,
            remainingFraction: headlineMeter?.remainingFraction,
            meters: meters,
            fetchedAt: now
        )
    }

    private static func meter(
        from window: OpenAIUsagePayload.Window,
        id: String,
        now: Date
    ) -> ModelUsageMeter {
        let usedPercent = window.usedPercent ?? 0
        let remaining = ModelUsageFormatting.remainingPercent(fromUsedPercent: usedPercent)
        let resetDate = window.resetDate
        return ModelUsageMeter(
            id: id,
            title: ModelUsageFormatting.windowTitle(limitWindowSeconds: window.limitWindowSeconds),
            remainingFraction: remaining / 100,
            usedText: ModelUsageFormatting.usedPercentText(usedPercent),
            remainingText: ModelUsageFormatting.remainingPercentText(usedPercent),
            resetsText: ModelUsageFormatting.resetsText(at: resetDate, now: now)
        )
    }

    private static func percentMeter(
        id: String,
        title: String,
        usedPercent: Double
    ) -> ModelUsageMeter {
        ModelUsageMeter(
            id: id,
            title: title,
            remainingFraction: ModelUsageFormatting.remainingFraction(fromUsedPercent: usedPercent),
            usedText: ModelUsageFormatting.usedPercentText(usedPercent),
            remainingText: ModelUsageFormatting.remainingPercentText(usedPercent),
            resetsText: nil
        )
    }

    private static func planMeter(
        from plan: CursorUsagePayload.Meter,
        id: String = "plan",
        title: String = "Plan",
        resetsText: String?
    ) -> ModelUsageMeter {
        // Cursor's count fields describe the base allowance, which may be
        // exhausted while bonus allowance is still available. Its aggregate
        // percentage includes both pools and is the accurate headline value.
        if let usedPercent = plan.totalPercentUsed ?? plan.usedPercent {
            return ModelUsageMeter(
                id: id,
                title: title,
                remainingFraction: ModelUsageFormatting.remainingFraction(fromUsedPercent: usedPercent),
                usedText: ModelUsageFormatting.usedPercentText(usedPercent),
                remainingText: ModelUsageFormatting.remainingPercentText(usedPercent),
                resetsText: resetsText
            )
        }
        if let remaining = plan.remaining, let limit = plan.limit, limit > 0 {
            let used = plan.used ?? max(0, limit - remaining)
            return ModelUsageMeter(
                id: id,
                title: title,
                remainingFraction: min(1, max(0, remaining / limit)),
                usedText: "\(ModelUsageFormatting.formattedCount(used)) of \(ModelUsageFormatting.formattedCount(limit))",
                remainingText: "\(ModelUsageFormatting.formattedCount(remaining)) left",
                resetsText: resetsText
            )
        }
        if let used = plan.used, let limit = plan.limit, limit > 0 {
            let remaining = max(0, limit - used)
            return ModelUsageMeter(
                id: id,
                title: title,
                remainingFraction: min(1, max(0, remaining / limit)),
                usedText: "\(ModelUsageFormatting.formattedCount(used)) of \(ModelUsageFormatting.formattedCount(limit))",
                remainingText: "\(ModelUsageFormatting.formattedCount(remaining)) left",
                resetsText: resetsText
            )
        }
        return ModelUsageMeter(
            id: id,
            title: title,
            remainingFraction: nil,
            usedText: nil,
            remainingText: "Usage available",
            resetsText: resetsText
        )
    }

    private static func onDemandMeter(from meter: CursorUsagePayload.Meter) -> ModelUsageMeter {
        if let remaining = meter.remaining, let limit = meter.limit, limit > 0 {
            return ModelUsageMeter(
                id: "onDemand",
                title: "On-demand",
                remainingFraction: min(1, max(0, remaining / limit)),
                usedText: meter.used.map { "\(ModelUsageFormatting.formattedCurrency($0)) used" },
                remainingText: "\(ModelUsageFormatting.formattedCurrency(remaining)) left",
                resetsText: nil
            )
        }
        if let used = meter.used {
            return ModelUsageMeter(
                id: "onDemand",
                title: "On-demand",
                remainingFraction: nil,
                usedText: nil,
                remainingText: "\(ModelUsageFormatting.formattedCurrency(used)) used",
                resetsText: nil
            )
        }
        return ModelUsageMeter(
            id: "onDemand",
            title: "On-demand",
            remainingFraction: nil,
            usedText: nil,
            remainingText: "Enabled",
            resetsText: nil
        )
    }

    private static func formattedOpenAICreditBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: balance)) ?? String(format: "$%.2f", balance)
    }
}

struct OpenAIUsagePayload: Equatable, Sendable {
    var planType: String?
    var rateLimit: RateLimit?
    var credits: Credits?

    struct RateLimit: Equatable, Sendable {
        var primaryWindow: Window?
        var secondaryWindow: Window?
    }

    struct Window: Equatable, Sendable {
        var usedPercent: Double?
        var resetAt: Double?
        var limitWindowSeconds: Double?

        var resetDate: Date? {
            guard let resetAt else { return nil }
            return Date(timeIntervalSince1970: resetAt)
        }
    }

    struct Credits: Equatable, Sendable {
        var hasCredits: Bool?
        var unlimited: Bool?
        var balance: Double?
    }
}

extension OpenAIUsagePayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        rateLimit = try container.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
        credits = try container.decodeIfPresent(Credits.self, forKey: .credits)
    }
}

extension OpenAIUsagePayload.RateLimit: Decodable {
    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

extension OpenAIUsagePayload.Window: Decodable {
    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeFlexibleNumberIfPresent(forKey: .usedPercent)
        resetAt = try container.decodeFlexibleNumberIfPresent(forKey: .resetAt)
        limitWindowSeconds = try container.decodeFlexibleNumberIfPresent(forKey: .limitWindowSeconds)
    }
}

extension OpenAIUsagePayload.Credits: Decodable {
    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try container.decodeIfPresent(Bool.self, forKey: .hasCredits)
        unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited)
        balance = try container.decodeFlexibleNumberIfPresent(forKey: .balance)
    }
}

struct CursorUsagePayload: Equatable, Sendable {
    var membershipType: String?
    var isUnlimited: Bool?
    var billingCycleEnd: String?
    var individualUsage: UsageGroup?
    var teamUsage: UsageGroup?

    struct UsageGroup: Equatable, Sendable {
        var plan: Meter?
        var overall: Meter?
        var onDemand: Meter?
    }

    struct Meter: Equatable, Sendable {
        var enabled: Bool?
        var used: Double?
        var limit: Double?
        var remaining: Double?
        var autoPercentUsed: Double?
        var apiPercentUsed: Double?
        var totalPercentUsed: Double?
        var usedPercent: Double?
    }

    var billingCycleEndDate: Date? {
        guard let billingCycleEnd else { return nil }
        return Self.parseDate(billingCycleEnd)
    }

    static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

extension CursorUsagePayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case membershipType
        case isUnlimited
        case billingCycleEnd
        case individualUsage
        case teamUsage
    }
}

extension CursorUsagePayload.UsageGroup: Decodable {
    enum CodingKeys: String, CodingKey {
        case plan
        case overall
        case onDemand
    }
}

extension CursorUsagePayload.Meter: Decodable {
    enum CodingKeys: String, CodingKey {
        case enabled
        case used
        case limit
        case remaining
        case autoPercentUsed
        case apiPercentUsed
        case totalPercentUsed
        case usedPercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        used = try container.decodeFlexibleNumberIfPresent(forKey: .used)
        limit = try container.decodeFlexibleNumberIfPresent(forKey: .limit)
        remaining = try container.decodeFlexibleNumberIfPresent(forKey: .remaining)
        autoPercentUsed = try container.decodeFlexibleNumberIfPresent(forKey: .autoPercentUsed)
        apiPercentUsed = try container.decodeFlexibleNumberIfPresent(forKey: .apiPercentUsed)
        totalPercentUsed = try container.decodeFlexibleNumberIfPresent(forKey: .totalPercentUsed)
        usedPercent = try container.decodeFlexibleNumberIfPresent(forKey: .usedPercent)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleNumberIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}
