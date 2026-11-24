import XCTest
import UIKit

final class InteractionTests: XCTestCase {
    var app: XCUIApplication!
    let uptime = { ProcessInfo.processInfo.systemUptime }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--studio-qa","-AppleLanguages","(en-GB)","-AppleLocale","en_GB"]
    }

    func button(_ identifier: String) -> XCUIElement { app.buttons[identifier] }

    func bring(_ identifier: String) -> XCUIElement {
        let element = button(identifier)
        if element.isHittable { return element }
        for _ in 0..<6 {
            app.swipeUp()
            if element.isHittable { return element }
        }
        XCTFail("Could not reach \(identifier)")
        return element
    }

    func frame(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func seconds() -> Double {
        let clock = app.staticTexts["clock"]
        let parts = clock.label.split(whereSeparator:{ $0 == ":" || $0 == "." }).compactMap { Double($0) }
        guard parts.count == 3 else { return -1 }
        return parts[0]*60 + parts[1] + parts[2]/100
    }

    func observeStart(_ start: Double) -> Double {
        let until = uptime() + 7
        while uptime() < until {
            let before = uptime()
            let t = seconds()
            let after = uptime()
            if t > start + 0.01 && t < start + 1.5 {
                return (before+after)/2-t
            }
            Thread.sleep(forTimeInterval:0.035)
        }
        XCTFail("Transport did not start from \(start)")
        return uptime() - start
    }

    func doAt(_ time: Double, epoch: Double, input: () -> Void) {
        let wait = epoch + time - uptime() - 0.16
        if wait > 0 { Thread.sleep(forTimeInterval:wait) }
        input()
    }

    func takeIsReady(_ mark: String) {
        XCTAssertTrue(app.staticTexts["mark." + mark].waitForExistence(timeout:23))
    }

    func finishMotion(_ start: Double,_ segment: Double) {
        Thread.sleep(forTimeInterval:max(0,start+segment-uptime()))
    }

    func recordMotionMarker(_ clip: String,_ start: Double,_ duration: Double) {
        let wall = Date().timeIntervalSince1970+start-uptime()
        print(String(format:"MOTION_VIDEO %@ %.5f %.2f",clip,wall,duration))
    }

    func motionPreview(_ clip: String, _ duration: Double, _ moment: Double, _ name: String) {
        if !button("screen.cinema").isHittable { app.swipeDown() }
        bring("screen.cinema").tap()
        let start = observeStart(0)
        recordMotionMarker(clip,start,duration)
        finishMotion(start,moment)
        frame(name)
        finishMotion(start,duration)
        button("cinema.close").tap()
    }

    func testMotionPhoneLateStills() {
        app.launchArguments.removeFirst()
        app.launch()
        XCTAssertTrue(app.staticTexts["All sixteen orders approved."].waitForExistence(timeout:9))
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"16 / 16 done")
        button("nav.shelf").tap()
        bring("shelf.broadcast").tap()
        let position = app.staticTexts["programme.position"]
        let shots = [(3,6.13,"Rim-Shot"),(4,8.23,"Banked-Sprint")]
        for (segment,moment,name) in shots {
            let expected = NSPredicate(format:"label BEGINSWITH %@","\(segment) / 4")
            let exists = XCTNSPredicateExpectation(predicate:expected,object:position)
            XCTAssertEqual(XCTWaiter.wait(for:[exists],timeout:26),.completed)
            let start = observeStart(0)
            finishMotion(start,moment)
            frame(name)
            print("PHONE_ORIGINAL",position.label,seconds(),name)
        }
    }

    func testMotionPhone() {
        app.launchArguments.removeFirst()
        app.launch()
        XCTAssertTrue(button("record.start").waitForExistence(timeout:9))
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"0 / 16 done")
        frame("Football-Studio")
        button("record.start").tap()
        let start = observeStart(0)
        hit("cushion",at:2.27,epoch:start)
        frame("Cushion-Strike")
        hit("keys",at:3.60,epoch:start)
        hit("card",at:4.23,epoch:start)
        takeIsReady("stand")
        XCTAssertEqual(app.staticTexts["mark.stand"].label,"Too early")
        bring("screen.save").tap()
        bring("screen.edit").tap()
        XCTAssertTrue(button("lane.ambience").exists)
        button("lane.ambience").tap()
        frame("Ambience-Edit")
        button("edit.rerecord").tap()
        let punch = observeStart(3.9)
        let card = button("prop.card").coordinate(withNormalizedOffset:CGVector(dx:0.32,dy:0.45))
        finishMotion(punch,4.61)
        card.press(forDuration:0.08,thenDragTo:card.withOffset(CGVector(dx:45,dy:0)),withVelocity:.fast,thenHoldForDuration:0.03)
        takeIsReady("stand")
        XCTAssertEqual(app.staticTexts["score.hits"].label,"3 / 3 cues")
        bring("screen.save").tap()
        bring("screen.pick").tap()
        motionPreview("net-goal",7.65,3.77,"Goal-Net")
        button("nav.shelf").tap()
        frame("Selected-Tape")
        app.terminate()
        app.launch()
        XCTAssertTrue(button("orders.next").waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"1 / 16 done")
    }

    func testPhoneFirstOrder() {
        app.launch()
        XCTAssertTrue(button("record.start").waitForExistence(timeout:9))
        let t = seconds()
        Thread.sleep(forTimeInterval:0.55)
        XCTAssertNotEqual(t,seconds())
        frame("01-clean-silent-desk")
        let cushion = button("prop.cushion")
        let keys = button("prop.keys")
        let card = button("prop.card")
        cushion.tap()
        keys.tap()
        card.tap()
        button("record.start").tap()
        let start = observeStart(0)
        doAt(2.35,epoch:start) { cushion.tap() }
        doAt(3.53,epoch:start) { keys.tap() }
        doAt(4.17,epoch:start) { card.tap() }
        takeIsReady("stand")
        XCTAssertEqual(app.staticTexts["mark.stand"].label,"Too early")
        XCTAssertEqual(app.staticTexts["score.hits"].label,"2 / 3 cues")
        frame("02-early-crowd")
        button("screen.play").tap()
        Thread.sleep(forTimeInterval:4.6)
        frame("03-early-crowd-in-replay")
        bring("screen.save").tap()
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"1 / 16 done")
        bring("screen.edit").tap()
        XCTAssertTrue(button("lane.ambience").waitForExistence(timeout:5))
        button("lane.ambience").tap()
        button("edit.solo").tap()
        frame("04-ambience-solo-timeline")
        button("edit.play").tap()
        Thread.sleep(forTimeInterval:0.7)
        button("edit.play").tap()
        button("edit.rerecord").tap()
        let punch = observeStart(3.9)
        doAt(4.9,epoch:punch) { card.tap() }
        takeIsReady("stand")
        XCTAssertEqual(app.staticTexts["score.hits"].label,"3 / 3 cues")
        XCTAssertTrue(button("screen.first").exists)
        frame("05-repaired-screening")
        button("screen.cinema").tap()
        XCTAssertTrue(button("cinema.close").waitForExistence(timeout:6))
        Thread.sleep(forTimeInterval:3.7)
        frame("05a-cinema-in-motion")
        button("cinema.first").tap()
        Thread.sleep(forTimeInterval:0.5)
        XCTAssertLessThan(seconds(),2)
        button("cinema.close").tap()
        bring("screen.save").tap()
        bring("screen.pick").tap()
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"1 / 16 done")
        bring("screen.next").tap()
        XCTAssertTrue(app.staticTexts["One-touch pass"].waitForExistence(timeout:4))
        frame("06-next-order")
        app.terminate()
        app.launch()
        XCTAssertTrue(button("orders.next").waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"1 / 16 done")
        button("nav.shelf").tap()
        frame("07-shelf-after-relaunch")
        button("nav.orders").tap()
        bring("order.net-goal").tap()
        button("nav.screen").tap()
        bring("version.1").tap()
        XCTAssertEqual(app.staticTexts["mark.stand"].label,"Too early")
        Thread.sleep(forTimeInterval:4.5)
        XCTAssertGreaterThan(seconds(),3.0)
        bring("version.2").tap()
        XCTAssertEqual(app.staticTexts["score.hits"].label,"3 / 3 cues")
        frame("08-both-versions-restored")
    }

    func testPhoneCleanReleasePathAndSuspension() {
        app.launchArguments.removeFirst()
        app.launch()
        XCTAssertTrue(button("record.start").waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"0 / 16 done")
        button("record.start").tap()
        _ = observeStart(0)
        Thread.sleep(forTimeInterval:1)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval:0.6)
        app.activate()
        XCTAssertTrue(button("record.start").waitForExistence(timeout:6))
        let frozen = seconds()
        Thread.sleep(forTimeInterval:1)
        XCTAssertEqual(seconds(),frozen,accuracy:0.04)
        XCTAssertFalse(button("screen.save").exists)
        frame("09-interrupted-recording-stopped")
        bring("desk.free").tap()
        button("record.start").tap()
        let start = observeStart(0)
        doAt(1.45,epoch:start) { button("prop.keys").tap() }
        takeIsReady("stand")
        XCTAssertEqual(app.staticTexts["score.result"].label,"Creative take")
        XCTAssertEqual(app.staticTexts["score.hits"].label,"0 / 3 cues")
        bring("screen.save").tap()
        bring("screen.pick").tap()
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"0 / 16 done")
        frame("10-creative-take-saved")
    }

    func hit(_ prop: String, at time: Double, epoch: Double, hold: Double = 0, swell: Bool = false) {
        let tile = button("prop." + prop)
        doAt(time,epoch:epoch) {
            if swell {
                let finger = tile.coordinate(withNormalizedOffset:CGVector(dx:0.34,dy:0.46))
                finger.press(forDuration:0.48,thenDragTo:finger.withOffset(CGVector(dx:72,dy:0)),
                             withVelocity:.fast,thenHoldForDuration:hold-0.67)
            } else if hold > 0 {
                tile.press(forDuration:hold - 0.04)
            } else {
                tile.tap()
            }
        }
    }

    func testFullCampaignFromNewFile() { runCampaign(shootMotion:false) }

    func testMotionCampaign() { runCampaign(shootMotion:true) }

    func testMotionResume() { runCampaign(shootMotion:true,after:13) }

    func runCampaign(shootMotion: Bool,after completed: Int = 0) {
        app.launchArguments.removeFirst()
        app.launch()
        if completed == 0 {
            XCTAssertTrue(button("record.start").waitForExistence(timeout:9))
            XCTAssertEqual(app.staticTexts["campaign.count"].label,"0 / 16 done")
            frame("campaign-00-clean-start")
        } else {
            XCTAssertTrue(button("orders.next").waitForExistence(timeout:9))
            XCTAssertEqual(app.staticTexts["campaign.count"].label,"\(completed) / 16 done")
            frame("campaign-resumed-from-ui-save")
            bring("order.first-serve").tap()
            button("nav.screen").tap()
            motionPreview("first-serve",5.4,4.36,"Tennis-Return")
            button("nav.orders").tap()
            XCTAssertEqual(app.staticTexts["campaign.count"].label,"\(completed) / 16 done")
            button("orders.next").tap()
        }
        struct Action {
            let prop: String
            let at: Double
            let length: Double
            let swell: Bool
            init(_ prop: String, _ at: Double, _ length: Double = 0, _ swell: Bool = false) {
                self.prop = prop; self.at = at; self.length = length; self.swell = swell
            }
        }
        let plan: [(String,String,[Action])] = [
            ("Into the net","stand",[Action("cushion",2.4),Action("keys",3.6),Action("card",4.95)]),
            ("One-touch pass","stand",[Action("pouch",1.65),Action("cushion",2.22),Action("keys",4.25),Action("card",5.65)]),
            ("Off the post","gasp",[Action("cushion",2.7),Action("lid",4),Action("cushion",5.4),Action("card",6.9)]),
            ("Penalty in the rain","stand",[Action("brush",0.8,2.25),Action("pouch",3.55),Action("keys",5.15),Action("card",6.5)]),
            ("First serve","stand",[Action("blocks",2.25),Action("pouch",3.65),Action("blocks",4.35),Action("card",5.8)]),
            ("After the rain","bounce2",[Action("brush",1.4,1.45),Action("blocks",3.25),Action("pouch",4.7),Action("blocks",5.45),Action("pouch",7.25)]),
            ("Long rally","stand",[Action("blocks",1.65),Action("pouch",2.6),Action("blocks",3.25),Action("pouch",4.8),
                                  Action("blocks",5.35),Action("pouch",6.95),Action("blocks",7.65),Action("card",10.9)]),
            ("Drop shot","stand",[Action("blocks",1.95),Action("pouch",3.1),Action("blocks",6.3),Action("pouch",7.65),Action("card",9.3)]),
            ("Parquet","pass",[Action("pouch",2.3),Action("pouch",3.6),Action("blocks",5.7)]),
            ("Dribble sequence","catch",[Action("pouch",2),Action("cushion",2.85),Action("pouch",3.43),Action("pouch",4.35),
                                          Action("blocks",6.6),Action("pouch",7.85)]),
            ("Off the rim","rebound",[Action("cushion",2.1),Action("blocks",4.05),Action("bowl",6.1),Action("cushion",7.8)]),
            ("At the buzzer","stand",[Action("cushion",1.95),Action("cushion",2.95),Action("blocks",5.25),
                                      Action("bowl",7.35),Action("card",8.25)]),
            ("Out of the blocks","track",[Action("blocks",2.15),Action("rubber",3.25,2.1),Action("brush",5.9,2.5)]),
            ("High on the banking","pedal2",[Action("blocks",1.65),Action("rubber",2.7,2.2,true),Action("brush",5.45,2.55),
                                             Action("bowl",9.05),Action("blocks",10.75)]),
            ("The overtake","stand",[Action("blocks",2.2),Action("rubber",5.35,3.2,true),Action("blocks",9.65),Action("card",12.3)]),
            ("Home straight","stand2",[Action("blocks",2),Action("brush",3.8,3.6),Action("blocks",8.1),
                                       Action("bowl",10.65),Action("card",12.15),Action("ratchet",14.35)])
        ]
        for (index,order) in plan.enumerated().dropFirst(completed) {
            let (title,mark,actions) = order
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout:5),title)
            var result = ""
            var hits = ""
            let approvals = ["Order approved","Precision cut"]
            for attempt in 1...3 {
                button("record.start").tap()
                let start = observeStart(0)
                if shootMotion && index == 13 {
                    let wall = Date().timeIntervalSince1970+start-uptime()
                    print(String(format:"MOTION_LIVE high-line %.5f 14.00",wall))
                }
                for action in actions {
                    // A late XCTest command must not tap the next screen after the clip has ended.
                    if uptime()-start > action.at+0.29 || !button("prop."+action.prop).exists { break }
                    hit(action.prop,at:action.at,epoch:start,hold:action.length,swell:action.swell)
                }
                takeIsReady(mark)
                if index == 10 {
                    let before = app.staticTexts["score.hits"].label
                    let missed = app.staticTexts["mark.shoes"].label
                    print("OFF THE RIM before ambience: " + before + " · Shoes: " + missed)
                    frame("campaign-rim-before-ambience-\(attempt)")
                    bring("screen.edit").tap()
                    button("lane.ambience").tap()
                    button("edit.rerecord").tap()
                    let punch = observeStart(0)
                    hit("brush",at:0.9,epoch:punch,hold:2.3)
                    takeIsReady(mark)
                    print("OFF THE RIM after ambience: " + app.staticTexts["score.hits"].label
                        + " · Shoes: " + app.staticTexts["mark.shoes"].label
                        + " · Dribble: " + app.staticTexts["mark.dribble"].label)
                    frame("campaign-rim-after-ambience-\(attempt)")
                }
                if index == 15 {
                    bring("screen.edit").tap()
                    button("lane.motion").tap()
                    button("edit.rerecord").tap()
                    let punch = observeStart(0)
                    hit("rubber",at:6.4,epoch:punch,hold:3.3,swell:true)
                    hit("bowl",at:10.65,epoch:punch)
                    takeIsReady(mark)
                    frame("campaign-late-selective-recording-\(attempt)")
                }
                result = app.staticTexts["score.result"].label
                hits = app.staticTexts["score.hits"].label
                if approvals.contains(result) && (!shootMotion || index != 0 || hits == "3 / 3 cues") { break }
                print("RETRY order \(index+1): \(title) · \(hits) · attempt \(attempt)")
                for key in ["shoes","slide","rain","air","track"] where app.staticTexts["mark." + key].exists {
                    print("MARK " + key + ": " + app.staticTexts["mark." + key].label)
                }
                if attempt < 3 { button("nav.desk").tap() }
            }
            if !approvals.contains(result) {
                frame("campaign-unapproved-\(index+1)")
                XCTFail("Order \(index+1) \(title): \(result), \(hits)")
            }
            if shootMotion && index == 0 { XCTAssertEqual(hits,"3 / 3 cues") }
            bring("screen.save").tap()
            XCTAssertEqual(app.staticTexts["campaign.count"].label,"\(index+1) / 16 done")
            print("CAMPAIGN \(index+1)/16: \(title) · \(result) · \(hits)")
            let picks = shootMotion ? [0,4,10,15] : [0,4,8,15]
            if picks.contains(index) { bring("screen.pick").tap() }
            if shootMotion {
                switch index {
                case 0: motionPreview("net-goal",7.8,3.77,"Goal-Net")
                case 4: motionPreview("first-serve",5.4,4.36,"Tennis-Return")
                case 10: motionPreview("iron-rim",8.9,6.19,"Rim-Rebound")
                case 15: motionPreview("finish-straight",11.4,8.22,"Track-Sprint")
                default: break
                }
            }
            if index < 15 { bring("screen.next").tap() }
        }
        frame("campaign-16-all-saved")
        button("nav.shelf").tap()
        frame("campaign-17-four-cassettes")
        if shootMotion { frame("Tape-Shelf") }
        if completed > 0 {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.staticTexts["All sixteen orders approved."].waitForExistence(timeout:9))
            XCTAssertEqual(app.staticTexts["campaign.count"].label,"16 / 16 done")
            button("nav.shelf").tap()
            print("BROADCAST reopened after relaunch with 16/16 saved")
        }
        bring("shelf.broadcast").tap()
        let position = app.staticTexts["programme.position"]
        for i in 1...4 {
            let expected = NSPredicate(format:"label BEGINSWITH %@", "\(i) / 4")
            let outcome = XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:expected,object:position)],timeout:23)
            XCTAssertEqual(outcome,.completed)
            frame("campaign-air-\(i)")
            print("BROADCAST " + position.label)
        }
        let ended = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@", "Replay programme"),
                                              object:button("programme.play"))
        XCTAssertEqual(XCTWaiter.wait(for:[ended],timeout:23),.completed)
        print("BROADCAST all four cuts played to the end")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["All sixteen orders approved."].waitForExistence(timeout:7))
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"16 / 16 done")
        button("nav.shelf").tap()
        XCTAssertTrue(button("shelf.broadcast").waitForExistence(timeout:5))
        frame("campaign-18-completed-after-relaunch")
    }

    func checkFraming(_ shots: [(UIDeviceOrientation,String)]) {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        if !button("record.start").waitForExistence(timeout:3) {
            button("nav.orders").tap()
            bring("order.net-goal").tap()
        }
        for (orientation,name) in shots {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
            let size = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
                let bounds = self.app.frame
                return landscape == (bounds.width > bounds.height)
            },object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[size],timeout:10),.completed)
            let lamp = button("record.start")
            XCTAssertTrue(lamp.waitForExistence(timeout:6) && lamp.isHittable)
            for prop in ["cushion","keys","card"] {
                let tile = button("prop." + prop)
                XCTAssertTrue(tile.isHittable)
                XCTAssertGreaterThanOrEqual(tile.frame.width,44)
                XCTAssertGreaterThanOrEqual(tile.frame.height,44)
            }
            lamp.tap()
            let epoch = observeStart(0)
            hit("cushion",at:2.4,epoch:epoch)
            doAt(2.99,epoch:epoch) { frame(name + "-recording") }
            hit("keys",at:3.6,epoch:epoch)
            hit("card",at:4.95,epoch:epoch)
            takeIsReady("stand")
            let playback = bring("screen.play")
            XCTAssertTrue(playback.isHittable)
            playback.tap()
            Thread.sleep(forTimeInterval:2.2)
            frame(name + "-screening")
            button("nav.desk").tap()
        }
    }

    func testPhoneFillsAllOrientations() {
        checkFraming([(.portrait,"phone-portrait"),(.landscapeLeft,"phone-landscape-left"),
                      (.landscapeRight,"phone-landscape-right")])
    }

    func testPadFillsPortraitAndLandscape() {
        checkFraming([(.portrait,"ipad-portrait"),(.landscapeLeft,"ipad-landscape")])
    }

    func testPadFullRangeHandles() {
        app.launchArguments.removeFirst()
        app.launch()
        XCTAssertTrue(app.staticTexts["All sixteen orders approved."].waitForExistence(timeout:8))
        button("nav.screen").tap()
        XCTAssertTrue(button("screen.edit").waitForExistence(timeout:6))
        bring("screen.edit").tap()
        let lower = app.descendants(matching:.any)["edit.in"].firstMatch
        let upper = app.descendants(matching:.any)["edit.out"].firstMatch
        XCTAssertTrue(lower.waitForExistence(timeout:5))
        XCTAssertTrue(upper.exists)
        XCTAssertTrue(lower.isHittable && upper.isHittable)
        XCTAssertLessThan(upper.frame.midX,app.frame.maxX)
        XCTAssertGreaterThan(upper.frame.midX,lower.frame.midX + 300)
        frame("ipad-range-full-with-two-handles")
        let right = upper.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        right.press(forDuration:0.08,thenDragTo:right.withOffset(CGVector(dx:-200,dy:0)))
        XCTAssertNotEqual(app.staticTexts["edit.outValue"].label,"00:18.00")
        XCTAssertEqual(app.staticTexts["edit.inValue"].label,"00:00.00")
        let left = lower.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        left.press(forDuration:0.08,thenDragTo:left.withOffset(CGVector(dx:180,dy:0)))
        XCTAssertNotEqual(app.staticTexts["edit.inValue"].label,"00:00.00")
        frame("ipad-range-both-handles-moved")
    }

    func testPadThreeLayersAndBroadcast() {
        app.launch()
        XCTAssertTrue(button("orders.next").waitForExistence(timeout:9))
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"15 / 16 done")
        button("orders.next").tap()
        XCTAssertTrue(app.staticTexts["Home straight"].exists)
        frame("11-final-order-ipad")
        button("nav.screen").tap()
        XCTAssertTrue(button("screen.edit").waitForExistence(timeout:5))
        bring("screen.edit").tap()
        button("lane.contact").tap()
        frame("12-ipad-timeline-before-layering")
        button("edit.rerecord").tap()
        var start = observeStart(0)
        doAt(2,epoch:start) { button("prop.blocks").tap() }
        doAt(8.1,epoch:start) { button("prop.blocks").tap() }
        takeIsReady("stand2")
        XCTAssertEqual(app.staticTexts["score.hits"].label,"2 / 7 cues")
        bring("screen.edit").tap()
        button("lane.motion").tap()
        button("edit.rerecord").tap()
        start = observeStart(0)
        hit("rubber",at:6.4,epoch:start,hold:1.8)
        hit("bowl",at:10.65,epoch:start)
        takeIsReady("stand2")
        XCTAssertEqual(app.staticTexts["mark.air"].label,"Released early")
        frame("12a-ipad-released-wind-too-early")
        bring("screen.edit").tap()
        button("lane.motion").tap()
        button("edit.rerecord").tap()
        start = observeStart(0)
        // Resolving both drag coordinates in the editor costs an extra snapshot.
        doAt(6.25,epoch:start) {
            let rubber = button("prop.rubber")
            let finger = rubber.coordinate(withNormalizedOffset:CGVector(dx:0.48,dy:0.50))
            finger.press(forDuration:0.65,thenDragTo:finger.withOffset(CGVector(dx:65,dy:0)),withVelocity:.fast,thenHoldForDuration:2.48)
        }
        doAt(10.65,epoch:start) { button("prop.bowl").tap() }
        takeIsReady("stand2")
        XCTAssertEqual(app.staticTexts["score.hits"].label,"4 / 7 cues")
        bring("screen.edit").tap()
        button("lane.ambience").tap()
        button("edit.rerecord").tap()
        start = observeStart(0)
        doAt(3.8,epoch:start) { button("prop.brush").press(forDuration:3.55) }
        doAt(12.15,epoch:start) { button("prop.card").tap() }
        doAt(14.35,epoch:start) { button("prop.ratchet").tap() }
        takeIsReady("stand2")
        XCTAssertGreaterThanOrEqual(Int(app.staticTexts["score.hits"].label.prefix(1)) ?? 0,6)
        let result = app.staticTexts["score.result"].label
        XCTAssertTrue(["Order approved","Precision cut"].contains(result))
        frame("13-ipad-layered-take")
        bring("screen.save").tap()
        bring("screen.pick").tap()
        XCTAssertEqual(app.staticTexts["campaign.count"].label,"16 / 16 done")
        bring("screen.edit").tap()
        frame("14-ipad-three-layer-waveforms")
        button("nav.shelf").tap()
        frame("15-ipad-tape-shelf")
        bring("shelf.broadcast").tap()
        let position = app.staticTexts["programme.position"]
        XCTAssertTrue(position.waitForExistence(timeout:10))
        XCTAssertTrue(position.label.hasPrefix("1 / 4"))
        for i in 2...4 {
            let expected = NSPredicate(format:"label BEGINSWITH %@", "\(i) / 4")
            let outcome = XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:expected,object:position)],timeout:21)
            XCTAssertEqual(outcome,.completed)
            frame("16-ipad-broadcast-\(i)")
        }
        let ended = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@", "Replay programme"),
                                              object:button("programme.play"))
        XCTAssertEqual(XCTWaiter.wait(for:[ended],timeout:23),.completed)
        button("programme.order").tap()
        XCTAssertTrue(app.staticTexts["Home straight"].exists)
    }
}
