import AppKit
import CoreImage
import CoreML
import CoreVideo
import Foundation
import Vision

enum MaskError: Error, CustomStringConvertible {
    case usage
    case imageLoad(String)
    case cgImage(String)
    case noResult
    case noInstances
    case output(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: vision-foreground-mask <input-image> <output-mask-png>"
        case .imageLoad(let path):
            return "cannot load image: \(path)"
        case .cgImage(let path):
            return "cannot decode CGImage: \(path)"
        case .noResult:
            return "Vision returned no foreground result"
        case .noInstances:
            return "Vision found no foreground instances"
        case .output(let path):
            return "cannot write output: \(path)"
        }
    }
}

func main() throws {
    guard CommandLine.arguments.count == 3 else { throw MaskError.usage }
    let input = CommandLine.arguments[1]
    let output = CommandLine.arguments[2]
    guard let image = NSImage(contentsOfFile: input) else {
        throw MaskError.imageLoad(input)
    }
    var rect = NSRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        throw MaskError.cgImage(input)
    }

    let request = VNGenerateForegroundInstanceMaskRequest()
    request.usesCPUOnly = true
    for (stage, devices) in try request.supportedComputeStageDevices {
        if let cpu = devices.first(where: { device in
            if case .cpu = device { return true }
            return false
        }) {
            request.setComputeDevice(cpu, for: stage)
        }
    }
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
    try handler.perform([request])
    guard let observation = request.results?.first else { throw MaskError.noResult }
    let instances = observation.allInstances
    guard !instances.isEmpty else { throw MaskError.noInstances }
    let buffer = try observation.generateScaledMaskForImage(
        forInstances: instances,
        from: handler
    )

    let ciImage = CIImage(cvPixelBuffer: buffer)
    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let maskImage = context.createCGImage(ciImage, from: ciImage.extent) else {
        throw MaskError.output(output)
    }
    let bitmap = NSBitmapImageRep(cgImage: maskImage)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw MaskError.output(output)
    }
    try data.write(to: URL(fileURLWithPath: output), options: .atomic)
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
