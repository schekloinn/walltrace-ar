import AppKit
import Foundation

let folder = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sizes: [(Double, Int)] = [(20,2),(20,3),(29,2),(29,3),(40,2),(40,3),(60,2),(60,3),(1024,1)]
var entries: [[String: String]] = []
for (points, scale) in sizes {
    let pixels = Int(points) * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixels, height: pixels)).fill()
    let p = CGFloat(pixels)
    for index in 0..<3 {
        let path = NSBezierPath()
        let y = p * (0.33 + CGFloat(index) * 0.17)
        path.move(to: NSPoint(x: p * 0.24, y: y))
        path.curve(to: NSPoint(x: p * 0.76, y: y), controlPoint1: NSPoint(x: p * 0.39, y: y + p * 0.16), controlPoint2: NSPoint(x: p * 0.61, y: y - p * 0.16))
        path.lineWidth = p * 0.052; path.lineCapStyle = .round
        NSColor.white.withAlphaComponent(index == 1 ? 1 : 0.55).setStroke(); path.stroke()
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let name = "icon-\(Int(points))-\(scale).png"
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    entries.append(["idiom": points == 1024 ? "ios-marketing" : "iphone", "size": "\(Int(points))x\(Int(points))", "scale": "\(scale)x", "filename": name])
}
let json: [String: Any] = ["images": entries, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
