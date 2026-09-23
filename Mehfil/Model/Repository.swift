import Foundation

/// One write against a vendor's data. Collections are the DATA_MODEL.md subcollection names.
enum WriteOp {
    case set(collection: String, id: String, value: any Encodable)
    case delete(collection: String, id: String)
}

enum Coll {
    static let clients = "clients", events = "events", milestones = "milestones", crew = "crew", inventory = "inventory", tasks = "tasks"
    static let attendance = "attendance", reminders = "reminders", expenses = "expenses", enquiries = "enquiries", packages = "packages", changeRequests = "changeRequests"
    static let all = [clients, events, milestones, crew, inventory, tasks, attendance, reminders, expenses, enquiries, packages, changeRequests]
}

/// Storage behind the app. Firestore in production; a JSON file on device when the build has no Firebase config.
/// Storage behind the app.
///
/// Isolated to the main actor: every caller is the `@MainActor` store, and the implementations hold mutable
/// state that would otherwise cross actor boundaries. The blocking work inside — file decoding — hops to a
/// background task explicitly, so nothing long-running actually runs on the main thread.
@MainActor
protocol Repository: AnyObject {
    var isCloud: Bool { get }
    func profile(uid: String) async throws -> VendorProfile?
    func saveProfile(uid: String, _ profile: VendorProfile) async throws
    /// Starts streaming the vendor's data; `onChange` receives the full picture after every change (local or remote).
    /// Starts streaming the vendor's data; `onChange` receives the full picture after every change.
    /// Asynchronous because the on-device implementation has to read and decode a file before the first
    /// emission, and that must not block the main actor.
    func observe(uid: String, onChange: @escaping @MainActor (VendorData) -> Void) async
    func stopObserving()
    func write(uid: String, _ ops: [WriteOp]) async throws
    func deleteEverything(uid: String) async throws
}

extension Repository {
    func write(uid: String, _ op: WriteOp) async throws { try await write(uid: uid, [op]) }
}

/// Which backend this build talks to.
enum Backend {
    /// True when a Firebase config is bundled (GoogleService-Info.plist) — see backend/README.md.
    static var isConfigured: Bool { Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil }
}

// MARK: - Local repository (device only). Used for development builds and for the on-device demo.

@MainActor
final class LocalRepository: Repository {
    let isCloud = false
    private var data = VendorData()
    private var onChange: (@MainActor (VendorData) -> Void)?
    private var uid = ""

    private func dir(_ uid: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mehfil/\(uid)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }
    private var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }

    func profile(uid: String) async throws -> VendorProfile? {
        guard let d = try? Data(contentsOf: dir(uid).appendingPathComponent("profile.json")) else { return nil }
        return try decoder.decode(VendorProfile.self, from: d)
    }
    func saveProfile(uid: String, _ profile: VendorProfile) async throws {
        try encoder.encode(profile).write(to: dir(uid).appendingPathComponent("profile.json"), options: .atomic)
    }
    /// Starts streaming the vendor's data; `onChange` receives the full picture after every change.
    /// Asynchronous because the on-device implementation has to read and decode a file before the first
    /// emission, and that must not block the main actor.
    func observe(uid: String, onChange: @escaping @MainActor (VendorData) -> Void) async {
        self.uid = uid; self.onChange = onChange
        if let d = try? Data(contentsOf: dir(uid).appendingPathComponent("data.json")), let v = try? decoder.decode(VendorData.self, from: d) { data = v } else { data = VendorData() }
        let snapshot = data
        Task { @MainActor in onChange(snapshot) }
    }
    func stopObserving() { onChange = nil }

    func write(uid: String, _ ops: [WriteOp]) async throws {
        for op in ops {
            switch op {
            case .set(let c, let id, let value): try apply(c, id, value)
            case .delete(let c, let id): remove(c, id)
            }
        }
        try encoder.encode(data).write(to: dir(uid).appendingPathComponent("data.json"), options: .atomic)
        let snapshot = data
        if let cb = onChange { await MainActor.run { cb(snapshot) } }
    }

    func deleteEverything(uid: String) async throws {
        try? FileManager.default.removeItem(at: dir(uid))
        data = VendorData()
    }

    private func apply(_ c: String, _ id: String, _ value: any Encodable) throws {
        // Round-trip through JSON so the local store holds exactly what Firestore would.
        let raw = try encoder.encode(value)
        func put<T: Identifiable & Codable>(_ arr: inout [T]) throws where T.ID == String {
            let item = try decoder.decode(T.self, from: raw)
            if let i = arr.firstIndex(where: { $0.id == id }) { arr[i] = item } else { arr.append(item) }
        }
        switch c {
        case Coll.clients: try put(&data.clients)
        case Coll.events: try put(&data.events)
        case Coll.milestones: try put(&data.milestones)
        case Coll.crew: try put(&data.crew)
        case Coll.inventory: try put(&data.inventory)
        case Coll.tasks: try put(&data.tasks)
        case Coll.attendance: try put(&data.attendance)
        case Coll.reminders: try put(&data.reminders)
        case Coll.expenses: try put(&data.expenses)
        case Coll.enquiries: try put(&data.enquiries)
        case Coll.packages: try put(&data.packages)
        case Coll.changeRequests: try put(&data.changeRequests)
        default: break
        }
    }
    private func remove(_ c: String, _ id: String) {
        switch c {
        case Coll.clients: data.clients.removeAll { $0.id == id }
        case Coll.events: data.events.removeAll { $0.id == id }
        case Coll.milestones: data.milestones.removeAll { $0.id == id }
        case Coll.crew: data.crew.removeAll { $0.id == id }
        case Coll.inventory: data.inventory.removeAll { $0.id == id }
        case Coll.tasks: data.tasks.removeAll { $0.id == id }
        case Coll.attendance: data.attendance.removeAll { $0.id == id }
        case Coll.reminders: data.reminders.removeAll { $0.id == id }
        case Coll.expenses: data.expenses.removeAll { $0.id == id }
        case Coll.enquiries: data.enquiries.removeAll { $0.id == id }
        case Coll.packages: data.packages.removeAll { $0.id == id }
        case Coll.changeRequests: data.changeRequests.removeAll { $0.id == id }
        default: break
        }
    }
}

/// Turns a whole VendorData into writes (used to load the sample season).
extension VendorData {
    var asWrites: [WriteOp] {
        var ops: [WriteOp] = []
        ops += clients.map { .set(collection: Coll.clients, id: $0.id, value: $0) }
        ops += events.map { .set(collection: Coll.events, id: $0.id, value: $0) }
        ops += milestones.map { .set(collection: Coll.milestones, id: $0.id, value: $0) }
        ops += crew.map { .set(collection: Coll.crew, id: $0.id, value: $0) }
        ops += inventory.map { .set(collection: Coll.inventory, id: $0.id, value: $0) }
        ops += tasks.map { .set(collection: Coll.tasks, id: $0.id, value: $0) }
        ops += attendance.map { .set(collection: Coll.attendance, id: $0.id, value: $0) }
        ops += reminders.map { .set(collection: Coll.reminders, id: $0.id, value: $0) }
        ops += expenses.map { .set(collection: Coll.expenses, id: $0.id, value: $0) }
        ops += enquiries.map { .set(collection: Coll.enquiries, id: $0.id, value: $0) }
        ops += packages.map { .set(collection: Coll.packages, id: $0.id, value: $0) }
        ops += changeRequests.map { .set(collection: Coll.changeRequests, id: $0.id, value: $0) }
        return ops
    }
}
