import AVFoundation
import CoreVideo
import Foundation
import Vision

let args = CommandLine.arguments
let asset = AVURLAsset(url:URL(fileURLWithPath:args[1]))
let from = Double(args[2])!, to = Double(args[3])!
func tm(_ seconds: Double) -> CMTime { CMTime(seconds:seconds,preferredTimescale:60000) }

if args.count > 4 && args[4] == "clock" {
    let generator = AVAssetImageGenerator(asset:asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceAfter = .zero
    generator.requestedTimeToleranceBefore = .zero
    for p in stride(from:from,through:to,by:1) {
        let frame = try await generator.image(at:tm(p))
        let request = VNRecognizeTextRequest()
        request.usesLanguageCorrection = false
        request.recognitionLevel = .accurate
        request.regionOfInterest = CGRect(x:0,y:0.85,width:1,height:0.145)
        try VNImageRequestHandler(cgImage:frame.image).perform([request])
        let strings = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        print(String(format:"%.3f",frame.actualTime.seconds),strings.joined(separator:" | "))
    }
} else {
    let track = try await asset.loadTracks(withMediaType:.video).first!
    let reader = try AVAssetReader(asset:asset)
    reader.timeRange = CMTimeRange(start:tm(from),end:tm(to))
    let output = AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { throw reader.error! }
    var count = 0, moves = 0
    var lastFrame = from, lastMove = from, maxFrameGap = 0.0, maxMoveGap = 0.0
    var previous = [UInt8]()
    while let sample = output.copyNextSampleBuffer(),
          let image = sample.imageBuffer {
        let time = sample.presentationTimeStamp.seconds
        maxFrameGap = max(maxFrameGap,time-lastFrame)
        lastFrame = time
        count += 1
        CVPixelBufferLockBaseAddress(image,.readOnly)
        let pixels = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to:UInt8.self)
        let width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image)
        let pitch = CVPixelBufferGetBytesPerRow(image)
        var values: [UInt8] = []
        for iy in 0..<84 {
            let y = height*32/100 + height*42/100*iy/84
            for ix in 0..<112 {
                let x = width*5/100 + width*90/100*ix/112
                let offset = y*pitch+x*4
                values.append(UInt8((Int(pixels[offset])+2*Int(pixels[offset+1])+Int(pixels[offset+2]))/4))
            }
        }
        CVPixelBufferUnlockBaseAddress(image,.readOnly)
        var changed = 0
        if !previous.isEmpty {
            for i in values.indices where abs(Int(values[i])-Int(previous[i])) >= 18 { changed += 1 }
        }
        if previous.isEmpty || changed >= 5 {
            moves += 1
            maxMoveGap = max(maxMoveGap,time-lastMove)
            lastMove = time
            previous = values
        }
    }
    let total = max(0.01,to-from)
    maxMoveGap = max(maxMoveGap,to-lastMove)
    print(String(format:"%.2f–%.2f s: %d source frames (%.2f/s), %d changes to the playing field (%.2f/s), max PTS gap %.0f ms, max scene-change gap %.0f ms.",
                 from,to,count,Double(count)/total,moves,Double(moves)/total,maxFrameGap*1000,maxMoveGap*1000))
}
