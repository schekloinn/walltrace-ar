import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var share: ExportFile?
    @State private var importing = false
    @State private var importURL: URL?
    @State private var confirmRestart = false
    @State private var editingPlan = false
    @State private var shortcutHelp = false
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Твій план")) {
                    HStack { Text("Початковий рівень"); Spacer(); Text("\(store.state.baseline) / день").foregroundColor(.secondary) }
                    HStack { Text("Крок скорочення"); Spacer(); Text("\(store.state.step) / день").foregroundColor(.secondary) }
                    Toggle("Адаптивний темп", isOn: binding(\.adaptive))
                    Toggle("Пауза скорочення", isOn: Binding(get: { store.state.paused }, set: { value in store.update { $0.setPaused(value, now: Date()) } }))
                    Button("Змінити план") { editingPlan = true }
                }
                Section(header: Text("Нагадування"), footer: Text("Одне м’яке щоденне нагадування. Дозвіл на сповіщення надається в iOS.")) {
                    Toggle("Щоденне нагадування", isOn: Binding(get: { store.state.reminder }, set: { value in store.update { $0.reminder = value }; store.scheduleReminder() }))
                    if store.state.reminder {
                        DatePicker("Час", selection: Binding(get: { Calendar.current.date(from: DateComponents(hour: store.state.reminderHour, minute: store.state.reminderMinute)) ?? Date() }, set: { date in
                            store.update { $0.reminderHour = Calendar.current.component(.hour, from: date); $0.reminderMinute = Calendar.current.component(.minute, from: date) }; store.scheduleReminder()
                        }), displayedComponents: .hourAndMinute)
                    }
                }
                Section(header: Text("Вигляд і відчуття")) {
                    Picker("Тема", selection: binding(\.appearance)) { Text("Світла").tag("light"); Text("Темна").tag("dark"); Text("Як у системі").tag("system") }
                    Toggle("Тактильний відгук", isOn: binding(\.haptics))
                    TextField("Твоя мотивація", text: Binding(get: { store.state.motivation }, set: { value in store.update { $0.motivation = String(value.prefix(200)) } }))
                }
                Section(header: Text("Витрати"), footer: Text("Економія — орієнтовний розрахунок відносно початкового рівня споживання.")) {
                    HStack {
                        Text("За день, \(store.state.currency)")
                        Spacer()
                        TextField("50", value: binding(\.dailyCost), formatter: costFormatter).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Валюта", selection: binding(\.currency)) { ForEach(["₴", "€", "$", "zł"], id: \.self) { Text($0).tag($0) } }
                }
                Section(header: Text("Швидкий доступ")) {
                    Button("Віджет і команди") { shortcutHelp = true }
                }
                Section(header: Text("Твої дані"), footer: Text("Дані зберігаються локально. Зроби резервну копію перед видаленням застосунку або перевстановленням.")) {
                    Button("Зберегти резервну копію") { export(json: true) }
                    Button("Експортувати історію CSV") { export(json: false) }
                    Button("Відновити з резервної копії") { importing = true }
                }
                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Puffline 1.0").font(.headline)
                        Text("Менше затяжок. Більше тебе.").font(.caption)
                        Text("Українською · без підписок · без реклами").font(.caption).foregroundColor(.secondary)
                        Text("Самостійний застосунок, натхненний ідеєю Puffless. Не пов’язаний із його розробником.").font(.system(size: 10)).foregroundColor(.secondary)
                    }.padding(.vertical, 8)
                }
            }
            .navigationTitle("Налаштування")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .sheet(item: $share) { ShareSheet(url: $0.url) }
            .sheet(isPresented: $editingPlan) { EditPlanView() }
            .sheet(isPresented: $shortcutHelp) { ShortcutsHelpView() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): importURL = url
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .confirmationDialog("Замінити поточні дані резервною копією?", isPresented: Binding(get: { importURL != nil }, set: { if !$0 { importURL = nil } }), titleVisibility: .visible) {
                Button("Відновити дані") {
                    do { if let url = importURL { try store.restore(url) } }
                    catch { store.error = error.localizedDescription }
                    importURL = nil
                }
                Button("Скасувати", role: .cancel) { importURL = nil }
            } message: { Text("Попередня історія також збережеться окремим файлом у сховищі застосунку.") }
        }.navigationViewStyle(.stack).tint(.primary)
    }
    var costFormatter: NumberFormatter {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2; f.minimum = 0; f.maximum = 100000; f.locale = Locale(identifier: "uk_UA"); return f
    }
    func binding<T>(_ key: WritableKeyPath<TrackerState, T>) -> Binding<T> {
        Binding(get: { store.state[keyPath: key] }, set: { value in store.update { $0[keyPath: key] = value } })
    }
    func export(json: Bool) {
        do { share = ExportFile(url: try (json ? store.exportJSON() : store.exportCSV())) }
        catch { store.error = error.localizedDescription }
    }
}
struct ExportFile: Identifiable { let id = UUID(); var url: URL }

