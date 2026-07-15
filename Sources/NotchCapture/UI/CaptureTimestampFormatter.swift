import Foundation

enum CaptureTimestampFormatter {
    static func string(
        from date: Date,
        timeFormat: AppViewModel.TimeFormat = .twelveHour,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = switch timeFormat {
        case .twelveHour: "MMM d, h:mm a"
        case .twentyFourHour: "MMM d, HH:mm"
        }
        return formatter.string(from: date)
    }
}
