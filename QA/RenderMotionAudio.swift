import Foundation

@main
struct RenderMotionAudio {
    struct StudioSave: Decodable {
        let completed: [String]
        let takes: [Take]
        let picks: [String: UUID]
    }

    static func main() throws {
        let current = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let assets = current.appendingPathComponent("SportingBeat")
        let clips = try JSONDecoder().decode([Clip].self,from:Data(contentsOf:assets.appendingPathComponent("Clips.json")))
        let sound = FoleySound(folder:assets.appendingPathComponent("Audio"))
        let path = URL(fileURLWithPath:CommandLine.arguments[1])
        let output = URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let save = try JSONDecoder().decode(StudioSave.self,from:Data(contentsOf:path))
        let ids = ["net-goal","first-serve","iron-rim","finish-straight"]
        for id in ids {
            guard let clip = clips.first(where:{ $0.id == id }),
                  let take = save.takes.last(where:{ $0.clip == id }) else { continue }
            let score = grade(take,clip)
            precondition(score.passed)
            try sound.wave(take.strokes,duration:clip.duration).write(to:output.appendingPathComponent(id+".wav"))
            for stroke in take.strokes {
                let physical = stroke.pressure.compactMap(\.travel).map(abs).max() ?? 0
                print(String(format:"%@ %@ @ %.4f, length %.3f, gesture travel %.2f",id,stroke.prop,stroke.time,stroke.length,physical))
            }
        }
        let goals = save.takes.filter { $0.clip == "net-goal" }
        if goals.count == 2 {
            let source = goals[0], edited = goals[1]
            precondition(source.strokes.filter { $0.lane != .ambience } == edited.strokes.filter { $0.lane != .ambience })
            for lane in [Lane.contact,.motion] {
                precondition(sound.wave(source.strokes,duration:8,only:lane) == sound.wave(edited.strokes,duration:8,only:lane))
            }
            let card = edited.strokes.first { $0.prop == "card" }!
            precondition(card.pressure.contains { abs($0.travel ?? 0) > 0.3 })
            try sound.wave(source.strokes,duration:8).write(to:output.appendingPathComponent("net-goal-original.wav"))
            print("PASS real iPhone takes: unchanged contact and movement; signed scrape restored from new save.")
        }
        if save.completed.count == 16 {
            let finish = save.takes.last { $0.clip == "finish-straight" }!
            let bend = finish.strokes.first { $0.prop == "rubber" }!
            precondition(bend.pressure.contains { abs($0.travel ?? 0) > 0.3 })
            precondition(Set(finish.strokes.compactMap(\.lane)).count == 3)
            print("PASS real iPad save: 16 orders, 3 layers and signed rubber pull.")
        }
    }
}
