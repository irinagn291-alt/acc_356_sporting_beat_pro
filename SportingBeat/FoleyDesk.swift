import SwiftUI
import UIKit

let ink = Color(red: 20/255, green: 40/255, blue: 71/255)
let night = Color(red: 11/255, green: 23/255, blue: 42/255)
let paper = Color(red: 241/255, green: 238/255, blue: 231/255)
let signal = Color(red: 236/255, green: 70/255, blue: 63/255)
let wood = Color(red: 175/255, green: 122/255, blue: 77/255)
let gold = Color(red: 1, green: 0.77, blue: 0.48)
let mint = Color(red: 0.57, green: 0.84, blue: 0.74)

extension Lane {
    var tint: Color {
        switch self {
        case .contact: return gold
        case .motion: return mint
        case .ambience: return Color(red: 0.99, green: 0.59, blue: 0.65)
        }
    }
    var icon: String {
        switch self {
        case .contact: return "burst"
        case .motion: return "wind"
        case .ambience: return "waveform"
        }
    }
    var title: String { L("lane." + rawValue) }
}

func clockText(_ time: Double) -> String {
    let ms = max(0, Int((time * 100).rounded(.down)))
    return String(format: "%02d:%02d.%02d", ms / 6000, ms / 100 % 60, ms % 100)
}

struct ActionButton: View {
    let label: String
    var icon: String? = nil
    var tint: Color = paper
    var filled = false
    var id: String? = nil
    let action: () -> Void

    init(_ label: String, icon: String? = nil, tint: Color = paper, filled: Bool = false,
         id: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.tint = tint
        self.filled = filled
        self.id = id
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .heavy)) }
                Text(label).font(.system(size: 13, weight: .bold)).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(filled ? (tint == signal ? Color.white : night) : tint)
            .background(filled ? tint : tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(tint.opacity(filled ? 0 : 0.22)) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id ?? label)
    }
}

struct PlayingFrame: View {
    let clip: Clip
    let time: Double
    var still = false
    var guides = true
    var immersive = false

    private static let photos: [String: UIImage] = {
        var result: [String: UIImage] = [:]
        for sport in ["football", "tennis", "basketball", "cycling"] {
            if let url = Bundle.main.url(forResource: sport, withExtension: "jpg", subdirectory: "Art"),
               let image = UIImage(contentsOfFile: url.path) { result[sport] = image }
        }
        return result
    }()

