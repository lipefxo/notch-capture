import Foundation

enum CaptureTimestampFormatter {
    static func string(
        from date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}