struct EditPlanView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var baseline = 150
    @State private var days = 30
    @State private var confirm = false
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Новий етап"), footer: Text("Історія затяжок залишиться. Сьогоднішній ліміт і майбутній прогноз будуть перераховані. Початковий рівень для оцінки економії також зміниться.")) {
                    Stepper("\(baseline) затяжок на старті", value: $baseline, in: 1...5000, step: 10)
                    Stepper("\(days) днів", value: $days, in: 7...365)
                }
                Button("Застосувати план") { confirm = true }
            }.navigationTitle("Змінити план").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } } }
                .confirmationDialog("Застосувати нові параметри?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Застосувати") { store.update { $0.start(baseline: baseline, duration: days, now: Date()); $0.quitAt = nil }; dismiss() }
                }
        }.onAppear { baseline = store.state.baseline; days = store.state.duration }.navigationViewStyle(.stack).tint(.primary)
    }
}

struct ShortcutsHelpView: View {
    @Environment(\.dismiss) var dismiss
    @State private var copied = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: "Завжди під рукою") { dismiss() }
                Card {
                    Label("Віджет", systemImage: "square.grid.2x2").font(.headline)
                    Text("Утримай порожнє місце на головному екрані iPhone → «+» → Puffline. Доступні малий і середній віджети.")
                        .font(.subheadline).foregroundColor(.secondary).padding(.top, 10)
                    Text("На iOS 15 дотик до віджета відкриває застосунок. Кнопка «+» запропонує підтвердити запис.")
                        .font(.caption).foregroundColor(.secondary).padding(.top, 10)
                }
                Card {
                    Label("Команди / Siri", systemImage: "square.stack.3d.up").font(.headline)
                    Text("У застосунку «Команди» створи команду з діями «URL» та «Відкрити URL». Встав адресу нижче. Назви команду, наприклад, «Відмітити затяжку».")
                        .font(.subheadline).foregroundColor(.secondary).padding(.top, 10)
                    Text("puffline://add?count=1").font(.system(size: 14, weight: .medium, design: .monospaced)).padding(.top, 14).textSelection(.enabled)
                    Button(copied ? "Скопійовано" : "Скопіювати адресу") { UIPasteboard.general.string = "puffline://add?count=1"; copied = true }.font(.subheadline).padding(.top, 12)
                    Text("Зміни count=1 на потрібну кількість. Застосунок попросить підтвердження, щоб уникнути випадкових записів.")
                        .font(.caption).foregroundColor(.secondary).padding(.top, 10)
                }
                Card {
                    Label("Швидка дія", systemImage: "hand.tap").font(.headline)
                    Text("Утримай іконку Puffline → «Додати затяжку».").font(.subheadline).foregroundColor(.secondary).padding(.top, 10)
                }
            }.padding(24)
        }.background(Style.bg.ignoresSafeArea()).tint(.primary)
    }
}
