import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStoreModel
    @ScaledMetric(relativeTo: .body) private var column: CGFloat = 83
    var open: (Modal) -> Void

    private var width: CGFloat { min(column, 108) }
    private var day: LocalDay { LocalDay(at: store.now, zone: store.zone) }
    private var visibleMilestone: Milestone? {
        store.state.milestones.last {
            $0.sheetID == store.sheet.id && !$0.used && $0.dismissedOn != day.key
                && ($0.kind != .week || TrainingState.week(at: store.now, zone: store.zone)?.contains($0.date) == true)
        }
    }

    var body: some View {
        PageHeader(title: L.t("home.title"),
                   subtitle: store.now.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
            Action(title: L.t("import.open"), id: "home.import") { open(.importSheet) }
        }
        if let workout = store.guided, let movement = workout.movement {
            GuidedWorkoutCard(workout: workout, movement: movement, open: open)
        } else {
            if !store.sheet.currentMoves.isEmpty {
                Action(title: L.t("guide.start"), id: "guide.start", style: .prominent) { store.startGuided() }
            }
            weekly
            trainingTable
            if store.state.history.isEmpty {
                Text(L.t("home.emptyHint")).font(.caption).foregroundStyle(Palette.muted)
            }
        }
        if store.guided == nil, let milestone = visibleMilestone {
            HStack(spacing: 4) {
                Text(milestone.headline).font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Action(title: L.t("card.view"), id: "home.milestone") { open(.card(milestone)) }
                Button {
                    store.change { draft in
                        if let index = draft.milestones.firstIndex(where: { $0.id == milestone.id }) {
                            draft.milestones[index].dismissedOn = day.key
                        }
                    }
                } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("card.dismiss"))
                .accessibilityIdentifier("milestone.dismiss")
            }
            .padding(.leading, 12)
            .background(Palette.tint, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var trainingTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.sheet.title).font(.headline).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home.sheet")
                Spacer(minLength: 4)
                if store.current?.entries.isEmpty == false {
                    Action(title: L.t("session.finish"), id: "session.finish") { store.finishSession() }
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            HStack(spacing: 8) {
                Text(L.t("table.movement")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L.t("table.last")).frame(width: width, alignment: .trailing)
                Text(L.t("tab.today")).frame(width: width)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.muted)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            ForEach(store.sheet.groups) { group in
                if let move = group.current {
                    Divider().overlay(Palette.line)
                    row(move, group)
                }
            }
        }
        .panel()
    }

    private var weekly: some View {
        let count = store.state.weeklyCount(at: store.now, zone: store.zone)
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("week.title")).font(.subheadline.weight(.bold)).foregroundStyle(Palette.action)
                Text(L.f("week.count", count, store.state.goal)).font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            ProgressMarks(count: count, total: store.state.goal)
        }
        .accessibilityElement(children: .combine)
        .padding(12)
        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ move: Movement, _ group: MovementGroup) -> some View {
        let current = store.current
        let today = current?.entry(for: move)
        let last = store.state.last(move, excluding: current?.id)
        return VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(move.title).font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        open(.progression(group))
                    } label: {
                        HStack(spacing: 4) {
                            Text(L.t("progress.open")).font(.caption.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(Palette.action)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.f("progress.open.a11y", move.title))
                    .accessibilityIdentifier("progress.\(group.id)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(last?.summary() ?? L.t("value.empty"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: width, alignment: .trailing)
                    .accessibilityLabel(L.f("table.last.a11y", move.title,
                                            last?.summary(spoken: true) ?? L.t("value.none")))
                    .accessibilityIdentifier("last.\(move.id)")
                Button {
                    store.tick()
                    open(.number(move, store.current?.id))
                } label: {
                    Text(today?.summary() ?? L.f("value.add", move.unit.short))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 5)
                        .frame(width: width, alignment: .center)
                        .frame(minHeight: 44)
                        .foregroundStyle(today == nil ? Palette.action : .white)
                        .background(today == nil ? Palette.tint : Palette.action,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.f("table.today.a11y", move.title,
                                        today?.summary(spoken: true) ?? L.t("value.none"),
                                        move.unit.spoken))
                .accessibilityIdentifier("today.\(move.id)")
            }
            if store.state.undo?.movementID == move.id {
                HStack(spacing: 6) {
                    Text(L.t("value.saved")).font(.caption).foregroundStyle(Palette.muted)
                    Action(title: L.t("value.undo"), id: "entry.undo") { store.undoRecord() }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

struct NumberView: View {
    @EnvironmentObject private var store: AppStoreModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var keyboard: Bool
    @State private var text = ""
    @State private var submitted = false
    var movement: Movement
    var sessionID: UUID?

    private var current: Entry? {
        store.state.sessions.first { $0.id == sessionID }?.entry(for: movement)
    }
    private var last: (session: Session, entry: Entry)? {
        store.state.lastPerformance(movement, excluding: sessionID)
    }
    private var previousValue: Int? { current?.sets.last?.value ?? last?.entry.sets.last?.value }
    private var number: Int? {
        guard let value = Int(text), (1...movement.unit.maximum).contains(value) else { return nil }
        return value
    }
    private var suggestion: [Int] {
        if let previousValue, previousValue > 1, previousValue < movement.unit.maximum {
            return [previousValue - 1, previousValue, previousValue + 1]
        }
        return movement.unit == .reps ? [5, 8, 12] : [15, 20, 30]
    }
    private var slider: Binding<Double> {
        Binding(get: { Double(number ?? previousValue ?? suggestion[1]) },
                set: { text = String(Int($0)) })
    }

    private var sliderRange: ClosedRange<Double> {
        let base = previousValue ?? suggestion[1]
        let span = movement.unit == .reps ? 30 : 90
        let maximum = movement.unit.maximum
        var low = max(1, base - span)
        var high = min(maximum, low + span * 2)
        low = max(1, min(low, high - span * 2))
        if let number { low = min(low, max(1, number)); high = max(high, min(maximum, number)) }
        return Double(low)...Double(high)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    PageHeader(title: movement.title, subtitle: lastCaption) {
                        Action(title: L.t("close"), id: "number.close") { dismiss() }
                    }
                    HStack {
                        ForEach(suggestion, id: \.self) { value in
                            Action(title: movement.unit.format(value), id: "number.quick.\(value)", style: .outline) {
                                save(value)
                            }
                        }
                    }
                    HStack {
                        TextField(L.t("number.placeholder"), text: $text)
                            .font(.title2.monospacedDigit())
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($keyboard)
                            .accessibilityLabel(L.f("number.field.label", movement.unit.spoken))
                            .accessibilityIdentifier("number.field")
                            .onChange(of: text) { _, value in
                                let digits = value.compactMap(\.wholeNumberValue).filter { $0 < 10 }
                                let cleaned = digits.prefix(4).map { String($0) }.joined()
                                if cleaned != value { text = cleaned }
                            }
                        Text(movement.unit.spoken).foregroundStyle(Palette.muted)
                    }
                    Slider(value: slider, in: sliderRange, step: 1)
                        .accessibilityLabel(L.f("number.field.label", movement.unit.spoken))
                        .accessibilityIdentifier("number.slider")
                    HStack {
                        Action(title: L.t("number.removeSet"), id: "number.clear", style: .outline) { save(nil) }
                            .disabled(current == nil)
                        Action(title: L.t("number.saveSet"), id: "number.save", style: .prominent) {
                            if let number { save(number) }
                        }
                        .disabled(number == nil)
                    }
                }
                .page()
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Action(title: L.t("done"), id: "number.keyboard.done") { keyboard = false }
                }
            }
        }
        .disabled(submitted)
        .onAppear {
            let value = previousValue ?? suggestion[1]
            text = String(value)
        }
    }

    private var lastCaption: String {
        guard let last else { return L.f("table.last.value", L.t("value.empty")) }
        let day = last.session.day.label(at: last.session.startedAt)
        let detail = "\(last.entry.summary()) · \(day)"
        return L.f("table.last.value", detail)
    }

    private func save(_ value: Int?) {
        guard !submitted else { return }
        submitted = true
        store.record(value, movement: movement, sessionID: sessionID)
        dismiss()
    }
}

