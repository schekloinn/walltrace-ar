import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var pendingAdd = false
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if options.shortcutItem?.type == "local.puffline.add" { Self.pendingAdd = true }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickSceneDelegate.self
        return configuration
    }
}
final class QuickSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        AppDelegate.pendingAdd = true
        NotificationCenter.default.post(name: Notification.Name("PufflineQuickAdd"), object: nil)
        completionHandler(true)
    }
}

@main
struct PufflineApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .environment(\.locale, Locale(identifier: "uk_UA"))
                .preferredColorScheme(store.state.appearance == "system" ? nil : (store.state.appearance == "dark" ? .dark : .light))
                .onOpenURL { store.route($0) }
        }
    }
}

enum ScreenSheet: String, Identifiable {
    case settings, add, breathe, history
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) var phase
    @State private var tab = ProcessInfo.processInfo.arguments.contains("--progress") ? 1 : 0
    @State private var sheet: ScreenSheet?
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var body: some View {
        Group {
            if store.storageBlocked { RecoveryView() }
            else if !store.state.onboarded { OnboardingView() }
            else {
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            header
                            if tab == 0 { HomeView(sheet: $sheet) }
                            else { ProgressViewContent() }
                            Text("Маленькі кроки. Твоя свобода.")
                                .font(.caption).foregroundColor(.secondary).padding(.vertical, 12)
                        }.padding(.horizontal, 18).padding(.top, 14)
                    }
                    tabBar
                }.background(Style.bg.ignoresSafeArea())
            }
        }
        .tint(.primary)
        .sheet(item: $sheet) { item in
            switch item {
            case .settings: SettingsView()
            case .add: AddPuffsView()
            case .breathe: BreatheView()
            case .history: HistoryView()
            }
        }
        .alert("Puffline", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Зрозуміло") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .alert("Додати затяжки?", isPresented: Binding(get: { store.incomingCount != nil }, set: { if !$0 { store.incomingCount = nil } })) {
            Button("Додати \(store.incomingCount ?? 1)") { store.add(store.incomingCount ?? 1, trigger: "Швидка команда"); store.incomingCount = nil }
            Button("Скасувати", role: .cancel) { store.incomingCount = nil }
        } message: { Text("Запис буде додано до сьогоднішнього лічильника.") }
        .onChange(of: phase) { value in if value == .active { store.refresh(); handleQuickAction() } }
        .onReceive(timer) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PufflineQuickAdd"))) { _ in handleQuickAction() }
        .onAppear {
            handleQuickAction()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--settings") { sheet = .settings }
            if ProcessInfo.processInfo.arguments.contains("--breathe") { sheet = .breathe }
            #endif
        }
    }
    func handleQuickAction() {
        if AppDelegate.pendingAdd { AppDelegate.pendingAdd = false; store.incomingCount = 1 }
    }
    var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Puffline").font(.system(size: 29, weight: .bold, design: .rounded)).tracking(-1.0)
                Text(tab == 0 ? store.now.ukSentence("EEEE, d MMMM") : "Твій прогрес, крок за кроком")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            Button { sheet = .settings } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44).background(Style.card).clipShape(Circle())
            }.accessibilityLabel("Налаштування")
        }.padding(.bottom, 4)
    }
    var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(0, "Сьогодні", "plus.app.fill")
            Rectangle().fill(Style.subtle).frame(width: 1, height: 25)
            tabButton(1, "Прогрес", "chart.bar.xaxis")
        }.padding(.top, 12).padding(.bottom, 8).background(Style.card)
    }
    func tabButton(_ index: Int, _ label: String, _ icon: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { tab = index } } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }.frame(maxWidth: .infinity).frame(minHeight: 42).foregroundColor(tab == index ? .primary : .secondary)
        }.accessibilityAddTraits(tab == index ? .isSelected : [])
    }
}

