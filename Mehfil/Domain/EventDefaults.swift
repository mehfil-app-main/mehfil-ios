import Foundation

/// The assumptions Mehfil makes when a vendor books an event from the two-step create flow.
///
/// These were inline literals at the call site. They are defaults a vendor edits afterwards, not rules — but
/// they decide what the first screen after booking says, so they are worth stating once.
enum EventDefaults {
    /// Indian wedding functions run into the evening; 18:00 is the spec's assumed start (§3).
    static let startHour = 18
    static let durationHours = 5

    /// One crew member per 40 guests, never fewer than a six-person team.
    static let guestsPerCrew = 40
    static let minimumCrew = 6

    /// The booking advance is a quarter of the quote; the balance falls due on the day.
    static let advanceShare = 4

    /// Bundled avatar tints, cycled so consecutive clients look different.
    static let avatarCount = 8

    static func window(on date: Date) -> (start: Date, end: Date) {
        let start = Cal.setting(hour: startHour, on: date)
        return (start, Cal.adding(durationHours, .hour, to: start))
    }

    static func crewNeeded(for guests: Int) -> Int { max(minimumCrew, guests / guestsPerCrew) }

    static func advance(of quoted: Int) -> Int { quoted / advanceShare }

    /// "Leela Ambience, Gurugram" → name and area. A single-part entry is treated as the name, so a vendor
    /// typing just "Leela Ambience" still gets a usable record.
    static func venue(from input: String) -> Venue {
        let parts = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Venue(name: parts.first ?? input, area: parts.count > 1 ? parts[1] : "", hall: nil)
    }

    /// Event colours cycle so two events on one day are always distinguishable on the calendar.
    static func hue(forExistingCount count: Int) -> EventHue {
        EventHue.allCases[count % EventHue.allCases.count]
    }

    static func newEvent(from draft: EventDraft, clientId: String, surname: String, existingEventCount: Int) -> Event? {
        guard let type = draft.type, let date = draft.date else { return nil }
        let window = window(on: date)
        return Event(
            id: Cal.newId(), name: "\(surname) \(type.rawValue)", clientId: clientId, type: type,
            start: window.start, end: window.end, venue: venue(from: draft.venue),
            guests: draft.guests, quoted: draft.quoted, hue: hue(forExistingCount: existingEventCount),
            status: .upcoming, crewAssigned: 0, crewNeeded: crewNeeded(for: draft.guests),
            crewPlan: nil, inventorySummary: nil, createdAt: Cal.today
        )
    }
}
