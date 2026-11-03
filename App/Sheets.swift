import SwiftUI
import UniformTypeIdentifiers

struct RecoveryView: View {
    @EnvironmentObject var store: Store
    @State private var importing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Puffline").font(.largeTitle.bold())
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 42))
            Text("Збережемо твою історію").font(.title2.bold())
            Text("Не вдалося прочитати файл даних. Оригінал залишився на місці; нові записи заблоковано, щоб нічого не перезаписати.")
                .foregroundColor(.secondary)
            PrimaryButton(title: "Відновити резервну копію", symbol: "arrow.clockwise") { importing = true }
            Spacer()
        }.padding(28).padding(.top, 30).background(Style.bg.ignoresSafeArea())
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { try store.restore(result.get()) }
                catch { store.error = error.localizedDescription }
            }
    }
}

struct AddPuffsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var count = 5
    @State private var trigger = "Не вказано"
    let triggers = ["Не вказано", "Звичка", "Стрес", "Перерва", "Після їжі", "У компанії", "Нудьга"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SheetHeader(title: "Додати затяжки") { dismiss() }
            Text("Якщо не відмітив одразу — додай кількість одним записом. Час запису буде поточним.").font(.subheadline).foregroundColor(.secondary)
            Card {
                Stepper(value: $count, in: 1...500) { Text("\(count)").font(.system(size: 54, weight: .semibold, design: .rounded)) }
                HStack {
                    ForEach([1, 5, 10, 20], id: \.self) { number in
                        Button("\(number)") { count = number }.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(count == number ? Style.ink : Style.subtle).foregroundColor(count == number ? Style.card : Style.ink).clipShape(Capsule())
                    }
                }.padding(.top, 12)
            }
            Card {
                Picker("Що спонукало?", selection: $trigger) { ForEach(triggers, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
            }
            PrimaryButton(title: "Додати \(count)", symbol: "plus") { store.add(count, trigger: trigger); dismiss() }
            Spacer()
        }.padding(24).background(Style.bg.ignoresSafeArea()).tint(.primary)
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var pendingDelete: PuffEvent?
    var body: some View {
        NavigationView {
            List {
                if store.state.events.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Поки що чистий аркуш").font(.headline)
                        Text("Твої записи з’являться тут після першої відмітки.").font(.subheadline).foregroundColor(.secondary)
                    }.padding(.vertical, 24)
                }
                ForEach(store.state.events.sorted { $0.date > $1.date }) { event in
                    HStack {
                        Text("+\(event.count)").font(.title3.bold().monospacedDigit()).frame(minWidth: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.date.uk("d MMMM, HH:mm")).font(.subheadline)
                            Text(event.trigger).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }.swipeActions { Button("Видалити", role: .destructive) { pendingDelete = event } }
                }
            }.navigationTitle("Історія").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
                .confirmationDialog("Видалити цей запис?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                    Button("Видалити запис", role: .destructive) { if let event = pendingDelete { store.remove(event) }; pendingDelete = nil }
                    Button("Скасувати", role: .cancel) { pendingDelete = nil }
                }
        }.navigationViewStyle(.stack).tint(.primary)
    }
}

struct BreatheView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var started: Date?
    @State private var now = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    var elapsed: Int { max(0, Int(now.timeIntervalSince(started ?? now))) }
    var phase: Int { elapsed % 10 }
    var finished: Bool { started != nil && elapsed >= 60 }
    var body: some View {
        VStack(spacing: 24) {
            SheetHeader(title: "Хвилина для себе") { dismiss() }
            Spacer()
            ZStack {
                Circle().stroke(Style.ink.opacity(0.08), lineWidth: 1).frame(width: 270, height: 270)
                Circle().fill(Style.ink.opacity(0.05)).frame(width: 235, height: 235)
                    .scaleEffect(reduceMotion ? 1 : (started != nil && !finished && phase < 4 ? 1.1 : 0.78))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 3.5), value: phase < 4)
                Circle().fill(Style.ink).frame(width: 180, height: 180)
                VStack(spacing: 10) {
                    Image(systemName: finished ? "checkmark" : "wind").font(.system(size: 28, weight: .light))
                    Text(finished ? "Ти впорався" : (started == nil ? "Зроби паузу" : (phase < 4 ? "Вдих" : "Видих"))).font(.title3.weight(.medium))
                    if started != nil && !finished { Text("\(max(0, 60 - elapsed)) с").font(.caption.monospacedDigit()) }
                }.foregroundColor(Style.card)
            }.accessibilityElement(children: .combine)
            Text(finished ? "Ще одна маленька перемога. Продовжуй у своєму темпі." : "Дихай спокійно й без зусиль. Якщо незручно — зупинись і дихай як звично.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            Spacer()
            PrimaryButton(title: finished ? "Повернутися" : (started == nil ? "Почати хвилину" : "Завершити"), symbol: finished ? "checkmark" : "arrow.right") {
                if started == nil { started = Date(); now = Date() } else { dismiss() }
            }
        }.padding(24).background(Style.bg.ignoresSafeArea()).onReceive(timer) { now = $0 }
    }
}
