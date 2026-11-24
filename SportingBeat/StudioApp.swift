import SwiftUI
import AVFoundation

func L(_ key: String, _ values: CVarArg...) -> String {
    let word = NSLocalizedString(key, comment: "")
    if values.isEmpty { return word }
    return String(format: word, locale: Locale.current, arguments: values)
}

struct StudioFile: Codable {
    var completed: [String] = []
    var takes: [Take] = []
    var picks: [String: UUID] = [:]
    var current: String?
}

final class Studio: ObservableObject {
    static let sports = ["football","tennis","basketball","cycling"]
    let clips: [Clip]
    let file: URL
    let isQA: Bool
    @Published var data: StudioFile

    init() {
        let url = Bundle.main.url(forResource: "Clips", withExtension: "json")!
        clips = try! JSONDecoder().decode([Clip].self, from: Data(contentsOf: url))
        let docs = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0]
        #if DEBUG
        isQA = ProcessInfo.processInfo.arguments.contains("--studio-qa")
        #else
        isQA = false
        #endif
        file = docs.appendingPathComponent(isQA ? "qa-studio.json" : "studio.json")
        data = (try? JSONDecoder().decode(StudioFile.self,from:Data(contentsOf:file))) ?? StudioFile()
    }
    var fresh: Bool { data.current == nil && data.takes.isEmpty }
    var ready: Bool { data.completed.count == clips.count && programme.count == 4 }
    var programme: [Take] {
        Self.sports.compactMap { sport in data.takes.first { $0.id == data.picks[sport] } }
    }
    var next: Clip? { clips.first { !data.completed.contains($0.id) } }

    func available(_ clip: Clip) -> Bool {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return false }
        return i == 0 || data.completed.contains(clips[i-1].id)
    }
    func commit(_ updated: StudioFile) -> Bool {
        do {
            try JSONEncoder().encode(updated).write(to: file,options: .atomic)
            data = updated
            return true
        } catch { return false }
    }
    func opened(_ clip: Clip) -> Bool {
        var replacement = data
        replacement.current = clip.id
        return commit(replacement)
    }
    func save(_ take: Take, _ clip: Clip, sound: FoleySound) -> Bool {
        var replacement = data
        replacement.current = clip.id
        if !replacement.takes.contains(where: { $0.id == take.id }) { replacement.takes.append(take) }
        if !take.creative && grade(take,clip).passed && !replacement.completed.contains(clip.id) {
            replacement.completed.append(clip.id)
        }
        guard commit(replacement) else { return false }
        if isQA {
            let wav = file.deletingLastPathComponent().appendingPathComponent(take.id.uuidString + ".wav")
            try? sound.wave(take.strokes,duration:clip.duration).write(to:wav,options:.atomic)
        }
        return true
    }
    func pick(_ take: Take, _ sport: String) -> Bool {
        var replacement = data
        replacement.picks[sport] = take.id
        return commit(replacement)
    }
}

@main
struct SportingBeatApp: App {
    var body: some Scene {
        WindowGroup { ControlRoom().preferredColorScheme(.dark) }
    }
}

struct ControlRoom: View {
    enum Page { case orders, desk, edit, screening, cinema, shelf, programme }
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var studio = Studio()
    @StateObject private var transport = Transport(folder:Bundle.main.resourceURL!.appendingPathComponent("Audio"))
    @State private var route = Page.desk
    @State private var clipIndex = 0
    @State private var take: Take?
    @State private var original: Take?
    @State private var selected = Lane.ambience
    @State private var rangeStart = 0.0
    @State private var rangeEnd = 8.0
    @State private var solo = false
    @State private var creative = false
    @State private var message: String?
    @State private var didStart = false
    @State private var programmeIndex = 0
    @State private var programmeRunning = false
    @State private var showBrief = false

    var clip: Clip { studio.clips[clipIndex] }
    var tablet: Bool { sizeClass == .regular }
    var underway: Bool { transport.mode == .capture || transport.mode == .countdown }
    var saved: Bool { take.map { draft in studio.data.takes.contains { $0.id == draft.id } } ?? false }
    var currentNumber: Int { clipIndex + 1 }

