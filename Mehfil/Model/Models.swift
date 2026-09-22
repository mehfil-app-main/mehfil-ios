import Foundation

// MARK: - Core domain types. Every type is Codable with the storage schema documented in the backend repo
// (DATA_MODEL.md): enums are stored as the raw strings below, dates as Firestore Timestamps, ids as strings.

enum EventType: String, CaseIterable, Codable, Identifiable {
    case sangeet, mehendi, reception, haldi, nikah, engagement
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum EventStatus: String, Codable { case upcoming, completed, cancelled }

/// Payment state shown on the event card chip (spec component 2).
enum PaymentState: String, Codable { case paid, partial, overdue, pending }

/// Event colour is assigned per event at creation, cycling 1→4. Ruby is excluded (NOTES ruling 2).
enum EventHue: Int, Codable, CaseIterable { case one = 1, two, three, four }

struct Venue: Codable, Hashable {
    var name: String
    var area: String
    var hall: String?
    var short: String { area.isEmpty ? name : "\(name), \(area)" }
    /// Without the leading article, for tight card lines ("Leela Ambience, Gurugram · 17:00").
    var shortName: String { name.hasPrefix("The ") ? String(name.dropFirst(4)) : name }
    var compact: String { area.isEmpty ? shortName : "\(shortName), \(area)" }
}

struct Event: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var clientId: String
    var type: EventType
    var start: Date
    var end: Date
    var venue: Venue
    var guests: Int
    var quoted: Int
    var hue: EventHue
    var status: EventStatus
    /// Planned headcount actually working the event (roster bookings plus daily-wage crew).
    var crewAssigned: Int
    var crewNeeded: Int
    /// Role breakdown of the crew plan ("2 coordinators, 6 decorators, 6 helpers").
    var crewPlan: String?
    var inventorySummary: String?
    var createdAt: Date

    var surname: String { name.split(separator: " ").first.map(String.init) ?? name }
    var isCompleted: Bool { status == .completed }
    var day: Date { Cal.startOfDay(start) }
}

struct Client: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var phone: String
    var isRepeat: Bool
    var avatar: Int            // 1…8 bundled avatar
    var createdAt: Date
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var surname: String { name.split(separator: " ").last.map(String.init) ?? name }
}

enum MilestoneStatus: String, Codable { case paid, pending, overdue }
enum MilestoneKind: String, Codable {
    case advance, instalment, balance, settlement
    var label: String { rawValue.capitalized }
}

enum PaymentMethod: String, CaseIterable, Codable, Identifiable {
    case upi, bank, cash, cheque
    var id: String { rawValue }
    var label: String { switch self { case .upi: "UPI"; case .bank: "Bank transfer"; case .cash: "Cash"; case .cheque: "Cheque" } }
}

struct Milestone: Identifiable, Codable, Hashable {
    var id: String
    var eventId: String
    var name: String
    var amount: Int
    var due: Date
    var status: MilestoneStatus
    var kind: MilestoneKind
    var paidOn: Date?
    var method: PaymentMethod?
    var reference: String?
    var isOpen: Bool { status != .paid }
    /// Overdue is a fact about the date, not a stored flag.
    var effectiveStatus: MilestoneStatus { status == .pending && due < Cal.startOfDay(Cal.today) ? .overdue : status }
}

enum ReminderTone: String, CaseIterable, Identifiable, Codable {
    case gentle, standard, firm
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum ReminderChannel: String, CaseIterable, Identifiable, Codable {
    case whatsapp, sms
    var id: String { rawValue }
    var label: String { self == .whatsapp ? "WhatsApp" : "SMS" }
}

struct SentReminder: Identifiable, Codable, Hashable {
    var id: String
    var milestoneId: String
    var tone: ReminderTone
    var channel: ReminderChannel
    var sentAt: Date
    var outcome: String
}

enum CrewRole: String, Codable, CaseIterable, Identifiable {
    case coordinator, decorator, helper
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var plural: String { rawValue.capitalized + "s" }
    var defaultDayRate: Int { switch self { case .coordinator: 2500; case .decorator: 1200; case .helper: 800 } }
}

enum AttendanceState: String, Codable, CaseIterable {
    case confirmed, arrived, absent
    var label: String { rawValue.capitalized }
    var next: AttendanceState { switch self { case .confirmed: .arrived; case .arrived: .absent; case .absent: .confirmed } }
}

struct CrewMember: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var role: CrewRole
    var isLead: Bool
    var dayRate: Int
    var avatar: Int?
    /// Event ids the member is booked on.
    var bookings: [String]
    var note: String?
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

struct Attendance: Identifiable, Codable, Hashable {
    var id: String              // event id
    var states: [String: AttendanceState]
}

struct Hold: Codable, Hashable {
    var eventId: String
    var qty: Int
    var date: Date
}

struct InventoryItem: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var total: Int
    var detail: String
    var holds: [Hold]
    func committed(on day: Date) -> Int { holds.filter { Cal.sameDay($0.date, day) }.reduce(0) { $0 + $1.qty } }
    func isOver(on day: Date) -> Bool { committed(on: day) > total }
    var unit: String { String(name.lowercased().split(separator: " ").last ?? "") }
}

