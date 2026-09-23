import Foundation

/// The read model: every ordering, index and bucket the UI needs, derived once per `VendorData` change.
///
/// The screens read the same derived collections many times per frame. Computing them as `var … { }`
/// properties meant re-sorting the roster and re-filtering the milestone list on every SwiftUI evaluation,
/// and `event(id)` was a linear scan inside list bodies. Everything here is computed once in `init` and read
/// as a stored property afterwards.
///
/// A plain `struct` with no SwiftUI or Firebase dependency, so the rules that matter commercially — what
/// counts as a conflict, what counts as overdue — are testable without a host application. `today` is
/// injected rather than read from the clock so a test can pin it.
struct VendorView {
    let events: [Event]
    let clients: [Client]
    let milestones: [Milestone]
    let crew: [CrewMember]
    let inventory: [InventoryItem]
    let tasks: [RunsheetTask]
    let reminders: [SentReminder]
    let expenses: [Expense]
    let enquiries: [Enquiry]
    let packages: [Package]
    let changeRequests: [ChangeRequest]

    private let today: Date
    private let eventsByID: [String: Event]
    private let clientsByID: [String: Client]
    private let crewByID: [String: CrewMember]
    private let inventoryByID: [String: InventoryItem]
    private let enquiriesByID: [String: Enquiry]
    private let milestonesByEvent: [String: [Milestone]]
    private let expensesByEvent: [String: [Expense]]
    private let remindersByMilestone: [String: [SentReminder]]
    private let eventsByDay: [Date: [Event]]
    private let attendance: [Attendance]
    private let conflictedEventIDs: Set<String>

