import AVFoundation
import CoreImage
import Foundation
import ImageIO
import VideoToolbox

enum HEVCAlphaEncodeError: Error, CustomStringConvertible {
  case usage
  case noFrames
  case load(String)
  case writer(String)
  case outputExists(String)

  var description: String {
    switch self {
    case .usage:
      "usage: encode-hevc-alpha <png-directory> <output.mov> <fps>"
    case .noFrames:
      "input directory has no PNG frames"
    case .load(let value):
      "failed to load \(value)"
    case .writer(let value):
      "asset writer failed: \(value)"
    case .outputExists(let value):
      "output already exists: \(value)"
    }
  }
}

func loadCGImage(_ url: URL) throws -> CGImage {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else {
    throw HEVCAlphaEncodeError.load(url.path)
  }
  return image
}

do {
  guard
    CommandLine.arguments.count == 4,
    let fps = Int32(CommandLine.arguments[3]),
    fps > 0
  else {
    throw HEVCAlphaEncodeError.usage
  }
  let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
  let output = URL(fileURLWithPath: CommandLine.arguments[2])
  let manager = FileManager.default
  if manager.fileExists(atPath: output.path) {
    throw HEVCAlphaEncodeError.outputExists(output.path)
  }
  let frames = try manager.contentsOfDirectory(
    at: inputDirectory,
    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
    options: [.skipsHiddenFiles]
  ).filter { url in
    guard url.pathExtension.lowercased() == "png" else { return false }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    return values.isRegularFile == true && values.isSymbolicLink != true
  }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  guard let firstURL = frames.first else {
    throw HEVCAlphaEncodeError.noFrames
  }
  let firstImage = try loadCGImage(firstURL)
  let width = firstImage.width
  let height = firstImage.height
  let started = CFAbsoluteTimeGetCurrent()

  let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
  let outputSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
  ]
  guard writer.canApply(outputSettings: outputSettings, forMediaType: .video) else {
    throw HEVCAlphaEncodeError.writer("HEVC with Alpha is unavailable")
  }
  let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
  input.expectsMediaDataInRealTime = false
  guard writer.canAdd(input) else {
    throw HEVCAlphaEncodeError.writer("cannot add video input")
  }
  writer.add(input)

  let attributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
  ]
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: attributes
  )
  guard writer.startWriting() else {
    throw HEVCAlphaEncodeError.writer(
      writer.error?.localizedDescription ?? "startWriting returned false"
    )
  }
  writer.startSession(atSourceTime: .zero)
  guard let pool = adaptor.pixelBufferPool else {
    throw HEVCAlphaEncodeError.writer("pixel buffer pool was not created")
  }
  let context = CIContext(options: [.cacheIntermediates: false])
  guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    throw HEVCAlphaEncodeError.writer("cannot create sRGB color space")
  }

  for (index, url) in frames.enumerated() {
    while !input.isReadyForMoreMediaData {
      if writer.status == .failed || writer.status == .cancelled {
        throw HEVCAlphaEncodeError.writer(
          writer.error?.localizedDescription ?? "writer stopped"
        )
      }
      usleep(1_000)
    }
    var optionalBuffer: CVPixelBuffer?
    let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
    guard status == kCVReturnSuccess, let pixelBuffer = optionalBuffer else {
      throw HEVCAlphaEncodeError.writer(
        "CVPixelBufferPoolCreatePixelBuffer returned \(status)"
      )
    }
    let image = try loadCGImage(url)
    guard image.width == width, image.height == height else {
      throw HEVCAlphaEncodeError.load("dimension mismatch at \(url.path)")
    }
    context.render(
      CIImage(cgImage: image),
      to: pixelBuffer,
      bounds: CGRect(x: 0, y: 0, width: width, height: height),
      colorSpace: colorSpace
    )
    CVBufferSetAttachment(
      pixelBuffer,
      kCVImageBufferAlphaChannelModeKey,
      kCVImageBufferAlphaChannelMode_PremultipliedAlpha,
      .shouldPropagate
    )
    CVBufferSetAttachment(
      pixelBuffer,
      kCVImageBufferColorPrimariesKey,
      kCVImageBufferColorPrimaries_ITU_R_709_2,
      .shouldPropagate
    )
    CVBufferSetAttachment(
      pixelBuffer,
      kCVImageBufferTransferFunctionKey,
      kCVImageBufferTransferFunction_sRGB,
      .shouldPropagate
    )
    CVBufferSetAttachment(
      pixelBuffer,
      kCVImageBufferYCbCrMatrixKey,
      kCVImageBufferYCbCrMatrix_ITU_R_709_2,
      .shouldPropagate
    )
    guard adaptor.append(
      pixelBuffer,
      withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps)
    ) else {
      throw HEVCAlphaEncodeError.writer(
        writer.error?.localizedDescription ?? "append failed at \(index)"
      )
    }
  }

  input.markAsFinished()
  let semaphore = DispatchSemaphore(value: 0)
  writer.finishWriting { semaphore.signal() }
  semaphore.wait()
  guard writer.status == .completed else {
    throw HEVCAlphaEncodeError.writer(
      writer.error?.localizedDescription ?? "finish status \(writer.status.rawValue)"
    )
  }
  let outputBytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
  let report: [String: Any] = [
    "frameCount": frames.count,
    "fps": fps,
    "width": width,
    "height": height,
    "bytes": outputBytes,
    "encodeSeconds": CFAbsoluteTimeGetCurrent() - started,
    "codec": "AVVideoCodecTypeHEVCWithAlpha",
    "alphaMode": "premultiplied",
    "transferFunction": "sRGB",
  ]
  let data = try JSONSerialization.data(
    withJSONObject: report,
    options: [.prettyPrinted, .sortedKeys]
  )
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
