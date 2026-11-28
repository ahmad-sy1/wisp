// Compares two PNGs pixel by pixel, for scripts/snapshots.sh.
// Usage: imagediff <reference.png> <new.png> <diff.png>
// Exit 0: the same (within a small tolerance for anti-aliasing). Exit 1: different, and
// <diff.png> shows the changed pixels in red over a faded copy of the new image.
// Exit 2: different sizes (the notch grew or shrank, or another Mac), or a file that can't be read.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A channel may differ this much before a pixel counts as changed.
let channelTolerance = 24
/// Changed pixels allowed, as a share of all pixels.
let pixelTolerance = 0.0005

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func rgba(_ path: String) -> (pixels: [UInt8], width: Int, height: Int) {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("can't read \(path)", code: 2) }
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return (pixels, width, height)
}

let args = CommandLine.arguments
guard args.count == 4 else { fail("usage: imagediff <reference.png> <new.png> <diff.png>", code: 2) }
let reference = rgba(args[1])
let new = rgba(args[2])
guard reference.width == new.width, reference.height == new.height else {
    fail(
        "size \(new.width)×\(new.height) px instead of \(reference.width)×\(reference.height) (the notch changed size, or this is another Mac)",
        code: 2)
}

var changed = 0
var diff = new.pixels
for i in stride(from: 0, to: diff.count, by: 4) {
    let differs = (0..<4).contains { abs(Int(reference.pixels[i + $0]) - Int(new.pixels[i + $0])) > channelTolerance }
    if differs {
        changed += 1
        diff[i] = 255
        diff[i + 1] = 0
        diff[i + 2] = 0
        diff[i + 3] = 255
    } else {
        for c in 0..<3 { diff[i + c] = diff[i + c] / 4 }
        diff[i + 3] = 255
    }
}

let total = reference.width * reference.height
if Double(changed) <= Double(total) * pixelTolerance { exit(0) }

diff.withUnsafeMutableBytes { buffer in
    let context = CGContext(
        data: buffer.baseAddress, width: new.width, height: new.height, bitsPerComponent: 8, bytesPerRow: new.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let url = URL(fileURLWithPath: args[3]) as CFURL
    if let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    {
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
print("\(changed) of \(total) pixels changed")
exit(1)
