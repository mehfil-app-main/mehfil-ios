import Foundation
import SwiftUI
import Observation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, events, money, team, profile
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .home: "house"
        case .events: "calendar"
        case .money: "creditcard"
        case .team: "person.2"
        case .profile: "person"
        }
    }
}

/// Every pushed destination in the app (spec §2: never more than three levels from a tab root).
enum Route: Hashable {
    case calendarMonth
    case dayDetail(Date)
    case seasonSummary
    case eventDetail(String)
    case createEvent
    case runsheet(String)
    case changeRequest(String)
    case paymentSchedule(String)
    case expenses(String)
    case assignCrew(String)
    case attendance(String)
    case inventory
    case itemDetail(String)
    case clients
    case sharedPage(String)
    case enquiry(String?)
    case crewList
    case packages
    case account
}

struct Toast: Identifiable, Equatable {
    enum Kind { case success, error, info }
    let id = UUID()
    var kind: Kind
    var message: String
}

@Observable
@MainActor
final class AppStore {
    let repo: Repository
    private(set) var uid: String?
    private(set) var vendor: VendorProfile?
    private(set) var profileChecked = false
    private(set) var data = VendorData()
    private(set) var loaded = false

    // Navigation
    var selectedTab: AppTab = .home
    var paths: [AppTab: [Route]] = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
    var toast: Toast?

    // Settings
    var appearance: Appearance { didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") } }
    var draft: EventDraft { didSet { if let d = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(d, forKey: "eventDraft") } } }

    init(repo: Repository) {
        self.repo = repo
        appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        if let d = UserDefaults.standard.data(forKey: "eventDraft"), let dr = try? JSONDecoder().decode(EventDraft.self, from: d) { draft = dr } else { draft = .empty }
    }

    // MARK: Session

    var needsOnboarding: Bool { uid != nil && profileChecked && vendor == nil }

    func bind(uid: String) async {
        guard self.uid != uid else { return }
        self.uid = uid; profileChecked = false; loaded = false; vendor = nil; data = VendorData()
        do { vendor = try await repo.profile(uid: uid) } catch { show(.error, "Couldn't load your profile: \(error.localizedDescription)") }
        profileChecked = true
        repo.observe(uid: uid) { [weak self] snapshot in
            guard let self else { return }
            self.data = snapshot
            self.loaded = true
        }
    }

