import Foundation
import FirebaseFirestore

/// Cloud Firestore behind the Repository protocol. Layout: vendors/{uid} + one subcollection per Coll.* name.
/// Offline persistence is on, so writes land locally first and the listeners fire immediately.
@MainActor
final class FirestoreRepository: Repository {
    let isCloud = true
    private let db: Firestore
    /// Registrations live in their own box so they can be released from `deinit`, which is nonisolated and
    /// therefore cannot touch main-actor state. Removing a registration is safe from any thread.
    private let listeners = ListenerBag()
    private var data = VendorData()

    init() {
        let db = Firestore.firestore()
        let settings = db.settings
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
        self.db = db
    }

    private func vendor(_ uid: String) -> DocumentReference { db.collection("vendors").document(uid) }

    func profile(uid: String) async throws -> VendorProfile? {
        let snap = try await vendor(uid).getDocument()
        guard snap.exists else { return nil }
        return try snap.data(as: VendorProfile.self)
    }

    func saveProfile(uid: String, _ profile: VendorProfile) async throws {
        try vendor(uid).setData(from: profile, merge: true)
    }

    func observe(uid: String, onChange: @escaping @MainActor (VendorData) -> Void) async {
        stopObserving()
        data = VendorData()
        func listen<T: Decodable>(_ coll: String, _ type: T.Type, _ assign: @escaping ([T]) -> Void) {
            let reg = vendor(uid).collection(coll).addSnapshotListener { [weak self] snap, error in
                guard let self, let snap else { return }
                let items: [T] = snap.documents.compactMap { doc in
                    do { return try doc.data(as: T.self) } catch {
                        // Document ids are vendor data, so they stay private in the system log.
                        Log.repository.error("Decode failed in \(coll, privacy: .public)/\(doc.documentID, privacy: .private)")
                        return nil
                    }
                }
                assign(items)
                let snapshot = self.data
                Task { @MainActor in onChange(snapshot) }
            }
            listeners.add(reg)
        }
        listen(Coll.clients, Client.self) { self.data.clients = $0 }
        listen(Coll.events, Event.self) { self.data.events = $0 }
        listen(Coll.milestones, Milestone.self) { self.data.milestones = $0 }
        listen(Coll.crew, CrewMember.self) { self.data.crew = $0 }
        listen(Coll.inventory, InventoryItem.self) { self.data.inventory = $0 }
        listen(Coll.tasks, RunsheetTask.self) { self.data.tasks = $0 }
        listen(Coll.attendance, Attendance.self) { self.data.attendance = $0 }
        listen(Coll.reminders, SentReminder.self) { self.data.reminders = $0 }
        listen(Coll.expenses, Expense.self) { self.data.expenses = $0 }
        listen(Coll.enquiries, Enquiry.self) { self.data.enquiries = $0 }
        listen(Coll.packages, Package.self) { self.data.packages = $0 }
        listen(Coll.changeRequests, ChangeRequest.self) { self.data.changeRequests = $0 }
    }

    func stopObserving() {
        listeners.removeAll()
    }

    func write(uid: String, _ ops: [WriteOp]) async throws {
        // Firestore batches cap at 500 operations.
        for chunk in stride(from: 0, to: ops.count, by: 450).map({ Array(ops[$0..<min($0 + 450, ops.count)]) }) {
            let batch = db.batch()
            for op in chunk {
                switch op {
                case .set(let c, let id, let value):
                    let fields = try encode(value)
                    batch.setData(fields, forDocument: vendor(uid).collection(c).document(id))
                case .delete(let c, let id):
                    batch.deleteDocument(vendor(uid).collection(c).document(id))
                }
            }
            try await batch.commit()
        }
    }

    private func encode(_ value: some Encodable) throws -> [String: Any] { try Firestore.Encoder().encode(value) }

    func deleteEverything(uid: String) async throws {
        for coll in Coll.all {
            let snap = try await vendor(uid).collection(coll).getDocuments()
            for chunk in stride(from: 0, to: snap.documents.count, by: 450).map({ Array(snap.documents[$0..<min($0 + 450, snap.documents.count)]) }) {
                let batch = db.batch()
                chunk.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        }
        try await vendor(uid).delete()
    }
}

/// Holds Firestore listener registrations and removes them when it is released.
///
/// Snapshot listeners retain their callback — and through it the repository and the store — until removed, so
/// ownership of the cleanup belongs with the registrations themselves rather than with a caller who might
/// forget. `@unchecked Sendable` is justified by the lock around the only mutable state.
private final class ListenerBag: @unchecked Sendable {
    private let lock = NSLock()
    private var registrations: [ListenerRegistration] = []

    func add(_ registration: ListenerRegistration) {
        lock.withLock { registrations.append(registration) }
    }

    func removeAll() {
        let current = lock.withLock { let all = registrations; registrations = []; return all }
        current.forEach { $0.remove() }
    }

    deinit { registrations.forEach { $0.remove() } }
}
