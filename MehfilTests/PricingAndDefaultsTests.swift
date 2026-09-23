import Testing
import Foundation
@testable import Mehfil

/// The commercial rules: what a change request costs, and what a new booking assumes.
struct PricingAndDefaultsTests {
    private let day = Cal.date(2026, 11, 14)

    private func event(guests: Int = 400, quoted: Int = 600_000) -> Event {
        Event(
            id: "e1", name: "Kapoor sangeet", clientId: "c1", type: .sangeet,
            start: Cal.setting(hour: 18, on: day), end: Cal.setting(hour: 23, on: day),
            venue: Venue(name: "Leela", area: "Gurugram", hall: nil),
            guests: guests, quoted: quoted, hue: .one, status: .upcoming,
            crewAssigned: 10, crewNeeded: 12, crewPlan: nil, inventorySummary: nil, createdAt: day
        )
    }

    private func chairs(total: Int, held: Int) -> InventoryItem {
        InventoryItem(id: "chairs", name: "Chairs", total: total, detail: "",
                      holds: held > 0 ? [Hold(eventId: "e1", qty: held, date: day)] : [])
    }

    private func helper(_ id: String) -> CrewMember {
        CrewMember(id: id, name: "Helper \(id)", role: .helper, isLead: false, dayRate: 900,
                   avatar: nil, bookings: [], note: nil)
    }

    @Test func stockThatCoversTheExtraGuestsCostsNothingToHire() {
        let cr = ChangeRequestPricing.price(
            event: event(), guestsDelta: 50, inventory: [chairs(total: 500, held: 400)],
            availableHelpers: [helper("h1")], via: "WhatsApp"
        )

        #expect(cr.impacts.first { $0.resource == "Chairs" }?.isShort == false)
        // Only the helper is chargeable: one helper covers 50 extra guests.
        #expect(cr.addedCost == 900)
    }

    @Test func stockThatRunsShortIsHiredAndCharged() {
        let cr = ChangeRequestPricing.price(
            event: event(), guestsDelta: 200, inventory: [chairs(total: 500, held: 400)],
            availableHelpers: [], via: "WhatsApp"
        )

        #expect(cr.impacts.first { $0.resource == "Chairs" }?.isShort == true)
        // 100 chairs at 40, 4 helpers at the default day rate, plus the transport surcharge.
        #expect(cr.addedCost == 100 * 40 + 4 * CrewRole.helper.defaultDayRate + 4_500)
    }

    @Test func aLargeIncreasePullsInTransportEvenWhenNothingIsShort() {
        let big = ChangeRequestPricing.price(
            event: event(), guestsDelta: 150, inventory: [chairs(total: 5_000, held: 0)],
            availableHelpers: (0..<3).map { helper("h\($0)") }, via: "Call"
        )
        #expect(big.impacts.contains { $0.resource == "Transport" })

        let small = ChangeRequestPricing.price(
            event: event(), guestsDelta: 20, inventory: [chairs(total: 5_000, held: 0)],
            availableHelpers: [helper("h1")], via: "Call"
        )
        #expect(!small.impacts.contains { $0.resource == "Transport" })
    }

    @Test func marginalGuestsAreChargedAShareOfTheAverageHeadRate() {
        // 600,000 over 400 guests is 1,500 a head; a quarter is 375.
        #expect(ChangeRequestPricing.perGuestRate(for: event(guests: 400, quoted: 600_000)) == 375)
    }

    @Test func thePerGuestRateNeverFallsBelowTheFloor() {
        #expect(ChangeRequestPricing.perGuestRate(for: event(guests: 400, quoted: 100_000)) == 200)
    }

    @Test func anEventWithNoGuestCountFallsBackRatherThanDividingByZero() {
        #expect(ChangeRequestPricing.perGuestRate(for: event(guests: 0, quoted: 100_000)) == 350)
    }

    @Test func theRevisedQuoteRoundsDownToTheNearestThousand() {
        let cr = ChangeRequestPricing.price(
            event: event(guests: 400, quoted: 600_000), guestsDelta: 50,
            inventory: [], availableHelpers: [helper("h1")], via: "WhatsApp"
        )
        // 600,000 + 50 × 375 = 618,750 → 618,000
        #expect(cr.revisedQuote == 618_000)
    }

    // MARK: Booking defaults

    @Test func crewScalesWithGuestsButNeverBelowASixPersonTeam() {
        #expect(EventDefaults.crewNeeded(for: 0) == 6)
        #expect(EventDefaults.crewNeeded(for: 200) == 6)
        #expect(EventDefaults.crewNeeded(for: 400) == 10)
    }

    @Test func theAdvanceIsAQuarterOfTheQuote() {
        #expect(EventDefaults.advance(of: 600_000) == 150_000)
    }

    @Test func aVenueSplitsIntoNameAndAreaAndSurvivesHavingNeither() {
        #expect(EventDefaults.venue(from: "Leela Ambience, Gurugram") == Venue(name: "Leela Ambience", area: "Gurugram", hall: nil))
        #expect(EventDefaults.venue(from: "Leela Ambience") == Venue(name: "Leela Ambience", area: "", hall: nil))
        #expect(EventDefaults.venue(from: "") == Venue(name: "", area: "", hall: nil))
    }

    @Test func eventColoursCycleSoTwoEventsOnADayStayDistinguishable() {
        let count = EventHue.allCases.count
        let hues = (0...count).map { EventDefaults.hue(forExistingCount: $0) }
        #expect(hues.first == hues.last)
        #expect(Set(hues.dropLast()).count == count)
    }

    @Test func anIncompleteDraftDoesNotProduceAnEvent() {
        var draft = EventDraft.empty
        draft.clientName = "Vikram Kapoor"
        draft.date = day
        #expect(EventDefaults.newEvent(from: draft, clientId: "c1", surname: "Kapoor", existingEventCount: 0) == nil)

        draft.type = .sangeet
        #expect(EventDefaults.newEvent(from: draft, clientId: "c1", surname: "Kapoor", existingEventCount: 0) != nil)
    }

    @Test func aBookedEventRunsFromSixInTheEveningForFiveHours() {
        let window = EventDefaults.window(on: day)
        #expect(window.start == Cal.setting(hour: 18, on: day))
        #expect(window.end == Cal.setting(hour: 23, on: day))
    }
}