struct ProgressionView: View {
    @EnvironmentObject private var store: AppStoreModel
    @Environment(\.dismiss) private var dismiss
    @State private var expandedID: String?
    var groupID: String

    var body: some View {
        ScrollView {
            if let group = store.sheet.groups.first(where: { $0.id == groupID }) {
                let count = group.moves.filter { isMastered($0) }.count
                VStack(alignment: .leading, spacing: 13) {
                    PageHeader(title: L.f("progress.title", group.title), subtitle: L.t("progress.subtitle")) {
                        Action(title: L.t("done"), id: "progress.done") { dismiss() }
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L.f("progress.count", count, group.moves.count))
                                .font(.subheadline.weight(.bold)).foregroundStyle(Palette.action)
                            Text(L.t("progress.order")).font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        if group.moves.count <= 6 { ProgressMarks(count: count, total: group.moves.count) }
                    }
                    .accessibilityElement(children: .combine)
                    .padding(12)
                    .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14))
                    VStack(spacing: 0) {
                        ForEach(group.moves) { move in
                            progressionRow(move, group: group)
                            if move.id != group.moves.last?.id { Divider().overlay(Palette.line) }
                        }
                    }
                    .panel()
                }
                .page()
            }
        }
    }

    private func progressionRow(_ move: Movement, group: MovementGroup) -> some View {
        let expanded = expandedID == move.id
        return VStack(alignment: .leading, spacing: 0) {
            progressionControls(move, group: group, expanded: expanded)
            if expanded {
                MovementDemonstration(movement: move)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .background(group.current?.id == move.id ? Palette.tint.opacity(0.6) : Color.clear)
    }

    private func progressionControls(_ move: Movement, group: MovementGroup, expanded: Bool) -> some View {
        let mastered = isMastered(move)
        let used = group.current?.id == move.id
        return HStack(alignment: .center, spacing: 6) {
            Button {
                store.change { $0.toggleMastery(move, at: store.now) }
            } label: {
                Image(systemName: mastered ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(Palette.action)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.f("progress.master.a11y", move.title))
            .accessibilityValue(L.t(mastered ? "progress.mastered" : "progress.unchecked"))
            .accessibilityIdentifier("master.\(move.id)")
            Button {
                expandedID = expanded ? nil : move.id
            } label: {
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(move.title).font(.subheadline.weight(.semibold))
                        if used { Text(L.t("progress.current")).font(.caption.bold()).foregroundStyle(Palette.action) }
                        if mastered { Text(L.t("progress.mastered")).font(.caption).foregroundStyle(Palette.action) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Palette.action)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L.t(expanded ? "demo.close" : "demo.open"))
            .accessibilityIdentifier("demo.toggle.\(move.id)")
            if !used {
                Action(title: L.t("progress.use"), id: "use.\(move.id)") {
                    store.updateSheet { sheet in
                        if let index = sheet.groups.firstIndex(where: { $0.id == groupID }) {
                            sheet.groups[index].currentID = move.id
                        }
                    }
                }
                .accessibilityLabel(L.f("progress.use.a11y", move.title))
            }
        }
        .padding(.horizontal, 5)
    }

    private func isMastered(_ move: Movement) -> Bool {
        store.state.mastery.contains(TrainingState.masteryKey(move, sheetID: store.sheet.id))
    }
}
