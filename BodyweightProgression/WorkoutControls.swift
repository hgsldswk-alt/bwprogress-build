import SwiftUI
import UIKit

struct RestBar: View {
    @ObservedObject var timer: RestTimer

    var body: some View {
        if let countdown = timer.countdown {
            HStack(spacing: 8) {
                Image(systemName: "timer").accessibilityHidden(true)
                Text(L.t("rest.title")).font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("rest.title")
                TimelineView(.periodic(from: countdown.startedAt, by: 1)) { context in
                    let remaining = max(0, Int(countdown.deadline.timeIntervalSince(context.date).rounded(.up)))
                    Text("\(remaining / 60):\(String(format: "%02d", remaining % 60))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .accessibilityLabel(L.f("rest.remaining", remaining))
                        .accessibilityIdentifier("rest.countdown")
                }
                .id(countdown.id)
                Spacer(minLength: 0)
                Action(title: L.t("rest.skip"), id: "rest.skip") { timer.skip() }
            }
            .padding(.horizontal, 12)
            .background(Palette.tint, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background(Palette.paper)
        }
    }
}

struct RestSettings: View {
    @EnvironmentObject private var store: AppStoreModel
    @ObservedObject var timer: RestTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: Binding(get: { store.state.restSeconds }, set: { seconds in
                store.change { $0.changeRestSeconds(seconds) }
            }), in: TrainingState.restRange) {
                Text(L.f("rest.settings", store.state.restSeconds)).font(.headline)
            }
            .accessibilityIdentifier("rest.settings")
            Text(L.t("rest.settings.help")).font(.caption).foregroundStyle(Palette.muted)
                .accessibilityIdentifier("rest.settings.help")
            if timer.authorization == .notDetermined {
                Action(title: L.t("rest.enable"), id: "rest.enable", style: .outline) {
                    Task { await timer.requestAuthorization() }
                }
            } else if timer.authorization == .denied,
                      let url = URL(string: UIApplication.openSettingsURLString) {
                Link(L.t("rest.systemSettings"), destination: url)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.action)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("rest.systemSettings")
            }
        }
        .padding(12)
        .panel()
        .task { await timer.refreshAuthorization() }
    }
}

struct GuidedWorkoutCard: View {
    @EnvironmentObject private var store: AppStoreModel
    var workout: GuidedWorkout
    var movement: Movement
    var open: (Modal) -> Void

    var body: some View {
        let session = store.current
        let today = session?.entry(for: movement)
        let last = store.state.last(movement, excluding: session?.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.f("guide.position", workout.index + 1, workout.movements.count))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("guide.position")
                Spacer(minLength: 4)
                Action(title: L.t("guide.exit"), id: "guide.exit") { store.exitGuided() }
            }
            Text(movement.title).font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("guide.movement")
            Text(L.f("table.last.value", last?.summary() ?? L.t("value.empty")))
                .foregroundStyle(Palette.muted)
                .accessibilityLabel(L.f("table.last.value", last?.summary(spoken: true) ?? L.t("value.none")))
                .accessibilityIdentifier("guide.last")
            if let today {
                Text(today.summary()).font(.body.monospacedDigit())
                    .accessibilityLabel(today.summary(spoken: true))
                    .accessibilityIdentifier("guide.sets")
            }
            Action(title: L.f("guide.record", (today?.sets.count ?? 0) + 1),
                   id: "guide.record", style: .prominent) {
                store.tick()
                if store.guided?.movement == movement {
                    open(.number(movement, store.current?.id))
                }
            }
            HStack {
                Action(title: L.t(workout.hasNext ? "guide.next" : "guide.finish"),
                       id: workout.hasNext ? "guide.next" : "guide.finish", style: .outline) {
                    store.advanceGuided()
                }
                if store.state.undo?.movementID == movement.id {
                    Action(title: L.t("value.undo"), id: "entry.undo") { store.undoRecord() }
                }
            }
        }
        .padding(12)
        .panel()
    }
}
