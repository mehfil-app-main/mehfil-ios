import Testing
import Foundation
@testable import Mehfil

/// The rules a vendor makes money on: what counts as a double-booking, and what counts as overdue.
/// `today` is fixed so the suite does not change meaning as the calendar moves.
struct VendorViewTests {
    private let today = Cal.date(2026, 11, 12)

    private func event(
        _ id: String,
        day: Date? = nil,
        startHour: Int = 18,
        durationHours: Int = 5,
        status: EventStatus = .upcoming,
        quoted: Int = 100_000,
        clientId: String = "c1"
    ) -> Event {
        let base = day ?? Cal.adding(7, .day, to: today)
        let start = Cal.setting(hour: startHour, on: base)
        return Event(
            id: id, name: "\(id) event", clientId: clientId, type: .sangeet,
            start: start, end: Cal.adding(durationHours, .hour, to: start),
            venue: Venue(name: "Hall", area: "Area", hall: nil),
            guests: 200, quoted: quoted, hue: .one, status: status,
            crewAssigned: 0, crewNeeded: 6, crewPlan: nil, inventorySummary: nil, createdAt: today
        )
    }

    private func member(_ id: String, bookings: [String]) -> CrewMember {
        CrewMember(id: id, name: "Member \(id)", role: .helper, isLead: false, dayRate: 900,
                   avatar: nil, bookings: bookings, note: nil)
    }

    private func milestone(_ id: String, event: String, amount: Int, due: Date, status: MilestoneStatus) -> Milestone {
        Milestone(id: id, eventId: event, name: "Balance", amount: amount, due: due,
                  status: status, kind: .balance, paidOn: nil, method: nil, reference: nil)
    }

    private func view(_ data: VendorData) -> VendorView { VendorView(data, today: today) }

    // MARK: Conflicts

    @Test func memberBookedOnTwoOverlappingEventsIsAConflict() {
        let a = event("a", startHour: 17, durationHours: 6)   // 17:00–23:00
        let b = event("b", startHour: 19, durationHours: 4)   // 19:00–23:00
        let v = view(VendorData(events: [a, b], crew: [member("m", bookings: ["a", "b"])]))

        #expect(v.isConflicted(a))
        #expect(v.isConflicted(b))
        #expect(v.seasonConflict?.2.id == "m")
    }

    @Test func sameDayButNonOverlappingIsNotAConflict() {
        let morning = event("a", startHour: 9, durationHours: 3)
        let evening = event("b", startHour: 18, durationHours: 4)
        let v = view(VendorData(events: [morning, evening], crew: [member("m", bookings: ["a", "b"])]))

        #expect(!v.isConflicted(morning))
        #expect(!v.isConflicted(evening))
        #expect(v.seasonConflict == nil)
    }

    @Test func overlappingEventsWithoutSharedCrewAreNotAConflict() {
        let a = event("a", startHour: 17, durationHours: 6)
        let b = event("b", startHour: 19, durationHours: 4)
        let v = view(VendorData(events: [a, b], crew: [member("m1", bookings: ["a"]), member("m2", bookings: ["b"])]))

        #expect(!v.isConflicted(a))
        #expect(v.seasonConflict == nil)
    }

    @Test func cancelledEventsNeverConflict() {
        let a = event("a", startHour: 17, durationHours: 6)
        let cancelled = event("b", startHour: 19, durationHours: 4, status: .cancelled)
        let v = view(VendorData(events: [a, cancelled], crew: [member("m", bookings: ["a", "b"])]))

        #expect(!v.isConflicted(a))
    }

    @Test func seasonConflictIgnoresEventsAlreadyPast() {
        let past = Cal.adding(-3, .day, to: today)
        let a = event("a", day: past, startHour: 17, durationHours: 6)
        let b = event("b", day: past, startHour: 19, durationHours: 4)
        let v = view(VendorData(events: [a, b], crew: [member("m", bookings: ["a", "b"])]))

        #expect(v.seasonConflict == nil)
    }

    // MARK: Money

    @Test func unpaidMilestoneDueBeforeTodayIsOverdue() {
        let e = event("a")
        let v = view(VendorData(
            events: [e],
            milestones: [milestone("m", event: "a", amount: 50_000, due: Cal.adding(-2, .day, to: today), status: .pending)]
        ))

        #expect(v.paymentState(e) == .overdue)
        #expect(v.overdueTotal == 50_000)
        #expect(v.totalOutstanding == 50_000)
    }

    @Test func paidMilestoneIsNeverOverdueHoweverOld() {
        let e = event("a")
        let v = view(VendorData(
            events: [e],
            milestones: [milestone("m", event: "a", amount: 50_000, due: Cal.adding(-90, .day, to: today), status: .paid)]
        ))

        #expect(v.paymentState(e) == .paid)
        #expect(v.overdueTotal == 0)
        #expect(v.totalOutstanding == 0)
    }

    @Test func partPaidReadsAsPartialAndOnlyTheOpenHalfIsOutstanding() {
        let e = event("a")
        let v = view(VendorData(
            events: [e],
            milestones: [
                milestone("paid", event: "a", amount: 40_000, due: Cal.adding(-30, .day, to: today), status: .paid),
                milestone("open", event: "a", amount: 60_000, due: Cal.adding(30, .day, to: today), status: .pending),
            ]
        ))

        #expect(v.paymentState(e) == .partial)
        #expect(v.collected(for: "a") == 40_000)
        #expect(v.balanceDue(for: "a") == 60_000)
        #expect(v.overdueTotal == 0)
    }

    @Test func moneyOwedAgainstACancelledEventIsNotOutstanding() {
        let cancelled = event("a", status: .cancelled)
        let v = view(VendorData(
            events: [cancelled],
            milestones: [milestone("m", event: "a", amount: 50_000, due: Cal.adding(-2, .day, to: today), status: .pending)]
        ))

        #expect(v.totalOutstanding == 0)
        #expect(v.overdue.isEmpty)
    }

    @Test func milestoneBucketsAreDisjoint() {
        let e = event("a")
        let v = view(VendorData(
            events: [e],
            milestones: [
                milestone("late", event: "a", amount: 10_000, due: Cal.adding(-5, .day, to: today), status: .pending),
                milestone("later", event: "a", amount: 20_000, due: Cal.adding(60, .day, to: today), status: .pending),
            ]
        ))

        let all = v.overdue + v.dueThisWeek + v.upcomingMilestones
        #expect(all.count == v.openMilestones.count)
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test func lifetimeValueCountsEveryEventExceptCancelled() {
        let client = Client(id: "c1", name: "Vikram Kapoor", phone: "9811000000", isRepeat: false, avatar: 1, createdAt: today)
        let v = view(VendorData(
            clients: [client],
            events: [
                event("a", quoted: 100_000),
                event("b", status: .completed, quoted: 250_000),
                event("c", status: .cancelled, quoted: 999_000),
            ]
        ))

        let stats = v.stats(for: client)
        #expect(stats.eventCount == 2)
        #expect(stats.lifetimeValue == 350_000)
        #expect(v.lifetimeValue == 350_000)
    }
}
