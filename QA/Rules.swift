import Foundation

@main
struct Rules {
    static func main() throws {
        setbuf(stdout,nil)
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resources = folder.appendingPathComponent("SportingBeat")
        let evidence = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath:$0) }
            ?? folder.appendingPathComponent("QA/evidence")
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        let clips = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: resources.appendingPathComponent("Clips.json")))
        let sound = FoleySound(folder: resources.appendingPathComponent("Audio"))
        let goal = clips[0]
        let original = Take(clip: goal.id, strokes: [
            Stroke(prop: "cushion", time: 2.4),
            Stroke(prop: "keys", time: 3.6),
            Stroke(prop: "card", time: 4.2)
        ])
        let marks = grade(original, goal)
        precondition(marks.passed && marks.hits == 2 && marks.marks.last?.note == "score.early")
        let corrected = Take(clip: goal.id, strokes: replaceBand(original.strokes,
            with: [Stroke(prop: "card", time: 4.95), Stroke(prop: "keys", time: 5)],
            lane: .ambience, from: 4, to: 6))
        precondition(corrected.strokes.prefix(2) == original.strokes.prefix(2))
        precondition(grade(corrected, goal).exact)
        let early = sound.wave(original.strokes, duration: goal.duration)
        let fixed = sound.wave(corrected.strokes, duration: goal.duration)
        func energy(_ data: Data, at: Double, length: Double) -> Int64 {
            let start = 44 + Int(at * 32000) * 2
            let end = start + Int(length * 32000) * 2
            return (start..<end).stride(step: 2).reduce(0) { sum, i in
                let sample = Int16(bitPattern: UInt16(data[i]) | (UInt16(data[i+1]) << 8))
                return sum + Int64(abs(Int(sample)))
            }
        }
        precondition(energy(early, at: 4.23, length: 0.25) > 500_000)
        precondition(energy(fixed, at: 4.34, length: 0.25) == 0)
        precondition(energy(fixed, at: 4.98, length: 0.25) > 500_000)
        for lane in [Lane.contact, .motion] {
            precondition(sound.wave(original.strokes, duration: 8, only: lane) ==
                         sound.wave(corrected.strokes, duration: 8, only: lane))
        }
        try early.write(to: evidence.appendingPathComponent("prototype-original.wav"))
        try fixed.write(to: evidence.appendingPathComponent("prototype-repair.wav"))
        print("PASS prototype: early crowd present in PCM; repair shifts crowd; contact and motion PCM equal")
        if clips.count == 1 { return }
        precondition(clips.count == 16)
        precondition(Set(clips.map(\.id)).count == 16)
        precondition(Set(clips.map(\.sport)).count == 4)
        for sport in Set(clips.map(\.sport)) {
            precondition(clips.filter { $0.sport == sport }.count == 4)
        }
        func ideal(_ clip: Clip) -> Take {
            Take(clip:clip.id,strokes:clip.cues.map { cue in
                let prop = clip.props.compactMap(Prop.find).first { $0.family == cue.family && $0.lane == cue.lane }!
                return Stroke(prop:prop.id,time:cue.time,length:cue.length ?? 0,pressure:[
                    Pressure(at:0,level:0.36),Pressure(at:(cue.length ?? 0)/2,level:0.90)
                ])
            })
        }
        for clip in clips {
            precondition((8...20).contains(clip.duration))
            precondition(clip.frames.first?.t == 0 && clip.frames.last?.t == clip.duration)
            precondition(zip(clip.frames,clip.frames.dropFirst()).allSatisfy { $0.t < $1.t })
            precondition(clip.cues.allSatisfy { $0.time >= 0 && $0.time + ($0.length ?? 0) <= clip.duration })
            precondition(clip.props.allSatisfy { Prop.find($0) != nil })
            let exemplar = ideal(clip)
            precondition(grade(exemplar,clip).passed && grade(exemplar,clip).exact,clip.id)
            precondition(!grade(Take(clip:clip.id),clip).passed,clip.id)
            print("PASS \(clip.id): \(Int(clip.duration)) s, \(clip.cues.count) cues, min \(clip.minimum), \(clip.frames.count) storyboards")
        }
        for clip in clips where clip.sport != "cycling" {
            guard let flight = clip.flight else { fatalError(clip.id) }
            precondition(flight.first?[0] == 0 && flight.last?[0] == clip.duration)
            precondition(flight.allSatisfy { $0.count == 4 && $0.allSatisfy(\.isFinite) })
            precondition(zip(flight,flight.dropFirst()).allSatisfy { $0[0] < $1[0] })
            for cue in clip.cues where cue.family == "soft" || cue.family == "dry" ||
                ["rim","post","net"].contains(cue.id) {
                precondition(flight.contains { abs($0[0]-cue.time) < 0.001 },"\(clip.id):\(cue.id)")
            }
        }
        precondition(goal.ball(at:1) == goal.ball(at:2.39))
        precondition(goal.ball(at:2.4).x < goal.ball(at:2.41).x)
        let rally = clips.first { $0.id == "first-serve" }!
        precondition(rally.ball(at:3.60).y < rally.ball(at:3.65).y && rally.ball(at:3.70).y < rally.ball(at:3.65).y)
        let rim = clips.first { $0.id == "iron-rim" }!
        precondition(rim.ball(at:5.13).y < rim.ball(at:4.05).y && rim.ball(at:6.09).x < rim.ball(at:6.1).x)
        precondition(rim.ball(at:6.11).x < rim.ball(at:6.1).x)
        let gesture = Stroke(prop:"rubber",time:1,length:3,pressure:[
            Pressure(at:0,level:0.36,travel:0),Pressure(at:1,level:0.92,travel:-0.8),
            Pressure(at:2,level:1,travel:1)
        ])
        let decoded = try JSONDecoder().decode(Stroke.self,from:JSONEncoder().encode(gesture))
        precondition(decoded.motion(at:2) == gesture.motion(at:2))
        let slices = replaceBand([decoded],with:[],lane:.motion,from:1.8,to:2.4)
        precondition(slices.count == 2)
        for t in [1.3,1.7,2.8,3.7] {
            let move = slices.map { $0.motion(at:t) }.first { $0.force > 0 }!
            precondition(abs(move.travel-gesture.motion(at:t).travel) < 0.00001)
        }
        let old = Data(#"{"id":"44ED7645-8859-42C8-AEBB-CB28584B08A7","prop":"card","time":2,"length":0,"pressure":[{"at":0,"level":0.8}],"offset":0}"#.utf8)
        let oldStroke = try JSONDecoder().decode(Stroke.self,from:old)
        precondition(oldStroke.motion(at:2).travel == 0)
        print("PASS authored contact boundaries, stationary ball before kick, bounce and rim restitution")
        print("PASS signed gesture round trip, range continuation and pre-motion save compatibility")
        if let path = CommandLine.arguments.dropFirst(2).first {
            struct OldStudio: Decodable {
                let completed: [String]
                let takes: [Take]
                let picks: [String:UUID]
            }
            let oldStudio = try JSONDecoder().decode(OldStudio.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
            precondition(oldStudio.completed.count == 16 && oldStudio.takes.count == 16 && oldStudio.picks.count == 4)
            for take in oldStudio.takes {
                let clip = clips.first { $0.id == take.clip }!
                precondition(grade(take,clip).passed)
            }
            print("PASS original full campaign save: all 16 takes still grade and all 4 picks decode")
        }
        var pouch = original
        pouch.strokes[0] = Stroke(prop:"pouch",time:2.4)
        precondition(grade(pouch,goal).hits == 2)
        precondition(sound.wave(pouch.strokes,duration:8,only:.contact) !=
                     sound.wave(original.strokes,duration:8,only:.contact))
        try sound.wave(original.strokes,duration:8,only:.contact).write(to:evidence.appendingPathComponent("timbre-cushion.wav"))
        try sound.wave(pouch.strokes,duration:8,only:.contact).write(to:evidence.appendingPathComponent("timbre-pouch.wav"))
        let two = clips[1]
        let between = Stroke(prop:"pouch",time:(two.cues[0].time + two.cues[1].time)/2)
        precondition(grade(Take(clip:two.id,strokes:[between]),two).hits == 1)
        let hold = clips.first { $0.id == "track-start" }!
        var missed = ideal(hold)
        missed.strokes[1].length -= 0.6
        let release = grade(missed,hold)
        precondition(!release.passed && release.marks[1].note == "score.releaseEarly")
        let late = clips.last!
        let target = ideal(late)
        var flat = target
        flat.strokes[2].pressure = [Pressure(at:0,level:0.65)]
        precondition(grade(flat,late).hits == 7 && !grade(flat,late).condition)
        let pause = clips.first { $0.id == "drop-shot" }!
        var noisy = ideal(pause)
        noisy.strokes.append(Stroke(prop:"card",time:4.6))
        precondition(!grade(noisy,pause).passed && grade(noisy,pause).hits == pause.cues.count)
        let base = ideal(hold)
        let withHole = replaceBand(base.strokes,with:[],lane:.motion,from:4,to:5)
        precondition(withHole.filter { $0.lane != .motion } == base.strokes.filter { $0.lane != .motion })
        precondition(withHole.filter { $0.lane == .motion }.count == 2)
        let card = Stroke(prop:"card",time:1.5)
        let cardHole = replaceBand([card],with:[],lane:.ambience,from:1.7,to:2)
        precondition(cardHole.count == 2)
        let intact = sound.wave([card],duration:3)
        let cut = sound.wave(cardHole,duration:3)
        let a = 44 + 2*Int(1.70*32000)
        let b = 44 + 2*Int(2.00*32000)
        precondition(intact.prefix(a) == cut.prefix(a) && intact.suffix(from:b) == cut.suffix(from:b))
        precondition(energy(cut,at:1.71,length:0.28) == 0)
        let boundary = Take(clip:goal.id,strokes:[
            Stroke(prop:"cushion",time:2.75), Stroke(prop:"keys",time:3.75)
        ])
        let boundaryScore = grade(boundary,goal)
        precondition(boundaryScore.hits == 2 && !boundaryScore.marks[0].exact && boundaryScore.marks[1].exact)
        print("PASS two compatible timbres; one action cannot satisfy two cues; 350/150 ms boundaries")
        print("PASS early release, flat wind, silence break, split range, and PCM outside impulse range")
        let completed = clips.dropLast().map(\.id)
        let selected = [clips[0], clips[4], clips[8]].map(ideal)
        let picks = Dictionary(uniqueKeysWithValues:zip(["football","tennis","basketball"],selected.map(\.id)))
        struct Fixture: Codable {
            let completed: [String]
            let takes: [Take]
            let picks: [String:UUID]
            let current: String
        }
        let fixture = Fixture(completed:completed,takes:selected + [Take(clip:late.id)],
                              picks:picks,current:late.id)
        try JSONEncoder().encode(fixture).write(to:evidence.appendingPathComponent("late-fixture.json"))
        print("Fixture: 15 graded orders, 3 selected tapes, empty editing base for final order. QA only.")

    }
}

extension Range where Bound == Int {
    func stride(step: Int) -> StrideTo<Int> { Swift.stride(from: lowerBound, to: upperBound, by: step) }
}