    var body: some View {
        Canvas(opaque:true,rendersAsynchronously:clip.sport == "cycling") { context, size in
            let w = size.width, h = size.height
            let full = CGRect(origin: .zero, size: size)
            let leftActor = clip.pose(at:time,lead:true)
            let rightActor = clip.pose(at:time,lead:false)
            let ball = clip.ball(at:time)
            let upright = h > w * 0.90
            var keep = [leftActor.x,rightActor.x]
            if clip.sport != "cycling" { keep.append(ball.x) }
            switch clip.sport {
            case "football": keep += [0.84,0.97]
            case "tennis": keep += [0.50,0.57]
            case "basketball": keep += [0.80,0.91]
            default:
                let stripe = clip.id == "track-start" ? 0.20 : 0.85
                let rider = keep.min { abs(stripe-$0) < abs(stripe-$1) } ?? stripe
                let blend = min(1,max(0,(0.72-abs(stripe-rider))/0.26))
                keep.append(rider+(stripe-rider)*blend)
            }
            // Keep the play and its landmarks in the frame before tightening the shot.
            let left = keep.min() ?? 0.2
            let right = keep.max() ?? 0.8
            let centre = (left+right)/2
            let edge = clip.sport == "cycling" ? 0.166 : clip.sport == "tennis" ? 0.15 : 0.135
            let span = max((right-left)/(1-2*edge),upright ? 0.66 : 0.86)
            let shift = (clip.angle ?? 0) * w * 0.045
            func p(_ x: Double,_ y: Double) -> CGPoint {
                if immersive {
                    let screenX = w * (0.5 + (x-centre)/span)
                    let screenY = h * (upright ? 0.09 + 0.86*y : 0.05 + 0.91*y)
                    return CGPoint(x:screenX,y:screenY)
                }
                return CGPoint(x:x*w+shift,y:y*h)
            }
            func line(_ points: [CGPoint], _ color: Color, _ width: Double = 1) {
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            func oval(_ center: CGPoint, _ rx: Double, _ ry: Double, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: center.x-rx, y: center.y-ry, width: 2*rx, height: 2*ry)), with: .color(color))
            }
            func polygon(_ points: [CGPoint], _ color: Color) {
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
                context.fill(path, with: .color(color))
            }
            context.fill(Path(full), with: .color(ink))
            if let image = Self.photos[clip.sport] {
                let scale = max(w / image.size.width, h / image.size.height)
                let iw = image.size.width * scale
                let ih = image.size.height * scale
                context.draw(Image(uiImage: image), in: CGRect(x: (w-iw)/2, y: (h-ih)*0.32, width: iw, height: ih))
            }
            let rule = paper.opacity(0.66)
            if clip.sport == "football" {
                line([p(-0.1,0.95),p(1.0,0.95),p(0.82,0.54),p(0.05,0.53)], rule, 1.4)
                line([p(0.86,0.78),p(0.71,0.78),p(0.68,0.59),p(0.83,0.59)], rule)
                let impact = clip.cues.first { $0.id == "net" }
                let age = time-(impact?.time ?? time+1)
                let contactY = impact.map { clip.ball(at:$0.time).y } ?? 0.61
                func mesh(_ depth: Double,_ row: Double) -> CGPoint {
                    let y = 0.43+0.33*row
                    let tension = max(0,1-abs(y-contactY)*3.1)
                    let wave = age < 0 ? 0 : (1-exp(-age*33))*exp(-age*4.6)*cos(age*22-depth*2)
                    let push = wave*tension*sin(Double.pi*depth*0.72)
                    return p(0.84+depth*(0.117+row*0.013)+push*0.037,
                             y+depth*(0.046-row*0.106)+push*0.016)
                }
                for i in 0...9 {
                    let depth = Double(i)/9
                    line((0...9).map { mesh(depth,Double($0)/9) },paper.opacity(0.43),0.9)
                }
                for i in 0...9 {
                    line((0...9).map { mesh(Double($0)/9,Double(i)/9) },paper.opacity(0.55),0.85)
                }
                line([p(0.84,0.76),p(0.84,0.43),p(0.957,0.476)],paper,2.65)
                line([p(0.84,0.76),mesh(1,1),mesh(1,0)],paper.opacity(0.74),1.35)
            }
            if clip.sport == "tennis" {
                line([p(0.04,0.89),p(0.92,0.89),p(0.87,0.56),p(0.12,0.56),p(0.04,0.89)], rule, 1.4)
                line([p(0.10,0.72),p(0.88,0.72)], rule, 0.9)
                func net(_ depth: Double,_ row: Double) -> CGPoint {
                    let cable = 0.48+depth*0.064+sin(depth*Double.pi)*0.011
                    let base = 0.742+depth*0.086
                    return p(0.50+depth*0.076,cable+(base-cable)*row)
                }
                let thread = Color(red:0.29,green:0.23,blue:0.19).opacity(0.46)
                let highlight = paper.opacity(0.40)
                for i in 0...16 {
                    let depth = Double(i)/16
                    line([net(depth,0),net(depth,1)],i.isMultiple(of:2) ? thread : highlight,0.72)
                }
                for i in 1...13 {
                    let row = Double(i)/13
                    line((0...16).map { net(Double($0)/16,row) },
                         i.isMultiple(of:2) ? highlight : thread,0.72)
                }
                line((0...24).map { net(Double($0)/24,0) },night.opacity(0.48),3.2)
                line((0...24).map { net(Double($0)/24,0) },paper,2.0)
                for end in [0.0,1.0] {
                    let top = net(end,0)
                    let foot = net(end,1)
                    let base = CGPoint(x:foot.x,y:foot.y+2)
                    line([CGPoint(x:top.x,y:top.y-3),base],night.opacity(0.88),3.1)
                    line([CGPoint(x:top.x-0.35,y:top.y-3),CGPoint(x:base.x-0.35,y:base.y)],paper.opacity(0.84),1.18)
                    oval(CGPoint(x:top.x,y:top.y-3),1.86,1.42,paper)
                    oval(base,2.7,1.18,night.opacity(0.61))
                }
            }
            if clip.sport == "basketball" {
                line([p(-0.1,0.95),p(0.92,0.94),p(0.92,0.59),p(0.73,0.59),p(0.71,0.83),p(0.92,0.84)], rule, 1.3)
                line([p(0.91,0.63),p(0.91,0.28),p(0.86,0.28)], night, 3)
                polygon([p(0.84,0.24),p(0.91,0.21),p(0.91,0.39),p(0.84,0.42)], paper.opacity(0.86))
                let collision = clip.cues.first { $0.id == "rim" }.map { time-$0.time } ?? -1
                let rattle = collision < 0 ? 0 : sin(collision*39)*exp(-collision*7)*0.011
                oval(p(0.832,0.404+rattle),w*0.039,h*0.017,signal)
                oval(p(0.832,0.400+rattle),w*0.026,h*0.009,night)
                for i in 0...6 {
                    let x = 0.802 + Double(i)*0.01
                    line([p(x,0.413+rattle),p(0.83+(x-0.83)*0.49,0.53-rattle*0.5)],paper,0.8)
                }
            }
            if clip.sport == "cycling" {
                for y in [0.60,0.76,0.92] {
                    line([p(-0.1,y+0.01),p(0.32,y),p(1.13,y-0.08)], rule, 1.2)
                }
                let stripeX = clip.id == "track-start" ? 0.20 : 0.85
                for i in 0..<7 {
                    let y = 0.53 + Double(i) * 0.064
                    polygon([p(stripeX,y),p(stripeX+0.016,y),p(stripeX+0.026,y+0.065),p(stripeX+0.01,y+0.065)], i.isMultiple(of: 2) ? paper : night)
                }
            }

            if let cue = clip.cues.last(where: { $0.family == "crowd" && time >= $0.time && time < $0.time + 1.35 }) {
                let rise = min(1, (time - cue.time) * 5)
                for i in 0..<25 {
                    let x = 0.04 + Double(i) * 0.04
                    let y = 0.26 + Double(i % 4) * 0.036 - rise * Double(2 + i % 3) * 0.014
                    let tint = [mint, paper, gold, signal][i % 4]
                    oval(p(x,y), h*0.012,h*0.016,tint)
                    line([p(x-0.012,y-0.032),p(x,y+0.036),p(x+0.014,y-0.038)], tint, 1.5)
                }
            }