struct HomeView: View {
    @EnvironmentObject var store: Store
    @Binding var sheet: ScreenSheet?
    @State private var confirmQuit = false
    var compact: Bool { UIScreen.main.bounds.height < 700 }
    var body: some View {
        VStack(spacing: 14) {
            limitStrip
            counter
            addButton
            HStack {
                Button { sheet = .add } label: { Label("Додати кілька", systemImage: "square.stack.3d.up") }
                Spacer()
                Button { store.undo() } label: { Label("Скасувати", systemImage: "arrow.uturn.backward") }.disabled(!store.canUndo)
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 2)
            HStack(spacing: 12) {
                Card { Metric(value: "\(store.remaining)", label: "залишилося на день") }
                Card { Metric(value: "\(store.state.avoided(until: store.now))", label: "затяжок уникнуто*") }
            }
            Button { sheet = .breathe } label: {
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "wind").font(.title2).frame(width: 42, height: 42).background(Style.subtle).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Хочеться попарити?").font(.system(size: 15, weight: .semibold))
                            Text("Зроби паузу на одну хвилину").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption)
                    }
                }
            }.buttonStyle(.plain)
            if let quit = store.state.quitAt {
                Card {
                    Label("Я обираю свободу", systemImage: "sparkles").font(.headline)
                    Text("Без вейпу з \(quit.uk("d MMMM, HH:mm"))").font(.subheadline).foregroundColor(.secondary).padding(.top, 4)
                    Text("\(max(0, Int(store.now.timeIntervalSince(quit) / 3600))) годин без нових записів")
                        .font(.title2.bold()).padding(.top, 10)
                }
            } else {
                Button("Це була остання затяжка") { confirmQuit = true }
                    .font(.system(size: 13, weight: .medium)).padding(.vertical, 8)
            }
            Text(store.state.motivation).font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 20)
            Button { sheet = .history } label: { Label("Історія записів", systemImage: "clock.arrow.circlepath").font(.caption) }.padding(.top, 8)
        }.confirmationDialog("Почати відлік без вейпу?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Так, почати відлік") { store.update { $0.quitAt = Date() } }
            Button("Скасувати", role: .cancel) {}
        } message: { Text("Історія збережеться. Новий запис затяжки скине цей відлік, але не твій прогрес.") }
    }
    var limitStrip: some View {
        HStack(spacing: 8) {
            Text("\(store.limit)").font(.system(size: 14, weight: .bold, design: .rounded))
                .padding(.horizontal, 13).padding(.vertical, 7).background(Style.ink).foregroundColor(Style.card).clipShape(Capsule())
            Text("Ліміт на сьогодні").font(.system(size: 11)).foregroundColor(.secondary)
            Spacer(minLength: 0)
            Text(store.state.paused ? "Пауза" : "День \(dayNumber)")
                .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 7)
                .background(Style.card).clipShape(Capsule())
        }.padding(6).background(Style.ink.opacity(0.07)).clipShape(Capsule())
    }
    var dayNumber: Int { max(1, (Calendar.current.dateComponents([.day], from: DayKey.date(store.state.startDay), to: store.now).day ?? 0) + 1) }
    var counter: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Style.card)
            GeometryReader { geo in
                VStack { Spacer(minLength: 0); Rectangle().fill(Style.ink.opacity(0.055)).frame(height: geo.size.height * min(1, CGFloat(store.used) / CGFloat(max(1, store.limit)))) }
            }.clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            VStack(spacing: compact ? 6 : 14) {
                HStack {
                    Label("ЗАТЯЖКИ", systemImage: "cloud").font(.system(size: 10, weight: .semibold))
                    Spacer()
                    if store.used > store.limit { Text("ПОНАД ЛІМІТ").font(.system(size: 9, weight: .bold)).foregroundColor(Style.warning) }
                }.foregroundColor(.secondary)
                Spacer(minLength: 0)
                Text("\(store.used)").font(.system(size: compact ? 76 : 88, weight: .semibold, design: .rounded)).tracking(-4)
                    .minimumScaleFactor(0.45).lineLimit(1)
                    .accessibilityLabel("Сьогодні \(store.used) затяжок")
                Text("із \(store.limit) на сьогодні").font(.system(size: 13)).foregroundColor(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Circle().fill(store.used > store.limit ? Style.warning : Style.ink.opacity(0.4)).frame(width: 5, height: 5)
                    Text(lastLabel).font(.system(size: 11))
                }.foregroundColor(.secondary).padding(.horizontal, 12).padding(.vertical, 8).background(Style.subtle).clipShape(Capsule())
            }.padding(compact ? 18 : 23)
        }.frame(height: compact ? 220 : 275)
    }
    var lastLabel: String {
        guard let last = store.last else { return "Твій перший крок починається тут" }
        let minutes = max(0, Int(store.now.timeIntervalSince(last.date) / 60))
        if minutes < 1 { return "Остання: щойно" }
        if minutes < 60 { return "Остання: \(minutes) хв тому" }
        return "Остання: \(last.date.uk("d MMM, HH:mm"))"
    }
    var addButton: some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { store.add() } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Style.ink)
                Circle().fill(Style.card.opacity(0.08)).frame(width: 150, height: 150).blur(radius: 8)
                VStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 28, weight: .medium))
                        .frame(width: 74, height: 48).background(Style.card).foregroundColor(Style.ink).clipShape(Capsule())
                    Text("Відмітити затяжку").font(.system(size: 11, weight: .medium)).foregroundColor(Style.card.opacity(0.6))
                }
            }.frame(height: compact ? 105 : 133).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }.buttonStyle(.plain).accessibilityLabel("Додати одну затяжку")
    }
}

