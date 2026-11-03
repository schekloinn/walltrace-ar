import SwiftUI

struct ProgressViewContent: View {
    @EnvironmentObject var store: Store
    @State private var weekOffset = 0
    @State private var monthOffset = 0
    @State private var showPlan = false
    var body: some View {
        VStack(spacing: 16) {
            Button { showPlan = true } label: { planCard }.buttonStyle(.plain)
            weekCard
            monthCard
            frequencyCard
            calendarCard
            Card {
                HStack {
                    Metric(value: String(format: "%.0f %@", store.state.savings(until: store.now), store.state.currency), label: "орієнтовно збережено*")
                    Metric(value: "\(store.state.avoided(until: store.now))", label: "затяжок уникнуто*")
                }
                Text("*Порівняно з початковими \(store.state.baseline) затяжками на день, лише за дні із записами. Сьогоднішні значення попередні.")
                    .font(.system(size: 10)).foregroundColor(.secondary).padding(.top, 10)
            }
        }.sheet(isPresented: $showPlan) { PlanView() }
    }
    var planCard: some View {
        Card {
            HStack {
                Label("План відмови", systemImage: "calendar").font(.system(size: 13, weight: .semibold))
                Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(recentDays, id: \.self) { date in
                    let key = DayKey.key(date)
                    let record = store.state.records[key]
                    let isToday = key == store.day
                    let good = key < store.day && record?.visited == true && store.state.count(on: key) <= (record?.limit ?? 0)
                    ZStack {
                        Circle().stroke(isToday ? Style.ink : Style.ink.opacity(0.1), lineWidth: isToday ? 2 : 1)
                        if good { Circle().fill(Style.ink); Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundColor(Style.card) }
                        else { Text(date.uk("d")).font(.system(size: 14, weight: isToday ? .bold : .regular)).foregroundColor(record?.visited == true || isToday ? .primary : .secondary) }
                    }.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                }
            }.padding(.vertical, 18)
            HStack {
                Metric(value: "\(store.used) / \(store.limit)", label: "затяжок сьогодні")
                Metric(value: reductionLabel, label: "від початкового рівня")
            }
            Divider().padding(.vertical, 12)
            Text(store.state.paused ? "План на паузі · ліміт збережено" : "Орієнтовно \(store.state.estimatedDaysRemaining(on: store.day)) дн. до нульового ліміту")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
    var reductionLabel: String {
        let percent = store.state.reductionPercent(on: store.day)
        return "↓ \(max(0, percent))%"
    }
    var recentDays: [Date] { (-3...3).map { Calendar.current.date(byAdding: .day, value: $0, to: store.now)! } }
    func chartHeader(_ title: String, subtitle: String, offset: Binding<Int>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: "cloud.fill").font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Button { offset.wrappedValue -= 1 } label: { Image(systemName: "chevron.left").frame(width: 28, height: 30).background(Style.subtle).clipShape(Circle()) }.accessibilityLabel("Попередній період")
            Button { offset.wrappedValue += 1 } label: { Image(systemName: "chevron.right").frame(width: 28, height: 30).background(Style.subtle).clipShape(Circle()) }.disabled(offset.wrappedValue >= 0).accessibilityLabel("Наступний період")
        }.font(.system(size: 11, weight: .semibold))
    }
    var weekStart: Date {
        var cal = Calendar.current; cal.firstWeekday = 2
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: cal.dateInterval(of: .weekOfYear, for: store.now)!.start)!
    }
    var weekData: [BarDatum] {
        (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart)!
            return datum(date, label: date.uk("EE"))
        }
    }
    func datum(_ date: Date, label: String) -> BarDatum {
        let key = DayKey.key(date)
        let target = store.state.records[key]?.limit ?? (key > store.day ? (store.state.paused ? store.limit : max(0, store.limit - store.state.step * max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: store.now), to: date).day ?? 0))) : 0)
        return BarDatum(id: key, value: store.state.count(on: key), target: target, label: label, selected: key == store.day, recorded: store.state.records[key]?.visited == true)
    }
    var weekCard: some View {
        Card {
            chartHeader("Затяжки за тиждень", subtitle: weekStart.uk("d MMM") + " — " + Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!.uk("d MMM"), offset: $weekOffset)
            Text("\(weekData.reduce(0) { $0 + $1.value })").font(.system(size: 30, weight: .semibold, design: .rounded)).padding(.top, 14)
            Text("затяжок").font(.caption).foregroundColor(.secondary)
            Bars(data: weekData).padding(.top, 18)
            legend
        }
    }
    var monthDate: Date { Calendar.current.date(byAdding: .month, value: monthOffset, to: store.now)! }
    var monthDays: [Date] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .month, for: monthDate)!.start
        return cal.range(of: .day, in: .month, for: monthDate)!.map { cal.date(byAdding: .day, value: $0 - 1, to: start)! }
    }
    var monthCard: some View {
        Card {
            chartHeader("Затяжки за місяць", subtitle: monthDate.uk("LLLL yyyy").capitalized, offset: $monthOffset)
            Text("\(monthDays.reduce(0) { $0 + store.state.count(on: DayKey.key($1)) })").font(.system(size: 30, weight: .semibold, design: .rounded)).padding(.top, 14)
            Text("затяжок").font(.caption).foregroundColor(.secondary)
            Bars(data: monthDays.map { datum($0, label: $0.uk("d")) }, dense: true).padding(.top, 18)
            HStack { Text("1"); Spacer(); Text("8"); Spacer(); Text("15"); Spacer(); Text("22"); Spacer(); Text("\(monthDays.count)") }.font(.system(size: 10)).foregroundColor(.secondary).padding(.top, 5)
            legend
        }
    }
    var legend: some View {
        HStack(spacing: 12) {
            Label("Фактично", systemImage: "circle.fill").foregroundColor(.primary)
            Label("Ліміт / прогноз", systemImage: "circle").foregroundColor(.secondary)
        }.font(.system(size: 9)).padding(.top, 12)
    }
    var hourCounts: [Int] {
        var counts = Array(repeating: 0, count: 24)
        for event in store.state.events { counts[Calendar.current.component(.hour, from: event.date)] += event.count }
        return counts
    }
    var averageBreak: String {
        let events = store.state.events.sorted { $0.date < $1.date }
        let gaps = zip(events, events.dropFirst()).compactMap { left, right -> Double? in
            guard Calendar.current.isDate(left.date, inSameDayAs: right.date) else { return nil }
            return right.date.timeIntervalSince(left.date) / 60
        }
        guard !gaps.isEmpty else { return "—" }
        return "\(Int(gaps.reduce(0, +) / Double(gaps.count))) хв"
    }
    var frequencyCard: some View {
        Card {
            Label("Ритм протягом доби", systemImage: "clock.fill").font(.system(size: 12, weight: .semibold))
            HStack {
                Metric(value: peakHour, label: "найактивніша година")
                Metric(value: averageBreak, label: "між записами за день")
            }.padding(.vertical, 18)
            Bars(data: (0..<24).map { BarDatum(id: "\($0)", value: hourCounts[$0], target: 0, label: "\($0):00", selected: false, recorded: true) }, dense: true)
            HStack { Text("00:00"); Spacer(); Text("06:00"); Spacer(); Text("12:00"); Spacer(); Text("18:00") }.font(.system(size: 9)).foregroundColor(.secondary).padding(.top, 7)
            Text("За всю історію. Кілька затяжок одним записом не дають точного інтервалу між затяжками.")
                .font(.system(size: 10)).foregroundColor(.secondary).padding(.top, 12)
        }
    }
    var peakHour: String {
        guard hourCounts.reduce(0, +) > 0, let index = hourCounts.enumerated().max(by: { $0.element < $1.element })?.offset else { return "—" }
        return String(format: "%02d–%02d", index, index + 1)
    }
    var calendarCard: some View {
        Card {
            Label("Календар прогресу", systemImage: "square.grid.3x3.fill").font(.system(size: 12, weight: .semibold))
            Text(monthDate.uk("LLLL yyyy").capitalized).font(.caption).foregroundColor(.secondary).padding(.top, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 7) {
                ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"], id: \.self) { Text($0).font(.system(size: 10)).foregroundColor(.secondary) }
                ForEach(0..<leadingDays, id: \.self) { _ in Color.clear.frame(height: 32) }
                ForEach(monthDays, id: \.self) { date in
                    let key = DayKey.key(date)
                    let record = store.state.records[key]
                    let known = record?.visited == true
                    let good = known && key < store.day && store.state.count(on: key) <= (record?.limit ?? 0)
                    Text(date.uk("d")).font(.system(size: 12, weight: key == store.day ? .bold : .regular))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .foregroundColor(good ? Style.card : Style.ink.opacity(known ? 1 : 0.35))
                        .background(good ? Style.ink : Style.subtle)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(key == store.day ? Style.ink : .clear, lineWidth: 1.5))
                        .accessibilityLabel("\(date.uk("d MMMM")): \(known ? "\(store.state.count(on: key)) затяжок" : "немає записів")")
                }
            }.padding(.top, 15)
            Text("Зафарбовані дні — завершені в межах ліміту. Сірі — немає записів або ліміт перевищено.")
                .font(.system(size: 10)).foregroundColor(.secondary).padding(.top, 12)
        }
    }
    var leadingDays: Int { (Calendar.current.component(.weekday, from: monthDays.first!) + 5) % 7 }
}