            let ballScreen = p(ball.x,ball.y)
            func athlete(_ lead: Bool,_ jersey: Color,_ scale: Double,_ flip: Double) {
                let actor = clip.pose(at:time,lead:lead)
                let q = p(actor.x,actor.y)
                let u = immersive ? min(h*scale*(upright ? 1.68 : 1.36),w*scale*1.03) : h*scale
                let skin = lead ? Color(red:0.83,green:0.53,blue:0.34) : Color(red:0.59,green:0.36,blue:0.26)
                func r(_ x: Double,_ y: Double) -> CGPoint {
                    CGPoint(x:q.x+x*u*flip,y:q.y+y*u)
                }
                typealias Joint = SIMD2<Double>
                func joint(_ a: Joint) -> CGPoint { r(a.x,a.y) }
                func bend(_ a: Joint,_ b: Joint,_ l1: Double,_ l2: Double,_ side: Double) -> Joint {
                    let vector = b-a
                    let length = max(0.0001,sqrt(vector.x*vector.x+vector.y*vector.y))
                    let aim = vector/length
                    let reach = min(l1+l2-0.0001,max(abs(l1-l2)+0.0001,length))
                    let along = (l1*l1-l2*l2+reach*reach)/(2*reach)
                    let rise = sqrt(max(0,l1*l1-along*along))*side
                    return a+aim*along+Joint(-aim.y,aim.x)*rise
                }
                func smooth(_ x: Double) -> Double {
                    let f = min(1,max(0,x))
                    return f*f*(3-2*f)
                }
                func mix(_ a: Joint,_ b: Joint,_ x: Double) -> Joint { a+(b-a)*x }
                func pulse(_ dt: Double,_ prep: Double,_ follow: Double) -> Double {
                    if dt < 0 { return smooth((dt+prep)/prep) }
                    return 1-smooth(dt/follow)
                }
                oval(r(0.03,0.028),u*0.61,u*0.095,night.opacity(0.27))

                if clip.sport == "cycling" {
                    // Distance travelled drives the spokes and both crank arms.
                    var distance = 0.0
                    var previous = clip.frames[0][lead]
                    for f in clip.frames.dropFirst() where f.t < time {
                        let at = f[lead]
                        distance += hypot(at.x-previous.x,(at.y-previous.y)*0.75)
                        previous = at
                    }
                    distance += hypot(actor.x-previous.x,(actor.y-previous.y)*0.75)
                    let roll = distance*w/max(1,u*0.247)
                    let crank = roll*0.54 + (lead ? 0 : 2.25)
                    let low = smooth((actor.z-0.9)/2.8)
                    let bob = sin(crank*2)*0.026
                    let wheels = [Joint(-0.70,-0.25),Joint(0.68,-0.25)]
                    for wheel in wheels {
                        let centre = joint(wheel)
                        oval(centre,u*0.257,u*0.257,night)
                        oval(centre,u*0.216,u*0.216,paper)
                        oval(centre,u*0.198,u*0.198,ink.opacity(0.97))
                        for spoke in 0..<10 {
                            let a = roll + Double(spoke)*Double.pi/5
                            let end = wheel + Joint(cos(a),sin(a))*0.197
                            line([centre,joint(end)],spoke == 0 ? jersey : paper.opacity(0.36),max(0.65,u*0.011))
                        }
                        oval(centre,u*0.033,u*0.033,jersey)
                    }
                    let bottom = Joint(-0.04,-0.31)
                    let seat = Joint(-0.37,-0.73)
                    let fork = Joint(0.43,-0.65)
                    line([joint(wheels[0]),joint(seat),joint(bottom),joint(wheels[0]),joint(fork),joint(wheels[1]),
                          joint(wheels[1]),joint(fork),joint(bottom)],jersey,u*0.048)
                    line([r(-0.49,-0.74),r(-0.28,-0.74)],night,u*0.036)
                    line([joint(fork),r(0.55,-0.76),r(0.66,-0.75),r(0.64,-0.65)],night,u*0.04)
                    let hip = Joint(-0.32,-0.83+bob)
                    let shoulder = Joint(0.15+0.1*low,-1.10+0.08*low+bob)
                    let front = bottom+Joint(cos(crank),sin(crank))*0.14
                    let back = 2*bottom-front
                    for (i,foot) in [back,front].enumerated() {
                        let knee = bend(hip,foot,0.31,0.36,-1)
                        let shade = i == 0 ? skin.opacity(0.72) : skin
                        line([joint(hip),joint(knee)],night,u*0.124)
                        line([joint(knee),joint(foot)],shade,u*0.095)
                        line([joint(bottom),joint(foot)],paper.opacity(0.55),u*0.027)
                        line([joint(foot),joint(foot+Joint(0.11,-0.012))],paper,u*0.049)
                    }
                    line([joint(hip),joint(shoulder)],jersey,u*0.178)
                    line([joint(shoulder),r(0.36,-0.85+0.04*low),r(0.60,-0.71)],skin,u*0.08)
                    let head = shoulder + Joint(0.15,-0.105)
                    oval(joint(head),u*0.118,u*0.108,skin)
                    oval(joint(head+Joint(-0.028,-0.063)),u*0.153,u*0.077,jersey)
                    line([joint(head+Joint(0.023,-0.016)),joint(head+Joint(0.112,-0.007))],night,u*0.022)
                    return
                }

                let runDelta = clip.pose(at:time+0.07,lead:lead).x-clip.pose(at:time-0.07,lead:lead).x
                let run = min(1,abs(runDelta)*100)
                let cadence = clip.sport == "tennis" ? 0.39 : 0.44
                let advance = 0.13*run
                // The standing foot uses the actor position at its plant time.
                func planted(_ offset: Double) -> Joint {
                    let phase = (time+offset)/cadence
                    let k = floor(phase), f = phase-k
                    let start = k*cadence-offset
                    let land = clip.pose(at:start+0.10,lead:lead)
                    let next = clip.pose(at:start+cadence+0.10,lead:lead)
                    let switchFoot = smooth((f-0.61)/0.39)
                    let x = land.x+(next.x-land.x)*switchFoot
                    let y = land.y+(next.y-land.y)*switchFoot
                    let planted = p(x,y)
                    let footX = (planted.x-q.x)/(max(1,u)*flip)+(offset == 0 ? -0.15 : 0.15)+advance
                    let lift = f > 0.61 ? sin(Double.pi*(f-0.61)/0.39)*0.23*run : 0
                    return Joint(footX,(planted.y-q.y)/max(1,u)-0.035-lift)
                }
                var back = planted(0)
                var front = planted(cadence/2)
                var hip = Joint(0,-0.59)
                var shoulder = Joint(0.08+0.10*run,-1.10)
                var hand = Joint(0.33+sin(time*2*Double.pi/cadence)*0.18*run,-0.72)
                var away = Joint(-0.34-sin(time*2*Double.pi/cadence)*0.17*run,-0.74)
                var rack = Joint(0.86,-0.96)
                var squash = 0.0
                var footAngle = 0.0

                // Select the athlete nearest the actual point of strike.
                func owns(_ cue: Cue) -> Bool {
                    let x = clip.ball(at:cue.time).x
                    return (abs(clip.pose(at:cue.time,lead:true).x-x) <= abs(clip.pose(at:cue.time,lead:false).x-x)) == lead
                }
                if clip.sport == "football" {
                    let strike = clip.cues.first { ["kick","pass","redirect","rebound"].contains($0.id)
                        && abs(time-$0.time) < 0.47 && owns($0) }
                    if let strike {
                        let dt = time-strike.time
                        let coil = pulse(dt+0.17,0.22,0.19)
                        let attack = pulse(dt,0.18,0.34)
                        let settle = pulse(dt-0.15,0.14,0.30)
                        let root = clip.pose(at:strike.time-0.21,lead:lead)
                        let target = p(clip.ball(at:strike.time).x,clip.ball(at:strike.time).y)
                        let contact = Joint((target.x-q.x)/(max(1,u)*flip)-0.09,(target.y-q.y)/max(1,u)+0.034)
                        let planted = p(root.x,root.y)
                        let support = Joint((planted.x-q.x)/(max(1,u)*flip)+0.01,(planted.y-q.y)/max(1,u)-0.038)
                        let load = smooth((dt+0.34)/0.18)*(1-smooth((dt-0.13)/0.25))
                        back = mix(back,support,load)
                        let windUp = mix(front,Joint(-0.47,-0.32),coil)
                        front = mix(windUp,contact,attack)
                        front += Joint(0.12,-0.26)*settle
                        hip += Joint(0.12,0.07)*load
                        shoulder += Joint(-0.25,0.08)*coil+Joint(0.25,-0.02)*settle
                        hand += Joint(-0.62,-0.18)*attack
                        away += Joint(-0.26,-0.30)*load
                        footAngle = -0.68*coil+0.25*settle
                    }
                    if !lead, let flight = clip.cues.first(where: { $0.id == "net" || $0.id == "post" }) {
                        let dt = time-flight.time
                        let dive = pulse(dt+0.19,0.58,0.56)
                        let crouch = pulse(dt+0.68,0.23,0.28)
                        hip += Joint(0.22,-0.08)*dive+Joint(0,0.17)*crouch
                        shoulder += Joint(0.51,0.27)*dive+Joint(0.05,0.21)*crouch
                        back += Joint(-0.35,-0.15)*dive
                        front += Joint(-0.06,-0.33)*dive
                        hand = mix(hand,Joint(1.03,-0.95),dive)
                        away = mix(away,Joint(0.86,-1.14),dive)
                    }
                }
                if clip.sport == "tennis" {
                    hand = Joint(0.32,-0.76)
                    rack = Joint(0.57,-1.13)
                    if let strike = clip.cues.first(where: { ["serve","return","return2","return3","drop"].contains($0.id)
                        && abs(time-$0.time) < 0.58 && owns($0) }) {
                        let dt = time-strike.time
                        let coil = pulse(dt+0.23,0.30,0.23)
                        let hit = pulse(dt,0.23,0.25)
                        let swing = pulse(dt-0.20,0.18,0.33)
                        let target = p(clip.ball(at:strike.time).x,clip.ball(at:strike.time).y)
                        let contact = Joint((target.x-q.x)/(max(1,u)*flip),(target.y-q.y)/max(1,u))
                        rack = mix(mix(rack,Joint(-0.54,-1.44),coil),contact,hit)
                        rack = mix(rack,Joint(0.22,-1.52),swing)
                        let arm = rack-shoulder
                        let d = max(0.001,hypot(arm.x,arm.y))
                        hand = rack-arm/d*0.33
                        away = mix(away,Joint(0.14,-1.45),coil)
                        shoulder += Joint(-0.22,0.12)*coil+Joint(0.10,-0.20)*hit
                        hip += Joint(0.04,-0.12)*hit
                        if strike.id == "serve" {
                            front += Joint(-0.04,-0.12)*hit
                        } else {
                            front = mix(front,Joint(0.43,-0.04),hit)
                        }
                    }
                }
                if clip.sport == "basketball" {
                    let rel = Joint((ballScreen.x-q.x)/(max(1,u)*flip),(ballScreen.y-q.y)/max(1,u))
                    if rel.x > -0.12 && rel.x < 0.66 && rel.y > -1.03 {
                        hand = Joint(max(0.19,rel.x-0.025),min(-0.56,rel.y-0.13))
                        away = Joint(-0.27,-0.68-0.12*run)
                    }
                    if let release = clip.cues.first(where: { ["pass","launch","rebound","catch"].contains($0.id)
                        && abs(time-$0.time) < 0.54 && owns($0) }) {
                        let dt = time-release.time
                        let effort = pulse(dt,0.38,0.43)
                        let dip = pulse(dt+0.29,0.21,0.24)
                        let target = p(clip.ball(at:release.time).x,clip.ball(at:release.time).y)
                        let reach = Joint((target.x-q.x)/(max(1,u)*flip),(target.y-q.y)/max(1,u)+0.12)
                        hand = mix(hand,reach,effort)
                        away = mix(away,reach-Joint(0.21,0.08),effort)
                        hip += Joint(0,0.11)*dip+Joint(0,-0.18)*effort
                        shoulder += Joint(-0.07,0.15)*dip+Joint(0.09,-0.23)*effort
                        if release.id == "launch" {
                            back += Joint(-0.06,-0.15)*effort
                            front += Joint(0.06,-0.21)*effort
                        }
                    }
                }
                if let crowd = clip.cues.first(where: { $0.family == "crowd" }),
                   time > crowd.time, (lead || clip.sport == "basketball") {
                    let reaction = pulse(time-crowd.time-0.26,0.30,0.57)
                    hand = mix(hand,Joint(0.53,-1.55),reaction)
                    away = mix(away,Joint(-0.48,-1.52),reaction)
                    squash = reaction*0.04
                }
                hip.y -= squash
                let axis = shoulder-hip
                let seam = Joint(-axis.y,axis.x)/max(0.01,hypot(axis.x,axis.y))
                let hiddenShoulder = shoulder-seam*0.095
                let rearElbow = bend(hiddenShoulder,away,0.31,0.30,-1)
                line([joint(hiddenShoulder),joint(rearElbow),joint(away)],skin.opacity(0.78),u*0.075)
                for (i,foot) in [back,front].enumerated() {
                    let pelvis = hip+Joint(i == 0 ? -0.084 : 0.082,0.035)
                    let knee = bend(pelvis,foot,0.32,0.37,-1)
                    let darkLeg = i == 0 ? skin.opacity(0.83) : skin
                    line([joint(pelvis),joint(knee)],darkLeg,u*0.136)
                    line([joint(knee),joint(foot)],darkLeg,u*0.096)
                    line([joint(pelvis),joint(mix(pelvis,knee,0.38))],night,u*0.157)
                    let angle = i == 1 ? footAngle : 0
                    let toe = foot+Joint(cos(angle)*0.16,sin(angle)*0.16)
                    line([joint(foot-Joint(0.055,-0.014)),joint(toe)],night,u*0.107)
                    line([joint(foot-Joint(0.04,-0.002)),joint(toe-Joint(0,0.015))],paper,u*0.075)
                }
                let belt = hip+axis*0.06
                polygon([joint(shoulder-seam*0.169),joint(shoulder+seam*0.166),joint(belt+seam*0.14),joint(belt-seam*0.13)],jersey)
                let stripe = mix(belt,shoulder,0.42)
                line([joint(stripe-seam*0.142),joint(stripe+seam*0.145)],paper.opacity(0.40),u*0.033)
                let visibleShoulder = shoulder+seam*0.09
                let elbow = bend(visibleShoulder,hand,0.29,0.32,1)
                line([joint(visibleShoulder),joint(elbow),joint(hand)],skin,u*0.091)
                oval(joint(hand),u*0.046,u*0.045,skin)
                let neck = shoulder + axis*0.16
                let skull = shoulder + axis*0.37 + Joint(0.025,-0.025)
                line([joint(shoulder),joint(neck)],skin,u*0.11)
                oval(joint(skull),u*0.132,u*0.151,skin)
                line([joint(skull+Joint(-0.09,-0.101)),joint(skull+Joint(0.064,-0.116))],night,u*0.083)
                oval(joint(skull+Joint(0.085,-0.012)),u*0.015,u*0.016,night.opacity(0.85))
                if clip.sport == "tennis" {
                    let headAxis = rack-hand
                    let d = max(0.001,hypot(headAxis.x,headAxis.y))
                    let vine = headAxis/d
                    let side = Joint(-vine.y,vine.x)
                    line([joint(hand),joint(rack-vine*0.11)],night,u*0.049)
                    var hoop: [CGPoint] = []
                    for i in 0...32 {
                        let angle = Double(i)*Double.pi/16
                        hoop.append(joint(rack+vine*cos(angle)*0.158+side*sin(angle)*0.105))
                    }
                    polygon(hoop,night.opacity(0.36))
                    line(hoop,paper,u*0.027)
                    for i in -2...2 {
                        let shift = side*Double(i)*0.031
                        line([joint(rack+shift-vine*0.119),joint(rack+shift+vine*0.119)],paper.opacity(0.55),max(0.5,u*0.007))
                    }
                    for i in -2...2 {
                        let shift = vine*Double(i)*0.047
                        line([joint(rack+shift-side*0.079),joint(rack+shift+side*0.079)],paper.opacity(0.55),max(0.5,u*0.007))
                    }
                }
            }
            let colours: (Color, Color)
            switch clip.sport {
            case "tennis": colours = (paper, ink)
            case "basketball": colours = (mint, signal)
            case "cycling": colours = (gold, ink)
            default: colours = (gold, mint)
            }
            athlete(false,colours.1,0.127,clip.sport == "cycling" ? 1 : -1)
            athlete(true,colours.0,0.153,1)

