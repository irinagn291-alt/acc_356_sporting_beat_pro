import Foundation
import ImageIO
import CoreGraphics

// Use the bright front goalpost as a fixed-size landmark in the football scene.
for filename in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath:filename)
    guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
          let image = CGImageSourceCreateImageAtIndex(source,0,nil) else { fatalError(filename) }
    let width = image.width, height = image.height, stride = width*4
    let colour = CGColorSpace(name:CGColorSpace.sRGB)!
    let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:stride,
                            space:colour,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
    let pixels = context.data!.assumingMemoryBound(to:UInt8.self)
    var best = (x:0,y:0,length:0)
    for x in width/2 ..< width*96/100 {
        var start = 0
        var run = 0
        for y in height/7 ..< height*83/100 {
            let offset = y*stride+x*4
            let red = Int(pixels[offset]), green = Int(pixels[offset+1]), blue = Int(pixels[offset+2])
            let goalWhite = red >= 222 && green >= 213 && blue >= 202 && abs(red-green) <= 16 && abs(green-blue) <= 18
            if goalWhite {
                if run == 0 { start = y }
                run += 1
                if run > best.length { best = (x,start,run) }
            } else {
                run = 0
            }
        }
    }
    var kitHeight = 0
    let kitTop = max(0,best.y + best.length / 14)
    let kitBottom = min(height,best.y + best.length * 11 / 10)
    // In this film the lead's gold top is the only flat gold region on the turf.
    for x in width*7/100 ..< width*66/100 {
        var run = 0
        for y in kitTop..<kitBottom {
            let offset = y*stride+x*4
            let red = Int(pixels[offset]), green = Int(pixels[offset+1]), blue = Int(pixels[offset+2])
            let kitGold = red >= 245 && (181...213).contains(green) && (109...137).contains(blue)
            run = kitGold ? run+1 : 0
            kitHeight = max(kitHeight,run)
        }
    }
    print("\(filename) \(width)x\(height) goalpost=\(best.length)px kit=\(kitHeight)px x=\(best.x) y=\(best.y)")
}
