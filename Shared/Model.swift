import Foundation

enum DayKey {
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }
    static func date(_ key: String, calendar: Calendar = .current) -> Date {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return calendar.startOfDay(for: Date()) }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? Date()
    }
    static func next(_ key: String, calendar: Calendar = .current) -> String {
        self.key(calendar.date(byAdding: .day, value: 1, to: date(key, calendar: calendar))!, calendar: calendar)
    }
}

struct PuffEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var count: Int
    var trigger: String
}

struct DayRecord: Codable, Equatable {
    var limit: Int
    var visited: Bool
    var paused: Bool
}

struct TrackerState: Codable, Equatable {
    var version = 1
    var onboarded = false
    var baseline = 150
    var duration = 30
    var adaptive = true
    var paused = false
    var startDay = ""
    var cursorDay = ""
    var records: [String: DayRecord] = [:]
    var events: [PuffEvent] = []
    var quitAt: Date?
    var dailyCost = 50.0
    var currency = "₴"
    var reminder = false
    var reminderHour = 20
    var reminderMinute = 0
    var haptics = true
    var appearance = "light"
    var motivation = "Більше свободи. Менше залежності."

    var step: Int { max(1, Int(ceil(Double(baseline) / Double(max(1, duration))))) }
    func count(on day: String, calendar: Calendar = .current) -> Int {
        events.filter { DayKey.key($0.date, calendar: calendar) == day }.reduce(0) { $0 + $1.count }
    }
    func limit(on day: String) -> Int { records[day]?.limit ?? baseline }
    mutating func start(baseline: Int, duration: Int, now: Date, calendar: Calendar = .current) {
        self.baseline = min(5000, max(1, baseline))
        self.duration = min(365, max(7, duration))
        onboarded = true
        startDay = DayKey.key(now, calendar: calendar)
        cursorDay = startDay
        records[startDay] = DayRecord(limit: self.baseline, visited: true, paused: false)
    }
    mutating func advance(to now: Date, calendar: Calendar = .current) {
        guard onboarded else { return }
        let today = DayKey.key(now, calendar: calendar)
        if cursorDay.isEmpty { cursorDay = today }
        // A backwards clock/time-zone change never rewrites a past day's target.
        guard today >= cursorDay else {
            if records[today] == nil { records[today] = DayRecord(limit: baseline, visited: true, paused: paused) }
            return
        }
        var safety = 0
        while cursorDay < today && safety < 20000 {
            let previous = records[cursorDay] ?? DayRecord(limit: baseline, visited: false, paused: paused)
            let used = count(on: cursorDay, calendar: calendar)
            let hold = previous.paused || !previous.visited || (adaptive && used > previous.limit)
            let nextLimit = hold ? previous.limit : max(0, previous.limit - step)
            cursorDay = DayKey.next(cursorDay, calendar: calendar)
            records[cursorDay] = DayRecord(limit: nextLimit, visited: false, paused: paused)
            safety += 1
        }
        if records[today] != nil { records[today]?.visited = true; records[today]?.paused = paused }
    }
    mutating func add(_ count: Int, trigger: String, now: Date, calendar: Calendar = .current) {
        guard onboarded, (1...500).contains(count) else { return }
        advance(to: now, calendar: calendar)
        events.append(PuffEvent(date: now, count: count, trigger: String(trigger.prefix(80))))
        quitAt = nil
    }
    mutating func setPaused(_ value: Bool, now: Date, calendar: Calendar = .current) {
        advance(to: now, calendar: calendar)
        paused = value
        records[DayKey.key(now, calendar: calendar)]?.paused = value
    }
    func estimatedDaysRemaining(on day: String) -> Int {
        Int(ceil(Double(limit(on: day)) / Double(step)))
    }
    func reductionPercent(on day: String) -> Int {
        max(0, Int(((1 - Double(limit(on: day)) / Double(max(1, baseline))) * 100).rounded()))
    }
    func avoided(until now: Date, calendar: Calendar = .current) -> Int {
        // Count only days with actual records; do not invent savings on missing days.
        let today = DayKey.key(now, calendar: calendar)
        return records.filter { $0.key <= today && $0.value.visited }
            .reduce(0) { $0 + max(0, baseline - count(on: $1.key, calendar: calendar)) }
    }
    func savings(until now: Date, calendar: Calendar = .current) -> Double {
        Double(avoided(until: now, calendar: calendar)) / Double(max(1, baseline)) * dailyCost
    }
    func valid() -> Bool {
        guard version == 1, (1...5000).contains(baseline), (7...365).contains(duration),
              dailyCost.isFinite, (0...100000).contains(dailyCost),
              (0...23).contains(reminderHour), (0...59).contains(reminderMinute),
              ["light", "dark", "system"].contains(appearance),
              events.count <= 1_000_000, records.count <= 20000 else { return false }
        let dayPattern = #"^\d{4}-\d{2}-\d{2}$"#
        let validKey: (String) -> Bool = { key in
            guard key.range(of: dayPattern, options: .regularExpression) != nil else { return false }
            return DayKey.key(DayKey.date(key)) == key
        }
        if onboarded && (!validKey(startDay) || !validKey(cursorDay)) { return false }
        return records.allSatisfy { validKey($0.key) && (0...5000).contains($0.value.limit) }
            && Set(events.map(\.id)).count == events.count
            && events.allSatisfy { (1...500).contains($0.count) && $0.date.timeIntervalSince1970.isFinite && $0.trigger.count <= 80 }
    }
}

enum SharedStorage {
    static let group = "group.local.puffline.shared"
    static let filename = "puffline-v1.json"
    static func folder() -> URL {
        #if os(iOS)
        if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) { return shared }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Puffline", isDirectory: true)
    }
    static func file() -> URL { folder().appendingPathComponent(filename) }
    static func load(from url: URL? = nil) throws -> TrackerState {
        let state = try JSONDecoder().decode(TrackerState.self, from: Data(contentsOf: url ?? file()))
        guard state.valid() else { throw NSError(domain: "Puffline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Резервна копія містить некоректні дані."]) }
        return state
    }
    static func save(_ state: TrackerState, to url: URL? = nil) throws {
        guard state.valid() else { throw NSError(domain: "Puffline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Некоректні дані. Попередню історію не змінено."]) }
        let destination = url ?? file()
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: destination, options: [.atomic])
    }
}
