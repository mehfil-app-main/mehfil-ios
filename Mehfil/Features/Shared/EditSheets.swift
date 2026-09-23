import SwiftUI

// Sheets that create or edit records. Each saves through the store and dismisses itself.

struct CrewMemberSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var existing: CrewMember?
    @State private var name = ""
    @State private var role: CrewRole = .helper
    @State private var isLead = false
    @State private var rate = ""
    @State private var confirmDelete = false

    var body: some View {
        SheetScaffold(title: existing == nil ? "Add crew member" : "Edit crew member", subtitle: existing.map { "\($0.bookings.count) bookings" }) {
            InputField(label: "Name", text: $name, placeholder: "Suresh Yadav")
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Role").type(.caption).foregroundStyle(MColor.textMute)
                SegmentedControl(items: CrewRole.allCases, label: \.label, selection: $role)
            }
            InputField(label: "Day rate", text: $rate, placeholder: "\(role.defaultDayRate)", keyboard: .numberPad)
            Toggle(isOn: $isLead) { Text("Team lead").type(.bodyMd).foregroundStyle(MColor.text) }.tint(MColor.accent)
            if existing != nil {
                MButton(title: "Remove from roster", style: .destructive, size: .compact) { confirmDelete = true }
            }
        } actions: {
            MButton(title: existing == nil ? "Add to roster" : "Save") {
                let m = CrewMember(id: existing?.id ?? Cal.newId(), name: name.trimmingCharacters(in: .whitespaces), role: role, isLead: isLead,
                                   dayRate: Int(rate) ?? role.defaultDayRate, avatar: existing?.avatar, bookings: existing?.bookings ?? [], note: existing?.note)
                store.saveCrewMember(m); dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { if let e = existing { name = e.name; role = e.role; isLead = e.isLead; rate = String(e.dayRate) } }
        .confirmationDialog("Remove \(existing?.name ?? "") from the roster?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let e = existing { store.deleteCrewMember(e.id) }; dismiss() }
        }
        .presentationDetents([.large])
    }
}

struct InventoryItemSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var existing: InventoryItem?
    @State private var name = ""
    @State private var total = ""
    @State private var detail = ""
    @State private var confirmDelete = false

    var body: some View {
        SheetScaffold(title: existing == nil ? "Add item" : "Edit stock", subtitle: existing.map { "\($0.holds.count) holds" }) {
            InputField(label: "Item", text: $name, placeholder: "Chiavari chairs")
            InputField(label: "Total in stock", text: $total, placeholder: "600", keyboard: .numberPad)
            InputField(label: "Detail", text: $detail, placeholder: "Gold · with cushions")
            if existing != nil { MButton(title: "Remove item", style: .destructive, size: .compact) { confirmDelete = true } }
        } actions: {
            MButton(title: existing == nil ? "Add item" : "Save") {
                let item = InventoryItem(id: existing?.id ?? Cal.newId(), name: name.trimmingCharacters(in: .whitespaces), total: Int(total) ?? 0, detail: detail, holds: existing?.holds ?? [])
                store.saveItem(item); dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (Int(total) ?? 0) <= 0)
        }
        .onAppear { if let e = existing { name = e.name; total = String(e.total); detail = e.detail } }
        .confirmationDialog("Remove \(existing?.name ?? "")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let e = existing { store.deleteItem(e.id) }; dismiss() }
        }
        .presentationDetents([.large])
    }
}

/// Hold quantities of every item for one event (B2 → Inventory).
struct EventHoldsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var event: Event
    @State private var qty: [String: Int] = [:]

    var body: some View {
        SheetScaffold(title: "Inventory for \(event.name)", subtitle: "\(Fmt.weekdayDayMonth.string(from: event.start)) · what this event holds") {
            if store.inventory.isEmpty {
                EmptyState(headline: "No inventory yet", line: "Add items from Team → Inventory first.")
            } else {
                RowGroup {
                    ForEach(Array(store.inventory.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Hairline() }
                        let held = qty[item.id] ?? 0
                        let others = item.committed(on: event.day) - (item.holds.first { $0.eventId == event.id }?.qty ?? 0)
                        HStack(spacing: Space.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).type(.bodyMdStrong).foregroundStyle(MColor.text)
                                Text("\(others + held) of \(item.total) on this date").type(.caption).foregroundStyle(others + held > item.total ? MColor.danger : MColor.textMute)
                            }
                            Spacer()
                            MStepper(value: Binding(get: { held }, set: { qty[item.id] = $0 }), range: 0...(item.total * 2), step: item.total >= 100 ? 10 : 1)
                        }
                        .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
                    }
                }
            }
        } actions: {
            MButton(title: "Save holds") {
                for item in store.inventory { store.setHold(itemId: item.id, eventId: event.id, qty: qty[item.id] ?? 0) }
                dismiss()
            }
        }
        .onAppear { for item in store.inventory { qty[item.id] = item.holds.first { $0.eventId == event.id }?.qty ?? 0 } }
        .presentationDetents([.large])
    }
}

