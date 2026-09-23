import Foundation

// MARK: - Calendar helpers.

enum Cal {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1 // Sunday-first grid, as in the design (S M T W T F S)
        return c
    }()

    /// The vendor's "today". Real time in production; the sample season is date-shifted to fit around it.
    static var today: Date { Date() }
    /// Next Saturday strictly after today (the wedding-season focal day).
    static var nextSaturday: Date {
        let wd = calendar.component(.weekday, from: today)
        let delta = (7 - wd + 7) % 7
        return startOfDay(adding(delta == 0 ? 7 : delta, .day, to: today))
    }
    /// Season window (Oct–Feb) containing `day`.
    static func seasonStart(containing day: Date) -> Date {
        let y = year(day), m = month(day)
        return date(m >= 10 ? y : y - 1, 10, 1)
    }
    static func seasonLabel(containing day: Date) -> String {
        let y = year(seasonStart(containing: day))
        return "Season \(y)–\(String(y + 1).suffix(2))"
    }
    static func newId() -> String { UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(20).description }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    static func sameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }
    /// The given wall-clock hour on `day`, used for the default event window.
    static func setting(hour: Int, on day: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay(day)) ?? startOfDay(day)
    }
    static func startOfDay(_ d: Date) -> Date { calendar.startOfDay(for: d) }
    static func adding(_ n: Int, _ unit: Calendar.Component, to d: Date) -> Date { calendar.date(byAdding: unit, value: n, to: d)! }
    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(a), to: startOfDay(b)).day ?? 0
    }
    static func day(_ d: Date) -> Int { calendar.component(.day, from: d) }
    static func month(_ d: Date) -> Int { calendar.component(.month, from: d) }
    static func year(_ d: Date) -> Int { calendar.component(.year, from: d) }
    static func hour(_ d: Date) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }
    /// Monday-to-Sunday week containing `today` (NOTES Phase 4: "this week" is Mon–Sun).
    static var thisWeek: ClosedRange<Date> {
        let wd = calendar.component(.weekday, from: today) // 1 = Sun
        let offsetToMonday = (wd + 5) % 7
        let monday = startOfDay(adding(-offsetToMonday, .day, to: today))
        let sundayEnd = adding(7, .day, to: monday)
        return monday...sundayEnd
    }
}

// MARK: - Formatting

enum Fmt {
    /// "+919811008123" → "+91 98110 08123"; anything else is returned as typed.
    static func phone(_ e164: String) -> String {
        let digits = e164.filter(\.isNumber)
        if e164.hasPrefix("+91"), digits.count == 12 { let n = digits.dropFirst(2); return "+91 \(n.prefix(5)) \(n.suffix(5))" }
        if digits.count == 10, !e164.hasPrefix("+") { return "\(digits.prefix(5)) \(digits.suffix(5))" }
        return e164
    }
    /// Digits for wa.me / tel: links — a bare 10-digit Indian number gets the 91 prefix.
    static func phoneDigits(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        return digits.count == 10 ? "91" + digits : digits
    }
    /// Indian mobile numbers are 10 digits. Stored and compared as digits only; displayed grouped 5+5.
    static func phoneDigitsOnly(_ input: String) -> String { String(input.filter(\.isNumber).prefix(10)) }

    /// nil when the number is acceptable, otherwise the reason. An empty number is allowed — phone is optional.
    static func phoneProblem(_ input: String) -> String? {
        let digits = input.filter(\.isNumber)
        if digits.isEmpty { return nil }
        if digits.count != 10 { return "A mobile number is 10 digits." }
        if let first = digits.first, !"6789".contains(first) { return "Indian mobile numbers start with 6, 7, 8 or 9." }
        return nil
    }

    static func isValidPhone(_ input: String) -> Bool { phoneProblem(input) == nil }

    /// Builds an E.164 number from a dialling code and a local number; nil when it can't be one.
    static func e164(code: String, number: String) -> String? {
        let c = code.filter(\.isNumber), n = number.filter(\.isNumber)
        guard c.count >= 1, c.count <= 3, n.count >= 6, n.count <= 12 else { return nil }
        return "+" + c + n
    }

    /// Indian digit grouping: ₹23,47,500 — never ₹2,347,500 (spec §6).
    static func inr(_ amount: Int, symbol: Bool = true) -> String {
        let negative = amount < 0
        let s = String(abs(amount))
        var grouped = ""
        if s.count > 3 {
            let last3 = s.suffix(3)
            var rest = String(s.dropLast(3))
            var parts: [String] = []
            while rest.count > 2 { parts.insert(String(rest.suffix(2)), at: 0); rest = String(rest.dropLast(2)) }
            if !rest.isEmpty { parts.insert(rest, at: 0) }
            grouped = parts.joined(separator: ",") + "," + last3
        } else { grouped = s }
        return (negative ? "−" : "") + (symbol ? "₹" : "") + grouped
    }

    /// Lakh notation for narrow columns only (NOTES number-formatting rule): ₹22.1L
    static func lakh(_ amount: Int) -> String {
        let l = Double(amount) / 100_000
        return "₹" + (l == l.rounded() ? String(Int(l)) : String(format: "%.1f", l)) + "L"
    }

    private static func f(_ format: String) -> DateFormatter {
        let df = DateFormatter(); df.calendar = Cal.calendar; df.locale = Locale(identifier: "en_IN"); df.dateFormat = format; return df
    }
    static let time = f("HH:mm")
    static let dayMonth = f("d MMM")            // 14 Nov
    static let dayMonthLong = f("d MMMM")       // 14 November
    static let weekdayDayMonth = f("EEE d MMM") // Sat 14 Nov
    static let weekdayLong = f("EEEE d MMMM")   // Saturday 14 November
    static let weekdayLongYear = f("EEEE d MMMM yyyy")
    static let monthYear = f("MMMM yyyy")
    static let monthShort = f("MMM")
    static let weekdayShort = f("EEE")
    static let dayNum = f("d")
    static let weekdayDayMonthTime = f("EEE d MMM, HH:mm")

    static func timeRange(_ a: Date, _ b: Date) -> String { "\(time.string(from: a))–\(time.string(from: b))" }

    static func relativeDays(_ d: Date, from today: Date = Cal.today) -> String {
        let n = Cal.daysBetween(today, d)
        switch n {
        case 0: return "today"
        case 1: return "tomorrow"
        case ..<0: return "\(-n) days late"
        default: return "in \(n) days"
        }
    }
    static func daysLate(_ d: Date) -> Int { max(0, Cal.daysBetween(d, Cal.today)) }
}
