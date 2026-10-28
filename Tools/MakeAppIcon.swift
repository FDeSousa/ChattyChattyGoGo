#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                          bytesPerRow: 0, space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("no ctx")
}

// Background gradient (indigo -> violet)
let colors = [
    CGColor(red: 0.29, green: 0.22, blue: 0.78, alpha: 1.0),
    CGColor(red: 0.55, green: 0.24, blue: 0.85, alpha: 1.0),
    CGColor(red: 0.13, green: 0.45, blue: 0.92, alpha: 1.0)
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.55, 1.0])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0),
                       options: [])

// Speech bubble
let bubbleRect = CGRect(x: 196, y: 300, width: 632, height: 470)
let bubblePath = CGPath(roundedRect: bubbleRect, cornerWidth: 130, cornerHeight: 130, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 48, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.97))
ctx.addPath(bubblePath)
ctx.fillPath()
ctx.restoreGState()

// Bubble tail
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.97))
ctx.beginPath()
ctx.move(to: CGPoint(x: 340, y: 318))
ctx.addLine(to: CGPoint(x: 300, y: 190))
ctx.addQuadCurve(to: CGPoint(x: 430, y: 306), control: CGPoint(x: 356, y: 288))
ctx.closePath()
ctx.fillPath()

// Three dots inside the bubble
let dotColor = CGColor(red: 0.35, green: 0.27, blue: 0.80, alpha: 1.0)
ctx.setFillColor(dotColor)
for (index, x) in [372.0, 512.0, 652.0].enumerated() {
    let pulse = 1.0 - (Double(abs(index - 1)) * 0.12)
    let radius = 38.0 * pulse
    ctx.addEllipse(in: CGRect(x: x - radius, y: 535 - radius, width: radius * 2, height: radius * 2))
}
ctx.fillPath()

guard let image = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