struct ExpenseSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var eventId: String
    @State private var name = ""
    @State private var detail = ""
    @State private var amount = 0

    var body: some View {
        SheetScaffold(title: "Add expense", subtitle: store.event(eventId)?.name) {
            InputField(label: "What", text: $name, placeholder: "Flowers")
            InputField(label: "Detail", text: $detail, placeholder: "Marigold, roses · Ghazipur mandi")
            AmountInput(amount: amount, label: "Amount")
            NumericKeypad(amount: $amount)
        } actions: {
            MButton(title: amount > 0 ? "Add \(Fmt.inr(amount))" : "Add expense") { store.addExpense(eventId: eventId, name: name.trimmingCharacters(in: .whitespaces), detail: detail, amount: amount); dismiss() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount == 0)
        }
        .presentationDetents([.large])
    }
}

struct PackageSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var existing: Package?
    @State private var name = ""
    @State private var detail = ""
    @State private var price = 0
    @State private var confirmDelete = false

    var body: some View {
        SheetScaffold(title: existing == nil ? "New package" : "Edit package") {
            InputField(label: "Name", text: $name, placeholder: "Stage & backdrop")
            InputField(label: "What's included", text: $detail, placeholder: "12 m truss, 40 par cans")
            AmountInput(amount: price, label: "Price")
            NumericKeypad(amount: $price)
            if existing != nil { MButton(title: "Delete package", style: .destructive, size: .compact) { confirmDelete = true } }
        } actions: {
            MButton(title: "Save") { store.savePackage(Package(id: existing?.id ?? Cal.newId(), name: name.trimmingCharacters(in: .whitespaces), detail: detail, price: price)); dismiss() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || price == 0)
        }
        .onAppear { if let e = existing { name = e.name; detail = e.detail; price = e.price } }
        .confirmationDialog("Delete \(existing?.name ?? "")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let e = existing { store.deletePackage(e.id) }; dismiss() }
        }
        .presentationDetents([.large])
    }
}

struct BusinessProfileSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var owner = ""
    @State private var business = ""
    @State private var phone = ""
    @State private var area = ""
    @State private var since = ""
    @State private var target = ""

    var body: some View {
        SheetScaffold(title: "Business details") {
            InputField(label: "Business name", text: $business)
            InputField(label: "Your name", text: $owner)
            PhoneField(text: $phone, helper: "Shown to clients on the page you share with them.")
            InputField(label: "Area", text: $area, placeholder: "Sector 44, Gurugram")
            InputField(label: "Operating since", text: $since, placeholder: "since 2018")
            InputField(label: "Season target (₹)", text: $target, placeholder: "6000000", helper: "The bar on the season summary measures bookings against this.", keyboard: .numberPad)
        } actions: {
            MButton(title: "Save") {
                store.updateProfile { p in
                    p.businessName = business.trimmingCharacters(in: .whitespaces); p.ownerName = owner.trimmingCharacters(in: .whitespaces)
                    p.phone = phone; p.area = area; p.since = since; p.seasonTarget = Int(target.filter(\.isNumber)) ?? p.seasonTarget
                }
                dismiss()
            }
            .disabled(business.trimmingCharacters(in: .whitespaces).isEmpty || owner.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { if let v = store.vendor { owner = v.ownerName; business = v.businessName; phone = v.phone; area = v.area; since = v.since; target = String(v.seasonTarget) } }
        .presentationDetents([.large])
    }
}

struct PaymentDetailsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var upi = ""
    @State private var bank = ""

    var body: some View {
        SheetScaffold(title: "Payment details", subtitle: "Shown to clients on the shared page and in reminders.") {
            InputField(label: "UPI ID", text: $upi, placeholder: "mehfil@upi")
            InputField(label: "Bank account label", text: $bank, placeholder: "HDFC ••4471", helper: "Only a label — never store the full account number here.")
        } actions: {
            MButton(title: "Save") { store.updateProfile { $0.upi = upi.trimmingCharacters(in: .whitespaces); $0.bankLabel = bank.trimmingCharacters(in: .whitespaces) }; dismiss() }
        }
        .onAppear { if let v = store.vendor { upi = v.upi; bank = v.bankLabel } }
        .presentationDetents([.medium])
    }
}

