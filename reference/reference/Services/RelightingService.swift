import Foundation
import CoreImage
import CoreGraphics
import simd

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Parameters for relighting effect
struct RelightingParams {
    var lightDirection: CGPoint = .zero  // -1 to 1 for X and Y
    var intensity: Double = 1.0          // 0 to 2
    var lightColor: CIColor = CIColor.white
    var shadowLift: Double = 0.0         // 0 to 1

    static let `default` = RelightingParams()
}

/// Service for applying relighting effects to images
enum RelightingService {

    /// Apply relighting effect to an image using a depth map
    /// - Parameters:
    ///   - imageData: Original image data
    ///   - depthMap: Depth map (brighter = closer)
    ///   - params: Relighting parameters
    /// - Returns: Relit image as CIImage
    static func applyRelighting(
        to imageData: Data,
        depthMap: CIImage,
        params: RelightingParams
    ) -> CIImage? {
        guard let originalImage = createCIImage(from: imageData) else { return nil }

        // Create lighting gradient based on light direction
        let lightingGradient = createLightingGradient(
            size: originalImage.extent.size,
            direction: params.lightDirection,
            depthMap: depthMap
        )

        guard let lightingGradient = lightingGradient else { return originalImage }

        // Apply the lighting effect
        return applyLightingEffect(
            to: originalImage,
            lighting: lightingGradient,
            params: params
        )
    }

    /// Create a lighting gradient based on light direction and depth
    private static func createLightingGradient(
        size: CGSize,
        direction: CGPoint,
        depthMap: CIImage
    ) -> CIImage? {
        // Create directional gradient based on light direction
        let angle = atan2(direction.y, direction.x)
        let magnitude = sqrt(direction.x * direction.x + direction.y * direction.y)

        // Start and end points for linear gradient
        let centerX = size.width / 2
        let centerY = size.height / 2
        let gradientLength = max(size.width, size.height) * 0.5

        let startX = centerX - cos(angle) * gradientLength
        let startY = centerY - sin(angle) * gradientLength
        let endX = centerX + cos(angle) * gradientLength
        let endY = centerY + sin(angle) * gradientLength

        // Create linear gradient for light direction
        guard let linearGradient = CIFilter(name: "CILinearGradient") else { return nil }
        linearGradient.setValue(CIVector(x: startX, y: startY), forKey: "inputPoint0")
        linearGradient.setValue(CIVector(x: endX, y: endY), forKey: "inputPoint1")

        // Light side (where light hits) is brighter
        let lightIntensity = min(1.0, magnitude)
        let brightColor = CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        // Increased contrast from 0.5 to 0.85 for more dramatic lighting
        let darkColor = CIColor(red: 1.0 - lightIntensity * 0.85, green: 1.0 - lightIntensity * 0.85, blue: 1.0 - lightIntensity * 0.85, alpha: 1.0)

        linearGradient.setValue(brightColor, forKey: "inputColor0")
        linearGradient.setValue(darkColor, forKey: "inputColor1")

        guard let directionGradient = linearGradient.outputImage?.cropped(to: CGRect(origin: .zero, size: size)) else {
            return nil
        }

        // Multiply direction gradient with depth map
        // Areas that are closer (brighter in depth) get more light effect
        guard let multiply = CIFilter(name: "CIMultiplyCompositing") else { return nil }
        multiply.setValue(directionGradient, forKey: kCIInputImageKey)
        multiply.setValue(depthMap.cropped(to: CGRect(origin: .zero, size: size)), forKey: kCIInputBackgroundImageKey)

        return multiply.outputImage
    }

    /// Apply lighting effect to original image
    private static func applyLightingEffect(
        to image: CIImage,
        lighting: CIImage,
        params: RelightingParams
    ) -> CIImage? {
        var result = image

        // Apply shadow lift first
        if params.shadowLift > 0 {
            guard let shadowsHighlights = CIFilter(name: "CIShadowsHighlights") else { return result }
            shadowsHighlights.setValue(result, forKey: kCIInputImageKey)
            shadowsHighlights.setValue(params.shadowLift, forKey: "inputShadowAmount")
            shadowsHighlights.setValue(0.0, forKey: "inputHighlightAmount")
            if let output = shadowsHighlights.outputImage {
                result = output
            }
        }

        // Create exposure adjustment based on lighting
        // The lighting gradient controls where exposure is increased/decreased
        guard let exposureAdjust = CIFilter(name: "CIExposureAdjust") else { return result }
        exposureAdjust.setValue(result, forKey: kCIInputImageKey)

        // Calculate exposure value based on intensity (0 = no change, 2 = strong effect)
        // Increased multiplier from 0.5 to 1.5 for more dramatic lighting
        let exposureValue = (params.intensity - 1.0) * 1.5
        exposureAdjust.setValue(exposureValue, forKey: kCIInputEVKey)

        guard let exposed = exposureAdjust.outputImage else { return result }

        // Blend the exposed version with original using the lighting map as mask
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return result }
        blend.setValue(exposed, forKey: kCIInputImageKey)
        blend.setValue(result, forKey: kCIInputBackgroundImageKey)
        blend.setValue(lighting, forKey: kCIInputMaskImageKey)

        guard let blended = blend.outputImage else { return result }

        // Apply light color tint
        if params.lightColor != CIColor.white {
            guard let colorMatrix = CIFilter(name: "CIColorMatrix") else { return blended }
            colorMatrix.setValue(blended, forKey: kCIInputImageKey)

            // Tint based on light color
            let r = params.lightColor.red
            let g = params.lightColor.green
            let b = params.lightColor.blue

            // Color tint - blend towards light color (increased from 0.15)
            let tintStrength = 0.3 * params.intensity
            colorMatrix.setValue(CIVector(x: 1.0 - tintStrength + tintStrength * r, y: 0, z: 0, w: 0), forKey: "inputRVector")
            colorMatrix.setValue(CIVector(x: 0, y: 1.0 - tintStrength + tintStrength * g, z: 0, w: 0), forKey: "inputGVector")
            colorMatrix.setValue(CIVector(x: 0, y: 0, z: 1.0 - tintStrength + tintStrength * b, w: 0), forKey: "inputBVector")

            if let tinted = colorMatrix.outputImage {
                return tinted
            }
        }

        return blended
    }

    /// Create CIImage from data
    private static func createCIImage(from data: Data) -> CIImage? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
        #else
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
        #endif
    }
}
