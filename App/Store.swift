import SwiftUI
import WidgetKit
import UserNotifications
import UIKit

final class Store: ObservableObject {
    @Published var state: TrackerState
    @Published var error: String?
    @Published var incomingCount: Int?
    @Published var toast: String?
    @Published var now = Date()
    private var undoState: TrackerState?
    private var storageBlocked = false
    var day: String { DayKey.key(now) }
    var used: Int { state.count(on: day) }
    var limit: Int { state.limit(on: day) }
    var remaining: Int { max(0, limit - used) }
    var last: PuffEvent? { state.events.max { $0.date < $1.date } }

    init() {
        do { state = try SharedStorage.load() }
        catch {
            state = TrackerState()
            if FileManager.default.fileExists(atPath: SharedStorage.file().path) {
                storageBlocked = true
                self.error = "Не вдалося прочитати дані. Оригінальний файл збережено. Спробуй відновити резервну копію."
            }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            storageBlocked = false; state = DemoData.state(); error = nil
            if ProcessInfo.processInfo.arguments.contains("--dark") { state.appearance = "dark" }
        }
        #endif
        if error == nil { refresh() }
    }
    func refresh() {
        now = Date()
        guard !storageBlocked else { return }
        let before = state
        state.advance(to: now)
        if before != state { persist() }
    }
    func persist() {
        guard !storageBlocked else { error = "Збереження заблоковане, щоб захистити файл із помилкою. Віднови резервну копію в налаштуваннях."; return }
        do { try SharedStorage.save(state); WidgetCenter.shared.reloadAllTimelines() }
        catch { self.error = "Не вдалося зберегти зміни: \(error.localizedDescription)" }
    }
    func update(_ change: (inout TrackerState) -> Void) {
        guard !storageBlocked else { persist(); return }
        refresh()
        change(&state)
        persist()
    }
    func start(baseline: Int, days: Int, cost: Double, reason: String) {
        guard !storageBlocked else { persist(); return }
        state.start(baseline: baseline, duration: days, now: Date())
        state.dailyCost = cost
        if !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { state.motivation = String(reason.prefix(200)) }
        persist()
    }
    func add(_ count: Int = 1, trigger: String = "Не вказано") {
        guard !storageBlocked, state.onboarded else { return }
        refresh()
        undoState = state
        state.add(count, trigger: trigger, now: now)
        persist()
        if state.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        toast = "+\(count) · записано"
    }
    func undo() {
        guard let previous = undoState else { return }
        state = previous
        undoState = nil
        refresh()
        persist()
        toast = "Останній запис скасовано"
    }
    var canUndo: Bool { undoState != nil }
    func remove(_ event: PuffEvent) {
        undoState = state
        state.events.removeAll { $0.id == event.id }
        persist()
    }
    func route(_ url: URL) {
        guard url.scheme == "puffline" else { return }
        refresh()
        if url.host == "add" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let count = Int(components?.queryItems?.first { $0.name == "count" }?.value ?? "1") ?? 1
            incomingCount = min(500, max(1, count))
        }
    }
    func exportJSON() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Puffline-backup.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
        return url
    }
    func exportCSV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Puffline-history.csv")
        func escaped(_ value: String) -> String {
            // Prevent spreadsheet formula execution from user-entered triggers.
            let safe = ["=", "+", "-", "@"].contains(String(value.prefix(1))) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let formatter = ISO8601DateFormatter()
        let rows = state.events.sorted { $0.date < $1.date }.map {
            [escaped(formatter.string(from: $0.date)), String($0.count), escaped($0.trigger)].joined(separator: ",")
        }
        try ("\u{feff}Дата,Затяжки,Причина\n" + rows.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func restore(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count < 50_000_000 else { throw NSError(domain: "Puffline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Файл завеликий."]) }
        let restored = try JSONDecoder().decode(TrackerState.self, from: data)
        guard restored.valid() else { throw NSError(domain: "Puffline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Це не коректна резервна копія Puffline."]) }
        // Keep the previous data available as a separate recovery file.
        if FileManager.default.fileExists(atPath: SharedStorage.file().path) {
            let backup = SharedStorage.folder().appendingPathComponent("before-restore-\(Int(Date().timeIntervalSince1970)).json")
            try FileManager.default.copyItem(at: SharedStorage.file(), to: backup)
        }
        try SharedStorage.save(restored)
        state = restored; undoState = nil; error = nil; storageBlocked = false
        refresh(); scheduleReminder()
    }
    func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-checkin"])
        guard state.reminder else { return }
        let hour = state.reminderHour, minute = state.reminderMinute
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, err in
            DispatchQueue.main.async {
                guard granted else {
                    self.state.reminder = false; self.persist()
                    self.error = err?.localizedDescription ?? "Сповіщення вимкнені в iOS. Їх можна дозволити в налаштуваннях телефону."
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "Мить для себе"
                content.body = "Зазирни у Puffline та відміть сьогоднішній прогрес."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
                center.add(UNNotificationRequest(identifier: "daily-checkin", content: content, trigger: trigger)) { error in
                    if let error = error { DispatchQueue.main.async { self.error = error.localizedDescription } }
                }
            }
        }
    }
}