struct NotificationsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var store = store
        SheetScaffold(title: "Notifications", subtitle: "What Mehfil should raise on the home screen.") {
            RowGroup {
                toggle("Payments", "Overdue and due-this-week milestones", store.vendor?.notifyPayments ?? true) { v in store.updateProfile { $0.notifyPayments = v } }
                Hairline()
                toggle("Conflicts", "Crew or inventory double-booked", store.vendor?.notifyConflicts ?? true) { v in store.updateProfile { $0.notifyConflicts = v } }
                Hairline()
                toggle("Change requests", "Guest count or scope changes from clients", store.vendor?.notifyChanges ?? true) { v in store.updateProfile { $0.notifyChanges = v } }
            }
        } actions: { MButton(title: "Done") { dismiss() } }
        .presentationDetents([.medium])
    }
    @MainActor
    private func toggle(_ title: String, _ subtitle: String, _ value: Bool, _ set: @escaping @MainActor (Bool) -> Void) -> some View {
        // Binding stores its setter, so SwiftUI requires it to be Sendable. The work inside touches the
        // main-actor store, which `MainActor.assumeIsolated` states explicitly: a Binding's setter is only
        // ever invoked from the main actor during a view update.
        Toggle(isOn: Binding(get: { value }, set: { newValue in MainActor.assumeIsolated { set(newValue) } })) {
            VStack(alignment: .leading, spacing: 2) { Text(title).type(.bodyMdStrong).foregroundStyle(MColor.text); Text(subtitle).type(.caption).foregroundStyle(MColor.textMute) }
        }
        .tint(MColor.accent).padding(.horizontal, Space.lg).padding(.vertical, Space.md)
    }
}

struct ClientSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var client: Client
    @State private var name = ""
    @State private var phone = ""
    @State private var isRepeat = false
    var body: some View {
        SheetScaffold(title: "Edit client") {
            InputField(label: "Name", text: $name)
            PhoneField(text: $phone)
            Toggle(isOn: $isRepeat) { Text("Repeat client").type(.bodyMd).foregroundStyle(MColor.text) }.tint(MColor.accent)
        } actions: {
            MButton(title: "Save") { var c = client; c.name = name.trimmingCharacters(in: .whitespaces); c.phone = phone; c.isRepeat = isRepeat; store.updateClient(c); dismiss() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { name = client.name; phone = client.phone; isRepeat = client.isRepeat }
        .presentationDetents([.medium])
    }
}

/// Logs a client's change request and computes what it moves (B6).
struct LogChangeRequestSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var event: Event
    var onLogged: (ChangeRequest) -> Void
    @State private var delta = 50
    @State private var via = "WhatsApp"
    private let channels = ["WhatsApp", "Call", "In person"]
    private struct Choice: Identifiable, Hashable { var id: String }

    var body: some View {
        SheetScaffold(title: "Log a change request", subtitle: "\(event.name) · \(event.guests) guests today") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add guests").type(.bodyMd).foregroundStyle(MColor.text)
                    Text("\(event.guests) becomes \(event.guests + delta)").type(.caption).foregroundStyle(MColor.textMute)
                }
                Spacer()
                MStepper(value: $delta, range: 10...2000, step: 10)
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Asked via").type(.caption).foregroundStyle(MColor.textMute)
                SegmentedControl(items: channels.map { Choice(id: $0) }, label: \.id, selection: Binding(get: { Choice(id: via) }, set: { via = $0.id }))
            }
            Text("Mehfil works out the chairs, tables, helpers and transport the change needs from your holds and roster, then shows the revised quote.")
                .type(.caption).foregroundStyle(MColor.textMute)
        } actions: {
            MButton(title: "See what it moves") { if let cr = store.logChangeRequest(eventId: event.id, guestsDelta: delta, via: via) { dismiss(); onLogged(cr) } }
        }
        .presentationDetents([.medium])
    }
}
