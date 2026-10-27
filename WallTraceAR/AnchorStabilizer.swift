import Foundation
import simd

// ARAnchor remains authoritative. This filter only controls presentation, never
// raycasts/reanchors placed content and never attaches an image to the camera.
struct AnchorStabilizer {
    enum Reason: Equatable { case steady, tooClose, tracking, recovering, correcting }
    struct Output {
        let transform: simd_float4x4
        let visible: Bool
        let reason: Reason
    }

    private(set) var transform: simd_float4x4
    private var lastTimestamp: TimeInterval
    private var normalSince: TimeInterval?
    private var nearWall = false
    private var candidate: simd_float4x4?
    private var candidateSince: TimeInterval = 0

    init(transform: simd_float4x4, timestamp: TimeInterval, requiresRecovery: Bool = false) {
        self.transform = transform
        lastTimestamp = timestamp
        // Placement itself requires a stable normal tracking period.
        normalSince = requiresRecovery ? nil : timestamp - 0.6
    }

    mutating func update(target: simd_float4x4, camera: SIMD3<Float>,
                         trackingNormal: Bool, timestamp: TimeInterval) -> Output {
        let dt = Float(min(max(timestamp - lastTimestamp, 0), 0.1))
        lastTimestamp = timestamp
        if !trackingNormal {
            normalSince = nil
            candidate = nil
            return output(false, .tracking)
        }
        let normal = SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let distance = abs(simd_dot(camera - Self.position(transform), normal))
        // Hysteresis prevents flicker around the near-wall threshold.
        nearWall = nearWall ? distance < 0.30 : distance < 0.20
        if nearWall {
            normalSince = nil
            candidate = nil
            return output(false, .tooClose)
        }
        if normalSince == nil { normalSince = timestamp }
        guard timestamp - (normalSince ?? timestamp) >= 0.5 else {
            return output(false, .recovering)
        }

        let oldPosition = Self.position(transform)
        let newPosition = Self.position(target)
        let oldRotation = simd_quatf(transform)
        let newRotation = simd_quatf(target)
        let displacement = simd_distance(oldPosition, newPosition)
        let angle = Self.rotationDifference(oldRotation, newRotation)
        // A large map correction is accepted only after the new estimate stays
        // consistent. Reconcile while hidden, rather than sliding across a wall.
        if displacement > 0.08 || angle > 8 * .pi / 180 {
            if let previous = candidate,
               simd_distance(Self.position(previous), newPosition) < 0.015,
               Self.rotationDifference(simd_quatf(previous), newRotation) < 1.5 * .pi / 180 {
                if timestamp - candidateSince >= 0.35 {
                    transform = target
                    candidate = nil
                    return output(true, .steady)
                }
            } else {
                candidateSince = timestamp
                candidate = target
            }
            return output(false, .correcting)
        }
        candidate = nil
        let alpha = 1 - exp(-dt / 0.18)
        var position = oldPosition
        var rotation = oldRotation
        if displacement > 0.001 {
            let fraction = min(alpha, 0.12 * dt / displacement)
            position += (newPosition - oldPosition) * fraction
        }
        if angle > 0.15 * .pi / 180 {
            let fraction = min(alpha, (25 * .pi / 180) * dt / angle)
            rotation = simd_slerp(oldRotation, newRotation, fraction)
        }
        transform = simd_float4x4(rotation)
        transform.columns.3 = SIMD4<Float>(position, 1)
        return output(true, .steady)
    }

    private func output(_ visible: Bool, _ reason: Reason) -> Output {
        Output(transform: transform, visible: visible, reason: reason)
    }

    static func position(_ matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    static func rotationDifference(_ first: simd_quatf, _ second: simd_quatf) -> Float {
        2 * acos(min(abs(simd_dot(first.vector, second.vector)), 1))
    }
}
