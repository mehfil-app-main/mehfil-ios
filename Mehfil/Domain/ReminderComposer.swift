import Foundation

/// Composes the payment reminder a vendor sends over WhatsApp or SMS.
///
/// These are the only strings in the app a *client* reads, so they are localizable with ordered arguments —
/// a vendor working in another language needs to reword them without touching Swift, and argument order
/// differs between languages.
enum ReminderComposer {

    static func message(tone: ReminderTone, milestone: Milestone, event: Event, client: Client, vendor: VendorProfile) -> String {
        let amount = Fmt.inr(milestone.amount)
        let due = Fmt.dayMonthLong.string(from: milestone.due)
        let item = milestone.name.lowercased()
        let eventDate = Fmt.dayMonthLong.string(from: event.day)
        let hasUPI = !vendor.upi.isEmpty

        switch tone {
        case .gentle:
            return String(
                localized: "reminder.gentle",
                defaultValue: "Hi \(client.firstName), hope the preparations are going well! Just a gentle nudge — the \(item) of \(amount) for the \(event.type.rawValue) was due on \(due). Whenever convenient this week works. Thanks so much — \(vendor.ownerFirstName), \(vendor.businessName)"
            )
        case .standard:
            let pay = hasUPI
                ? String(localized: "reminder.payUpiOrBank", defaultValue: "by UPI to \(vendor.upi) or by bank transfer")
                : String(localized: "reminder.payBank", defaultValue: "by bank transfer")
            return String(
                localized: "reminder.standard",
                defaultValue: "Hi \(client.firstName), a reminder that the \(item) of \(amount) for the \(event.type.rawValue) on \(eventDate) was due on \(due). You can pay \(pay). Thank you — \(vendor.ownerFirstName), \(vendor.businessName)"
            )
        case .firm:
            let pay = hasUPI
                ? String(localized: "reminder.payUpiToday", defaultValue: "by UPI to \(vendor.upi) today")
                : String(localized: "reminder.payToday", defaultValue: "today")
            let daysLate = Cal.daysBetween(milestone.due, Cal.today)
            return String(
                localized: "reminder.firm",
                defaultValue: "\(client.firstName), the \(item) of \(amount) for the \(event.type.rawValue) on \(eventDate) is \(daysLate) days overdue. We need it cleared by tomorrow to hold the crew and inventory for your date. Please pay \(pay). — \(vendor.ownerFirstName), \(vendor.businessName)"
            )
        }
    }
}
