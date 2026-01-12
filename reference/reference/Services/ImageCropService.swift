import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ImageCropService {

    /// Apply a normalized crop rect and rotation to image data and return cropped image data
    /// - Parameters:
    ///   - data: Original image data
    ///   - cropRect: Normalized rect (0.0-1.0) defining the crop area
    ///   - rotation: Rotation angle in degrees
    /// - Returns: Cropped image data as JPEG, or nil if cropping fails
    static func applyCrop(to data: Data, cropRect: CGRect, rotation: Double = 0.0) -> Data? {
        // Only skip cropping if the image is already square AND crop is full size at origin AND no rotation
        if cropRect.origin.x == 0 && cropRect.origin.y == 0 && cropRect.width >= 1.0 && rotation == 0 {
            if let size = getImageSize(from: data), abs(size.width - size.height) < 1 {
                // Image is already square, no crop needed
                return data
            }
        }

        #if os(macOS)
        return applyCropMacOS(to: data, cropRect: cropRect, rotation: rotation)
        #else
        return applyCropiOS(to: data, cropRect: cropRect, rotation: rotation)
        #endif
    }

    #if os(macOS)
    private static func applyCropMacOS(to data: Data, cropRect: CGRect, rotation: Double) -> Data? {
        guard let nsImage = NSImage(data: data) else { return nil }

        // Get the bitmap representation to access actual pixel dimensions
        guard let bitmapRep = nsImage.representations.first as? NSBitmapImageRep else {
            // Fallback: try to create bitmap from TIFF
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else {
                return nil
            }
            return cropBitmap(bitmap, cropRect: cropRect, rotation: rotation)
        }

        return cropBitmap(bitmapRep, cropRect: cropRect, rotation: rotation)
    }

    private static func cropBitmap(_ bitmap: NSBitmapImageRep, cropRect: CGRect, rotation: Double) -> Data? {
        let imageWidth = CGFloat(bitmap.pixelsWide)
        let imageHeight = CGFloat(bitmap.pixelsHigh)

        // cropRect uses normalized coordinates where:
        // - origin.x and origin.y are 0.0-1.0 relative to image dimensions
        // - width/height (cropSize) is relative to shorter dimension for square crop
        let shorterDim = min(imageWidth, imageHeight)
        let cropPixelSize = cropRect.width * shorterDim

        // Convert normalized rect to pixel rect (square crop)
        let cropCenterX = cropRect.origin.x * imageWidth + cropPixelSize / 2
        let cropCenterY = cropRect.origin.y * imageHeight + cropPixelSize / 2

        guard let sourceCGImage = bitmap.cgImage else { return nil }

        // Create output context for square crop
        let outputSize = Int(cropPixelSize)
        guard let context = CGContext(
            data: nil,
            width: outputSize,
            height: outputSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Move to center of output, rotate, then draw image offset so crop area is centered
        context.translateBy(x: CGFloat(outputSize) / 2, y: CGFloat(outputSize) / 2)
        context.rotate(by: rotation * .pi / 180)  // Match SwiftUI rotation direction
        context.translateBy(x: -cropCenterX, y: -(imageHeight - cropCenterY))  // Flip Y for CG coordinates

        context.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard let outputCGImage = context.makeImage() else { return nil }

        let croppedBitmap = NSBitmapImageRep(cgImage: outputCGImage)
        return croppedBitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
    #endif

    #if os(iOS) || os(visionOS)
    private static func applyCropiOS(to data: Data, cropRect: CGRect, rotation: Double) -> Data? {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            return nil
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // cropRect uses normalized coordinates where:
        // - origin.x and origin.y are 0.0-1.0 relative to image dimensions
        // - width/height (cropSize) is relative to shorter dimension for square crop
        let shorterDim = min(imageWidth, imageHeight)
        let cropPixelSize = cropRect.width * shorterDim

        // Convert normalized rect to pixel rect (square crop)
        let cropCenterX = cropRect.origin.x * imageWidth + cropPixelSize / 2
        let cropCenterY = cropRect.origin.y * imageHeight + cropPixelSize / 2

        // Create output context for square crop
        let outputSize = Int(cropPixelSize)
        guard let context = CGContext(
            data: nil,
            width: outputSize,
            height: outputSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Move to center of output, rotate, then draw image offset so crop area is centered
        context.translateBy(x: CGFloat(outputSize) / 2, y: CGFloat(outputSize) / 2)
        context.rotate(by: rotation * .pi / 180)  // Match SwiftUI rotation direction
        context.translateBy(x: -cropCenterX, y: -(imageHeight - cropCenterY))  // Flip Y for CG coordinates

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard let outputCGImage = context.makeImage() else { return nil }

        let croppedUIImage = UIImage(cgImage: outputCGImage)
        return croppedUIImage.jpegData(compressionQuality: 0.9)
    }
    #endif

    /// Get image dimensions from data
    static func getImageSize(from data: Data) -> CGSize? {
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