            if clip.sport != "cycling" {
                let radius = clip.sport == "tennis" ? 0.013 : clip.sport == "basketball" ? 0.022 : 0.0195
                let b = min(h*radius*1.32,w*radius)
                let floor = 0.85-ball.x*(clip.sport == "football" ? 0.105 : 0.125)
                let shadow = p(ball.x,min(0.94,max(floor,ball.y+0.011)))
                let lift = min(1,max(0,(floor-ball.y)*4))
                oval(shadow,b*(1.11-lift*0.38),b*0.30,night.opacity(0.32-lift*0.16))
                let impact = clip.cues.first { ($0.id.hasPrefix("bounce") || $0.id.hasPrefix("dribble") ||
                    ["kick","rim","post","net","return","return2","return3","serve","launch"].contains($0.id))
                    && time >= $0.time && time-$0.time < 0.08 }
                let crush = impact.map { 1-(time-$0.time)/0.08 } ?? 0
                let tint = clip.sport == "basketball" ? Color(red:0.93,green:0.36,blue:0.20) : clip.sport == "tennis" ? gold : paper
                oval(ballScreen,b*(1+0.15*crush),b*(1-0.22*crush),tint)
                let angle = (ball.x*47+ball.y*12)*(clip.sport == "tennis" ? 1.7 : 1)
                let cross = CGPoint(x:cos(angle)*b*0.89,y:sin(angle)*b*0.89)
                line([CGPoint(x:ballScreen.x-cross.x,y:ballScreen.y-cross.y),
                      CGPoint(x:ballScreen.x+cross.x,y:ballScreen.y+cross.y)],night.opacity(0.74),max(0.75,b*0.15))
                if clip.sport == "football" {
                    oval(CGPoint(x:ballScreen.x+sin(angle)*b*0.31,y:ballScreen.y+cos(angle)*b*0.35),
                         b*0.23,b*0.16,night.opacity(0.81))
                }

            }
            if clip.weather == "rain" || clip.weather == "wet" {
                let rain = clip.weather == "rain"
                for i in 0..<(rain ? 49 : 12) {
                    let x = Double((i*41)%113)/110
                    let y = rain ? (time*0.84 + Double(i*31 % 103)/103).truncatingRemainder(dividingBy: 1) : 0.70 + Double(i%4)*0.057
                    if rain { line([p(x,y),p(x-0.014,y+0.065)], paper.opacity(0.38),0.8) }
                    else { oval(p(x,y),w*0.025,h*0.012,ink.opacity(0.25)) }
                }
            }
            if !still && guides {
                let cues = clip.cues.filter { time >= $0.time - 0.55 && time <= $0.time + ($0.length ?? 0) + 0.18 }
                for (index,cue) in cues.enumerated() {
                    let growth = max(0,(cue.time-time)/0.55)
                    let x = w - 17 - Double(index)*27, y = h - 17
                    oval(CGPoint(x:x,y:y),8,8,night.opacity(0.83))
                    oval(CGPoint(x:x,y:y),6-growth*3,6-growth*3,cue.lane.tint)
                    if let length = cue.length, time > cue.time {
                        let remaining = min(1,max(0,(cue.time + length-time)/length))
                        let width = 4+remaining*57
                        line([CGPoint(x:x-12-width,y:y),CGPoint(x:x-12,y:y)], night, 7)
                        line([CGPoint(x:x-12-width,y:y),CGPoint(x:x-12,y:y)],cue.lane.tint,4)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct PropDrawing: View {
    let prop: String
    var motion = PropMotion()

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width,size.height)/56
            let force = min(1,max(0,motion.force))
            let travel = min(1,max(-1,motion.travel))
            let t = motion.age
            var c = ctx
            c.translateBy(x:size.width/2-28*s,y:size.height/2-28*s)
            c.scaleBy(x:s,y:s)
            let squash = ["cushion","pouch"].contains(prop) ? force*0.43 : prop == "card" ? force*0.11 : 0
            let swing = prop == "keys" ? (sin(t*31)*0.26+travel*0.36)*force :
                        ["bowl","lid","ratchet","blocks"].contains(prop) ? sin(t*47)*force*0.12 :
                        prop == "brush" ? travel*0.24 : prop == "card" ? travel*0.16 : 0
            c.translateBy(x:28+travel*(prop == "brush" || prop == "card" ? 8 : 2),y:43)
            c.rotate(by:.radians(swing))
            c.scaleBy(x:1+squash*0.32,y:1-squash)
            c.translateBy(x:-28,y:-43)
            func shape(_ path: Path, _ tint: Color) { c.fill(path, with: .color(tint)) }
            func stroke(_ path: Path,_ tint: Color,_ width: Double) { c.stroke(path,with: .color(tint),style: StrokeStyle(lineWidth: width,lineCap: .round,lineJoin: .round)) }
            func line(_ points: [CGPoint]) -> Path {
                var p = Path()
                p.addLines(points)
                return p
            }
            func box(_ x: Double,_ y: Double,_ w: Double,_ h: Double,_ r: Double) -> Path {
                Path(roundedRect: CGRect(x:x,y:y,width:w,height:h),cornerRadius:r)
            }
            func circle(_ x: Double,_ y: Double,_ w: Double,_ h: Double) -> Path {
                Path(ellipseIn: CGRect(x:x,y:y,width:w,height:h))
            }
            shape(circle(4,43,48,8),night.opacity(0.19))
            switch prop {
            case "cushion":
                let base = box(5,13,46,31,11)
                shape(base, Color(red:0.63,green:0.25,blue:0.19))
                shape(box(6,11,44,28,10),Color(red:0.88,green:0.46,blue:0.32))
                stroke(box(10,15,36,21,7),gold.opacity(0.62),1)
                for i in 0..<3 { shape(circle(18+Double(i)*9,24,2,2),ink.opacity(0.45)) }
            case "keys":
                stroke(circle(17,6,20,18),paper,3.2)
                for (index,x) in [13.0,25,36].enumerated() {
                    let tint = [gold,Color(red:0.78,green:0.82,blue:0.83),Color(red:0.86,green:0.63,blue:0.38)][index]
                    let ring = x+5
                    let wobble = force*sin(t*38-Double(index)*1.1)*9+travel*7
                    stroke(line([CGPoint(x:ring,y:23),CGPoint(x:x+wobble,y:44),CGPoint(x:x+5+wobble,y:45)]),tint,4)
                    shape(circle(x-1,17,12,13),tint)
                    shape(circle(x+3,20,4,4),ink.opacity(0.65))
                }
            case "card":
                shape(box(6,13,43,31,4),Color(red:0.53,green:0.31,blue:0.16))
                shape(box(5,10,44,29,4),gold)
                for i in 0..<9 {
                    let x = 10 + Double(i)*4
                    let flex = sin(t*37+Double(i)*0.61)*force*2.8+travel*5
                    stroke(line([CGPoint(x:x,y:13),CGPoint(x:x+flex,y:25),CGPoint(x:x,y:36)]),wood,1.4)
                }
            case "blocks":
                shape(box(10,10,31,24,3),gold)
                shape(box(17,22,32,24,3),Color(red:0.65,green:0.34,blue:0.15))
                shape(box(17,22,32,13,3),Color(red:0.87,green:0.56,blue:0.30))
                stroke(line([CGPoint(x:21,y:27),CGPoint(x:44,y:27)]),gold,1)
            case "bowl","lid":
                let height = prop == "bowl" ? 26.0 : 13
                shape(circle(6,18,44,height),wood)
                shape(circle(5,13,46,17),gold)
                shape(circle(10,16,36,10),ink.opacity(0.49))
                stroke(circle(5,13,46,17),paper.opacity(0.75),1.4)
                if prop == "lid" { shape(box(24,10,8,9,3),paper) }
            case "brush":
                for i in 0..<13 {
                    let x = 7 + Double(i)*3.3
                    let bristle = force*sin(t*39+Double(i)*0.27)*2.6+travel*7+force*4
                    stroke(line([CGPoint(x:x,y:29),CGPoint(x:x+bristle*0.45,y:38),
                                 CGPoint(x:x+bristle,y:43-force*3)]),gold,1.7)
                }
                shape(box(5,23,46,11,4),wood)
                shape(box(16,12,23,14,6),Color(red:0.66,green:0.30,blue:0.18))
            case "rubber":
                shape(box(5,10,9,35,4),wood)
                shape(box(42,10,9,35,4),wood)
                for i in 0..<4 {
                    let y = 16 + Double(i)*7
                    let deflection = force*(0.7+sin(t*40+Double(i))*1.3)+travel*10
                    stroke(line([CGPoint(x:8,y:y),CGPoint(x:28,y:y+deflection),CGPoint(x:48,y:y)]),mint,2.3)
                }
            case "ratchet":
                shape(circle(9,11,29,29),mint)
                shape(circle(16,18,15,15),ink)
                stroke(line([CGPoint(x:24,y:26),CGPoint(x:48,y:39)]),gold,6)
            default:
                shape(box(9,18,38,27,10),mint.opacity(0.87))
                shape(box(20,11,16,14,3),mint)
                stroke(line([CGPoint(x:17,y:20),CGPoint(x:29,y:22),CGPoint(x:40,y:18)]),paper,1.8)
            }
        }
        .accessibilityHidden(true)
    }
}

// The table needs touch-down and touch-up even when the finger stays still.
struct HoldSurface: UIViewRepresentable {
    let began: (Double) -> Void
    let changed: (Double,Double,Double) -> Void
    let ended: (Double) -> Void

