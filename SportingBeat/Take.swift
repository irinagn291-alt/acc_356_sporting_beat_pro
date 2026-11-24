import Foundation
import AVFoundation
import Combine

enum Lane: String, CaseIterable, Codable, Identifiable {
    case contact, motion, ambience
    var id: String { rawValue }
}

struct Prop: Identifiable {
    let id: String
    let lane: Lane
    let family: String
    let sustained: Bool
    let file: String

    static let all = [
        Prop(id: "cushion", lane: .contact, family: "soft", sustained: false, file: "cushion"),
        Prop(id: "keys", lane: .motion, family: "net", sustained: false, file: "keys"),
        Prop(id: "card", lane: .ambience, family: "crowd", sustained: false, file: "card"),
        Prop(id: "blocks", lane: .contact, family: "dry", sustained: false, file: "blocks"),
        Prop(id: "bowl", lane: .motion, family: "metal", sustained: false, file: "bowl"),
        Prop(id: "brush", lane: .ambience, family: "surface", sustained: true, file: "brush"),
        Prop(id: "rubber", lane: .motion, family: "air", sustained: true, file: "rubber"),
        Prop(id: "lid", lane: .motion, family: "metal", sustained: false, file: "lid"),
        Prop(id: "pouch", lane: .contact, family: "soft", sustained: false, file: "pouch"),
        Prop(id: "ratchet", lane: .ambience, family: "crowd", sustained: false, file: "ratchet")
    ]

    var swipe: Bool { id == "card" || id == "keys" || id == "ratchet" }

    var tail: Double {
        switch id {
        case "cushion": return 0.37
        case "keys": return 0.67
        case "card": return 0.93
        case "blocks": return 0.22
        case "bowl": return 0.76
        case "lid": return 0.54
        case "pouch": return 0.32
        case "ratchet": return 0.82
        default: return 0.8
        }
    }

    static func find(_ id: String) -> Prop? { all.first { $0.id == id } }
}

struct Cue: Codable, Identifiable {
    let id: String
    let time: Double
    let lane: Lane
    let family: String
    let length: Double?
    let swell: Bool?
}

struct Frame: Codable {
    let t: Double
    let lead: [Double]
    let other: [Double]
    let ball: [Double]

    subscript(lead: Bool) -> SIMD2<Double> {
        let point = lead ? self.lead : other
        return SIMD2(point[0],point[1])
    }
}

struct Clip: Codable, Identifiable {
    let id: String
    let sport: String
    let duration: Double
    let minimum: Int
    let props: [String]
    let cues: [Cue]
    let frames: [Frame]
    let silence: [Double]?
    let layers: Bool?
    let weather: String?
    let angle: Double?
    let flight: [[Double]]?

    func pose(at time: Double, lead: Bool) -> SIMD3<Double> {
        let next = frames.firstIndex { $0.t > time } ?? frames.count-1
        let a = frames[max(0,next-1)], b = frames[next]
        let u = min(1,max(0,(time-a.t)/max(0.001,b.t-a.t)))
        let left = lead ? a.lead : a.other
        let right = lead ? b.lead : b.other
        // Smooth tangent at stops. Keep travelling segments at a steady pace.
        let blend = u + 0.27*(u*u*(3-2*u)-u)
        return SIMD3(left[0]+(right[0]-left[0])*blend,left[1]+(right[1]-left[1])*blend,left[2]+(right[2]-left[2])*u)
    }

    func ball(at time: Double) -> SIMD2<Double> {
        guard let flight, !flight.isEmpty else { return .zero }
        let next = flight.firstIndex { $0[0] > time } ?? flight.count-1
        let a = flight[max(0,next-1)], b = flight[next]
        let u = min(1,max(0,(time-a[0])/max(0.001,b[0]-a[0])))
        return SIMD2(a[1]+(b[1]-a[1])*u,a[2]+(b[2]-a[2])*u-4*a[3]*u*(1-u))
    }
}

struct Pressure: Codable, Equatable {
    var at: Double
    var level: Float
    var travel: Float? = nil
}

struct PropMotion: Equatable {
    var age: Double = 0
    var force: Double = 0
    var travel: Double = 0
}


struct Stroke: Codable, Equatable, Identifiable {
    var id = UUID()
    let prop: String
    var time: Double
    var length: Double = 0
    var pressure: [Pressure] = [Pressure(at: 0, level: 0.65)]
    var offset: Double = 0
    var audibleLength: Double?
    var envelopeLength: Double?

