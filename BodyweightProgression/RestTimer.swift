import AudioToolbox
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class RestTimer: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    struct Countdown {
        let id = "rest.\(UUID().uuidString)"
        let startedAt: Date
        let deadline: Date
    }

    @Published private(set) var countdown: Countdown?
    @Published private(set) var authorization: UNAuthorizationStatus?

    private let center = UNUserNotificationCenter.current()
    private var expiry: Task<Void, Never>?
    private var reminderID: String?

    override init() {
        super.init()
        if !Launch.testing { center.delegate = self }
    }

    func start(seconds: Int) {
        skip()
        let start = Date()
        let next = Countdown(startedAt: start, deadline: start.addingTimeInterval(Double(seconds)))
        countdown = next
        reminderID = next.id
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.countdown?.id == next.id else { return }
            self.countdown = nil
            self.expiry = nil
            if !Launch.testing, UIApplication.shared.applicationState == .active,
               Date().timeIntervalSince(next.deadline) < 1 {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
        if !Launch.testing { Task { await schedule(next) } }
    }

    func skip() {
        guard let countdown else { return }
        expiry?.cancel()
        expiry = nil
        self.countdown = nil
        reminderID = nil
        if !Launch.testing {
            removeReminder(countdown.id)
        }
    }

    func refreshAuthorization() async {
        if Launch.testing {
            authorization = .notDetermined
        } else {
            let settings = await center.notificationSettings()
            authorization = settings.authorizationStatus
        }
    }

    func requestAuthorization() async {
        guard !Launch.testing else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
        if let countdown { await schedule(countdown) }
    }

    private func schedule(_ next: Countdown) async {
        let settings = await center.notificationSettings()
        guard [UNAuthorizationStatus.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        else { return }
        let remaining = next.deadline.timeIntervalSinceNow
        guard countdown?.id == next.id, remaining > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = L.t("rest.notification.title")
        content.body = L.t("rest.notification.body")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: next.id, content: content, trigger: trigger))
        if reminderID != next.id { removeReminder(next.id) }
    }

    private func removeReminder(_ id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
