import Foundation
import simd

/// Represents head rotation in Euler angles (degrees)
struct HeadRotation: Equatable {
    var yaw: Double    // Left/Right (-180 to 180)
    var pitch: Double  // Up/Down (-90 to 90)
    var roll: Double   // Tilt (-180 to 180)

    static let zero = HeadRotation(yaw: 0, pitch: 0, roll: 0)

    /// Convert to radians for SceneKit (pitch, yaw, roll order)
    var asRadians: (pitch: Float, yaw: Float, roll: Float) {
        (
            pitch: Float(pitch * .pi / 180),
            yaw: Float(yaw * .pi / 180),
            roll: Float(roll * .pi / 180)
        )
    }

    /// Calculate angular distance between two rotations using quaternions
    /// Returns a value from 0 (identical) to 180 (opposite)
    func angularDistance(to other: HeadRotation) -> Double {
        let q1 = self.toQuaternion()
        let q2 = other.toQuaternion()

        // Dot product of quaternions gives cos(theta/2)
        let dot = abs(simd_dot(q1, q2))
        let clampedDot = min(1.0, max(-1.0, Double(dot)))

        // Convert to angle in degrees
        return 2.0 * acos(clampedDot) * 180.0 / .pi
    }

    /// Check if rotation is within tolerance of another
    func isWithinTolerance(of other: HeadRotation, degrees: Double = 20.0) -> Bool {
        return angularDistance(to: other) <= degrees
    }

    /// Convert Euler angles to quaternion for accurate angle comparison
    private func toQuaternion() -> simd_quatf {
        let yawRad = Float(yaw * .pi / 180)
        let pitchRad = Float(pitch * .pi / 180)
        let rollRad = Float(roll * .pi / 180)

        // Apply rotations in YXZ order (yaw, pitch, roll)
        let qYaw = simd_quatf(angle: yawRad, axis: SIMD3<Float>(0, 1, 0))
        let qPitch = simd_quatf(angle: pitchRad, axis: SIMD3<Float>(1, 0, 0))
        let qRoll = simd_quatf(angle: rollRad, axis: SIMD3<Float>(0, 0, 1))

        return qYaw * qPitch * qRoll
    }
}

// MARK: - Photo Extension

extension Photo {
    /// Get head rotation as HeadRotation struct, nil if not set
    var headRotation: HeadRotation? {
        get {
            guard let yaw = headYaw,
                  let pitch = headPitch,
                  let roll = headRoll else {
                return nil
            }
            return HeadRotation(yaw: yaw, pitch: pitch, roll: roll)
        }
        set {
            headYaw = newValue?.yaw
            headPitch = newValue?.pitch
            headRoll = newValue?.roll
        }
    }
}