    var lane: Lane? { Prop.find(prop)?.lane }

    var soundLength: Double {
        if let audibleLength { return audibleLength }
        guard let prop = Prop.find(prop) else { return 0 }
        return prop.sustained ? length : prop.tail
    }

    func level(at elapsed: Double) -> Float { sample(at:elapsed).level }

    func sample(at elapsed: Double) -> Pressure {
        guard let first = pressure.first else { return Pressure(at:elapsed,level:0.65) }
        var previous = first
        for next in pressure.dropFirst() {
            if elapsed < next.at {
                let f = Float(max(0,(elapsed-previous.at)/max(0.001,next.at-previous.at)))
                let a = previous.travel ?? 0, b = next.travel ?? a
                return Pressure(at:elapsed,level:previous.level+(next.level-previous.level)*f,travel:a+(b-a)*f)
            }
            previous = next
        }
        return Pressure(at:elapsed,level:previous.level,travel:previous.travel)
    }

    func motion(at cursor: Double) -> PropMotion {
        guard cursor >= time && cursor < time + soundLength else { return PropMotion() }
        let t = cursor-time
        let sample = sample(at:t)
        let age = t+offset
        let decay = Prop.find(prop)?.sustained == true ? 1 : exp(-max(0,age-0.085)*(prop == "keys" ? 5 : 7.2))
        return PropMotion(age:age,force:Double(sample.level)*decay,travel:Double(sample.travel ?? 0)*decay)
    }

}

struct Take: Codable, Identifiable {
    var id = UUID()
    let clip: String
    var strokes: [Stroke] = []
    var creative = false
}

struct Mark: Identifiable {
    let cue: Cue
    let hit: Stroke?
    let exact: Bool
    let note: String
    var id: String { cue.id }
}

struct Score {
    let marks: [Mark]
    let condition: Bool
    let passed: Bool
    var hits: Int { marks.filter { $0.hit != nil }.count }
    var exact: Bool { condition && marks.allSatisfy(\.exact) }
}

func grade(_ take: Take, _ clip: Clip) -> Score {
    func matches(_ cue: Cue, _ stroke: Stroke, _ window: Double) -> Bool {
        guard stroke.offset == 0, stroke.lane == cue.lane, Prop.find(stroke.prop)?.family == cue.family,
              abs(stroke.time - cue.time) <= window + 0.000001 else { return false }
        if let length = cue.length {
            return abs(stroke.time + stroke.length - cue.time - length) <= window + 0.000001
        }
        return true
    }

    // Find a one-to-one assignment. Prefer exact matches when a cue has several candidates.
    let choices = clip.cues.map { cue in
        take.strokes.indices.filter { matches(cue, take.strokes[$0], 0.35) }.sorted {
            let a = take.strokes[$0], b = take.strokes[$1]
            if matches(cue,a,0.15) != matches(cue,b,0.15) { return matches(cue,a,0.15) }
            return abs(a.time - cue.time) < abs(b.time - cue.time)
        }
    }
    var owners: [Int: Int] = [:]
    func assign(_ cue: Int, _ seen: inout Set<Int>) -> Bool {
        for action in choices[cue] where seen.insert(action).inserted {
            if let owner = owners[action], !assign(owner, &seen) { continue }
            owners[action] = cue
            return true
        }
        return false
    }
    for index in clip.cues.indices {
        var seen = Set<Int>()
        _ = assign(index, &seen)
    }

    let marks = clip.cues.enumerated().map { index, cue -> Mark in
        if let action = owners.first(where: { $0.value == index })?.key {
            let stroke = take.strokes[action]
            let exact = matches(cue, stroke, 0.15)
            return Mark(cue: cue, hit: stroke, exact: exact, note: exact ? "score.exact" : "score.hit")
        }
        let correct = take.strokes.filter { $0.lane == cue.lane && Prop.find($0.prop)?.family == cue.family }
        guard let near = correct.min(by: { abs($0.time - cue.time) < abs($1.time - cue.time) }) else {
            let wrong = take.strokes.contains { abs($0.time - cue.time) <= 0.35 }
            return Mark(cue: cue, hit: nil, exact: false, note: wrong ? "score.family" : "score.missing")
        }
        var note = near.time < cue.time ? "score.early" : "score.late"
        if abs(near.time - cue.time) <= 0.350001 {
            if let length = cue.length,
               abs(near.time + near.length - cue.time - length) > 0.350001 {
                note = near.time + near.length < cue.time + length ? "score.releaseEarly" : "score.releaseLate"
            } else {
                note = "score.used"
            }
        }
        return Mark(cue: cue, hit: nil, exact: false, note: note)
    }

    var condition = true
    if let pause = clip.silence {
        condition = !take.strokes.contains { $0.time < pause[1] && $0.time + max(0.001, $0.soundLength) > pause[0] }
    }
    for mark in marks where mark.cue.swell == true {
        guard let hit = mark.hit else { condition = false; continue }
        let quiet = hit.pressure.map(\.level).min() ?? 0
        let loud = hit.pressure.map(\.level).max() ?? 0
        condition = condition && loud - quiet >= 0.28
    }
    if clip.layers == true {
        condition = condition && Set(marks.compactMap { $0.hit?.lane }).count == Lane.allCases.count
    }
    return Score(marks: marks, condition: condition,
                 passed: condition && marks.filter { $0.hit != nil }.count >= clip.minimum)
}

