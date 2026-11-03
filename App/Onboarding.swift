import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: Store
    @State private var baseline = 150
    @State private var days = 30
    @State private var cost = "50"
    @State private var reason = ""
    @State private var step = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Puffline").font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-1)
                    Spacer()
                    Text("\(step + 1) / 2").font(.caption).foregroundColor(.secondary)
                }.padding(.top, 18)
                Image(systemName: step == 0 ? "wind" : "slider.horizontal.3")
                    .font(.system(size: 42, weight: .light)).frame(width: 100, height: 100)
                    .background(Style.ink).foregroundColor(Style.card).clipShape(RoundedRectangle(cornerRadius: 30)).padding(.top, 28)
                Text(step == 0 ? "Менше затяжок.\nБільше тебе." : "Твій темп.\nТвій початок.")
                    .font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.5)
                Text(step == 0 ? "Відмічай затяжки, стеж за лімітом і поступово рухайся до свободи. Без підписок і зайвого шуму." : "Обери початковий рівень і бажану тривалість. Змінити їх можна пізніше.")
                    .font(.system(size: 15)).foregroundColor(.secondary).lineSpacing(4)
                if step == 0 {
                    VStack(alignment: .leading, spacing: 18) {
                        introRow("plus", "Один дотик — один запис")
                        introRow("chart.bar", "Твій прогрес у простих графіках")
                        introRow("lock", "Історія зберігається на телефоні")
                    }.padding(.vertical, 12)
                    PrimaryButton(title: "Почати") { withAnimation { step = 1 } }
                } else {
                    Card {
                        Stepper(value: $baseline, in: 1...5000, step: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(baseline)").font(.title.bold().monospacedDigit())
                                Text("затяжок на день зараз").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Divider().padding(.vertical, 12)
                        Picker("Тривалість плану", selection: $days) {
                            Text("14 днів").tag(14); Text("30 днів").tag(30); Text("60 днів").tag(60); Text("90 днів").tag(90)
                        }.pickerStyle(.menu)
                        Divider().padding(.vertical, 12)
                        HStack {
                            Text("Витрати за день, ₴").font(.subheadline)
                            TextField("50", text: $cost).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                    TextField("Заради чого ти починаєш?", text: $reason).padding(18).background(Style.card).clipShape(RoundedRectangle(cornerRadius: 18))
                    PrimaryButton(title: "Створити мій план", symbol: "checkmark") {
                        let parsed = Double(cost.replacingOccurrences(of: ",", with: ".")) ?? 0
                        store.start(baseline: baseline, days: days, cost: min(100000, max(0, parsed)), reason: reason)
                    }
                    Button("Назад") { step = 0 }.font(.caption).frame(maxWidth: .infinity)
                }
                Text("Puffline — інструмент самоконтролю. Застосунок не визначає затяжки автоматично: їх потрібно відмічати вручну.")
                    .font(.system(size: 11)).foregroundColor(.secondary).padding(.bottom, 16)
            }.padding(24)
        }.background(Style.bg.ignoresSafeArea()).tint(.primary)
    }
    func introRow(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 14) { Image(systemName: icon).font(.system(size: 15, weight: .semibold)).frame(width: 24); Text(title).font(.system(size: 14)) }
    }
}
