import Foundation

@main
enum Checks {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12))!
        let next = cal.date(byAdding: .day, value: 1, to: day)!
        var state = TrackerState()
        check(!state.onboarded, "Fresh install must be empty")
        state.add(1, trigger: "x", now: day, calendar: cal)
        check(state.events.isEmpty, "No events before onboarding")
        state.start(baseline: 100, duration: 30, now: day, calendar: cal)
        check(state.step == 4, "Ceiling reduction step")
        state.add(30, trigger: "Перерва", now: day, calendar: cal)
        check(state.count(on: "2026-10-23", calendar: cal) == 30, "Batch count")
        state.add(0, trigger: "x", now: day, calendar: cal)
        state.add(501, trigger: "x", now: day, calendar: cal)
        check(state.events.count == 1, "Reject invalid batches")
        state.advance(to: next, calendar: cal)
        check(state.limit(on: "2026-10-24") == 96, "Reduce after successful tracked day")
        check(state.count(on: "2026-10-24", calendar: cal) == 0, "Reset daily counter")
        state.add(100, trigger: "x", now: next, calendar: cal)
        let third = cal.date(byAdding: .day, value: 2, to: day)!
        state.advance(to: third, calendar: cal)
        check(state.limit(on: "2026-10-25") == 96, "Hold on excess")
        state.setPaused(true, now: third, calendar: cal)
        let fourth = cal.date(byAdding: .day, value: 3, to: day)!
        state.advance(to: fourth, calendar: cal)
        check(state.limit(on: "2026-10-26") == 96, "Pause holds target across DST")
        state.setPaused(false, now: fourth, calendar: cal)
        let sixth = cal.date(byAdding: .day, value: 5, to: day)!
        state.advance(to: sixth, calendar: cal)
        check(state.limit(on: "2026-10-28") == 92, "Missing days hold limit")
        check(state.records["2026-10-27"]?.visited == false, "Missing day not marked successful")
        check(DayKey.next("2026-10-25", calendar: cal) == "2026-10-26", "DST fall day")
        check(DayKey.next("2026-03-29", calendar: cal) == "2026-03-30", "DST spring day")
        check(DayKey.next("2028-02-28", calendar: cal) == "2028-02-29", "Leap year")
        check(DayKey.next("2026-12-31", calendar: cal) == "2027-01-01", "Year boundary")
        let before = state.records["2026-10-24"]
        state.advance(to: next, calendar: cal)
        check(state.records["2026-10-24"] == before, "Backwards clock preserves limits")
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TrackerState.self, from: data)
        check(decoded == state, "Exact JSON roundtrip")
        check(decoded.valid(), "Valid backup accepted")
        var corrupt = state; corrupt.baseline = 0
        check(!corrupt.valid(), "Reject zero baseline backup")
        corrupt = state; corrupt.events.append(corrupt.events[0])
        check(!corrupt.valid(), "Reject duplicate event IDs")
        corrupt = state; corrupt.records["2026-99-77"] = DayRecord(limit: 2, visited: true, paused: false)
        check(!corrupt.valid(), "Reject impossible date")
        corrupt = state; corrupt.dailyCost = .infinity
        check(!corrupt.valid(), "Reject infinite cost")
        var minimal = TrackerState(); minimal.start(baseline: 1, duration: 30, now: day, calendar: cal)
        minimal.advance(to: next, calendar: cal)
        check(minimal.limit(on: "2026-10-24") == 0, "Reach zero, never negative")
        minimal.quitAt = day
        minimal.add(1, trigger: "x", now: next, calendar: cal)
        check(minimal.quitAt == nil, "New puff resets abstinence timer")
        var fixed = TrackerState(); fixed.start(baseline: 100, duration: 30, now: day, calendar: cal)
        fixed.adaptive = false; fixed.add(150, trigger: "x", now: day, calendar: cal); fixed.advance(to: next, calendar: cal)
        check(fixed.limit(on: "2026-10-24") == 96, "Fixed pace ignores excess")
        var money = TrackerState(); money.start(baseline: 100, duration: 30, now: day, calendar: cal)
        money.dailyCost = 50; money.add(50, trigger: "x", now: day, calendar: cal)
        check(money.avoided(until: day, calendar: cal) == 50, "Avoided puffs")
        check(money.savings(until: day, calendar: cal) == 25, "Proportional savings")
        money.add(100, trigger: "x", now: day, calendar: cal)
        check(money.savings(until: day, calendar: cal) == 0, "No negative savings")
        money.start(baseline: 120, duration: 14, now: next, calendar: cal)
        check(money.events.count == 2, "Changing plan preserves event history")
        let count = state.events.count
        for _ in 0..<100 { state.advance(to: sixth, calendar: cal) }
        check(state.events.count == count, "Refresh never creates phantom events")
        print("PASS: \(checks) model checks, including DST, skipped days, adaptation, backups and savings")
    }
}