    func makeUIView(context: Context) -> Pad {
        let pad = Pad()
        pad.accessibilityElementsHidden = true
        return pad
    }

    func updateUIView(_ pad: Pad,context: Context) {
        pad.began = began
        pad.changed = changed
        pad.ended = ended
    }

    final class Pad: UIView {
        var began: ((Double) -> Void)?
        var changed: ((Double,Double,Double) -> Void)?
        var ended: ((Double) -> Void)?
        private var finger: UITouch?
        private var origin = CGPoint.zero

        override func touchesBegan(_ touches: Set<UITouch>,with event: UIEvent?) {
            guard finger == nil, let touch = touches.first else { return }
            finger = touch
            origin = touch.location(in:self)
            began?(touch.timestamp)
        }

        override func touchesMoved(_ touches: Set<UITouch>,with event: UIEvent?) {
            guard let finger, touches.contains(finger) else { return }
            let point = finger.location(in:self)
            let dx = point.x-origin.x, dy = point.y-origin.y
            let shift = abs(dx) >= abs(dy) ? dx : dy
            changed?(abs(shift),shift,finger.timestamp)
        }

        override func touchesEnded(_ touches: Set<UITouch>,with event: UIEvent?) {
            guard let finger, touches.contains(finger) else { return }
            self.finger = nil
            ended?(finger.timestamp)
        }