    init(_ data: VendorData, today: Date = Cal.startOfDay(Cal.today)) {
        self.today = today
        events = data.events
        clients = data.clients
        milestones = data.milestones
        crew = data.crew.sorted { ($0.role.rawValue, $0.name) < ($1.role.rawValue, $1.name) }
        inventory = data.inventory
        tasks = data.tasks.sorted { $0.order < $1.order }
        reminders = data.reminders
        expenses = data.expenses
        enquiries = data.enquiries.sorted { $0.createdAt > $1.createdAt }
        packages = data.packages
        changeRequests = data.changeRequests
        attendance = data.attendance

        eventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        clientsByID = Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        crewByID = Dictionary(crew.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        inventoryByID = Dictionary(inventory.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        enquiriesByID = Dictionary(enquiries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        milestonesByEvent = Dictionary(grouping: milestones, by: \.eventId).mapValues { $0.sorted { $0.due < $1.due } }
        expensesByEvent = Dictionary(grouping: expenses, by: \.eventId)
        remindersByMilestone = Dictionary(grouping: reminders, by: \.milestoneId).mapValues { $0.sorted { $0.sentAt < $1.sentAt } }
        eventsByDay = Dictionary(grouping: events.filter { $0.status != .cancelled }, by: \.day).mapValues { $0.sorted { $0.start < $1.start } }

        let index = eventsByID
        var conflicted: Set<String> = []
        for member in crew {
            let booked = member.bookings.compactMap { index[$0] }.filter { $0.status == .upcoming }
            for event in booked where booked.contains(where: { VendorView.overlap(event, $0) }) {
                conflicted.insert(event.id)
            }
        }
        conflictedEventIDs = conflicted
    }

    // MARK: Lookups

    func event(_ id: String) -> Event? { eventsByID[id] }
    func client(_ id: String) -> Client? { clientsByID[id] }
    func client(for event: Event) -> Client? { clientsByID[event.clientId] }
    func member(_ id: String) -> CrewMember? { crewByID[id] }
    func item(_ id: String) -> InventoryItem? { inventoryByID[id] }
    func enquiry(_ id: String) -> Enquiry? { enquiriesByID[id] }
    func milestones(for eventID: String) -> [Milestone] { milestonesByEvent[eventID] ?? [] }
    func expenses(for eventID: String) -> [Expense] { expensesByEvent[eventID] ?? [] }
    func reminders(for milestoneID: String) -> [SentReminder] { remindersByMilestone[milestoneID] ?? [] }
    func events(on day: Date) -> [Event] { eventsByDay[Cal.startOfDay(day)] ?? [] }
    func attendance(for eventID: String) -> [String: AttendanceState] {
        attendance.first { $0.id == eventID }?.states ?? [:]
    }

    func eventsIn(month: Int, year: Int) -> [Event] {
        events.filter { $0.status != .cancelled && Cal.month($0.start) == month && Cal.year($0.start) == year }
            .sorted { $0.start < $1.start }
    }

    func pendingChangeRequest(for eventID: String) -> ChangeRequest? {
        changeRequests.first { $0.eventId == eventID && $0.status == .pending }
    }
    func changeRequest(_ id: String) -> ChangeRequest? { changeRequests.first { $0.id == id } }

    var upcomingEvents: [Event] { events.filter { $0.status == .upcoming }.sorted { $0.start < $1.start } }
    var completedEvents: [Event] { events.filter { $0.status == .completed }.sorted { $0.start > $1.start } }
    var openEnquiries: [Enquiry] { enquiries.filter { $0.status == .open } }

    // MARK: Conflicts

    /// Two events clash when they overlap in time. Same day but consecutive is not a conflict.
    private static func overlap(_ a: Event, _ b: Event) -> Bool {
        a.id != b.id && a.start < b.end && b.start < a.end
    }

    /// A crew conflict is a fact about bookings: someone is booked on two events that overlap in time.
    func isConflicted(_ event: Event) -> Bool { conflictedEventIDs.contains(event.id) }

    func conflicts(on day: Date) -> [Event] {
        let list = events(on: day)
        return list.filter { event in list.contains { Self.overlap(event, $0) } }
    }

    /// The first double-booking still ahead of us: (event, the other event, the member booked on both).
    var seasonConflict: (Event, Event, CrewMember)? {
        for member in crew {
            let booked = member.bookings
                .compactMap { eventsByID[$0] }
                .filter { $0.status == .upcoming && $0.day >= today }
                .sorted { $0.start < $1.start }
            for event in booked {
                if let other = booked.first(where: { Self.overlap(event, $0) }) { return (event, other, member) }
            }
        }
        return nil
    }

    func crewOnDuty(on day: Date) -> Int {
        let ids = Set(events(on: day).map(\.id))
        return crew.filter { member in member.bookings.contains { ids.contains($0) } }.count
    }

    func assignedCrew(_ eventID: String) -> [CrewMember] { crew.filter { $0.bookings.contains(eventID) } }

    /// The member double-booked across this event and another that day, for the inline warning on B2.
    func conflictedMember(for event: Event) -> CrewMember? {
        let otherIDs = Set(events(on: event.day).filter { $0.id != event.id }.map(\.id))
        guard !otherIDs.isEmpty else { return nil }
        return crew.first { $0.bookings.contains(event.id) && $0.bookings.contains { otherIDs.contains($0) } }
    }

    // MARK: Money

    /// Single definition of "late", evaluated against this view's `today` rather than the clock.
    func isOverdue(_ milestone: Milestone) -> Bool { milestone.effectiveStatus(on: today) == .overdue }

    func paymentState(_ event: Event) -> PaymentState {
        let ms = milestones(for: event.id)
        if ms.contains(where: isOverdue) { return .overdue }
        if !ms.isEmpty, ms.allSatisfy({ $0.status == .paid }) { return .paid }
        if ms.contains(where: { $0.status == .paid }) { return .partial }
        return .pending
    }

    func collected(for eventID: String) -> Int { milestones(for: eventID).filter { $0.status == .paid }.reduce(0) { $0 + $1.amount } }
    func balanceDue(for eventID: String) -> Int { milestones(for: eventID).filter(\.isOpen).reduce(0) { $0 + $1.amount } }
    func overdueAmount(for eventID: String) -> Int { milestones(for: eventID).filter(isOverdue).reduce(0) { $0 + $1.amount } }

    var openMilestones: [Milestone] {
        milestones.filter { $0.isOpen && eventsByID[$0.eventId]?.status != .cancelled }.sorted { $0.due < $1.due }
    }
    var overdue: [Milestone] {
        openMilestones.filter(isOverdue).sorted { (eventsByID[$0.eventId]?.day ?? $0.due) < (eventsByID[$1.eventId]?.day ?? $1.due) }
    }
    var dueThisWeek: [Milestone] {
        openMilestones.filter { !isOverdue($0) && Cal.thisWeek.contains($0.due) }
    }
    var upcomingMilestones: [Milestone] {
        let handled = Set(overdue.map(\.id)).union(dueThisWeek.map(\.id))
        return openMilestones.filter { !handled.contains($0.id) }
    }
    var totalOutstanding: Int { openMilestones.reduce(0) { $0 + $1.amount } }
    var overdueTotal: Int { overdue.reduce(0) { $0 + $1.amount } }
    var eventsWithOpenMoney: Int { Set(openMilestones.map(\.eventId)).count }
    var overdueSurnames: String {
        overdue.sorted { $0.amount > $1.amount }
            .compactMap { eventsByID[$0.eventId]?.surname }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ", ")
    }

    var lifetimeValue: Int { events.filter { $0.status != .cancelled }.reduce(0) { $0 + $1.quoted } }

    func stats(for client: Client) -> ClientStats {
        let theirs = events.filter { $0.clientId == client.id && $0.status != .cancelled }
        return ClientStats(
            eventCount: theirs.count,
            lifetimeValue: theirs.reduce(0) { $0 + $1.quoted },
            nextEventDate: theirs.filter { $0.status == .upcoming && $0.day >= today }.map(\.day).min()
        )
    }

    // MARK: Season

    var season: SeasonSummary {
        let start = Cal.seasonStart(containing: today)
        let end = Cal.adding(Self.seasonMonths, .month, to: start)
        let inSeason = events.filter { $0.status != .cancelled && $0.day >= start && $0.day < end }
        let months = (0..<Self.seasonMonths).map { index -> (String, Int) in
            let month = Cal.adding(index, .month, to: start)
            let booked = inSeason
                .filter { Cal.month($0.start) == Cal.month(month) && Cal.year($0.start) == Cal.year(month) }
                .reduce(0) { $0 + $1.quoted }
            return (Fmt.monthShort.string(from: month), booked)
        }
        return SeasonSummary(
            booked: inSeason.reduce(0) { $0 + $1.quoted },
            count: inSeason.count,
            months: months,
            label: Cal.seasonLabel(containing: today)
        )
    }

    /// An Indian wedding season runs October to February — five months (spec §2).
    private static let seasonMonths = 5
}

struct ClientStats: Equatable {
    let eventCount: Int
    let lifetimeValue: Int
    let nextEventDate: Date?
}

struct SeasonSummary {
    let booked: Int
    let count: Int
    let months: [(String, Int)]
    let label: String
}
