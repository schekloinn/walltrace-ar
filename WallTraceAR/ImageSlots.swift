// The three image slots are independent; rendering/AR state lives separately.
struct ImageSlots<Content> {
    struct Item {
        var content: Content?
        var name = ""
        var width: Float = 0.5
        var opacity: Float = 0.65
    }

    static var capacity: Int { 3 }
    private var items: [Item] = (0..<3).map { _ in Item() }
    private(set) var selectedIndex = 0
    subscript(index: Int) -> Item { items[index] }

    mutating func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    mutating func replace(at index: Int, content: Content, name: String) {
        guard items.indices.contains(index) else { return }
        items[index].content = content
        items[index].name = name
    }

    mutating func setAppearance(width: Float, opacity: Float) {
        items[selectedIndex].width = min(max(width, 0.05), 2)
        items[selectedIndex].opacity = min(max(opacity, 0.05), 1)
    }

    mutating func removeSelected() { items[selectedIndex] = Item() }
}