        override func touchesCancelled(_ touches: Set<UITouch>,with event: UIEvent?) {
            touchesEnded(touches,with:event)
        }
    }
}

struct PropTile: View {
    let prop: Prop
    @ObservedObject var transport: Transport
    var compact = false
    @State private var held = false

    var enabled: Bool {
        transport.mode != .countdown && transport.mode != .replay &&
        (transport.mode != .capture || transport.only == nil || transport.only == prop.lane)
    }
    var body: some View {
        GeometryReader { area in
            let motion = transport.propMotion(prop.id)
            let active = motion.force > 0.12
            VStack(spacing: 3) {
                PropDrawing(prop:prop.id,motion:motion).frame(height: compact ? 39 : 49)
                Text(L(compact && prop.id == "card" ? "prop.card.short" : "prop." + prop.id))
                    .font(.system(size:compact ? 11 : 13,weight:.heavy))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.74)
                HStack(spacing: 4) {
                    Image(systemName: prop.sustained || prop.swipe ? "hand.draw" : "hand.tap")
                    Text(L(prop.sustained ? "gesture.hold" : prop.swipe ? "gesture.swipe" : "gesture.tap")).lineLimit(1).minimumScaleFactor(0.65)
                }.font(.system(size: 9, weight: .semibold))
            }
            .frame(maxWidth: .infinity,maxHeight: .infinity)
            .foregroundStyle(night)
            .background(active ? prop.lane.tint : Color(red:0.96,green:0.84,blue:0.67),in: RoundedRectangle(cornerRadius: 11))
            .overlay(alignment: .topTrailing) {
                Circle().fill(prop.lane.tint).frame(width: 9,height: 9).overlay { Circle().strokeBorder(night.opacity(0.32)) }.padding(7)
            }
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(night.opacity(0.19)) }
            .opacity(enabled ? 1 : 0.48)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard enabled, !prop.sustained else { return }
                if !held {
                    held = true
                    let strength = Float(max(0.45,min(0.95,0.95 - drag.startLocation.y/100*0.48)))
                    transport.down(prop, level: strength)
                    #if !targetEnvironment(simulator)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: CGFloat(strength))
                    #endif
                }
                if prop.swipe {
                    let delta = max(abs(drag.translation.width),abs(drag.translation.height))
                    if delta > 8 {
                        let dx = drag.translation.width, dy = drag.translation.height
                        let scale = max(42,area.size.width*0.53)
                        let shift = abs(dx) >= abs(dy) ? dx : dy
                        transport.move(prop.id,level:Float(min(1,0.55+delta/scale)),
                                       travel:Float(max(-1,min(1,shift/scale))))
                    }
                }
            }.onEnded { _ in
                guard !prop.sustained else { return }
                held = false
                transport.up(prop.id)
            },including:prop.sustained ? .none : .all)
            .overlay {
                if prop.sustained {
                    HoldSurface { time in
                        guard enabled else { return }
                        transport.down(prop,level:0.36,timestamp:time)
                        #if !targetEnvironment(simulator)
                        UIImpactFeedbackGenerator(style:.light).impactOccurred()
                        #endif
                    } changed: { delta,shift,time in
                        let scale = max(42,area.size.width*0.53)
                        let level = Float(min(1,0.36+delta/scale))
                        transport.move(prop.id,level:level,travel:Float(max(-1,min(1,shift/scale))),timestamp:time)
                    } ended: { time in
                        transport.up(prop.id,timestamp:time)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("prop." + prop.id))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("prop." + prop.id)
            .accessibilityAction {
                guard enabled else { return }
                transport.down(prop, level: 0.65)
                if prop.sustained {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { transport.up(prop.id) }
                } else { transport.up(prop.id) }
            }
        }
        .frame(height:compact ? 79 : 93)
    }
}

