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
    private(set) var data = VendorData() { didSet { cachedView = nil } }
    private(set) var loaded = false

    // Navigation
    var selectedTab: AppTab = .home
    var paths: [AppTab: [Route]] = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
    var toast: Toast?

    // Settings
    var appearance: Appearance { didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") } }
    @ObservationIgnored private var dismissToastTask: Task<Void, Never>?

    var draft: EventDraft { didSet { if let d = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(d, forKey: "eventDraft") } } }

    deinit {
        // The repository releases its own snapshot listeners when it is deallocated with this store; a
        // nonisolated deinit cannot safely reach main-actor state to do it here.
        dismissToastTask?.cancel()
    }

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
        do { vendor = try await repo.profile(uid: uid) } catch { report(error, String(localized: "error.loadProfile", defaultValue: "Couldn't load your business details.")) }
        profileChecked = true
        await repo.observe(uid: uid) { [weak self] snapshot in
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
        } catch { report(error, String(localized: "error.saveProfile", defaultValue: "Couldn't save your business details.")) }
    }

    func updateProfile(_ change: (inout VendorProfile) -> Void) {
        guard let uid, var p = vendor else { return }
        change(&p); vendor = p
        Task { do { try await repo.saveProfile(uid: uid, p) } catch { report(error, String(localized: "error.save", defaultValue: "Couldn't save that. Try again.")) } }
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
        catch { report(error, String(localized: "error.removeSample", defaultValue: "Couldn't remove the sample season.")) }
    }

    func loadSampleSeason() async {
        guard let uid else { return }
        do { try await repo.write(uid: uid, SampleSeason.data().asWrites); show(.success, "Sample season loaded") }
        catch { report(error, String(localized: "error.loadSample", defaultValue: "Couldn't load the sample season.")) }
    }

    func eraseAllData() async throws {
        guard let uid else { return }
        try await repo.deleteEverything(uid: uid)
    }

    private func save(_ ops: [WriteOp], success: String? = nil) {
        guard let uid else { return }
        Task {
            do { try await repo.write(uid: uid, ops); if let success { show(.success, success) } }
            catch { report(error, String(localized: "error.save", defaultValue: "Couldn't save that. Try again.")) }
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
        // A structured task rather than asyncAfter: a rapid sequence of toasts used to leave one pending
        // timer per toast, and none of them were cancellable.
        dismissToastTask?.cancel()
        dismissToastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.toastDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    /// Reports a failure the vendor can act on and logs the detail. The underlying error is deliberately not
    /// shown: it is untranslatable and exposes storage internals.
    private func report(_ error: Error, _ fallback: String) {
        let classified = AppError(error)
        Log.store.warning("Operation failed: \(String(describing: classified), privacy: .public)")
        show(.error, classified.message(fallback: fallback))
    }

    private static let toastDuration: Double = 2.8

    /// The read model, rebuilt only when `data` changes rather than on every SwiftUI evaluation.
    ///
    /// `@ObservationIgnored` keeps the cache itself out of observation: the screens observe `data`, and this
    /// is derived from it. Without the cache, `crew` re-sorted the roster and `overdue` re-filtered every
    /// milestone on each read, several times per frame.
    @ObservationIgnored private var cachedView: VendorView?

    var view: VendorView {
        if let cachedView { return cachedView }
        let fresh = VendorView(data)
        cachedView = fresh
        return fresh
    }

    // Collections and lookups delegate to the read model. The rules live in VendorView, which is a plain
    // struct with no SwiftUI or Firebase dependency and is covered by unit tests; this class stays
    // responsible for session, navigation, persistence and user feedback.

    var events: [Event] { view.events }
    var clients: [Client] { view.clients }
    var milestones: [Milestone] { view.milestones }
    var crew: [CrewMember] { view.crew }
    var inventory: [InventoryItem] { view.inventory }
    var tasks: [RunsheetTask] { view.tasks }
    var reminders: [SentReminder] { view.reminders }
    var expenses: [Expense] { view.expenses }
    var enquiries: [Enquiry] { view.enquiries }
    var packages: [Package] { view.packages }
    var changeRequests: [ChangeRequest] { view.changeRequests }

    func event(_ id: String) -> Event? { view.event(id) }
    func client(_ id: String) -> Client? { view.client(id) }
    func client(for event: Event) -> Client? { view.client(for: event) }
    func member(_ id: String) -> CrewMember? { view.member(id) }
    func item(_ id: String) -> InventoryItem? { view.item(id) }
    func enquiry(_ id: String) -> Enquiry? { view.enquiry(id) }
    func milestones(for eventId: String) -> [Milestone] { view.milestones(for: eventId) }
    func expenses(for eventId: String) -> [Expense] { view.expenses(for: eventId) }
    func reminders(for milestoneId: String) -> [SentReminder] { view.reminders(for: milestoneId) }
    func pendingChangeRequest(for eventId: String) -> ChangeRequest? { view.pendingChangeRequest(for: eventId) }
    func changeRequest(_ id: String) -> ChangeRequest? { view.changeRequest(id) }

    var upcomingEvents: [Event] { view.upcomingEvents }
    var completedEvents: [Event] { view.completedEvents }
    var openEnquiries: [Enquiry] { view.openEnquiries }
    func events(on day: Date) -> [Event] { view.events(on: day) }
    func events(inMonth month: Int, year: Int) -> [Event] { view.eventsIn(month: month, year: year) }
    func conflicts(on day: Date) -> [Event] { view.conflicts(on: day) }
    func isConflicted(_ e: Event) -> Bool { view.isConflicted(e) }
    var seasonConflict: (Event, Event, CrewMember)? { view.seasonConflict }
    func crewOnDuty(_ day: Date) -> Int { view.crewOnDuty(on: day) }
    /// The member double-booked across this event and another that day, or nil when the day is clean.
    func conflictedMember(for e: Event) -> CrewMember? { view.conflictedMember(for: e) }

    // MARK: Money

    func paymentState(for event: Event) -> PaymentState { view.paymentState(event) }
    func collected(for eventId: String) -> Int { view.collected(for: eventId) }
    func balanceDue(for eventId: String) -> Int { view.balanceDue(for: eventId) }
    func overdueAmount(for eventId: String) -> Int { view.overdueAmount(for: eventId) }
    var openMilestones: [Milestone] { view.openMilestones }
    var overdue: [Milestone] { view.overdue }
    var dueThisWeek: [Milestone] { view.dueThisWeek }
    var upcomingMilestones: [Milestone] { view.upcomingMilestones }
    var totalOutstanding: Int { view.totalOutstanding }
    var overdueTotal: Int { view.overdueTotal }
    var eventsWithOpenMoney: Int { view.eventsWithOpenMoney }
    var overdueSurnames: String { view.overdueSurnames }
    var lifetimeValue: Int { view.lifetimeValue }
    func stats(for c: Client) -> ClientStats { view.stats(for: c) }
    func attendance(for eventId: String) -> [String: AttendanceState] { view.attendance(for: eventId) }
    func assignedCrew(for eventId: String) -> [CrewMember] { view.assignedCrew(eventId) }
    var season: SeasonSummary { view.season }

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
        return ReminderComposer.message(tone: tone, milestone: m, event: e, client: c, vendor: v)
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
    /// Builds and stores a costed change request. The pricing lives in `ChangeRequestPricing` so the rates
    /// are visible and testable; this only decides which helpers are actually free on the day.
    func logChangeRequest(eventId: String, guestsDelta: Int, via: String) -> ChangeRequest? {
        guard let e = event(eventId) else { return nil }
        let free = crew.filter { member in
            member.role == .helper && !member.bookings.contains { id in
                event(id).map { Cal.sameDay($0.start, e.start) } ?? false
            }
        }
        let cr = ChangeRequestPricing.price(
            event: e, guestsDelta: guestsDelta, inventory: inventory,
            availableHelpers: free, via: via
        )
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

    func cycleAttendance(eventId: String, crewId: String) {
        var a = data.attendance.first { $0.id == eventId } ?? Attendance(id: eventId, states: [:])
        a.states[crewId] = (a.states[crewId] ?? .confirmed).next
        save(.set(collection: Coll.attendance, id: a.id, value: a))
    }
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

}
