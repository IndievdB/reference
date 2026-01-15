import Foundation
import CoreImage
import CoreML
import Vision

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Service for estimating depth from images using Core ML
enum DepthEstimationService {

    private static var cachedModel: VNCoreMLModel?

    /// Estimate depth from image data using Depth Anything V2
    /// Returns a grayscale CIImage where brighter = closer, darker = farther
    static func estimateDepth(from imageData: Data) async -> CIImage? {
        guard let cgImage = createCGImage(from: imageData) else {
            print("DepthEstimation: Failed to create CGImage")
            return nil
        }

        // Try ML model first, fall back to approximation
        if let depthMap = await estimateDepthWithML(cgImage: cgImage) {
            return depthMap
        }

        print("DepthEstimation: ML model failed, using approximation")
        return createApproximateDepthMap(from: imageData)
    }

    /// Estimate depth using the Core ML model
    private static func estimateDepthWithML(cgImage: CGImage) async -> CIImage? {
        do {
            let model = try await loadModel()

            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            guard let results = request.results,
                  let observation = results.first as? VNPixelBufferObservation else {
                print("DepthEstimation: No results from model")
                return nil
            }

            // Convert pixel buffer to CIImage
            var depthImage = CIImage(cvPixelBuffer: observation.pixelBuffer)

            // The model outputs inverse depth (closer = higher values)
            // Normalize and scale to match original image size
            let originalWidth = CGFloat(cgImage.width)
            let originalHeight = CGFloat(cgImage.height)
            let depthWidth = depthImage.extent.width
            let depthHeight = depthImage.extent.height

            // Scale depth map to original image size
            let scaleX = originalWidth / depthWidth
            let scaleY = originalHeight / depthHeight
            depthImage = depthImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            return depthImage

        } catch {
            print("DepthEstimation error: \(error)")
            return nil
        }
    }

    /// Load the Core ML model (cached for performance)
    private static func loadModel() async throws -> VNCoreMLModel {
        if let cached = cachedModel {
            return cached
        }

        // Try to load the bundled model
        guard let modelURL = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc") ??
                            Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlpackage") else {
            throw DepthEstimationError.modelNotFound
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all  // Use Neural Engine when available

        let mlModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
        let vnModel = try VNCoreMLModel(for: mlModel)

        cachedModel = vnModel
        return vnModel
    }

    /// Creates an approximate depth map using radial gradient (fallback)
    private static func createApproximateDepthMap(from imageData: Data) -> CIImage? {
        guard let size = getImageSize(from: imageData) else { return nil }

        let centerX = size.width / 2
        let centerY = size.height / 2
        let radius = min(size.width, size.height) * 0.6

        guard let radialGradient = CIFilter(name: "CIRadialGradient") else { return nil }
        radialGradient.setValue(CIVector(x: centerX, y: centerY), forKey: "inputCenter")
        radialGradient.setValue(radius * 0.3, forKey: "inputRadius0")
        radialGradient.setValue(radius, forKey: "inputRadius1")
        radialGradient.setValue(CIColor.white, forKey: "inputColor0")
        radialGradient.setValue(CIColor.black, forKey: "inputColor1")

        guard let gradientImage = radialGradient.outputImage else { return nil }
        return gradientImage.cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Create CGImage from data
    private static func createCGImage(from data: Data) -> CGImage? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.cgImage
        #else
        guard let uiImage = UIImage(data: data) else { return nil }
        return uiImage.cgImage
        #endif
    }

    /// Get image dimensions from data
    private static func getImageSize(from data: Data) -> CGSize? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data),
              let rep = nsImage.representations.first else { return nil }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        #else
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return nil }
        return CGSize(width: cgImage.width, height: cgImage.height)
        #endif
    }
}

enum DepthEstimationError: Error {
    case modelNotFound
    case predictionFailed
}