func replaceBand(_ source: [Stroke], with new: [Stroke], lane: Lane,
                 from lower: Double, to upper: Double) -> [Stroke] {
    var result: [Stroke] = []
    for stroke in source {
        if stroke.lane != lane || stroke.time >= upper || stroke.time + stroke.soundLength <= lower {
            result.append(stroke)
            continue
        }
        if stroke.time < lower {
            var before = stroke
            let cut = lower - stroke.time
            before.audibleLength = cut
            if Prop.find(stroke.prop)?.sustained == true {
                before.envelopeLength = stroke.envelopeLength ?? stroke.length
                before.length = cut
                before.pressure = stroke.pressure.filter { $0.at < cut }
                before.pressure.append(stroke.sample(at:cut))
            }
            result.append(before)
        }
        if stroke.time + stroke.soundLength > upper {
            var after = stroke
            let cut = upper - stroke.time
            after.id = UUID()
            after.time = upper
            after.audibleLength = stroke.soundLength - cut
            if Prop.find(stroke.prop)?.sustained == true {
                after.envelopeLength = stroke.envelopeLength ?? stroke.length
            }
            after.length = max(0,stroke.length - cut)
            after.offset += cut
            var split = stroke.sample(at:cut)
            split.at = 0
            after.pressure = [split]
            after.pressure += stroke.pressure.filter { $0.at > cut }.map {
                Pressure(at:$0.at-cut,level:$0.level,travel:$0.travel)
            }
            result.append(after)
        }
    }
    result += new.filter { $0.lane == lane && $0.time >= lower && $0.time < upper }.map {
        var stroke = $0
        stroke.audibleLength = min(stroke.soundLength, upper - stroke.time)
        stroke.length = min(stroke.length, upper - stroke.time)
        return stroke
    }
    return result.sorted { $0.time < $1.time }
}

final class FoleySound {
    static let rate = 32000
    private var samples: [String: [Int16]] = [:]
    private var preview: [String: AVAudioPlayer] = [:]
    private var player: AVAudioPlayer?

    init(folder: URL) {
        for prop in Prop.all {
            if let wav = try? Data(contentsOf: folder.appendingPathComponent(prop.file + ".wav")), wav.count > 44 {
                samples[prop.id] = wav.dropFirst(44).withUnsafeBytes {
                    Array($0.bindMemory(to: Int16.self))
                }
                #if !targetEnvironment(simulator)
                preview[prop.id] = try? AVAudioPlayer(data: wav)
                preview[prop.id]?.prepareToPlay()
                #endif
            }
        }
        #if os(iOS) && !targetEnvironment(simulator)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        #endif
    }

    func tap(_ prop: Prop, _ level: Float) {
        let voice = preview[prop.id]
        voice?.currentTime = 0
        voice?.numberOfLoops = prop.sustained ? -1 : 0
        voice?.volume = level
        voice?.play()
    }

    func volume(_ id: String, _ level: Float) { preview[id]?.volume = level }
    func release(_ id: String) { preview[id]?.stop() }

    func stop() {
        player?.stop()
        for voice in preview.values { voice.stop() }
    }

    func prepare(_ strokes: [Stroke], duration: Double, from time: Double, only lane: Lane?) {
        #if !targetEnvironment(simulator)
        player = try? AVAudioPlayer(data: wave(strokes, duration: duration, only: lane))
        player?.currentTime = time
        player?.prepareToPlay()
        #endif
    }

    func playPrepared() { player?.play() }

