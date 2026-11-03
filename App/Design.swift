import SwiftUI
import UIKit

enum Style {
    static let bg = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let muted = Color.secondary
    static let subtle = Color.primary.opacity(0.055)
    static let success = Color(red: 0.22, green: 0.52, blue: 0.37)
    static let warning = Color(red: 0.78, green: 0.37, blue: 0.23)
}

struct Card<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Style.card).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct PrimaryButton: View {
    var title: String
    var symbol: String = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: symbol) }
                .font(.system(size: 16, weight: .semibold)).padding(19)
                .foregroundColor(Style.card).background(Style.ink)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }.buttonStyle(.plain)
    }
}

struct Metric: View {
    var value: String
    var label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension Date {
    func uk(_ format: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "uk_UA"); formatter.dateFormat = format
        return formatter.string(from: self)
    }
}

struct BarDatum: Identifiable {
    var id: String
    var value: Int
    var target: Int
    var label: String
    var selected: Bool
    var recorded: Bool
}

struct Bars: View {
    var data: [BarDatum]
    var dense = false
    var body: some View {
        let maximum = max(1, data.map { max($0.value, $0.target) }.max() ?? 1)
        HStack(alignment: .bottom, spacing: dense ? 3 : 8) {
            ForEach(data) { item in
                VStack(spacing: 8) {
                    GeometryReader { proxy in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: dense ? 3 : 6)
                                .fill(Style.subtle)
                                .frame(height: max(3, proxy.size.height * CGFloat(item.target) / CGFloat(maximum)))
                            RoundedRectangle(cornerRadius: dense ? 3 : 6)
                                .fill(item.selected ? Style.ink : Style.ink.opacity(0.45))
                                .frame(height: item.value > 0 ? max(3, proxy.size.height * CGFloat(item.value) / CGFloat(maximum)) : 0)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    if !dense { Text(item.label).font(.system(size: 10, weight: item.selected ? .bold : .regular)).foregroundColor(.secondary) }
                }.accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.label): \(item.value) затяжок, ліміт \(item.target)\(item.recorded ? "" : ", немає записів")")
            }
        }.frame(height: dense ? 110 : 140)
    }
}

struct SheetHeader: View {
    var title: String
    var dismiss: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.title2.bold())
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).padding(12).background(Style.subtle).clipShape(Circle()) }
                .accessibilityLabel("Закрити")
        }.foregroundColor(.primary)
    }
}
