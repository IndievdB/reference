import Foundation
import Vision
import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Service for detecting head pose from images using Vision framework
enum HeadPoseDetectionService {

    /// Detect head pose from the cropped region of an image
    /// - Parameters:
    ///   - imageData: Original image data
    ///   - cropRect: Normalized crop rect (0.0-1.0)
    ///   - rotation: Crop rotation in degrees
    /// - Returns: Detected HeadRotation, or nil if no face found
    static func detectHeadPose(from imageData: Data, cropRect: CGRect, rotation: Double) -> HeadRotation? {
        // Apply crop to analyze only the visible region
        guard let croppedData = ImageCropService.applyCrop(to: imageData, cropRect: cropRect, rotation: rotation),
              let cgImage = createCGImage(from: croppedData) else {
            return nil
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let face = request.results?.first else {
                return nil
            }

            // Vision returns angles in radians, convert to degrees
            // Yaw: positive = looking right, negative = looking left
            // Pitch: positive = looking up, negative = looking down
            // Roll: head tilt
            let yawDegrees = (face.yaw?.doubleValue ?? 0) * 180 / .pi
            let pitchDegrees = (face.pitch?.doubleValue ?? 0) * 180 / .pi
            let rollDegrees = (face.roll?.doubleValue ?? 0) * 180 / .pi

            return HeadRotation(
                yaw: yawDegrees,
                pitch: pitchDegrees,
                roll: rollDegrees
            )
        } catch {
            return nil
        }
    }

    /// Create a CGImage from image data
    private static func createCGImage(from data: Data) -> CGImage? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.cgImage
        #else
        guard let uiImage = UIImage(data: data) else {
            return nil
        }
        return uiImage.cgImage
        #endif
    }
}
