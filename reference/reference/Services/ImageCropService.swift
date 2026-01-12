import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ImageCropService {

    /// Apply a normalized crop rect to image data and return cropped image data
    /// - Parameters:
    ///   - data: Original image data
    ///   - cropRect: Normalized rect (0.0-1.0) defining the crop area
    /// - Returns: Cropped image data as JPEG, or nil if cropping fails
    static func applyCrop(to data: Data, cropRect: CGRect) -> Data? {
        // Only skip cropping if the image is already square AND crop is full size at origin
        // For non-square images, we always need to crop to make it square
        if cropRect.origin.x == 0 && cropRect.origin.y == 0 && cropRect.width >= 1.0 {
            if let size = getImageSize(from: data), abs(size.width - size.height) < 1 {
                // Image is already square, no crop needed
                return data
            }
        }

        #if os(macOS)
        return applyCropMacOS(to: data, cropRect: cropRect)
        #else
        return applyCropiOS(to: data, cropRect: cropRect)
        #endif
    }

    #if os(macOS)
    private static func applyCropMacOS(to data: Data, cropRect: CGRect) -> Data? {
        guard let nsImage = NSImage(data: data) else { return nil }

        // Get the bitmap representation to access actual pixel dimensions
        guard let bitmapRep = nsImage.representations.first as? NSBitmapImageRep else {
            // Fallback: try to create bitmap from TIFF
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else {
                return nil
            }
            return cropBitmap(bitmap, cropRect: cropRect)
        }

        return cropBitmap(bitmapRep, cropRect: cropRect)
    }

    private static func cropBitmap(_ bitmap: NSBitmapImageRep, cropRect: CGRect) -> Data? {
        let imageWidth = CGFloat(bitmap.pixelsWide)
        let imageHeight = CGFloat(bitmap.pixelsHigh)

        // cropRect uses normalized coordinates where:
        // - origin.x and origin.y are 0.0-1.0 relative to image dimensions
        // - width/height (cropSize) is relative to shorter dimension for square crop
        let shorterDim = min(imageWidth, imageHeight)
        let cropPixelSize = cropRect.width * shorterDim

        // Convert normalized rect to pixel rect (square crop)
        let pixelRect = CGRect(
            x: cropRect.origin.x * imageWidth,
            y: cropRect.origin.y * imageHeight,
            width: cropPixelSize,
            height: cropPixelSize
        )

        guard let cgImage = bitmap.cgImage?.cropping(to: pixelRect) else {
            return nil
        }

        let croppedBitmap = NSBitmapImageRep(cgImage: cgImage)
        return croppedBitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
    #endif

    #if os(iOS) || os(visionOS)
    private static func applyCropiOS(to data: Data, cropRect: CGRect) -> Data? {
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
        let pixelRect = CGRect(
            x: cropRect.origin.x * imageWidth,
            y: cropRect.origin.y * imageHeight,
            width: cropPixelSize,
            height: cropPixelSize
        )

        guard let croppedCGImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }

        let croppedUIImage = UIImage(cgImage: croppedCGImage)
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
