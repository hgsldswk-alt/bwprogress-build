import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStoreModel
    var open: (Modal) -> Void

    var body: some View {
        let sessions = store.state.history
        PageHeader(title: L.t("tab.history"), subtitle: nil) {
            ShareControl(title: L.t("history.export"), id: "history.export", style: .plain) {
                (.init(("\u{feff}" + TrainingCSV.render(sessions)).utf8), L.t("csv.filename") + ".csv")
            }
            .disabled(sessions.isEmpty)
        }
        if sessions.isEmpty { Text(L.t("history.empty")).foregroundStyle(Palette.muted).padding(.vertical, 22) }
        if !store.state.milestones.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(store.state.milestones.reversed())) { milestone in
                    HStack {
                        Text(milestone.headline).font(.subheadline.weight(.semibold))
                        Spacer()
                        Action(title: L.t("card.history"), id: "history.card") { open(.card(milestone)) }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .panel()
        }
        let days = Dictionary(grouping: sessions) { $0.day.key }
        ForEach(days.keys.sorted(by: >), id: \.self) { key in
            if let daySessions = days[key], let first = daySessions.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text(first.day.label(at: first.startedAt))
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(daySessions) { session in
                            sessionRow(session)
                            if session.id != daySessions.last?.id { Divider().overlay(Palette.line) }
                        }
                    }
                    .panel()
                }
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        Button {
            open(.history(session))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title).font(.subheadline.weight(.semibold))
                    Text(session.day.label(at: session.startedAt, timeOnly: true))
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(L.f("history.movements", session.entries.count))
                    .font(.caption).foregroundStyle(Palette.muted)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.action).accessibilityHidden(true)
            }
            .padding(12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history.session")
    }
}

struct SessionView: View {
    @EnvironmentObject private var store: AppStoreModel
    @Environment(\.dismiss) private var dismiss
    var sessionID: UUID

    var body: some View {
        ScrollView {
            if let session = store.state.sessions.first(where: { $0.id == sessionID }) {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader(title: session.title, subtitle: session.day.label(at: session.startedAt)) {
                        Action(title: L.t("done"), id: "history.done") { dismiss() }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(session.entries) { entry in
                            HStack {
                                Text(entry.movement.title).font(.body.weight(.semibold))
                                Spacer()
                                Text(entry.summary()).font(.body.monospacedDigit())
                                    .multilineTextAlignment(.trailing)
                                    .accessibilityLabel(entry.summary(spoken: true))
                                    .accessibilityIdentifier("history.sets.\(entry.movement.id)")
                            }
                            .padding(12)
                            if entry.id != session.entries.last?.id { Divider().overlay(Palette.line) }
                        }
                    }
                    .panel()
                }
                .page()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStoreModel
    var open: (Modal) -> Void

    var body: some View {
        PageHeader(title: L.t("tab.settings"), subtitle: nil) { EmptyView() }
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: Binding(get: { store.state.goal }, set: { goal in
                store.change { $0.changeGoal(goal) }
            }), in: 1...7) {
                Text(L.f("settings.goal", store.state.goal)).font(.headline)
            }
            .accessibilityIdentifier("settings.goal")
            Text(L.t("settings.weekStart")).font(.caption).foregroundStyle(Palette.muted)
        }
        .padding(12).panel()

        RestSettings(timer: store.rest)

        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("settings.sheets")).font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(store.state.sheets) { sheet in
                HStack {
                    Text(sheet.title)
                    Spacer()
                    if sheet.id == store.state.activeSheetID {
                        Text(L.t("settings.active")).font(.caption.weight(.semibold)).foregroundStyle(Palette.action)
                    } else {
                        Action(title: L.t("settings.activate"), id: "settings.sheet.\(sheet.id)") { store.activate(sheet) }
                    }
                }
            }
            Action(title: L.t("settings.add"), id: "settings.new", style: .outline) {
                open(store.pro ? .editor(true) : .paywall)
            }
            Action(title: L.t("settings.edit"), id: "settings.edit", style: .outline) {
                open(store.pro ? .editor(false) : .paywall)
            }
        }
        .padding(12).panel()

        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("settings.widget")).font(.headline).accessibilityAddTraits(.isHeader)
            Text(L.t("settings.widget.help")).font(.caption).foregroundStyle(Palette.muted)
            if store.pro {
                Picker(selection: Binding<String?>(get: {
                    let pin = store.state.pinID
                    return store.sheet.currentMoves.contains { $0.id == pin } ? pin : nil
                }, set: { id in store.change { $0.pinID = id } })) {
                    Text(L.t("settings.widget.auto")).tag(nil as String?)
                    ForEach(store.sheet.currentMoves) { move in Text(move.title).tag(Optional(move.id)) }
                } label: {
                    Text(L.t("settings.widget.pin"))
                }
                .accessibilityIdentifier("settings.widget.pin")
                .frame(minHeight: 44)
            } else {
                Action(title: L.t("settings.widget.pin"), id: "settings.widget.locked", style: .outline) { open(.paywall) }
            }
        }
        .padding(12).panel()

        Action(title: L.t("settings.share"), id: "settings.customCard", style: .outline) {
            if store.pro {
                open(.card(Milestone(id: UUID().uuidString, kind: .custom, date: store.now, sheetID: store.sheet.id)))
            } else {
                open(.paywall)
            }
        }
        Action(title: L.t("settings.pro"), id: "settings.pro", style: .outline) { open(.paywall) }
        if Launch.testing {
            Action(title: L.t("testing.advance"), id: "testing.advance") { store.advanceTestDay() }
        }
    }
}