    var body: some View {
        Group {
            if route == .cinema {
                cinema
            } else {
                studioPages
            }
        }
        .background {
            LinearGradient(colors: [ink,night,night],startPoint: .topLeading,endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
        .foregroundStyle(paper)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            if studio.fresh {
                transport.mute(clip.duration)
            } else {
                let next = studio.data.current ?? studio.next?.id
                clipIndex = studio.clips.firstIndex { $0.id == next } ?? 0
                take = studio.data.takes.last { $0.clip == clip.id }
                rangeEnd = clip.duration
                route = .orders
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase != .active { interrupt() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue {
                interrupt()
            }
        }
        .sheet(isPresented:$showBrief) {
            VStack(alignment:.leading,spacing:14) {
                title(L("orders.title"),L("clip." + clip.id))
                brief
                ActionButton(L("ok"),tint:gold,filled:true,id:"brief.close") { showBrief = false }
            }.padding(18).presentationDetents([.medium]).presentationBackground(night)
        }
        .alert(L("app.title"),isPresented: Binding(get: { message != nil },set: { if !$0 { message = nil } })) {
            Button(L("ok"),role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    var studioPages: some View {
        VStack(spacing:0) {
            header
            GeometryReader { window in
                let size = window.size
                switch route {
                case .desk:
                    desk(size)
                case .screening, .cinema:
                    screening(size)
                case .programme:
                    broadcast(size)
                default:
                    ScrollView {
                        Group {
                            switch route {
                            case .orders: orders
                            case .edit: editor(wide:tablet && size.width > 680,shallow:size.height < 540)
                            default: shelf
                            }
                        }
                        .frame(maxWidth:1020)
                        .padding(.horizontal,tablet ? 24 : 14)
                        .padding(.vertical,10)
                        .frame(maxWidth:.infinity)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDisabled(underway)
                    .id(route)
                }
            }
            navigation
        }
    }

    func sideways(_ size: CGSize) -> Bool {
        size.width > size.height * 1.27 && size.width > 560
    }

    var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(signal).frame(width: 38,height: 38)
                Image(systemName: "waveform").font(.system(size: 20,weight: .black)).foregroundStyle(.white)
            }.accessibilityHidden(true)
            VStack(alignment: .leading,spacing: 1) {
                Text(L("app.title")).font(.system(size: 23,weight: .black)).tracking(-0.8)
                Text(L("app.studio")).font(.system(size: 9,weight: .heavy,design: .monospaced)).tracking(2).foregroundStyle(mint)
            }
            Spacer()
            Text(L("campaign.count",studio.data.completed.count,studio.clips.count))
                .font(.system(size: 11,weight: .bold,design: .monospaced))
                .padding(8).background(paper.opacity(0.10),in: Capsule())
                .accessibilityIdentifier("campaign.count")
        }
        .padding(.horizontal,tablet ? 22 : 12).padding(.vertical,4)
        .background(night.opacity(0.8))
    }

    var navigation: some View {
        HStack(spacing: 3) {
            tab(L("nav.orders"),"list.bullet.rectangle",.orders,"nav.orders")
            tab(L("nav.desk"),"dial.medium",.desk,"nav.desk")
            tab(L("nav.screen"),"play.rectangle",.screening,"nav.screen")
            tab(L("nav.shelf"),"rectangle.stack",.shelf,"nav.shelf")
        }
        .padding(.horizontal,12).padding(.top,5).padding(.bottom,2)
        .background(night)
        .overlay(alignment:.top) { Rectangle().fill(paper.opacity(0.12)).frame(height:1) }
    }

    func tab(_ name: String, _ icon: String, _ page: Page, _ id: String) -> some View {
        let active = route == page || (route == .edit && page == .desk) || (route == .programme && page == .shelf)
        return Button {
            go(page)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18,weight: .semibold))
                Text(name).font(.system(size: 10,weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity,minHeight: 45)
                .foregroundStyle(active ? gold : paper.opacity(0.68))
                .background(active ? gold.opacity(0.1) : .clear,in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    func go(_ next: Page) {
        if route == next { return }
        transport.stop()
        transport.ended = nil
        programmeRunning = false
        route = next
        if next == .desk { transport.mute(clip.duration) }
    }

    func open(_ chosen: Clip, _ version: Take? = nil) {
        guard let index = studio.clips.firstIndex(where: { $0.id == chosen.id }) else { return }
        transport.stop()
        transport.ended = nil
        programmeRunning = false
        clipIndex = index
        let history = studio.data.takes.filter { $0.clip == chosen.id }
        take = version ?? history.last
        original = history.first
        creative = false
        solo = false
        selected = .ambience
        rangeStart = 0
        rangeEnd = chosen.duration
        transport.cursor = 0
        showBrief = false
        if !studio.opened(chosen) { message = L("save.error") }
        route = version == nil ? .desk : .screening
        if version == nil { transport.mute(chosen.duration) }
    }

    func interrupt() {
        guard transport.mode != .idle else { return }
        transport.stop()
        transport.ended = nil
        programmeRunning = false
    }

    func stage(_ shown: Clip, _ label: String, headline: String,
               subheading: String? = nil, close: Bool = false) -> some View {
        ZStack(alignment:.topLeading) {
            PlayingFrame(clip:shown,time:transport.cursor,still:route == .programme || route == .screening || route == .cinema,
                         guides:!creative,immersive:true)
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            LinearGradient(colors:[Color.black.opacity(0.86),Color.black.opacity(0.43),Color.clear],
                           startPoint:.top,endPoint:.bottom)
                .frame(height:124)
                .allowsHitTesting(false)
            VStack(alignment:.leading,spacing:5) {
                HStack(spacing:6) {
                    Circle().fill(transport.mode == .capture ? signal : mint).frame(width:7,height:7)
                    Text(label).lineLimit(1).minimumScaleFactor(0.65)
                    Spacer(minLength:4)
                    ForEach(Lane.allCases) { lane in
                        Circle().fill(lane.tint.opacity(transport.isAudible(lane) ? 1 : 0.23))
                            .frame(width:6,height:6).accessibilityHidden(true)
                    }
                    Text(clockText(transport.cursor)).monospacedDigit().accessibilityIdentifier("clock")
                }
                .font(.system(size:11,weight:.heavy,design:.monospaced))
                VStack(alignment:.leading,spacing:2) {
                    if !headline.isEmpty {
                        Text(headline).font(.system(size:tablet ? 32 : 23,weight:.black)).lineLimit(1).minimumScaleFactor(0.55)
                    }
                    if let subheading {
                        Text(subheading).font(.system(size:11,weight:.bold,design:.monospaced)).lineLimit(1)
                            .accessibilityIdentifier("programme.position")
                    }
                }
            }
            .padding(.leading,14).padding(.trailing,close ? 60 : 14).padding(.top,11)
            if close {
                Button { go(.screening) } label: {
                    Image(systemName:"xmark").font(.system(size:16,weight:.black))
                        .frame(width:44,height:44).background(.black.opacity(0.52),in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(L("screen.exit")).accessibilityIdentifier("cinema.close")
                    .frame(maxWidth:.infinity,alignment:.trailing).padding(9)
            }
            if transport.mode == .countdown {
                Color.black.opacity(0.22).allowsHitTesting(false)
                VStack(spacing:2) {
                    Text("\(transport.count)").font(.system(size:76,weight:.black,design:.monospaced))
                    Text(L("record.ready")).font(.system(size:11,weight:.heavy,design:.monospaced)).tracking(2)
                }
                .padding(.horizontal,19).padding(.vertical,11)
                .background(.black.opacity(0.45),in: RoundedRectangle(cornerRadius:15))
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                .accessibilityIdentifier("countdown").allowsHitTesting(false)
            }
        }
        .overlay(alignment:.bottomTrailing) {
            HStack(spacing:6) {
                ForEach(transport.shownProps) { stroke in
                    if let lane = stroke.lane {
                        PropDrawing(prop:stroke.prop,motion:stroke.motion(at:transport.cursor))
                            .frame(width:tablet ? 56 : 42,height:tablet ? 51 : 38)
                            .background(night.opacity(0.85),in:RoundedRectangle(cornerRadius:7))
                            .overlay { RoundedRectangle(cornerRadius:7).strokeBorder(lane.tint.opacity(0.8)) }
                    }
                }
            }.padding(9).accessibilityHidden(true).allowsHitTesting(false)
        }
        .overlay(alignment:.bottomLeading) {
            GeometryReader { size in
                Rectangle().fill(paper.opacity(0.18)).overlay(alignment:.leading) {
                    Rectangle().fill(transport.mode == .capture ? signal : mint)
                        .frame(width:size.size.width*min(1,max(0,transport.cursor/shown.duration)))
                }
            }.frame(height:3).environment(\.layoutDirection,.leftToRight)
        }
        .clipped()
        .animation(nil,value:transport.cursor)
    }

    func title(_ eyebrow: String,_ headline: String) -> some View {
        VStack(alignment:.leading,spacing:3) {
            Text(eyebrow).font(.system(size:10,weight:.heavy,design:.monospaced)).tracking(1.8).foregroundStyle(gold)
            Text(headline).font(.system(size:30,weight:.black)).tracking(-1)
                .lineLimit(2).minimumScaleFactor(0.72)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

    var brief: some View {
        VStack(alignment:.leading,spacing: 7) {
            HStack(spacing: 8) {
                Label(L("brief.minimum",clip.minimum,clip.cues.count),systemImage:"scope")
                    .font(.system(size:13,weight:.heavy))
                Spacer()
                Text(L("brief.window")).font(.system(size:10,weight:.bold,design:.monospaced)).foregroundStyle(mint)
            }
            Text(L("brief." + clip.id)).font(.system(size: 12,weight:.medium)).foregroundStyle(paper.opacity(0.83))
                .fixedSize(horizontal:false,vertical:true)
            if let silence = clip.silence {
                Text(L("brief.silence",clockText(silence[0]),clockText(silence[1]))).font(.system(size:12,weight:.heavy)).foregroundStyle(gold)
            }
            if clip.layers == true { Label(L("brief.layers"),systemImage:"square.stack.3d.up").font(.system(size:12,weight:.heavy)).foregroundStyle(gold) }
            if clip.cues.contains(where: { $0.swell == true }) {
                Label(L("brief.swell"),systemImage:"speaker.wave.3").font(.system(size:12,weight:.heavy)).foregroundStyle(mint)
            }
            if showBrief {
                Text(L("brief.intro")).font(.system(size:12,weight:.medium)).foregroundStyle(paper.opacity(0.83))
            }
        }.padding(11).background(ink,in: RoundedRectangle(cornerRadius: 10))
    }

    func woodenDesk(repair: Bool = false, compact: Bool = false) -> some View {
        let props = clip.props.compactMap { Prop.find($0) }
        return VStack(alignment:.leading,spacing:10) {
            HStack(spacing: 8) {
                VStack(alignment:.leading,spacing:1) {
                    Text(L("desk.table")).font(.system(size:15,weight:.black))
                    Text(underway ? L("desk.live") : L("desk.preview")).font(.system(size:10,weight:.bold))
                }
                Spacer(minLength: 1)
                if !repair || underway {
                    Button {
                        if underway { transport.stop() }
                        else { record() }
                    } label: {
                        HStack(spacing:7) {
                            Image(systemName: underway ? "stop.fill" : "record.circle.fill").font(.system(size:18,weight:.black))
                            Text(underway ? L("cancel") : L("record")).font(.system(size:13,weight:.black))
                                .lineLimit(1).minimumScaleFactor(0.72).fixedSize(horizontal:true,vertical:false)
                        }.padding(.horizontal,12).frame(minHeight:44)
                            .foregroundStyle(.white).background(signal,in: Capsule())
                            .overlay { Capsule().strokeBorder(.white.opacity(0.23)) }
                    }.buttonStyle(.plain).accessibilityIdentifier(underway ? "record.cancel" : "record.start")
                }
            }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:7),
                                    count:props.count <= 3 ? 3 : (tablet && !compact ? props.count : 3)),spacing:7) {
                ForEach(props) { prop in PropTile(prop:prop,transport:transport,compact:compact) }
            }
        }
        .padding(11).foregroundStyle(night)
        .background {
            RoundedRectangle(cornerRadius:13).fill(LinearGradient(colors:[gold.opacity(0.9),wood,Color(red:0.70,green:0.40,blue:0.24)],startPoint:.topLeading,endPoint:.bottomTrailing))
            Canvas { c,size in
                for i in 0..<16 {
                    let y = Double(i)*size.height/15
                    var grain = Path()
                    grain.move(to:CGPoint(x:0,y:y))
                    grain.addQuadCurve(to:CGPoint(x:size.width,y:y-5),control:CGPoint(x:size.width*0.46,y:y+11))
                    c.stroke(grain,with:.color(night.opacity(i.isMultiple(of:4) ? 0.14 : 0.07)),lineWidth:1)
                }
            }.clipShape(RoundedRectangle(cornerRadius:13))
        }
    }

    func desk(_ size: CGSize) -> some View {
        let rail = sideways(size)
        let picture = stage(clip,underway ? L("monitor.recording") : L("monitor.mute"),headline:L("clip." + clip.id))
        return Group {
            if rail {
                HStack(spacing:6) {
                    picture
                    ScrollView {
                        deskControls(compact:true,narrow:!tablet)
                    }.scrollIndicators(.hidden)
                        .frame(width:min(tablet ? 330 : 274,max(216,size.width*0.31)))
                }
            } else {
                VStack(spacing:6) {
                    picture
                    deskControls(compact:size.height < 690)
                }
            }
        }
    }

    func deskControls(compact: Bool, narrow: Bool = false) -> some View {
        VStack(spacing:5) {
            woodenDesk(compact:compact)
            if !narrow || !underway {
                HStack(spacing:5) {
                    ActionButton(L("brief.minimum",clip.minimum,clip.cues.count),icon:"scope",tint:mint,id:"desk.brief") {
                        if !underway { showBrief = true }
                    }
                    ActionButton(L("desk.free"),icon:creative ? "checkmark.circle.fill" : "sparkles",tint:gold,filled:creative,id:"desk.free") {
                        if !underway { creative.toggle() }
                    }
                    if take != nil && !narrow { deskEdit }
                }
                if take != nil && narrow { deskEdit }
            }
            if clip.layers == true || clip.silence != nil {
                Text(clip.layers == true ? L("brief.layers") : L("brief.silence",clockText(clip.silence![0]),clockText(clip.silence![1])))
                    .font(.system(size:10,weight:.bold)).foregroundStyle(gold).lineLimit(2)
            }
            if clip.cues.contains(where: { $0.swell == true }) {
                Text(L("brief.swell")).font(.system(size:10,weight:.bold)).foregroundStyle(mint).lineLimit(1)
            }
            if creative { Text(L("desk.freeHelp")).font(.system(size:11,weight:.medium)).foregroundStyle(gold) }
        }.padding(.horizontal,8).padding(.bottom,4)
    }

    var deskEdit: some View {
        ActionButton(L("edit.title"),icon:"slider.horizontal.3",tint:mint,id:"desk.edit") { beginEditing() }
    }

    func record() {
        showBrief = false
        let newCreative = creative
        transport.finished = { actions in
            if original == nil { original = take }
            take = Take(clip:clip.id,strokes:actions.sorted { $0.time < $1.time },creative:newCreative)
            route = .screening
            transport.cursor = 0
        }
        transport.capture(from:0,to:clip.duration,lane:nil,backing:[],duration:clip.duration)
    }

    func beginEditing() {
        guard take != nil, !underway else { return }
        transport.stop()
        transport.cursor = 0
        solo = false
        rangeStart = 0
        rangeEnd = clip.duration
        rangeStart = firstEditStart
        rangeEnd = firstEditEnd
        route = .edit
    }

    var firstEditStart: Double { clip.id == "net-goal" ? 3.9 : 0 }
    var firstEditEnd: Double { clip.id == "net-goal" ? 6.15 : clip.duration }

    func editor(wide: Bool, shallow: Bool) -> some View {
        VStack(alignment:.leading,spacing: 10) {
            HStack {
                title(L("edit.repair"),L("clip." + clip.id))
                Button {
                    if !underway { go(.screening) }
                } label: {
                    Image(systemName:"xmark").font(.system(size:14,weight:.heavy)).padding(12)
                        .background(paper.opacity(0.10),in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(L("edit.close")).accessibilityIdentifier("edit.close")
            }
            stage(clip,underway ? L("monitor.recording") : L("monitor.edit"),headline:"")
                .aspectRatio(shallow ? 4.1 : wide ? 2.25 : 2.15,contentMode:.fit)
                .clipShape(RoundedRectangle(cornerRadius:10))
            if let take {
                if underway { woodenDesk(repair:true,compact:shallow) }
                Timeline(clip:clip,take:take,transport:transport,lane:$selected,start:$rangeStart,end:$rangeEnd,solo:$solo) {
                    let base = take
                    let lane = selected, start = rangeStart, end = rangeEnd
                    solo = false
                    transport.finished = { actions in
                        if original == nil { original = base }
                        let revised = replaceBand(base.strokes,with:actions,lane:lane,from:start,to:end)
                        self.take = Take(clip:clip.id,strokes:revised,creative:base.creative)
                        transport.cursor = 0
                        route = .screening
                    }
                    let backing = replaceBand(base.strokes,with:[],lane:lane,from:start,to:end)
                    transport.capture(from:start,to:end,lane:lane,backing:backing,duration:clip.duration)
                }
                Text(L("edit.help")).font(.system(size:12,weight:.medium)).foregroundStyle(paper.opacity(0.72))
            }
        }
    }

    func screening(_ size: CGSize) -> some View {
        let picture = stage(clip,L("monitor.review"),headline:L("clip." + clip.id))
        return Group {
            if sideways(size) {
                HStack(spacing:6) {
                    VStack(spacing:5) {
                        picture
                        if let take { screeningControls(take) }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    ScrollView {
                        assessment
                    }.scrollIndicators(.hidden).frame(width:min(tablet ? 355 : 260,size.width*0.33))
                }
            } else {
                ScrollView {
                    VStack(spacing:7) {
                        picture.frame(height:max(235,size.height*(tablet ? 0.66 : 0.64)))
                        if let take { screeningControls(take) }
                        assessment
                    }
                }.scrollIndicators(.hidden)
            }
        }
    }

    func screeningControls(_ take: Take) -> some View {
        HStack(spacing:7) {
            if let original, original.id != take.id {
                ActionButton(L("screen.first"),icon:"play.fill",id:"screen.first") {
                    transport.replay(original,duration:clip.duration)
                }
            }
            ActionButton(transport.mode == .replay ? L("stop") : L("screen.current"),
                         icon:transport.mode == .replay ? "stop.fill" : "play.fill",tint:paper,filled:true,id:"screen.play") {
                if transport.mode == .replay { transport.stop() }
                else { transport.replay(take,duration:clip.duration) }
            }
            ActionButton(L("screen.cinema"),icon:"arrow.up.left.and.arrow.down.right",tint:mint,id:"screen.cinema") {
                route = .cinema
                transport.replay(take,duration:clip.duration)
            }
        }
        .padding(.horizontal,7)
    }


    var assessment: some View {
        VStack(alignment:.leading,spacing:9) {
            if let take {
                let score = grade(take,clip)
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Text(L(take.creative ? "score.creative" : score.exact ? "score.cut" : score.passed ? "score.pass" : "score.try"))
                            .font(.system(size:19,weight:.black)).foregroundStyle(score.passed ? mint : gold)
                            .accessibilityIdentifier("score.result")
                        Spacer()
                        Text(L("score.hits",score.hits,score.marks.count)).font(.system(size:13,weight:.bold,design:.monospaced))
                            .accessibilityIdentifier("score.hits")
                    }
                    if !score.condition && !take.creative { Text(L("score.condition")).font(.system(size:12,weight:.semibold)).foregroundStyle(gold) }
                    ForEach(score.marks) { mark in
                        HStack(spacing:6) {
                            Image(systemName:mark.hit == nil ? "circle.dashed" : "checkmark.circle.fill")
                                .foregroundStyle(mark.hit == nil ? gold : mint)
                            Text(L("cue." + mark.cue.id)).lineLimit(1).minimumScaleFactor(0.72)
                            Spacer()
                            Text(clockText(mark.cue.time)).font(.system(size:10,weight:.medium,design:.monospaced))
                            Text(L(mark.note)).foregroundStyle(mark.hit == nil ? gold : mint)
                                .lineLimit(1).minimumScaleFactor(0.65)
                                .accessibilityIdentifier("mark." + mark.cue.id)
                        }.font(.system(size:12,weight:.bold))
                    }
                }.padding(11).background(ink,in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing:7) {
                    ActionButton(L("edit.title"),icon:"slider.horizontal.3",tint:mint,id:"screen.edit") { beginEditing() }
                    ActionButton(saved ? L("screen.saved") : L("screen.save"),icon:saved ? "checkmark" : "tray.and.arrow.down",
                                 tint:gold,filled:!saved,id:"screen.save") {
                        if !studio.save(take,clip,sound:transport.sound) { message = L("save.error") }
                    }.disabled(saved)
                }
                if saved {
                    HStack(spacing:7) {
                        let chosen = studio.data.picks[clip.sport] == take.id
                        ActionButton(chosen ? L("shelf.chosen") : L("shelf.pick"),icon:chosen ? "checkmark" : "star",tint:mint,id:"screen.pick") {
                            if !studio.pick(take,clip.sport) { message = L("save.error") }
                        }
                        if let next = studio.next, next.id != clip.id {
                            ActionButton(L("screen.next"),icon:"arrow.forward",tint:gold,filled:true,id:"screen.next") { open(next) }
                        }
                    }
                }
                let history = studio.data.takes.filter { $0.clip == clip.id }
                if history.count > 1 {
                    ForEach(Array(history.enumerated()),id:\.element.id) { index, version in
                        ActionButton(L("screen.version",index+1),icon:take.id == version.id ? "checkmark.circle.fill" : "play.circle",
                                     tint:paper,id:"version.\(index+1)") {
                            if original == nil { original = history.first }
                            self.take = version
                            transport.replay(version,duration:clip.duration)
                        }
                    }
                }
            } else {
                Text(L("screen.empty")).font(.system(size:14,weight:.medium))
                ActionButton(L("nav.desk"),icon:"dial.medium",tint:gold,filled:true) { go(.desk) }
            }
        }
        .padding(.horizontal,8).padding(.bottom,10)
    }

    var cinema: some View {
        VStack(spacing:6) {
            stage(clip,L("monitor.review"),headline:L("clip." + clip.id),close:true)
            HStack(spacing:6) {
                if let original, original.id != take?.id {
                    ActionButton(L("screen.first"),icon:"play.fill",id:"cinema.first") {
                        transport.replay(original,duration:clip.duration)
                    }
                }
                if let take {
                    ActionButton(L("screen.current"),icon:"play.fill",tint:paper,filled:true,id:"cinema.current") {
                        transport.replay(take,duration:clip.duration)
                    }
                }
                if transport.mode == .replay {
                    ActionButton(L("stop"),icon:"stop.fill",id:"cinema.stop") { transport.stop() }
                }
            }.padding(.horizontal,8).padding(.bottom,5)
        }.background(Color.black.ignoresSafeArea())
    }

    func cassette(_ item: Clip, _ index: Int, _ chosen: Bool) -> some View {
        VStack(spacing:0) {
            VStack(alignment:.leading,spacing:4) {
                PlayingFrame(clip:item,time:item.cues[item.cues.count/2].time,still:true)
                    .aspectRatio(1.70,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:4))
                HStack(spacing:4) {
                    Text(L("clip." + item.id)).font(.system(size:12,weight:.black)).lineLimit(2)
                    Spacer(minLength:2)
                    Text(String(format:"%02d",index+1)).font(.system(size:12,weight:.heavy,design:.monospaced))
                }.foregroundStyle(night)
                Rectangle().fill(chosen ? mint : signal).frame(height:3)
            }
            .padding(6)
            .background(paper,in: RoundedRectangle(cornerRadius:5))
            HStack(spacing: 0) {
                ForEach(0..<2) { side in
                    if side == 1 {
                        Rectangle().fill(paper.opacity(0.23)).frame(maxWidth:.infinity).frame(height:3)
                    }
                    ZStack {
                        Circle().fill(night).frame(width:20,height:20)
                        Image(systemName:"gearshape.fill").font(.system(size:12)).foregroundStyle(chosen ? mint : paper.opacity(0.65))
                    }
                }
            }
            .padding(.horizontal,22)
            .padding(.vertical,5)
            .accessibilityHidden(true)
        }
        .padding(5)
        .background(Color(red:0.14,green:0.19,blue:0.24),in: RoundedRectangle(cornerRadius:8))
        .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(paper.opacity(0.24)) }
        .accessibilityLabel(L("clip." + item.id) + " · " + L("screen.version",index+1))
    }

    var orders: some View {
        VStack(alignment:.leading,spacing:12) {
            title(L("app.studio"),L("orders.title"))
            if let next = studio.next {
                Button { open(next) } label: {
                    HStack(spacing:11) {
                        PlayingFrame(clip:next,time:next.cues[0].time,still:true)
                            .frame(width:97,height:65).clipShape(RoundedRectangle(cornerRadius:7))
                        VStack(alignment:.leading,spacing:4) {
                            Text(L("orders.next")).font(.system(size:10,weight:.black,design:.monospaced))
                            Text(L("clip." + next.id)).font(.system(size:19,weight:.black))
                            Text(L("orders.info",L("sport." + next.sport),Int(next.duration))).font(.system(size:12,weight:.semibold))
                        }
                        Spacer()
                        Image(systemName:"arrow.forward.circle.fill").font(.system(size:26,weight:.bold))
                    }.padding(10).foregroundStyle(night).background(gold,in: RoundedRectangle(cornerRadius:11))
                }.buttonStyle(.plain).accessibilityIdentifier("orders.next")
            } else { Text(L("orders.complete")).foregroundStyle(mint).font(.system(size:14,weight:.bold)) }
            ForEach(Studio.sports,id:\.self) { sport in
                VStack(alignment:.leading,spacing:6) {
                    Text(L("sport." + sport)).font(.system(size:18,weight:.black)).foregroundStyle(gold)
                    ForEach(studio.clips.filter { $0.sport == sport }) { item in
                        Button { open(item) } label: {
                            HStack {
                                Image(systemName: studio.data.completed.contains(item.id) ? "checkmark.circle.fill" :
                                        studio.available(item) ? "play.circle" : "lock")
                                    .foregroundStyle(studio.available(item) ? mint : paper.opacity(0.5)).frame(width:21)
                                Text(L("clip." + item.id)).font(.system(size:14,weight:.bold))
                                Spacer()
                                Text(L("seconds",Int(item.duration))).font(.system(size:11,weight:.bold,design:.monospaced))
                            }.padding(.horizontal,7).frame(minHeight:42)
                                .background(paper.opacity(0.04),in: RoundedRectangle(cornerRadius:7))
                        }.buttonStyle(.plain).disabled(!studio.available(item)).accessibilityIdentifier("order." + item.id)
                    }
                }.padding(10).background(ink,in: RoundedRectangle(cornerRadius:11))
            }
        }
    }

    var shelf: some View {
        VStack(alignment:.leading,spacing:12) {
            title(L("shelf.cassettes"),L("shelf.title"))
            if studio.ready {
                ActionButton(L("shelf.broadcast"),icon:"play.tv.fill",tint:gold,filled:true,id:"shelf.broadcast") { startProgramme() }
            } else {
                Text(L("shelf.unlock",studio.programme.count)).font(.system(size:13,weight:.semibold)).foregroundStyle(paper.opacity(0.81))
            }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:tablet ? 230 : 155),spacing:9)],spacing:9) {
                ForEach(Studio.sports,id:\.self) { sport in
                    VStack(alignment:.leading,spacing:7) {
                        Text(L("sport." + sport)).font(.system(size:17,weight:.black)).foregroundStyle(gold)
                        let versions = studio.data.takes.filter { draft in studio.clips.contains { $0.id == draft.clip && $0.sport == sport } }
                        if versions.isEmpty {
                            RoundedRectangle(cornerRadius:6).strokeBorder(paper.opacity(0.14),style:StrokeStyle(lineWidth:1,dash:[3,4]))
                                .frame(height:68).overlay { Image(systemName:"rectangle.on.rectangle.slash").foregroundStyle(paper.opacity(0.43)) }
                            Text(L("shelf.empty")).font(.system(size:12,weight:.medium)).foregroundStyle(paper.opacity(0.65))
                        }
                        ForEach(Array(versions.enumerated()),id:\.element.id) { index,draft in
                            if let item = studio.clips.first(where:{ $0.id == draft.clip }) {
                                let chosen = studio.data.picks[sport] == draft.id
                                Button { open(item,draft) } label: {
                                    cassette(item,index,chosen)
                                }.buttonStyle(.plain)
                                ActionButton(chosen ? L("shelf.chosen") : L("shelf.pick"),icon:chosen ? "checkmark" : "star",tint:mint,
                                             filled:chosen,id:"pick." + sport + ".\(index)") {
                                    if !studio.pick(draft,sport) { message = L("save.error") }
                                }
                                if draft.id != versions.last?.id { Divider().overlay(paper.opacity(0.10)) }
                            }
                        }
                    }.padding(9).frame(maxWidth:.infinity,alignment:.topLeading).background(ink,in: RoundedRectangle(cornerRadius:10))
                }
            }
        }
    }

    func broadcast(_ size: CGSize) -> some View {
        VStack(spacing:6) {
            if studio.programme.indices.contains(programmeIndex) {
                let draft = studio.programme[programmeIndex]
                if let item = studio.clips.first(where:{ $0.id == draft.clip }) {
                    stage(item,L("monitor.broadcast"),headline:L("programme.title"),
                          subheading:L("programme.position",programmeIndex+1,4,L("clip." + item.id)))
                    HStack(spacing:6) {
                        ActionButton(programmeRunning ? L("stop") : L("programme.replay"),
                                     icon:programmeRunning ? "stop.fill" : "play.fill",tint:gold,filled:true,id:"programme.play") {
                            if programmeRunning { interrupt() }
                            else { startProgramme() }
                        }
                        ActionButton(L("programme.order"),icon:"arrow.uturn.backward",id:"programme.order") { open(item) }
                    }.padding(.horizontal,8).padding(.bottom,4)
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }

    func startProgramme() {
        guard studio.ready else { return }
        route = .programme
        programmeIndex = 0
        programmeRunning = true
        playProgrammeItem()
    }

    func playProgrammeItem() {
        guard programmeRunning, studio.programme.indices.contains(programmeIndex) else { return }
        let draft = studio.programme[programmeIndex]
        guard let item = studio.clips.first(where: { $0.id == draft.clip }) else { return }
        transport.ended = {
            if programmeIndex < studio.programme.count - 1 {
                programmeIndex += 1
                playProgrammeItem()
            } else {
                programmeRunning = false
                transport.ended = nil
            }
        }
        transport.replay(draft,duration:item.duration)
    }
}
