import SwiftUI

/// C1 · Receivables — Overdue always renders first regardless of chronology.
struct ReceivablesView: View {
    @Environment(AppStore.self) private var store
    @State private var reminder: Milestone?

    var body: some View {
        let open = store.openMilestones
        ScreenScaffold(title: "Receivables", subtitle: open.isEmpty ? "All paid up" : "\(store.eventsWithOpenMoney) events · \(open.count) open milestones", isRoot: true, spacing: Space.lg) {
            if open.isEmpty {
                EmptyState(headline: store.upcomingEvents.isEmpty ? "Nothing to collect yet" : "Nothing outstanding",
                           line: store.upcomingEvents.isEmpty ? "Milestones appear here as soon as you book an event." : "Every milestone across your \(store.upcomingEvents.count) events is paid up.",
                           actionTitle: store.upcomingEvents.isEmpty ? "Create event" : "View payment schedules", actionIcon: store.upcomingEvents.isEmpty ? "plus" : nil, primary: store.upcomingEvents.isEmpty) {
                    if let e = store.upcomingEvents.first { store.push(.paymentSchedule(e.id)) } else { store.push(.createEvent, in: .events) }
                }
                .padding(.top, 160)
            } else {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Total outstanding across \(store.eventsWithOpenMoney) event\(store.eventsWithOpenMoney == 1 ? "" : "s")").type(.caption).foregroundStyle(MColor.textMute)
                    Text(Fmt.inr(store.totalOutstanding)).type(.displayHero).foregroundStyle(MColor.text)
                    if store.overdueTotal > 0 {
                        HStack(spacing: Space.xs) {
                            Image(systemName: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(MColor.danger)
                            Text("\(Fmt.inr(store.overdueTotal)) overdue · \(store.overdueSurnames)").type(.caption).foregroundStyle(MColor.danger)
                        }
                    }
                }
                .padding(.bottom, Space.md)

                group("Overdue", store.overdue, action: true)
                group("Due this week", store.dueThisWeek)
                group("Upcoming", store.upcomingMilestones)
            }
        }
        .sheet(item: $reminder) { m in SendReminderSheet(milestone: m).presentationDetents([.large]) }
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [Milestone], action: Bool = false) -> some View {
        if !list.isEmpty {
            VStack(spacing: Space.md) {
                SectionHeading(title: title, trailing: "\(Fmt.inr(list.reduce(0) { $0 + $1.amount })) · \(list.count)")
                RowGroup {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { Hairline() }
                        let e = store.event(m.eventId)
                        PaymentRow(milestone: m, title: e?.name ?? m.name, subtitle: subtitle(m), subtitleColor: m.effectiveStatus == .overdue ? MColor.danger : MColor.textMute,
                                   trailingAction: action ? { reminder = m } : nil) { store.push(.paymentSchedule(m.eventId)) }
                    }
                }
            }
        }
    }
    private func subtitle(_ m: Milestone) -> String {
        m.effectiveStatus == .overdue ? "\(m.kind.label) · \(Fmt.daysLate(m.due)) days late" : "\(m.kind.label) · \(Fmt.weekdayDayMonth.string(from: m.due))"
    }
}

/// C2 · Event payment schedule — collection progress, milestone rows, add milestone, record payment docked.
struct PaymentScheduleView: View {
    @Environment(AppStore.self) private var store
    var eventId: String
    @State private var record: Milestone?
    @State private var addMilestone = false
    @State private var newName = ""
    @State private var newAmount = 0
    @State private var newDue = Cal.startOfDay(Cal.today)
    @State private var showDue = false