struct SheetEditor: View {
    @EnvironmentObject private var store: AppStoreModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrainingSheet?
    @State private var newName = ""
    @State private var unit: Measurement = .reps
    @State private var groupID = ""
    var isNew: Bool

    private var cleanedName: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: L.t(isNew ? "settings.add" : "settings.edit"), subtitle: nil) {
                    Action(title: L.t("close"), id: "editor.close") { dismiss() }
                }
                if let draft {
                    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    TextField(L.t("editor.name"), text: Binding(get: { draft.title }, set: { self.draft?.name = String($0.prefix(60)) }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("editor.name")
                    VStack(spacing: 4) {
                        ForEach(Array(draft.groups.enumerated()), id: \.element.id) { index, group in
                            HStack {
                                Text(group.title).frame(maxWidth: .infinity, alignment: .leading)
                                Action(title: L.t("editor.up"), id: "editor.up.\(index)") { move(index, by: -1) }
                                    .disabled(index == 0)
                                Action(title: L.t("editor.down"), id: "editor.down.\(index)") { move(index, by: 1) }
                                    .disabled(index == draft.groups.count - 1)
                            }
                        }
                    }
                    .padding(12).panel()
                    customMove(groups: draft.groups)
                    Action(title: L.t("save"), id: "editor.save", style: .prominent) {
                        guard store.pro, var edited = self.draft else { return }
                        if edited.name != "sheet.starter" || edited.id != "starter" { edited.name = title }
                        if isNew { store.activate(edited) } else { store.updateSheet { $0 = edited } }
                        dismiss()
                    }
                    .disabled(title.isEmpty || title.rangeOfCharacter(from: .controlCharacters) != nil || !store.pro)
                }
            }
            .page()
        }
        .onAppear {
            var sheet = store.sheet
            if isNew {
                sheet.id = UUID().uuidString
                sheet.name = L.t("editor.default")
            }
            draft = sheet
            groupID = sheet.groups.first?.id ?? ""
        }
    }

    private func customMove(groups: [MovementGroup]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("editor.custom")).font(.headline)
            TextField(L.t("editor.move.name"), text: $newName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("editor.move.name")
            Picker(selection: $groupID) {
                ForEach(groups) { group in Text(group.title).tag(group.id) }
            } label: {
                Text(L.t("editor.group"))
            }
            .accessibilityIdentifier("editor.group")
            Picker(selection: $unit) {
                ForEach(Measurement.allCases) { measurement in Text(measurement.spoken).tag(measurement) }
            } label: {
                Text(L.t("editor.unit"))
            }
            .accessibilityIdentifier("editor.unit")
            Action(title: L.t("editor.add"), id: "editor.move.add", style: .outline) {
                let movement = Movement(id: UUID().uuidString, name: cleanedName, unit: unit)
                guard let draft, let index = draft.groups.firstIndex(where: { $0.id == groupID }) else { return }
                self.draft?.groups[index].moves.append(movement)
                self.draft?.groups[index].currentID = movement.id
                newName = ""
            }
            .disabled(cleanedName.isEmpty || cleanedName.count > 60
                      || cleanedName.rangeOfCharacter(from: .controlCharacters) != nil
                      || groups.reduce(0, { $0 + $1.moves.count }) >= SheetCode.maxMoves)
            Text(L.t("editor.unit.help")).font(.caption).foregroundStyle(Palette.muted)
        }
        .padding(12).panel()
    }

    private func move(_ index: Int, by offset: Int) {
        guard let draft, draft.groups.indices.contains(index + offset) else { return }
        self.draft?.groups.swapAt(index, index + offset)
    }
}