    func waveform(_ stroke: Stroke, at time: Double, span: Double) -> Double {
        guard let sample = samples[stroke.prop], !sample.isEmpty else { return 0 }
        let start = Int((time + stroke.offset) * Double(Self.rate))
        let step = max(1,Int(span * Double(Self.rate)) / 12)
        var peak = 0
        for i in 0..<12 {
            peak = max(peak,abs(Int(sample[(start + i*step) % sample.count])))
        }
        return min(1, Double(peak) / 18000 * Double(stroke.level(at: time)))
    }

    // Replay and QA export both use this PCM renderer.
    func wave(_ strokes: [Stroke], duration: Double, only lane: Lane? = nil) -> Data {
        let rate = Self.rate
        var mix = [Float](repeating: 0, count: max(1, Int(duration * Double(rate))))
        for stroke in strokes {
            guard let prop = Prop.find(stroke.prop), lane == nil || lane == prop.lane,
                  let sample = samples[stroke.prop], !sample.isEmpty else { continue }
            let start = max(0, Int((stroke.time * Double(rate)).rounded()))
            let count = max(0, Int((stroke.soundLength * Double(rate)).rounded()))
            let phase = Int((stroke.offset * Double(rate)).rounded())
            let fullLength = Int(((stroke.envelopeLength ?? stroke.length) * Double(rate)).rounded())
            guard start < mix.count, count > 0 else { continue }
            let end = min(count, mix.count - start)
            var pressureIndex = 0
            let points = stroke.pressure
            for i in 0..<end {
                let sampleTime = Double(i) / Double(rate)
                while pressureIndex + 1 < points.count && points[pressureIndex + 1].at <= sampleTime {
                    pressureIndex += 1
                }
                var level = points.isEmpty ? 0.65 : points[pressureIndex].level
                if pressureIndex + 1 < points.count {
                    let previous = points[pressureIndex], next = points[pressureIndex + 1]
                    let f = Float(max(0,(sampleTime - previous.at) / max(0.001,next.at - previous.at)))
                    level += (next.level - level) * f
                }
                let sampleIndex = i + phase
                let fade = prop.sustained ? max(0,min(1,Float(min(sampleIndex + 1,fullLength - sampleIndex)) / 256)) : 1
                mix[start + i] += Float(sample[sampleIndex % sample.count]) * level * fade
            }
        }
        let pcm = mix.map { Int16(max(-32767, min(32767, $0))) }
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + pcm.count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(pcm.count * 2))
        pcm.withUnsafeBufferPointer { data.append(contentsOf: UnsafeRawBufferPointer($0)) }
        return data
    }
}

final class Transport: ObservableObject {
    enum Mode { case idle, mute, countdown, capture, replay }
    @Published var mode: Mode = .idle
    @Published var cursor = 0.0
    @Published var count = 0
    @Published var pressed: [String: Float] = [:]
    @Published var recorded: [Stroke] = []
    @Published var lastHit: Stroke?
    var lastHitAt = -10.0
    var playback: [Stroke] = []
    private var touched: [String: Double] = [:]
    private var travel: [String: Float] = [:]

    let sound: FoleySound
    var limit = 8.0
    var lower = 0.0
    var only: Lane?
    var finished: (([Stroke]) -> Void)?
    var ended: (() -> Void)?
    private var epoch = 0.0
    private var pending: [String: Stroke] = [:]
    private var timer: Timer?