struct Timeline: View {
    let clip: Clip
    let take: Take
    @ObservedObject var transport: Transport
    @Binding var lane: Lane
    @Binding var start: Double
    @Binding var end: Double
    @Binding var solo: Bool
    let record: () -> Void

    private var locked: Bool { transport.mode == .capture || transport.mode == .countdown }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(L("edit.title")).font(.system(size: 22,weight: .black))
                Spacer()
                Button {
                    guard !locked else { return }
                    solo.toggle()
                    if transport.mode == .replay {
                        transport.replay(take,duration:clip.duration,from:min(clip.duration - 0.03, transport.cursor),solo:solo ? lane : nil)
                    }
                } label: {
                    Label(L("edit.solo"),systemImage: "headphones").font(.system(size: 12,weight: .heavy))
                        .padding(8).background(solo ? lane.tint : paper.opacity(0.10),in: Capsule()).foregroundStyle(solo ? night : paper)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("edit.solo")
            }
            HStack {
                Text(clockText(start)).accessibilityIdentifier("edit.inValue")
                Spacer()
                Text(clockText(transport.cursor)).foregroundStyle(signal)
                Spacer()
                Text(clockText(end)).accessibilityIdentifier("edit.outValue")
            }.font(.system(size: 11,weight: .bold,design: .monospaced))

