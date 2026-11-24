import AVFoundation
import Foundation
import Vision

let args = CommandLine.arguments
let run = URL(fileURLWithPath:args[1],isDirectory:true)
let audio = URL(fileURLWithPath:args[2],isDirectory:true)
let output = URL(fileURLWithPath:args[3])
let selected = args.count > 4 ? Set(args[4].split(separator:",").map(String.init)) :
    Set(["net-goal","first-serve","iron-rim","finish-straight"])
let cuts: [String:(Double,Double)] = [
    "net-goal": (0.88,7.57), "first-serve": (1.54,5.14),
    "iron-rim": (1.49,8.65), "finish-straight": (4.98,11.12)
]
let runs = [run]+args.dropFirst(5).map { URL(fileURLWithPath:$0,isDirectory:true) }
let clockPattern = try NSRegularExpression(pattern:#"([0-9]{2})\s*[:.;]\s*([0-9]{2})\s*[:.,]\s*([0-9]{2})"#)
func clock(_ value: String) -> Double? {
    guard let match = clockPattern.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)) else { return nil }
    let values = (1...3).compactMap { Range(match.range(at:$0),in:value).flatMap { Double(value[$0]) } }
    return values.count == 3 ? values[0]*60+values[1]+values[2]/100 : nil
}
func tm(_ x: Double) -> CMTime { CMTime(seconds:x,preferredTimescale:60000) }

func resolve(_ estimate: Double,_ id: String,_ generator: AVAssetImageGenerator) async throws -> Double {
    var readings: [Double] = []
    for dt in [1.73,2.38,3.24,4.02,4.83] {
        let sample = try await generator.image(at:tm(estimate+dt))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.regionOfInterest = CGRect(x:0.53,y:0.86,width:0.46,height:0.135)
        try VNImageRequestHandler(cgImage:sample.image).perform([request])
        let values = (request.results ?? []).compactMap { $0.topCandidates(1).first }.compactMap { clock($0.string) }
        if let value = values.first(where:{ abs($0-dt) < 1.5 }) {
            readings.append(sample.actualTime.seconds-value)
        }
    }
    guard readings.count >= 2 else { throw NSError(domain:"No HUD sync for "+id,code:1) }
    let ordered = readings.sorted()
    let middle = ordered[ordered.count/2]
    let agreeing = ordered.filter { abs($0-middle) <= 0.10 }
    guard agreeing.count >= 2 else { throw NSError(domain:"Inconsistent HUD sync for "+id,code:2) }
    let aligned = agreeing.reduce(0,+)/Double(agreeing.count)
    print(String(format:"%@ HUD sync from %d samples, spread %.0f ms; source starts at %.3f",
                 id,agreeing.count,((agreeing.last ?? aligned)-(agreeing.first ?? aligned))*1000,aligned))
    return aligned
}
let mix = AVMutableComposition()
let picture = mix.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!
let soundtrack = mix.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!
var head = CMTime.zero
var clips: [String:(group: URL,wall: Double)] = [:]
for group in runs {
    let log = try String(contentsOf:group.appendingPathComponent("test.log"),encoding:.utf8)
    for row in log.split(separator:"\n") where row.hasPrefix("MOTION_VIDEO ") {
        let fields = row.split(separator:" ")
        guard fields.count == 4, let wall = Double(fields[2]) else { continue }
        clips[String(fields[1])] = (group,wall)
    }
}
for id in ["net-goal","first-serve","iron-rim","finish-straight"] where selected.contains(id) {
    guard let take = clips[id], let (start,end) = cuts[id] else { continue }
    let host = try Double(String(contentsOf:take.group.appendingPathComponent("video-start.txt"),encoding:.utf8)
        .trimmingCharacters(in:.whitespacesAndNewlines))!
    let source = AVURLAsset(url:take.group.appendingPathComponent("session.mp4"))
    let video = try await source.loadTracks(withMediaType:.video).first!
    let generator = AVAssetImageGenerator(asset:source)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    if head == .zero { picture.preferredTransform = try await video.load(.preferredTransform) }
    let origin = try await resolve(take.wall-host,id,generator)
    let wave = AVURLAsset(url:audio.appendingPathComponent(id+".wav"))
    let pcm = try await wave.loadTracks(withMediaType:.audio).first!
    let length = tm(end-start)
    try picture.insertTimeRange(CMTimeRange(start:tm(origin+start),duration:length),of:video,at:head)
    try soundtrack.insertTimeRange(CMTimeRange(start:tm(start),duration:length),of:pcm,at:head)
    print(String(format:"%@ %@ clip %.2f–%.2f, output %.2f, duration %.2f",
                 take.group.lastPathComponent,id,start,end,head.seconds,length.seconds))
    head = head+length
}
precondition(head > .zero)
let exporter = AVAssetExportSession(asset:mix,presetName:AVAssetExportPresetHighestQuality)!
exporter.shouldOptimizeForNetworkUse = true
try await exporter.export(to:output,as:.mp4)
let result = AVURLAsset(url:output)
print("Film:",try await result.load(.duration).seconds,"seconds; audio tracks:",try await result.loadTracks(withMediaType:.audio).count)
