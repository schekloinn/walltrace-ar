#if DEBUG
import Foundation

// Used only in DEBUG simulator previews. Release builds never load sample history.
enum DemoData {
    static func state() -> TrackerState {
        var state = TrackerState()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -6, to: today)!
        state.start(baseline: 180, duration: 30, now: start)
        state.motivation = "Мій вибір — більше свободи."
        let counts = [164, 153, 148, 136, 124, 112, 42]
        for offset in 0...6 {
            let date = cal.date(byAdding: .day, value: offset, to: start)!
            let key = DayKey.key(date)
            state.records[key] = DayRecord(limit: 180 - offset * 6, visited: true, paused: false)
            let amount = counts[offset]
            for batch in 0..<6 {
                let eventTime: Date
                if offset == 6 { eventTime = Date().addingTimeInterval(Double(batch - 6) * 600) }
                else { eventTime = date.addingTimeInterval(Double(8 + batch * 2) * 3600) }
                state.events.append(PuffEvent(date: eventTime, count: amount / 6 + (batch < amount % 6 ? 1 : 0), trigger: ["Звичка", "Перерва", "Після їжі"][batch % 3]))
            }
        }
        state.cursorDay = DayKey.key(today)
        return state
    }
}
#endif
