import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

enum ColorworkImage {
    static func chart(from data: Data, name: String, width: Int, height: Int, colorCount: Int) -> ColorworkChart? {
        guard ColorworkChart.validSize(width, height), (2...8).contains(colorCount),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return chart(from: CIImage(cgImage: thumbnail), name: name, width: width, height: height, colorCount: colorCount)
    }

    static func chart(from image: CIImage, name: String, width: Int, height: Int, colorCount: Int) -> ColorworkChart? {
        guard ColorworkChart.validSize(width, height), (2...8).contains(colorCount),
              !image.extent.isInfinite, image.extent.width > 0, image.extent.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY)).clampedToExtent()
        let scale = CGFloat(height) / image.extent.height
        filter.scale = Float(scale)
        filter.aspectRatio = Float(CGFloat(width) / image.extent.width / scale)
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        guard let scaled = filter.outputImage?.cropped(to: bounds) else { return nil }
        let opaque = scaled.composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: bounds))
        guard let image = CIContext().createCGImage(opaque, from: bounds, format: .RGBA8, colorSpace: space) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4 * width * height)
        let pixels: [ChartSwatch]? = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            context.draw(image, in: bounds)
            return stride(from: 0, to: buffer.count, by: 4).map { ChartSwatch(buffer[$0], buffer[$0 + 1], buffer[$0 + 2]) }
        }
        return pixels.flatMap { ChartQuantizer.chart(name: name, width: width, height: height, pixels: $0, colorCount: colorCount) }
    }
}