    var body: some View {
        if let e = store.event(eventId) {
            let ms = store.milestones(for: eventId)
            let collected = store.collected(for: eventId)
            let overdue = store.overdueAmount(for: eventId)
            let pct = e.quoted == 0 ? 0 : Int((Double(collected) / Double(e.quoted) * 100).rounded())
            ScreenScaffold(title: "Payment schedule", subtitle: "\(e.name) · \(Fmt.weekdayLong.string(from: e.start))", spacing: Space.lg, bottomPadding: 100) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Collected").type(.caption).foregroundStyle(MColor.textMute)
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(Fmt.inr(collected)).type(.displayMd).foregroundStyle(MColor.text)
                        Text("of \(Fmt.inr(e.quoted)) · \(pct)%").type(.caption).foregroundStyle(MColor.textMute)
                    }
                    ProgressBar(fraction: Double(collected) / Double(max(1, e.quoted)))
                    Text("\(Fmt.inr(max(0, e.quoted - collected))) to collect" + (overdue > 0 ? " · \(Fmt.inr(overdue)) overdue" : "")).type(.caption).foregroundStyle(MColor.textMute)
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                RowGroup {
                    ForEach(Array(ms.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { Hairline() }
                        PaymentRow(milestone: m, subtitle: paymentSubtitle(m), subtitleColor: m.effectiveStatus == .overdue ? MColor.danger : MColor.textMute, action: { if m.isOpen { record = m } })
                    }
                    if !ms.isEmpty { Hairline() }
                    Button { newDue = e.day; addMilestone = true } label: {
                        HStack(spacing: Space.sm) { Image(systemName: "plus").font(.system(size: 14)); Text("Add milestone").type(.buttonSm) }
                            .foregroundStyle(MColor.accentText).padding(.horizontal, Space.lg).frame(height: Dim.row).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .dockedActions {
                MButton(title: "Record payment", icon: "indianrupeesign") { record = ms.first(where: \.isOpen) }.disabled(!ms.contains(where: \.isOpen))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Expenses and margin", systemImage: "chart.bar") { store.push(.expenses(eventId)) }
                        Button("Open event", systemImage: "calendar") { store.push(.eventDetail(eventId)) }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            .sheet(item: $record) { m in RecordPaymentSheet(milestone: m).presentationDetents([.large]) }
            .sheet(isPresented: $addMilestone) {
                SheetScaffold(title: "Add milestone", subtitle: e.name) {
                    InputField(label: "Name", text: $newName, placeholder: "Third instalment")
                    PickerField(label: "Due", value: Fmt.weekdayLongYear.string(from: newDue), trailing: "calendar") { showDue = true }
                    AmountInput(amount: newAmount, label: "Amount")
                    NumericKeypad(amount: $newAmount)
                } actions: {
                    MButton(title: "Add milestone") {
                        store.addMilestone(eventId: eventId, name: newName.trimmingCharacters(in: .whitespaces), amount: newAmount, due: newDue)
                        newName = ""; newAmount = 0; addMilestone = false
                    }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newAmount == 0)
                }
                .presentationDetents([.large])
                .sheet(isPresented: $showDue) {
                    SheetScaffold(title: "Due date") {
                        DatePicker("Due", selection: $newDue, displayedComponents: .date).datePickerStyle(.graphical).tint(MColor.accent).environment(\.calendar, Cal.calendar)
                    } actions: { MButton(title: "Done") { showDue = false } }
                    .presentationDetents([.large])
                }
            }
        }
    }
}

/// C3 · Record payment — completable in under 20 seconds while the money changes hands. Sheet, large detent.
struct RecordPaymentSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var milestone: Milestone
    @State private var amount: Int = 0
    @State private var method: PaymentMethod = .upi
    @State private var date = Cal.today
    @State private var reference = ""
    @State private var showReference = false
    @State private var showDate = false

    var body: some View {
        let e = store.event(milestone.eventId)
        SheetScaffold(title: "Record payment", subtitle: "\(e?.name ?? "") · \(Fmt.inr(store.balanceDue(for: milestone.eventId))) balance due") {
            AmountInput(amount: amount, error: amount > milestone.amount ? "More than the \(Fmt.inr(milestone.amount)) due on this milestone" : nil)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.sm), GridItem(.flexible(), spacing: Space.sm)], spacing: Space.sm) {
                ForEach(PaymentMethod.allCases) { m in
                    Button { withAnimation(.snappy(duration: 0.15)) { method = m } } label: {
                        Text(m.label).type(.buttonSm)
                            .foregroundStyle(method == m ? MColor.accentSoftText : MColor.accentText)
                            .frame(maxWidth: .infinity).frame(height: Dim.buttonCompact)
                            .background(method == m ? MColor.accentSoftBg : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(method == m ? Color.clear : MColor.accentText, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { showDate = true } label: {
                ListRow(title: Cal.sameDay(date, Cal.today) ? "Today, \(Fmt.weekdayDayMonth.string(from: date))" : Fmt.weekdayLong.string(from: date), subtitle: "Date received") {
                    IconTile(symbol: "calendar")
                } trailing: { Chevron() }
                .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(MColor.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            if showReference {
                InputField(label: "Reference", text: $reference, placeholder: "UTR or cheque number")
            } else {
                Button { withAnimation { showReference = true } } label: {
                    HStack(spacing: Space.sm) { Image(systemName: "plus").font(.system(size: 14)); Text("Add reference").type(.buttonSm) }.foregroundStyle(MColor.accentText)
                }.buttonStyle(.plain)
            }
            NumericKeypad(amount: $amount)
        } actions: {
            MButton(title: amount > 0 ? "Record \(Fmt.inr(amount))" : "Record payment") {
                store.recordPayment(milestoneId: milestone.id, amount: amount, method: method, date: date, reference: reference.isEmpty ? nil : reference)
                dismiss()
            }
            .disabled(amount == 0 || amount > milestone.amount)
        }
        .onAppear { amount = milestone.amount }
        .sheet(isPresented: $showDate) {
            SheetScaffold(title: "Date received") {
                DatePicker("Date", selection: $date, in: ...Cal.today, displayedComponents: .date).datePickerStyle(.graphical).tint(MColor.accent).environment(\.calendar, Cal.calendar)
            } actions: { MButton(title: "Done") { showDate = false } }
            .presentationDetents([.large])
        }
    }
}

/// C4 · Send reminder — tone selector with real composed copy, channel picker, history of what was sent before.
struct SendReminderSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var milestone: Milestone
    @State private var tone: ReminderTone = .standard
    @State private var channel: ReminderChannel = .whatsapp
    @State private var message = ""
    @State private var edited = false
    @FocusState private var editing: Bool

    var body: some View {
        let e = store.event(milestone.eventId)
        let client = e.flatMap { store.client(for: $0) }
        SheetScaffold(title: "Send reminder", subtitle: "\(milestone.name) · \(Fmt.inr(milestone.amount)) · \(Fmt.daysLate(milestone.due)) days late") {
            if let client, let e {
                HStack(spacing: Space.md) {
                    Avatar(index: client.avatar, name: client.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name).type(.bodyMdStrong).foregroundStyle(MColor.text)
                        Text("\(e.name) · \(Fmt.weekdayDayMonth.string(from: e.start)) · \(client.phone.isEmpty ? "no phone" : client.phone)").type(.caption).foregroundStyle(MColor.textMute)
                    }
                    Spacer()
                }
                .card(padding: Space.md)
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Tone").type(.caption).foregroundStyle(MColor.textMute)
                SegmentedControl(items: ReminderTone.allCases, label: \.label, selection: $tone)
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Message").type(.caption).foregroundStyle(MColor.textMute)
                TextEditor(text: $message)
                    .type(.bodyMd).foregroundStyle(MColor.text).scrollContentBackground(.hidden).focused($editing)
                    .frame(minHeight: 120).padding(Space.sm)
                    .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(editing ? MColor.accent : MColor.lineInput, lineWidth: 1))
                    .onChange(of: message) { _, _ in if editing { edited = true } }
                HStack(spacing: Space.xs) {
                    Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(MColor.textMute)
                    Text("\(edited ? "Edited" : "Tap to edit") · \(message.count) characters").type(.caption).foregroundStyle(MColor.textMute)
                }
            }
            let history = store.reminders(for: milestone.id)
            if !history.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Sent before").type(.caption).foregroundStyle(MColor.textMute)
                    RowGroup {
                        ForEach(Array(history.enumerated()), id: \.element.id) { i, r in
                            if i > 0 { Hairline() }
                            ListRow(title: "\(r.tone.label) · \(Fmt.weekdayDayMonthTime.string(from: r.sentAt))", subtitle: "\(r.channel.label) · \(r.outcome)") {
                                IconTile(symbol: r.channel == .whatsapp ? "bubble" : "paperplane")
                            } trailing: { EmptyView() }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Send via").type(.caption).foregroundStyle(MColor.textMute)
                SegmentedControl(items: ReminderChannel.allCases, label: \.label, selection: $channel)
            }
        } actions: {
            MButton(title: "Send on \(channel.label)", icon: "paperplane") {
                store.sendReminder(milestoneId: milestone.id, tone: tone, channel: channel)
                let phone = Fmt.phoneDigits(client?.phone ?? "")
                let text = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let url = channel == .whatsapp ? "https://wa.me/\(phone)?text=\(text)" : "sms:+\(phone)&body=\(text)"
                if !phone.isEmpty, let u = URL(string: url) { UIApplication.shared.open(u) }
                dismiss()
            }
        }
        .onAppear { message = store.reminderMessage(for: milestone, tone: tone) }
        .onChange(of: tone) { _, new in edited = false; message = store.reminderMessage(for: milestone, tone: new) }
    }
}

/// C5 · Event expenses — margin as a large figure; loss state gets the danger treatment.
struct ExpensesView: View {
    @Environment(AppStore.self) private var store
    var eventId: String
    @State private var addSheet = false

    var body: some View {
        if let e = store.event(eventId) {
            let expenses = store.expenses(for: eventId)
            let total = expenses.reduce(0) { $0 + $1.amount }
            let margin = e.quoted - total
            let loss = margin < 0
            let pct = e.quoted == 0 ? 0 : Double(margin) / Double(e.quoted) * 100
            ScreenScaffold(title: "Expenses", subtitle: "\(e.name) · \(Fmt.weekdayLong.string(from: e.start))", spacing: Space.lg, bottomPadding: 100) {
                if expenses.isEmpty {
                    EmptyState(headline: "No expenses logged", line: "Add flowers, crew wages, hire and transport as they come in to see the real margin.", actionTitle: "Add expense", actionIcon: "plus", primary: true) { addSheet = true }
                        .padding(.vertical, Space.xl)
                } else {
                    RowGroup {
                        ForEach(Array(expenses.enumerated()), id: \.element.id) { i, x in
                            if i > 0 { Hairline() }
                            ListRow(title: x.name, subtitle: x.detail.isEmpty ? nil : x.detail) { EmptyView() } trailing: { Money(x.amount) }
                                .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { store.deleteExpense(x.id) } }
                        }
                        Hairline()
                        ListRow(title: "Total cost", subtitle: "\(expenses.count) entr\(expenses.count == 1 ? "y" : "ies")") { EmptyView() } trailing: { Money(total) }
                            .background(MColor.surfacePressed)
                    }
                }

                VStack(alignment: .leading, spacing: Space.md) {
                    row("Quoted", e.quoted)
                    row("Total cost", total)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Margin").type(.caption).foregroundStyle(MColor.textMute)
                        Text(Fmt.inr(margin)).type(.displayHero).foregroundStyle(loss ? MColor.danger : MColor.text)
                    }
                    HStack(spacing: Space.md) {
                        if loss { StatusChip(kind: .loss) }
                        Text(loss ? String(format: "−%.1f%% · costs exceed the quote", abs(pct)) : String(format: "%.1f%% margin on the quote", pct)).type(.caption).foregroundStyle(MColor.textMute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(fill: loss ? MColor.dangerTint : MColor.surface)
            }
            .dockedActions { MButton(title: "Add expense", icon: "plus", style: .secondary) { addSheet = true } }
            .sheet(isPresented: $addSheet) { ExpenseSheet(eventId: eventId) }
        }
    }
    private func row(_ label: String, _ amount: Int) -> some View {
        HStack { Text(label).type(.bodyMd).foregroundStyle(MColor.textMute); Spacer(); Money(amount) }
    }
}