struct RunsheetTask: Identifiable, Codable, Hashable {
    var id: String
    var eventId: String
    var block: String
    var blockTime: String
    var title: String
    var crew: String
    var duration: String
    var done: Bool
    var order: Int
}

struct Expense: Identifiable, Codable, Hashable {
    var id: String
    var eventId: String
    var name: String
    var detail: String
    var amount: Int
}

struct Package: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var detail: String
    var price: Int
}

struct ChangeImpact: Codable, Hashable {
    var resource: String
    var detail: String
    var delta: String
    var isShort: Bool
    var icon: String            // "inventory" | "people" | "transport"
}

enum ChangeRequestStatus: String, Codable { case pending, approved, declined }

struct ChangeRequest: Identifiable, Codable, Hashable {
    var id: String
    var eventId: String
    var summary: String         // "Add 200 guests."
    var guestsDelta: Int
    var impacts: [ChangeImpact]
    var addedCost: Int
    var revisedQuote: Int
    var perGuest: Int
    var status: ChangeRequestStatus
    var requestedAt: Date
    var via: String             // "WhatsApp"
}

enum EnquiryStatus: String, Codable { case open, converted, closed }

struct Enquiry: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var phone: String
    var source: String
    var budget: String
    var date: Date?
    var guests: Int
    var notes: String
    var status: EnquiryStatus
    var createdAt: Date
}

/// The vendor's own profile — one document per signed-in account.
struct VendorProfile: Codable, Hashable {
    var ownerName: String
    var businessName: String
    var phone: String
    var area: String
    var since: String
    var upi: String
    var bankLabel: String
    var seasonTarget: Int
    var lastSeasonBooked: Int?
    var lastSeasonEvents: Int?
    var notifyPayments: Bool
    var notifyConflicts: Bool
    var notifyChanges: Bool
    var createdAt: Date

    var ownerFirstName: String { ownerName.split(separator: " ").first.map(String.init) ?? ownerName }
    var monogram: String { String(businessName.prefix(1)).uppercased() }

    static func new(owner: String, business: String, phone: String, area: String) -> VendorProfile {
        VendorProfile(ownerName: owner, businessName: business, phone: phone, area: area, since: "since \(Cal.year(Cal.today))",
                      upi: "", bankLabel: "", seasonTarget: 6_000_000, lastSeasonBooked: nil, lastSeasonEvents: nil,
                      notifyPayments: true, notifyConflicts: true, notifyChanges: true, createdAt: Cal.today)
    }
}

/// New-event draft (spec §5: back navigation never loses entered data).
struct EventDraft: Codable, Equatable {
    var clientName = ""
    var phone = ""
    var type: EventType? = nil
    var date: Date? = nil
    var venue = ""
    var guests = 300
    var packageIds: Set<String> = []
    var quoted: Int = 0
    var fromEnquiryId: String? = nil
    static let empty = EventDraft()
}

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .system: "Follows system"; case .light: "Light"; case .dark: "Dark" } }
}

/// Everything under one vendor, as delivered by the repository.
struct VendorData: Codable {
    var clients: [Client] = []
    var events: [Event] = []
    var milestones: [Milestone] = []
    var crew: [CrewMember] = []
    var inventory: [InventoryItem] = []
    var tasks: [RunsheetTask] = []
    var attendance: [Attendance] = []
    var reminders: [SentReminder] = []
    var expenses: [Expense] = []
    var enquiries: [Enquiry] = []
    var packages: [Package] = []
    var changeRequests: [ChangeRequest] = []
}