struct PlanView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "Твій план") { dismiss() }
                Card {
                    Text(store.state.paused ? "Зараз на паузі" : "Менше з кожним днем").font(.title2.bold())
                    Text("Початковий рівень: \(store.state.baseline) затяжок. Крок скорочення: \(store.state.step) на день.")
                        .font(.subheadline).foregroundColor(.secondary).padding(.top, 8)
                    Text("Адаптивний темп утримує ліміт після перевищення. Пропущений день також утримує ліміт. Пауза не стирає історію. Прогноз змінюється разом із тобою.")
                        .font(.caption).foregroundColor(.secondary).padding(.top, 12)
                }
                ForEach(0..<min(60, store.state.estimatedDaysRemaining(on: store.day) + 1), id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: store.now)!
                    HStack {
                        Text(offset == 0 ? "Сьогодні" : date.uk("d MMMM"))
                        Spacer()
                        Text("\(store.state.paused ? store.limit : max(0, store.limit - offset * store.state.step))").font(.headline.monospacedDigit())
                        Text("затяжок").font(.caption).foregroundColor(.secondary)
                    }.padding(16).background(Style.card).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text("Це інструмент самоконтролю, а не медичне призначення. Темп ти обираєш самостійно.")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(20)
        }.background(Style.bg.ignoresSafeArea())
    }
}
