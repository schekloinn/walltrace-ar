import Foundation
import simd

@main
enum Checks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func main() {
        var slots = ImageSlots<String>()
        for index in 0..<3 {
            slots.select(index)
            slots.replace(at: index, content: "image\(index)", name: "\(index).png")
            slots.setAppearance(width: Float(index + 1) * 0.3, opacity: Float(index + 1) * 0.2)
        }
        slots.select(9)
        require(slots.selectedIndex == 2, "Invalid selection must not escape three slots")
        slots.replace(at: 3, content: "fourth", name: "fourth.png")
        require(ImageSlots<String>.capacity == 3, "Only three slots")
        slots.select(1)
        slots.removeSelected()
        require(slots[0].content == "image0" && slots[2].content == "image2", "Deleting one slot must preserve its neighbours")
        require(slots[1].content == nil, "Selected image deleted")
        require(abs(slots[0].width - 0.3) < 0.0001 && abs(slots[2].opacity - 0.6) < 0.0001,
                "Slot appearances must be independent")
        slots.select(0)
        slots.setAppearance(width: 99, opacity: -2)
        require(slots[0].width == 2 && slots[0].opacity == 0.05, "Clamp controls safely")

        let identity = matrix_identity_float4x4
        let far = SIMD3<Float>(0, 0, 1)
        var filter = AnchorStabilizer(transform: identity, timestamp: 0)
        let near = filter.update(target: identity, camera: SIMD3<Float>(0, 0, 0.15), trackingNormal: true, timestamp: 0.1)
        require(!near.visible && near.reason == .tooClose, "Hide an unreliable close-up overlay")
        let hysteresis = filter.update(target: identity, camera: SIMD3<Float>(0, 0, 0.25), trackingNormal: true, timestamp: 0.2)
        require(!hysteresis.visible && hysteresis.reason == .tooClose, "No near-threshold flicker")
        require(!filter.update(target: identity, camera: far, trackingNormal: true, timestamp: 0.3).visible,
                "Wait for normal tracking to settle")
        require(filter.update(target: identity, camera: far, trackingNormal: true, timestamp: 0.9).visible,
                "Restore after recovery")
        require(!filter.update(target: identity, camera: far, trackingNormal: false, timestamp: 1).visible,
                "Tracking loss must hide content")
        _ = filter.update(target: identity, camera: far, trackingNormal: true, timestamp: 1.1)
        require(filter.update(target: identity, camera: far, trackingNormal: true, timestamp: 1.7).visible,
                "Recover after tracking loss")

        var smoothing = AnchorStabilizer(transform: identity, timestamp: 0)
        var shifted = identity
        shifted.columns.3.x = 0.04
        let smoothed = smoothing.update(target: shifted, camera: far, trackingNormal: true, timestamp: 1.0 / 30)
        require(smoothed.visible && smoothed.transform.columns.3.x > 0 && smoothed.transform.columns.3.x <= 0.00401,
                "Small correction must be speed limited, not snap")
        var jump = identity
        jump.columns.3.x = 0.2
        let held = smoothing.update(target: jump, camera: far, trackingNormal: true, timestamp: 0.1)
        require(!held.visible && held.reason == .correcting, "Large correction must be hidden")
        require(held.transform.columns.3.x < 0.01, "Hold the last accepted world pose")
        require(!smoothing.update(target: jump, camera: far, trackingNormal: true, timestamp: 0.3).visible,
                "Reject a single short-lived correction")
        let settled = smoothing.update(target: jump, camera: far, trackingNormal: true, timestamp: 0.5)
        require(settled.visible && abs(settled.transform.columns.3.x - 0.2) < 0.0001,
                "Accept a persistent correction while hidden")
        var restored = AnchorStabilizer(transform: identity, timestamp: 0, requiresRecovery: true)
        require(!restored.update(target: identity, camera: far, trackingNormal: true, timestamp: 0.1).visible,
                "A restored map must not show content before tracking settles")
        require(restored.update(target: identity, camera: far, trackingNormal: true, timestamp: 0.7).visible,
                "Show restored content after stable tracking")
        var drifting = AnchorStabilizer(transform: identity, timestamp: 0)
        _ = drifting.update(target: jump, camera: far, trackingNormal: true, timestamp: 0.1)
        jump.columns.3.x = 0.212
        _ = drifting.update(target: jump, camera: far, trackingNormal: true, timestamp: 0.2)
        jump.columns.3.x = 0.224
        require(!drifting.update(target: jump, camera: far, trackingNormal: true, timestamp: 0.3).visible,
                "A wandering correction must restart its consistency window")
        require(!drifting.update(target: jump, camera: far, trackingNormal: true, timestamp: 0.5).visible,
                "Do not accept accumulated drift as a stable correction")
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let storedImage = SavedProject.Image(slot: 2, name: "saved.png", png: pngHeader, width: 0.7,
                                            opacity: 0.4, anchorID: UUID())
        let project = SavedProject(selectedIndex: 2, worldMap: Data([1, 2, 3]), images: [storedImage])
        do {
            let data = try JSONEncoder().encode(project)
            let decoded = try JSONDecoder().decode(SavedProject.self, from: data)
            try decoded.validate()
            let saveURL = URL(fileURLWithPath: "build/check-scene.json")
            try project.write(to: saveURL)
            let fromDisk = try SavedProject.read(from: saveURL)
            require(fromDisk.images[0].name == "saved.png", "Read the written scene from disk")
            let validBytes = try Data(contentsOf: saveURL)
            require(decoded.images[0].anchorID == storedImage.anchorID && decoded.selectedIndex == 2,
                    "Persist anchor identity and selection")
            require(decoded.images[0].width == 0.7 && decoded.images[0].opacity == 0.4,
                    "Persist per-image settings")
            var invalid = decoded
            invalid.images.append(storedImage)
            do { try invalid.write(to: saveURL); fatalError("Do not overwrite a valid save with invalid data") } catch {}
            require((try? Data(contentsOf: saveURL)) == validBytes, "A failed save must preserve the last valid scene")
            do { try invalid.validate(); fatalError("Reject duplicate slots and anchor identities") } catch {}
            invalid = decoded
            invalid.formatVersion = 99
            do { try invalid.validate(); fatalError("Reject unsupported saved format") } catch {}
            invalid = decoded
            invalid.images[0].slot = 4
            do { try invalid.validate(); fatalError("Reject saved fourth slot") } catch {}
        } catch { fatalError("Saved project roundtrip failed: \(error)") }
        print("PASS: saved scene roundtrip, anchor identities, per-image settings and corrupt-state rejection")
        print("PASS: three independent image slots, deletion and limits; close-range hysteresis, tracking recovery, smoothing and large-correction rejection")
    }
}