            VStack(spacing: 5) {
                GeometryReader { proxy in
                    let w = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(paper.opacity(0.13)).frame(height: 4)
                        Capsule().fill(lane.tint.opacity(0.64))
                            .frame(width: max(2,(end-start)/clip.duration*w),height: 4)
                            .offset(x: start/clip.duration*w)
                        handle(w: w, lower: true)
                        handle(w: w, lower: false)
                    }.frame(maxHeight: .infinity)
                    .coordinateSpace(name: "editRange")
                }
                .frame(height: 37)
                .padding(.leading,73)
                .padding(.trailing,8)
                ForEach(Lane.allCases) { row in
                    HStack(spacing: 7) {
                        Button {
                            guard !locked else { return }
                            lane = row
                            if solo && transport.mode == .replay {
                                transport.replay(take,duration:clip.duration,from:min(clip.duration-0.03,transport.cursor),solo:row)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: row.icon).font(.system(size: 13,weight: .bold))
                                Text(row.title).font(.system(size: 9,weight: .bold)).lineLimit(1).minimumScaleFactor(0.57)
                            }
                            .frame(width: 66,height: 48)
                            .background(row == lane ? row.tint : paper.opacity(0.08),in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(row == lane ? night : row.tint)
                        }.buttonStyle(.plain).accessibilityIdentifier("lane." + row.rawValue)
                        GeometryReader { area in
                            Canvas { c,size in
                                let w = size.width, h = size.height
                                func x(_ t: Double) -> Double { w * (t/clip.duration) }
                                c.fill(Path(CGRect(x:x(start),y:0,width:max(0,x(end)-x(start)),height:h)),with:.color(row.tint.opacity(0.09)))
                                for i in 0...Int(clip.duration) {
                                    c.fill(Path(CGRect(x:x(Double(i)),y:0,width:1,height:h)),with:.color(paper.opacity(0.09)))
                                }
                                for cue in clip.cues where cue.lane == row {
                                    let point = x(cue.time)
                                    c.fill(Path(ellipseIn:CGRect(x:point-2,y:3,width:4,height:4)),with:.color(row.tint))
                                    if let length = cue.length {
                                        c.fill(Path(CGRect(x:point,y:4,width:x(length),height:2)),with:.color(row.tint.opacity(0.62)))
                                    }
                                }
                                let displayed = take.strokes + (locked ? transport.recorded : [])
                                for stroke in displayed where stroke.lane == row {
                                    let seconds = stroke.soundLength
                                    let bars = max(4,Int(seconds*22))
                                    for i in 0..<bars {
                                        let t = Double(i)/Double(bars)*seconds
                                        let peak = transport.sound.waveform(stroke,at:t,span:seconds/Double(bars))
                                        let y = h*(0.08+0.83*peak)
                                        c.fill(Path(CGRect(x:x(stroke.time+t),y:(h-y)/2+3,width:1.8,height:y)),with:.color(row.tint))
                                    }
                                }
                                c.fill(Path(CGRect(x:min(w-1,x(transport.cursor)),y:0,width:1,height:h)),with:.color(signal))
                            }
                            .background(night,in: RoundedRectangle(cornerRadius: 6))
                            .clipped()
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance:0).onChanged { drag in
                                guard !locked else { return }
                                if transport.mode != .idle { transport.stop() }
                                transport.cursor = min(clip.duration,max(0,drag.location.x/area.size.width*clip.duration))
                            })
                        }.frame(height: 48).accessibilityHidden(true)
                    }
                }
            }.environment(\.layoutDirection,.leftToRight)

            HStack(spacing: 7) {
                ActionButton(transport.mode == .replay ? L("stop") : L("edit.play"),icon:transport.mode == .replay ? "stop.fill" : "play.fill",id:"edit.play") {
                    guard !locked else { return }
                    if transport.mode == .replay { transport.stop() }
                    else {
                        let from = transport.cursor >= clip.duration - 0.03 ? 0 : transport.cursor
                        transport.replay(take,duration:clip.duration,from:from,solo:solo ? lane : nil)
                    }
                }
                ActionButton(L("edit.rerecord"),icon:"record.circle",tint:signal,filled:true,id:"edit.rerecord",action:record)
                    .disabled(locked)
            }
        }
        .padding(13).background(ink,in: RoundedRectangle(cornerRadius: 13))
    }

    func handle(w: Double, lower: Bool) -> some View {
        let value = lower ? start : end
        return ZStack {
            Rectangle().fill(.clear).frame(width: 37,height: 37)
            RoundedRectangle(cornerRadius: 4).fill(lane.tint).frame(width: 13,height: 28)
            Image(systemName: lower ? "chevron.left" : "chevron.right").font(.system(size: 7,weight: .black)).foregroundStyle(night)
        }
        .frame(width:37,height:37)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0,coordinateSpace: .named("editRange")).onChanged { drag in
            guard !locked else { return }
            if drag.startLocation.x > w + 20 || drag.startLocation.x < -20 { return }
            let next = min(clip.duration,max(0,(drag.location.x/w*clip.duration*20).rounded()/20))
            if lower { start = min(next,end-0.4) }
            else { end = max(start+0.4,next) }
        })
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(L(lower ? "edit.in" : "edit.out"))
        .accessibilityValue(clockText(value))
        .accessibilityIdentifier(lower ? "edit.in" : "edit.out")
        .accessibilityAdjustableAction { direction in
            guard !locked else { return }
            let increment = direction == .increment ? 0.5 : -0.5
            if lower { start = min(end-0.4,max(0,start+increment)) }
            else { end = max(start+0.4,min(clip.duration,end+increment)) }
        }
        .position(x:value/clip.duration*w,y:18.5)
    }
}
