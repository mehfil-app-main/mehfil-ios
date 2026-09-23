import Foundation

/// Turns "the client wants N more guests" into a costed change request: what runs short, what it costs to
/// cover, and the revised quote.
///
/// The rates were inline literals at the call site, which made them invisible and unchangeable. They are a
/// commercial policy, not an implementation detail, so a new operator can price their own market by editing
/// `Rates` alone. Figures are the Delhi-NCR day rates the product spec was written against.
enum ChangeRequestPricing {

    struct Rates {
        /// Per-chair hire once the vendor's own stock is fully committed.
        var chairHire = 40
        /// Per-table hire. One table seats `guestsPerTable`.
        var tableHire = 400
        var guestsPerTable = 10
        /// One extra helper covers this many additional guests.
        var guestsPerHelper = 50
        /// A second truck, charged once, when anything runs short or the party grows past `bulkGuestThreshold`.
        var transport = 4_500
        var bulkGuestThreshold = 150
        /// Per-head price floor, and the fallback when the event has no guest count to divide by.
        var minimumPerGuest = 200
        var fallbackPerGuest = 350
        /// Marginal guests are charged a share of the average head rate; quotes round down to `quoteRounding`.
        var marginalShare = 4
        var quoteRounding = 1_000

        static let standard = Rates()
    }

    static func price(
        event: Event,
        guestsDelta: Int,
        inventory: [InventoryItem],
        availableHelpers: [CrewMember],
        via: String,
        rates: Rates = .standard
    ) -> ChangeRequest {
        let day = event.day
        var impacts: [ChangeImpact] = []
        var added = 0

        if let chairs = inventory.first(where: { $0.name.localizedCaseInsensitiveContains("chair") }) {
            let committed = chairs.committed(on: day)
            let wanted = committed + guestsDelta
            if wanted > chairs.total {
                let hire = wanted - chairs.total
                added += hire * rates.chairHire
                impacts.append(ChangeImpact(
                    resource: chairs.name,
                    detail: "All \(chairs.total) held · hire \(hire) more",
                    delta: "+\(guestsDelta) · \(Fmt.inr(hire * rates.chairHire))",
                    isShort: true, icon: Icon.inventory
                ))
            } else {
                impacts.append(ChangeImpact(
                    resource: chairs.name,
                    detail: "\(committed) → \(wanted) of \(chairs.total) held on \(Fmt.dayMonth.string(from: day))",
                    delta: "+\(guestsDelta)", isShort: false, icon: Icon.inventory
                ))
            }
        }

        if let tables = inventory.first(where: { $0.name.localizedCaseInsensitiveContains("table") }) {
            let extra = Int((Double(guestsDelta) / Double(rates.guestsPerTable)).rounded(.up))
            let committed = tables.committed(on: day)
            let wanted = committed + extra
            if wanted > tables.total {
                let hire = wanted - tables.total
                added += hire * rates.tableHire
                impacts.append(ChangeImpact(
                    resource: tables.name,
                    detail: "All \(tables.total) held · hire \(hire) more",
                    delta: "+\(extra) · \(Fmt.inr(hire * rates.tableHire))",
                    isShort: true, icon: Icon.inventory
                ))
            } else {
                impacts.append(ChangeImpact(
                    resource: tables.name,
                    detail: "\(committed) → \(wanted) of \(tables.total) held",
                    delta: "+\(extra)", isShort: false, icon: Icon.inventory
                ))
            }
        }

        let helpersNeeded = max(1, guestsDelta / rates.guestsPerHelper)
        let free = Array(availableHelpers.prefix(helpersNeeded))
        let helperCost = helpersNeeded * (free.first?.dayRate ?? CrewRole.helper.defaultDayRate)
        added += helperCost
        impacts.append(ChangeImpact(
            resource: "Helpers",
            detail: free.isEmpty ? "Hire \(helpersNeeded) day-wage" : free.map(\.firstName).joined(separator: ", "),
            delta: "+\(helpersNeeded) · \(Fmt.inr(helperCost))",
            isShort: free.count < helpersNeeded, icon: Icon.people
        ))

        if impacts.contains(where: \.isShort) || guestsDelta >= rates.bulkGuestThreshold {
            added += rates.transport
            impacts.append(ChangeImpact(
                resource: "Transport", detail: "Second truck, chairs and tables",
                delta: Fmt.inr(rates.transport), isShort: false, icon: Icon.transport
            ))
        }

        let perGuest = perGuestRate(for: event, rates: rates)
        let revised = ((event.quoted + guestsDelta * perGuest) / rates.quoteRounding) * rates.quoteRounding

        return ChangeRequest(
            id: Cal.newId(), eventId: event.id,
            summary: "Add \(guestsDelta) guests. \(event.guests) becomes \(event.guests + guestsDelta).",
            guestsDelta: guestsDelta, impacts: impacts, addedCost: added,
            revisedQuote: revised, perGuest: perGuest,
            status: .pending, requestedAt: Cal.today, via: via
        )
    }

    /// Extra guests are charged a share of the average head rate, not the full one: the fixed costs (stage,
    /// lighting, coordination) are already covered by the original quote.
    static func perGuestRate(for event: Event, rates: Rates = .standard) -> Int {
        max(rates.minimumPerGuest, event.guests == 0 ? rates.fallbackPerGuest : (event.quoted / event.guests) / rates.marginalShare)
    }

    enum Icon {
        static let inventory = "shippingbox"
        static let people = "person.2"
        static let transport = "truck.box"
    }
}
