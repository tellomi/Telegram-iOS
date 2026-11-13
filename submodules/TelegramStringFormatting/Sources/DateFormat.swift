import Foundation
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import TextFormat

public func getDateTimeComponents(timestamp: Int32) -> (day: Int32, month: Int32, year: Int32, hour: Int32, minutes: Int32) {
    var t: time_t = Int(timestamp)
    var timeinfo = tm()
    localtime_r(&t, &timeinfo);
    
    return (timeinfo.tm_mday, timeinfo.tm_mon + 1, timeinfo.tm_year, timeinfo.tm_hour, timeinfo.tm_min)
}

/// `year` is `tm_year` (years since 1900), which every caller passes through.
/// Two-digit display used to be `tm_year - 100`. That is 26 for 2026 and **-30 for 1970**,
/// so a last-seen timestamp of 0 rendered as `01/01/-30`. Years before 2000 show in full.
func calendarDisplayYear(tmYear year: Int32, requiresFullYear: Bool) -> Int32 {
    let fullYear = year + 1900
    if requiresFullYear || fullYear < 2000 {
        return fullYear
    }
    return fullYear % 100
}

public func stringForMediumCompactDate(timestamp: Int32, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, withTime: Bool = true) -> String {
    var t: time_t = Int(timestamp)
    var timeinfo = tm()
    localtime_r(&t, &timeinfo);
    
    let day = timeinfo.tm_mday
    let month = monthAtIndex(Int(timeinfo.tm_mon), strings: strings)
    
    let timeString: String
    if withTime {
        timeString = " \(stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min), dateTimeFormat: dateTimeFormat))"
    } else {
        timeString = ""
    }
    let dateString: String
    switch dateTimeFormat.dateFormat {
        case .monthFirst:
            dateString = String(format: "%@ %02d%@", month, day, timeString)
        case .dayFirst:
            dateString = String(format: "%02d %@%@", day, month, timeString)
    }
    return dateString
}

public func stringForMediumDate(timestamp: Int32, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, withTime: Bool = true) -> String {
    var t: time_t = Int(timestamp)
    var timeinfo = tm()
    localtime_r(&t, &timeinfo);
    
    let day = timeinfo.tm_mday
    let month = timeinfo.tm_mon + 1
    let year = timeinfo.tm_year
    
    let dateString: String
    let separator = dateTimeFormat.dateSeparator
    let suffix = dateTimeFormat.dateSuffix
    let displayYear = calendarDisplayYear(tmYear: year, requiresFullYear: dateTimeFormat.requiresFullYear)
    switch dateTimeFormat.dateFormat {
        case .monthFirst:
            dateString = String(format: "%02d%@%02d%@%02d%@", month, separator, day, separator, displayYear, suffix)
        case .dayFirst:
            dateString = String(format: "%02d%@%02d%@%02d%@", day, separator, month, separator, displayYear, suffix)
    }
    
    if withTime {
        let timeString = stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min), dateTimeFormat: dateTimeFormat)
        return strings.Time_MediumDate(dateString, timeString).string
    } else {
        return dateString
    }
}

public func stringForFullDate(timestamp: Int32, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat) -> String {
    var t: time_t = Int(timestamp)
    var timeinfo = tm()
    localtime_r(&t, &timeinfo);
    
    let dayString = "\(timeinfo.tm_mday)"
    let yearString = "\(calendarDisplayYear(tmYear: timeinfo.tm_year, requiresFullYear: true))"
    let timeString = stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min), dateTimeFormat: dateTimeFormat)
    
    let monthFormat: (String, String, String) -> PresentationStrings.FormattedString
    switch timeinfo.tm_mon + 1 {
    case 1:
        monthFormat = strings.Time_PreciseDate_m1
    case 2:
        monthFormat = strings.Time_PreciseDate_m2
    case 3:
        monthFormat = strings.Time_PreciseDate_m3
    case 4:
        monthFormat = strings.Time_PreciseDate_m4
    case 5:
        monthFormat = strings.Time_PreciseDate_m5
    case 6:
        monthFormat = strings.Time_PreciseDate_m6
    case 7:
        monthFormat = strings.Time_PreciseDate_m7
    case 8:
        monthFormat = strings.Time_PreciseDate_m8
    case 9:
        monthFormat = strings.Time_PreciseDate_m9
    case 10:
        monthFormat = strings.Time_PreciseDate_m10
    case 11:
        monthFormat = strings.Time_PreciseDate_m11
    case 12:
        monthFormat = strings.Time_PreciseDate_m12
    default:
        return ""
    }

    return monthFormat(dayString, yearString, timeString).string
}

public func stringForDate(timestamp: Int32, timeZone: TimeZone? = TimeZone(secondsFromGMT: 0), strings: PresentationStrings) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .none
    formatter.dateStyle = .medium
    formatter.timeZone = timeZone
    formatter.locale = localeWithStrings(strings)
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
}

public func stringForDate(date: Date, timeZone: TimeZone? = TimeZone(secondsFromGMT: 0), strings: PresentationStrings) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .none
    formatter.dateStyle = .medium
    formatter.timeZone = timeZone
    formatter.locale = localeWithStrings(strings)
    return formatter.string(from: date)
}

public func stringForDateWithoutYear(date: Date, timeZone: TimeZone? = TimeZone(secondsFromGMT: 0), strings: PresentationStrings) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .none
    formatter.timeZone = timeZone
    formatter.locale = localeWithStrings(strings)
    formatter.setLocalizedDateFormatFromTemplate("MMMMd")
    return formatter.string(from: date)
}

public func roundDateToDays(_ timestamp: Int32) -> Int32 {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = calendar.dateComponents(Set([.era, .year, .month, .day]), from: Date(timeIntervalSince1970: Double(timestamp)))
    components.hour = 0
    components.minute = 0
    components.second = 0
    
    guard let date = calendar.date(from: components) else {
        assertionFailure()
        return timestamp
    }
    return Int32(date.timeIntervalSince1970)
}