    func unbind() {
        repo.stopObserving()
        uid = nil; vendor = nil; profileChecked = false; loaded = false; data = VendorData()
        paths = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) }); selectedTab = .home
    }

    /// Onboarding: creates the vendor profile, default packages, and optionally the sample season.
    func completeOnboarding(profile: VendorProfile, loadSample: Bool) async {
        guard let uid else { return }
        do {
            var p = profile
            if loadSample {
                let sample = SampleSeason.profile()
                p.since = sample.since; p.upi = sample.upi; p.bankLabel = sample.bankLabel
                p.lastSeasonBooked = sample.lastSeasonBooked; p.lastSeasonEvents = sample.lastSeasonEvents
                try await repo.write(uid: uid, SampleSeason.data().asWrites)
            } else {
                try await repo.write(uid: uid, SampleSeason.defaultPackages().map { .set(collection: Coll.packages, id: $0.id, value: $0) })
            }
            try await repo.saveProfile(uid: uid, p)
            vendor = p
        } catch { show(.error, "Couldn't save your profile: \(error.localizedDescription)") }
    }

    func updateProfile(_ change: (inout VendorProfile) -> Void) {
        guard let uid, var p = vendor else { return }
        change(&p); vendor = p
        Task { do { try await repo.saveProfile(uid: uid, p) } catch { show(.error, "Couldn't save: \(error.localizedDescription)") } }
    }

    /// Deletes exactly the records the sample season wrote. Its ids are fixed ("kapoor", "kapoor-sangeet", …),
    /// so anything the vendor created themselves is untouched — unlike `eraseAllData`, which clears everything.
    func removeSampleSeason() async {
        guard let uid else { return }
        let deletes: [WriteOp] = SampleSeason.data().asWrites.map { op in
            if case .set(let collection, let id, _) = op { return .delete(collection: collection, id: id) }
            return op
        }
        do { try await repo.write(uid: uid, deletes); show(.success, "Sample season removed") }
        catch { show(.error, "Couldn't remove it: \(error.localizedDescription)") }
    }

    func loadSampleSeason() async {
        guard let uid else { return }
        do { try await repo.write(uid: uid, SampleSeason.data().asWrites); show(.success, "Sample season loaded") }
        catch { show(.error, "Couldn't load the sample: \(error.localizedDescription)") }
    }

    func eraseAllData() async throws {
        guard let uid else { return }
        try await repo.deleteEverything(uid: uid)
    }

    private func save(_ ops: [WriteOp], success: String? = nil) {
        guard let uid else { return }
        Task {
            do { try await repo.write(uid: uid, ops); if let success { show(.success, success) } }
            catch { show(.error, "Couldn't save: \(error.localizedDescription)") }
        }
    }
    private func save(_ op: WriteOp, success: String? = nil) { save([op], success: success) }

    // MARK: Navigation

    func push(_ route: Route, in tab: AppTab? = nil) {
        let t = tab ?? selectedTab
        if t != selectedTab { selectedTab = t }
        paths[t, default: []].append(route)
    }
    func pop(_ tab: AppTab? = nil) { _ = paths[tab ?? selectedTab, default: []].popLast() }
    func popToRoot(_ tab: AppTab? = nil) { paths[tab ?? selectedTab] = [] }
    func binding(for tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab, default: []] }, set: { self.paths[tab] = $0 })
    }

    func show(_ kind: Toast.Kind, _ message: String) {
        withAnimation(.spring(duration: 0.35)) { toast = Toast(kind: kind, message: message) }
        let current = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            if self?.toast == current { withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil } }
        }
    }

    // MARK: Collections

    var events: [Event] { data.events }
    var clients: [Client] { data.clients }
    var milestones: [Milestone] { data.milestones }
    var crew: [CrewMember] { data.crew.sorted { ($0.role.rawValue, $0.name) < ($1.role.rawValue, $1.name) } }
    var inventory: [InventoryItem] { data.inventory }
    var tasks: [RunsheetTask] { data.tasks.sorted { $0.order < $1.order } }
    var reminders: [SentReminder] { data.reminders }
    var expenses: [Expense] { data.expenses }
    var enquiries: [Enquiry] { data.enquiries.sorted { $0.createdAt > $1.createdAt } }
    var packages: [Package] { data.packages }
    var changeRequests: [ChangeRequest] { data.changeRequests }

    func event(_ id: String) -> Event? { events.first { $0.id == id } }
    func client(_ id: String) -> Client? { clients.first { $0.id == id } }
    func client(for event: Event) -> Client? { client(event.clientId) }
    func member(_ id: String) -> CrewMember? { crew.first { $0.id == id } }
    func item(_ id: String) -> InventoryItem? { inventory.first { $0.id == id } }
    func enquiry(_ id: String) -> Enquiry? { enquiries.first { $0.id == id } }
    func milestones(for eventId: String) -> [Milestone] { milestones.filter { $0.eventId == eventId }.sorted { $0.due < $1.due } }
    func expenses(for eventId: String) -> [Expense] { expenses.filter { $0.eventId == eventId } }
    func reminders(for milestoneId: String) -> [SentReminder] { reminders.filter { $0.milestoneId == milestoneId }.sorted { $0.sentAt < $1.sentAt } }
    func pendingChangeRequest(for eventId: String) -> ChangeRequest? { changeRequests.first { $0.eventId == eventId && $0.status == .pending } }
    func changeRequest(_ id: String) -> ChangeRequest? { changeRequests.first { $0.id == id } }

    var upcomingEvents: [Event] { events.filter { $0.status == .upcoming }.sorted { $0.start < $1.start } }
    var completedEvents: [Event] { events.filter { $0.status == .completed }.sorted { $0.start > $1.start } }
    var openEnquiries: [Enquiry] { enquiries.filter { $0.status == .open } }
    func events(on day: Date) -> [Event] { events.filter { Cal.sameDay($0.start, day) && $0.status != .cancelled }.sorted { $0.start < $1.start } }
    func events(inMonth month: Int, year: Int) -> [Event] {
        events.filter { $0.status != .cancelled && Cal.month($0.start) == month && Cal.year($0.start) == year }.sorted { $0.start < $1.start }
    }
    /// Events on the same day with overlapping hours (A3, B3, E3 conflict checks).
    func conflicts(on day: Date) -> [Event] {
        let list = events(on: day)
        return list.filter { e in list.contains { $0.id != e.id && $0.start < e.end && e.start < $0.end } }
    }
    private func overlap(_ a: Event, _ b: Event) -> Bool { a.id != b.id && a.start < b.end && b.start < a.end }

    /// A crew conflict is a fact about bookings: someone is booked on two events that overlap in time.
    func isConflicted(_ e: Event) -> Bool {
        guard e.status == .upcoming else { return false }
        return crew.contains { m in m.bookings.contains(e.id) && m.bookings.contains { other in event(other).map { overlap(e, $0) } ?? false } }
    }
    /// The first double-booking in the season: (event, other event, member).
    var seasonConflict: (Event, Event, CrewMember)? {
        for m in crew {
            let booked = m.bookings.compactMap { event($0) }.filter { $0.status == .upcoming && $0.start >= Cal.startOfDay(Cal.today) }.sorted { $0.start < $1.start }
            for a in booked { if let b = booked.first(where: { overlap(a, $0) }) { return (a, b, m) } }
        }
        return nil
    }
    func crewOnDuty(_ day: Date) -> Int {
        let ids = Set(events(on: day).map(\.id))
        return crew.filter { m in m.bookings.contains { ids.contains($0) } }.count
    }

    // MARK: Money

    func paymentState(for event: Event) -> PaymentState {
        let ms = milestones(for: event.id)
        if ms.contains(where: { $0.effectiveStatus == .overdue }) { return .overdue }
        if ms.allSatisfy({ $0.status == .paid }) && !ms.isEmpty { return .paid }
        if ms.contains(where: { $0.status == .paid }) { return .partial }
        return .pending
    }
    func collected(for eventId: String) -> Int { milestones(for: eventId).filter { $0.status == .paid }.reduce(0) { $0 + $1.amount } }
    func balanceDue(for eventId: String) -> Int { milestones(for: eventId).filter { $0.isOpen }.reduce(0) { $0 + $1.amount } }
    func overdueAmount(for eventId: String) -> Int { milestones(for: eventId).filter { $0.effectiveStatus == .overdue }.reduce(0) { $0 + $1.amount } }

    var openMilestones: [Milestone] { milestones.filter { $0.isOpen && event($0.eventId)?.status != .cancelled }.sorted { $0.due < $1.due } }
    var overdue: [Milestone] {
        openMilestones.filter { $0.effectiveStatus == .overdue }
            .sorted { (event($0.eventId)?.start ?? $0.due) < (event($1.eventId)?.start ?? $1.due) }
    }
    var dueThisWeek: [Milestone] {
        let w = Cal.thisWeek
        return openMilestones.filter { $0.effectiveStatus != .overdue && w.contains($0.due) }
    }
    var upcomingMilestones: [Milestone] { openMilestones.filter { $0.effectiveStatus != .overdue && !dueThisWeek.contains($0) } }
    var totalOutstanding: Int { openMilestones.reduce(0) { $0 + $1.amount } }
    var overdueTotal: Int { overdue.reduce(0) { $0 + $1.amount } }
    var eventsWithOpenMoney: Int { Set(openMilestones.map(\.eventId)).count }
    var overdueSurnames: String {
        var seen: [String] = []
        for m in overdue.sorted(by: { $0.amount > $1.amount }) { if let e = event(m.eventId), !seen.contains(e.surname) { seen.append(e.surname) } }
        return seen.joined(separator: ", ")
    }

    func recordPayment(milestoneId: String, amount: Int, method: PaymentMethod, date: Date, reference: String?) {
        guard var m = milestones.first(where: { $0.id == milestoneId }) else { return }
        var ops: [WriteOp] = []
        if amount < m.amount {
            // Partial payment: the remainder becomes a new pending milestone.
            var rest = m; rest.id = Cal.newId(); rest.amount = m.amount - amount; rest.status = .pending; rest.paidOn = nil; rest.method = nil; rest.reference = nil
            ops.append(.set(collection: Coll.milestones, id: rest.id, value: rest))
            m.amount = amount
        }
        m.status = .paid; m.paidOn = date; m.method = method; m.reference = reference
        ops.append(.set(collection: Coll.milestones, id: m.id, value: m))
        save(ops, success: "Recorded \(Fmt.inr(amount))")
    }

    func addMilestone(eventId: String, name: String, amount: Int, due: Date) {
        let m = Milestone(id: Cal.newId(), eventId: eventId, name: name, amount: amount, due: due, status: .pending, kind: .instalment, paidOn: nil, method: nil, reference: nil)
        save(.set(collection: Coll.milestones, id: m.id, value: m), success: "Milestone added")
    }

    func sendReminder(milestoneId: String, tone: ReminderTone, channel: ReminderChannel) {
        let r = SentReminder(id: Cal.newId(), milestoneId: milestoneId, tone: tone, channel: channel, sentAt: Cal.today, outcome: channel == .whatsapp ? "sent" : "delivered")
        save(.set(collection: Coll.reminders, id: r.id, value: r), success: "Sent on \(channel.label)")
    }

    /// Composed reminder copy — real text for each tone (spec C4).
    func reminderMessage(for m: Milestone, tone: ReminderTone) -> String {
        guard let e = event(m.eventId), let c = client(for: e), let v = vendor else { return "" }
        let first = c.firstName, amount = Fmt.inr(m.amount), due = Fmt.dayMonthLong.string(from: m.due), eventDate = Fmt.dayMonthLong.string(from: e.start), name = m.name.lowercased()
        let pay = v.upi.isEmpty ? "by bank transfer" : "by UPI to \(v.upi) or by bank transfer"
        switch tone {
        case .gentle:
            return "Hi \(first), hope the preparations are going well! Just a gentle nudge — the \(name) of \(amount) for the \(e.type.rawValue) was due on \(due). Whenever convenient this week works. Thanks so much — \(v.ownerFirstName), \(v.businessName)"
        case .standard:
            return "Hi \(first), a reminder that the \(name) of \(amount) for the \(e.type.rawValue) on \(eventDate) was due on \(due). You can pay \(pay). Thank you — \(v.ownerFirstName), \(v.businessName)"
        case .firm:
            return "\(first), the \(name) of \(amount) for the \(e.type.rawValue) on \(eventDate) is \(Fmt.daysLate(m.due)) days overdue. We need it cleared by tomorrow to hold the crew and inventory for your date. Please pay \(v.upi.isEmpty ? "today" : "by UPI to \(v.upi) today"). — \(v.ownerFirstName), \(v.businessName)"
        }
    }

    func addExpense(eventId: String, name: String, detail: String, amount: Int) {
        let x = Expense(id: Cal.newId(), eventId: eventId, name: name, detail: detail, amount: amount)
        save(.set(collection: Coll.expenses, id: x.id, value: x), success: "Expense added")
    }
    func deleteExpense(_ id: String) { save(.delete(collection: Coll.expenses, id: id)) }

    // MARK: Events

    func toggleTask(_ id: String) {
        guard var t = tasks.first(where: { $0.id == id }) else { return }
        t.done.toggle()
        save(.set(collection: Coll.tasks, id: t.id, value: t))
    }
    func moveTask(_ id: String, delta: Int) {
        guard let t = tasks.first(where: { $0.id == id }) else { return }
        var block = tasks.filter { $0.eventId == t.eventId && $0.block == t.block }
        guard let i = block.firstIndex(where: { $0.id == id }), block.indices.contains(i + delta) else { return }
        block.swapAt(i, i + delta)
        let base = block.map(\.order).min() ?? 0
        save(block.enumerated().map { j, task in var x = task; x.order = base + j; return .set(collection: Coll.tasks, id: x.id, value: x) })
    }
    func addTask(eventId: String, block: String, title: String, crew: String) {
        let siblings = tasks.filter { $0.eventId == eventId }
        let blockTime = siblings.first { $0.block == block }?.blockTime ?? ""
        let order = (siblings.map(\.order).max() ?? -1) + 1
        let t = RunsheetTask(id: Cal.newId(), eventId: eventId, block: block, blockTime: blockTime, title: title, crew: crew, duration: "—", done: false, order: order)
        save(.set(collection: Coll.tasks, id: t.id, value: t), success: "Task added")
    }
    func runsheetSummary(for e: Event) -> String {
        let ts = tasks.filter { $0.eventId == e.id }
        guard !ts.isEmpty else { return "No tasks yet" }
        return "\(ts.count) tasks · \(ts.filter(\.done).count) done"
    }
    var runsheetMarkers: [String] { ["09:00", "12:00", "14:00", "17:00", "21:00", "23:30"] }

    func approveChangeRequest(_ id: String) {
        guard var cr = changeRequest(id), var e = event(cr.eventId) else { return }
        e.guests += cr.guestsDelta; e.quoted = cr.revisedQuote; cr.status = .approved
        save([.set(collection: Coll.events, id: e.id, value: e), .set(collection: Coll.changeRequests, id: cr.id, value: cr)], success: "Revised quote sent to \(client(for: e)?.firstName ?? "the client")")
    }
    func declineChangeRequest(_ id: String) {
        guard var cr = changeRequest(id) else { return }
        cr.status = .declined
        save(.set(collection: Coll.changeRequests, id: cr.id, value: cr), success: "Change declined")
    }
    /// Builds a change request from a guest delta using the vendor's actual holds and roster (B6 reasoning).
    func logChangeRequest(eventId: String, guestsDelta: Int, via: String) -> ChangeRequest? {
        guard let e = event(eventId) else { return nil }
        let day = e.day
        var impacts: [ChangeImpact] = []; var added = 0
        if let chairs = inventory.first(where: { $0.name.localizedCaseInsensitiveContains("chair") }) {
            let c = chairs.committed(on: day), new = c + guestsDelta
            if new > chairs.total { let hire = new - chairs.total; added += hire * 40; impacts.append(ChangeImpact(resource: chairs.name, detail: "All \(chairs.total) held · hire \(hire) more", delta: "+\(guestsDelta) · \(Fmt.inr(hire * 40))", isShort: true, icon: "inventory")) }
            else { impacts.append(ChangeImpact(resource: chairs.name, detail: "\(c) → \(new) of \(chairs.total) held on \(Fmt.dayMonth.string(from: day))", delta: "+\(guestsDelta)", isShort: false, icon: "inventory")) }
        }
        if let tables = inventory.first(where: { $0.name.localizedCaseInsensitiveContains("table") }) {
            let extra = Int((Double(guestsDelta) / 10).rounded(.up)), c = tables.committed(on: day), new = c + extra
            if new > tables.total { let hire = new - tables.total; added += hire * 400; impacts.append(ChangeImpact(resource: tables.name, detail: "All \(tables.total) held · hire \(hire) more", delta: "+\(extra) · \(Fmt.inr(hire * 400))", isShort: true, icon: "inventory")) }
            else { impacts.append(ChangeImpact(resource: tables.name, detail: "\(c) → \(new) of \(tables.total) held", delta: "+\(extra)", isShort: false, icon: "inventory")) }
        }
        let helpers = max(1, guestsDelta / 50)
        let free = crew.filter { $0.role == .helper && !$0.bookings.contains(where: { id in event(id).map { overlap(e, $0) || Cal.sameDay($0.start, e.start) } ?? false }) }.prefix(helpers)
        let helperCost = helpers * (free.first?.dayRate ?? CrewRole.helper.defaultDayRate); added += helperCost
        impacts.append(ChangeImpact(resource: "Helpers", detail: free.isEmpty ? "Hire \(helpers) day-wage" : free.map(\.firstName).joined(separator: ", "), delta: "+\(helpers) · \(Fmt.inr(helperCost))", isShort: free.count < helpers, icon: "people"))
        if impacts.contains(where: \.isShort) || guestsDelta >= 150 { added += 4_500; impacts.append(ChangeImpact(resource: "Transport", detail: "Second truck, chairs and tables", delta: Fmt.inr(4_500), isShort: false, icon: "transport")) }
        let perGuest = max(200, e.guests == 0 ? 350 : (e.quoted / e.guests) / 4)
        let revised = ((e.quoted + guestsDelta * perGuest) / 1000) * 1000
        let cr = ChangeRequest(id: Cal.newId(), eventId: e.id, summary: "Add \(guestsDelta) guests. \(e.guests) becomes \(e.guests + guestsDelta).", guestsDelta: guestsDelta, impacts: impacts,
                               addedCost: added, revisedQuote: revised, perGuest: perGuest, status: .pending, requestedAt: Cal.today, via: via)
        save(.set(collection: Coll.changeRequests, id: cr.id, value: cr))
        return cr
    }

    func cancelEvent(_ id: String) {
        guard var e = event(id) else { return }
        e.status = .cancelled
        var ops: [WriteOp] = [.set(collection: Coll.events, id: e.id, value: e)]
        for var m in crew where m.bookings.contains(id) { m.bookings.removeAll { $0 == id }; ops.append(.set(collection: Coll.crew, id: m.id, value: m)) }
        for var item in inventory where item.holds.contains(where: { $0.eventId == id }) { item.holds.removeAll { $0.eventId == id }; ops.append(.set(collection: Coll.inventory, id: item.id, value: item)) }
        save(ops, success: "\(e.name) cancelled")
    }
    func markCompleted(_ id: String) {
        guard var e = event(id) else { return }
        e.status = .completed
        save(.set(collection: Coll.events, id: e.id, value: e), success: "\(e.name) marked completed")
    }

    func createEvent(from d: EventDraft) -> Event? {
        guard let type = d.type, let date = d.date, !d.clientName.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let clientName = d.clientName.trimmingCharacters(in: .whitespaces)
        let surname = clientName.split(separator: " ").last.map(String.init) ?? clientName
        let hue = EventHue(rawValue: (events.count % 4) + 1) ?? .one
        var ops: [WriteOp] = []
        let clientId: String
        if let existing = clients.first(where: { $0.surname.lowercased() == surname.lowercased() }) {
            clientId = existing.id
            var c = existing; c.isRepeat = true; if !d.phone.isEmpty { c.phone = d.phone }
            ops.append(.set(collection: Coll.clients, id: c.id, value: c))
        } else {
            clientId = Cal.newId()
            ops.append(.set(collection: Coll.clients, id: clientId, value: Client(id: clientId, name: clientName, phone: d.phone, isRepeat: false, avatar: (clients.count % 8) + 1, createdAt: Cal.today)))
        }
        let start = Cal.calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        let end = Cal.adding(5, .hour, to: start)
        let parts = d.venue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let venue = Venue(name: parts.first ?? d.venue, area: parts.dropFirst().first ?? "", hall: nil)
        let e = Event(id: Cal.newId(), name: "\(surname) \(type.rawValue)", clientId: clientId, type: type, start: start, end: end, venue: venue, guests: d.guests, quoted: d.quoted,
                      hue: hue, status: .upcoming, crewAssigned: 0, crewNeeded: max(6, d.guests / 40), crewPlan: nil, inventorySummary: nil, createdAt: Cal.today)
        ops.append(.set(collection: Coll.events, id: e.id, value: e))
        let advance = d.quoted / 4
        let m1 = Milestone(id: Cal.newId(), eventId: e.id, name: "Booking advance", amount: advance, due: Cal.startOfDay(Cal.today), status: .pending, kind: .advance, paidOn: nil, method: nil, reference: nil)
        let m2 = Milestone(id: Cal.newId(), eventId: e.id, name: "Balance", amount: d.quoted - advance, due: date, status: .pending, kind: .balance, paidOn: nil, method: nil, reference: nil)
        ops.append(.set(collection: Coll.milestones, id: m1.id, value: m1))
        ops.append(.set(collection: Coll.milestones, id: m2.id, value: m2))
        if let q = d.fromEnquiryId, var enq = enquiry(q) { enq.status = .converted; ops.append(.set(collection: Coll.enquiries, id: enq.id, value: enq)) }
        save(ops, success: "\(e.name) created")
        draft = .empty
        return e
    }

    func updateEvent(_ e: Event) { save(.set(collection: Coll.events, id: e.id, value: e), success: "Saved") }
    func updateClient(_ c: Client) { save(.set(collection: Coll.clients, id: c.id, value: c), success: "Saved") }

    // MARK: Clients

    struct ClientStats { var eventCount: Int; var lifetimeValue: Int; var nextEventDate: Date? }
    func stats(for c: Client) -> ClientStats {
        let evs = events.filter { $0.clientId == c.id && $0.status != .cancelled }
        let next = evs.filter { $0.status == .upcoming && $0.start >= Cal.startOfDay(Cal.today) }.map(\.start).min()
        return ClientStats(eventCount: evs.count, lifetimeValue: evs.reduce(0) { $0 + $1.quoted }, nextEventDate: next)
    }
    var lifetimeValue: Int { events.filter { $0.status != .cancelled }.reduce(0) { $0 + $1.quoted } }

    // MARK: Enquiries

    func saveEnquiry(_ q: Enquiry) { save(.set(collection: Coll.enquiries, id: q.id, value: q), success: "Enquiry saved") }
    func closeEnquiry(_ id: String) {
        guard var q = enquiry(id) else { return }
        q.status = .closed
        save(.set(collection: Coll.enquiries, id: q.id, value: q), success: "Enquiry closed")
    }

    // MARK: Packages

    func savePackage(_ p: Package) { save(.set(collection: Coll.packages, id: p.id, value: p), success: "Saved") }
    func deletePackage(_ id: String) { save(.delete(collection: Coll.packages, id: id)) }

    // MARK: Crew

    func attendance(for eventId: String) -> [String: AttendanceState] { data.attendance.first { $0.id == eventId }?.states ?? [:] }
    func cycleAttendance(eventId: String, crewId: String) {
        var a = data.attendance.first { $0.id == eventId } ?? Attendance(id: eventId, states: [:])
        a.states[crewId] = (a.states[crewId] ?? .confirmed).next
        save(.set(collection: Coll.attendance, id: a.id, value: a))
    }
    func assignedCrew(for eventId: String) -> [CrewMember] { crew.filter { $0.bookings.contains(eventId) } }
    func toggleAssignment(crewId: String, eventId: String) {
        guard var m = member(crewId), var e = event(eventId) else { return }
        let on = m.bookings.contains(eventId)
        if on { m.bookings.removeAll { $0 == eventId } } else { m.bookings.append(eventId) }
        e.crewAssigned = max(0, e.crewAssigned + (on ? -1 : 1))
        save([.set(collection: Coll.crew, id: m.id, value: m), .set(collection: Coll.events, id: e.id, value: e)])
    }
    /// D2 comparison outcome: move the member off the other event.
    func moveTeam(crewId: String, to eventId: String, from otherId: String) {
        guard var m = member(crewId) else { return }
        m.bookings.removeAll { $0 == otherId }
        if !m.bookings.contains(eventId) { m.bookings.append(eventId) }
        var ops: [WriteOp] = [.set(collection: Coll.crew, id: m.id, value: m)]
        if var other = event(otherId) { other.crewAssigned = max(0, other.crewAssigned - 1); ops.append(.set(collection: Coll.events, id: other.id, value: other)) }
        save(ops, success: "\(m.firstName)'s team moved to \(event(eventId)?.surname ?? "")")
    }
    func saveCrewMember(_ m: CrewMember) { save(.set(collection: Coll.crew, id: m.id, value: m), success: "Saved") }
    func deleteCrewMember(_ id: String) { save(.delete(collection: Coll.crew, id: id)) }

    // MARK: Inventory

    func saveItem(_ item: InventoryItem) { save(.set(collection: Coll.inventory, id: item.id, value: item), success: "Saved") }
    func deleteItem(_ id: String) { save(.delete(collection: Coll.inventory, id: id)) }
    func setHold(itemId: String, eventId: String, qty: Int) {
        guard var item = item(itemId), let e = event(eventId) else { return }
        item.holds.removeAll { $0.eventId == eventId }
        if qty > 0 { item.holds.append(Hold(eventId: eventId, qty: qty, date: e.day)) }
        save(.set(collection: Coll.inventory, id: item.id, value: item))
    }
    func inventorySummary(for e: Event) -> String {
        let holds = inventory.compactMap { item -> String? in
            guard let h = item.holds.first(where: { $0.eventId == e.id }) else { return nil }
            return "\(h.qty) \(item.unit)"
        }
        return holds.isEmpty ? (e.inventorySummary ?? "Not planned yet") : holds.prefix(3).joined(separator: " · ")
    }

    // MARK: Season

    struct SeasonSummary { var booked: Int; var count: Int; var months: [(String, Int)]; var label: String }
    var season: SeasonSummary {
        let start = Cal.seasonStart(containing: Cal.today)
        let end = Cal.adding(5, .month, to: start)
        let inSeason = events.filter { $0.status != .cancelled && $0.start >= start && $0.start < end }
        let months = (0..<5).map { i -> (String, Int) in
            let m = Cal.adding(i, .month, to: start)
            return (Fmt.monthShort.string(from: m), inSeason.filter { Cal.month($0.start) == Cal.month(m) && Cal.year($0.start) == Cal.year(m) }.reduce(0) { $0 + $1.quoted })
        }
        return SeasonSummary(booked: inSeason.reduce(0) { $0 + $1.quoted }, count: inSeason.count, months: months, label: Cal.seasonLabel(containing: Cal.today))
    }
}