    init(folder: URL) {
        sound = FoleySound(folder: folder)
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private var elapsed: Double { position(now) }

    private func position(_ uptime: Double) -> Double {
        max(lower,min(limit,uptime-epoch))
    }

    func mute(_ duration: Double) {
        stop()
        lower = 0
        cursor = 0
        limit = duration
        epoch = now
        mode = .mute
    }

    func capture(from: Double, to: Double, lane: Lane?, backing: [Stroke], duration: Double) {
        stop()
        lower = from
        cursor = from
        limit = to
        only = lane
        recorded = []
        hasBacking = !backing.isEmpty
        playback = backing
        if hasBacking { sound.prepare(backing, duration: duration, from: from, only: nil) }
        epoch = now + 3 - from
        count = 3
        mode = .countdown
    }

    private var hasBacking = false

    func replay(_ take: Take, duration: Double, from: Double = 0, solo: Lane? = nil) {
        stop()
        lower = from
        cursor = from
        limit = duration
        playback = take.strokes.filter { solo == nil || $0.lane == solo }
        sound.prepare(playback, duration: duration, from: from, only: nil)
        sound.playPrepared()
        epoch = now - from
        mode = .replay
    }

    func stop() {
        if mode == .capture || mode == .replay || mode == .mute { cursor = elapsed }
        mode = .idle
        pressed = [:]
        pending = [:]
        touched = [:]
        travel = [:]
        sound.stop()
    }

    func tick() {
        if lastHit != nil && now - lastHitAt >= 0.24 { lastHit = nil }
        if mode == .countdown {
            let left = Int(ceil(epoch + lower - now))
            if left > 0 {
                if left != count { count = left }
                return
            }
            if hasBacking { sound.playPrepared() }
            epoch = now - lower
            mode = .capture
        }
        if mode == .idle { return }
        cursor = elapsed
        guard cursor >= limit else { return }
        let previous = mode
        if previous == .capture {
            for id in Array(pending.keys) { up(id) }
        }
        stop()
        if previous == .capture { finished?(recorded) }
        if previous == .replay { ended?() }
        if previous == .mute { mute(limit) }
    }

    func isAudible(_ lane: Lane) -> Bool {
        if lastHit?.lane == lane && now - lastHitAt < 0.24 { return true }
        if pressed.keys.contains(where: { Prop.find($0)?.lane == lane }) { return true }
        guard mode == .replay || mode == .capture else { return false }
        return playback.contains { $0.lane == lane && cursor >= $0.time && cursor < $0.time + $0.soundLength }
    }

    var shownProps: [Stroke] {
        guard mode == .replay || (mode == .capture && hasBacking) else { return [] }
        return Lane.allCases.compactMap { lane in
            playback.last { $0.lane == lane && $0.motion(at:cursor).force > 0.025 }
        }
    }

    func propMotion(_ id: String) -> PropMotion {
        if let started = touched[id] {
            let age = max(0,now-started)
            if let force = pressed[id], Prop.find(id)?.sustained == true {
                return PropMotion(age:age,force:Double(force),travel:Double(travel[id] ?? 0))
            }
            if age < 0.46 {
                let decay = exp(-max(0,age-0.10)*7)
                return PropMotion(age:age,force:Double(pressed[id] ?? 0.74)*decay,travel:Double(travel[id] ?? 0)*decay)
            }
        }
        if let stroke = shownProps.first(where: { $0.prop == id }) { return stroke.motion(at:cursor) }
        return PropMotion()
    }

    func down(_ prop: Prop, level: Float, timestamp: Double? = nil) {
        if mode == .countdown || mode == .replay || pressed[prop.id] != nil { return }
        if mode == .capture && only != nil && only != prop.lane { return }
        let time = position(timestamp ?? now)
        if mode == .capture && time >= limit { return }
        touched[prop.id] = now
        travel[prop.id] = 0
        pressed[prop.id] = level
        sound.tap(prop, level)
        lastHitAt = now
        lastHit = Stroke(prop: prop.id, time: mode == .capture ? time : cursor,
                         pressure: [Pressure(at: 0, level: level)])
        guard mode == .capture, let stroke = lastHit else { return }
        if prop.sustained { pending[prop.id] = stroke }
        else { recorded.append(stroke) }
    }

    func move(_ id: String, level: Float, travel shift: Float? = nil, timestamp: Double? = nil) {
        guard pressed[id] != nil, let prop = Prop.find(id), prop.sustained || prop.swipe else { return }
        guard abs((pressed[id] ?? 0)-level) > 0.03 ||
              abs((travel[id] ?? 0)-(shift ?? 0)) > 0.055 else { return }
        travel[id] = shift
        pressed[id] = level
        sound.volume(id, level)
        let time = position(timestamp ?? now)
        if var stroke = pending[id] {
            let at = max(0,time-stroke.time)
            stroke.pressure.append(Pressure(at:at,level:level,travel:shift))
            pending[id] = stroke
        } else if mode == .capture, prop.swipe,
                  let index = recorded.lastIndex(where: { $0.prop == id && time - $0.time < prop.tail }) {
            let at = max(0,time-recorded[index].time)
            recorded[index].pressure.append(Pressure(at:at,level:level,travel:shift))
        }
    }

    func up(_ id: String, timestamp: Double? = nil) {
        pressed[id] = nil
        if Prop.find(id)?.sustained == true { sound.release(id) }
        if var stroke = pending.removeValue(forKey: id) {
            stroke.length = max(0.04,position(timestamp ?? now)-stroke.time)
            recorded.append(stroke)
        }
    }
}
