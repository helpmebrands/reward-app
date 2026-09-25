#!/usr/bin/env swift
// Generates the native brand icons from the sources in the repo's
// assets/logo, so no icon package is needed (epic #279). Run from anywhere:
//
//   swift apps/mobile/scripts/brand-icons.swift
//
// CoreGraphics and ImageIO ship with Xcode; sips cannot flatten alpha or
// separate the glyph from its ground, which the icons need. The output is
// deterministic, so a second run leaves no diff.
//
// The source icon is a rounded square with transparent corners over a
// diagonal gradient. Full-bleed icons redraw that gradient underneath, so
// the corners continue it; the adaptive and monochrome layers need the glyph
// (speech bubble and star) apart from the ground, found by flooding the
// ground in from the edges.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let mobile = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent()
let root = mobile.deletingLastPathComponent().deletingLastPathComponent()
let logo = root.appendingPathComponent("assets/logo")
let ios = mobile.appendingPathComponent("ios/Runner/Assets.xcassets")
let res = mobile.appendingPathComponent("android/app/src/main/res")

/// The icon's own ground: the gradient runs from the top-left corner to the
/// bottom-right, measured from the source's pixels.
let groundStart = (r: 124, g: 44, b: 68)
let groundEnd = (r: 191, g: 97, b: 112)

let densities: [(name: String, scale: Double)] = [
  ("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4),
]

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ url: URL) -> CGImage {
  let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
  return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}

/// An RGBA canvas, or RGB with no alpha channel when [opaque].
func canvas(_ width: Int, _ height: Int, opaque: Bool = false) -> CGContext {
  let info = opaque
    ? CGImageAlphaInfo.noneSkipLast.rawValue
    : CGImageAlphaInfo.premultipliedLast.rawValue
  let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: space, bitmapInfo: info)!
  context.interpolationQuality = .high
  return context
}

func save(_ image: CGImage, _ url: URL) {
  try! FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  precondition(CGImageDestinationFinalize(destination), "could not write \(url.path)")
}

func write(_ text: String, _ url: URL) {
  try! FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try! text.write(to: url, atomically: true, encoding: .utf8)
}

func colour(_ c: (r: Int, g: Int, b: Int)) -> CGColor {
  CGColor(
    colorSpace: space,
    components: [CGFloat(c.r) / 255, CGFloat(c.g) / 255, CGFloat(c.b) / 255, 1])!
}

/// Fills the context with the icon's ground, top-left to bottom-right.
func fillGround(_ context: CGContext) {
  let gradient = CGGradient(
    colorsSpace: space, colors: [colour(groundStart), colour(groundEnd)] as CFArray,
    locations: [0, 1])!
  // CoreGraphics puts the origin at the bottom left.
  context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: context.height),
    end: CGPoint(x: context.width, y: 0), options: [])
}

/// [image] scaled to fill a [size] square, on its ground and without alpha.
func flattened(_ image: CGImage, _ size: Int) -> CGImage {
  let context = canvas(size, size, opaque: true)
  fillGround(context)
  context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
  return context.makeImage()!
}

/// [image] scaled to a [size] square as it is, transparent corners kept.
func scaled(_ image: CGImage, _ size: Int) -> CGImage {
  let context = canvas(size, size)
  context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
  return context.makeImage()!
}

/// The glyph apart from its ground, at [size]: the glyph's own pixels where
/// the ground cannot reach, and white at the ground's anti-aliased edge so
/// the glyph's outline stays smooth. With [white], every pixel is white and
/// only the alpha carries the shape: the monochrome layer.
func glyph(_ image: CGImage, _ size: Int, white: Bool) -> CGImage {
  let source = canvas(size, size)
  source.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
  let pixels = source.data!.bindMemory(to: UInt8.self, capacity: size * size * 4)

  // How white each pixel is: 0 for the ground, 1 for the glyph's white.
  var whiteness = [Double](repeating: 0, count: size * size)
  for i in 0..<(size * size) {
    let a = Double(pixels[i * 4 + 3])
    guard a > 0 else { continue }
    let lowest = (0..<3).map { Double(pixels[i * 4 + $0]) * 255 / a }.min()!
    whiteness[i] = min(1, max(0, (lowest - 120) / 135)) * a / 255
  }

  // The ground: everything not white that the edges can reach.
  var ground = [Bool](repeating: false, count: size * size)
  var queue: [Int] = []
  for i in 0..<size {
    queue += [i, (size - 1) * size + i, i * size, i * size + size - 1]
  }
  while let i = queue.popLast() {
    guard !ground[i], whiteness[i] < 0.5 else { continue }
    ground[i] = true
    let x = i % size
    let y = i / size
    if x > 0 { queue.append(i - 1) }
    if x < size - 1 { queue.append(i + 1) }
    if y > 0 { queue.append(i - size) }
    if y < size - 1 { queue.append(i + size) }
  }

  let out = canvas(size, size)
  let target = out.data!.bindMemory(to: UInt8.self, capacity: size * size * 4)
  for i in 0..<(size * size) {
    if ground[i] || white {
      let alpha = UInt8((whiteness[i] * 255).rounded())
      target[i * 4] = alpha
      target[i * 4 + 1] = alpha
      target[i * 4 + 2] = alpha
      target[i * 4 + 3] = alpha
    } else {
      for c in 0..<4 { target[i * 4 + c] = pixels[i * 4 + c] }
    }
  }
  return out.makeImage()!
}

/// [layer] on a transparent [size] square, drawn at [fraction] of it and
/// centred: the adaptive icon's 108dp canvas shows the icon in its middle
/// 72dp, so a layer drawn at two thirds lines up with the legacy icon.
func centred(_ layer: CGImage, _ size: Int, fraction: Double) -> CGImage {
  let context = canvas(size, size)
  let side = Double(size) * fraction
  let inset = (Double(size) - side) / 2
  context.draw(layer, in: CGRect(x: inset, y: inset, width: side, height: side))
  return context.makeImage()!
}

let icon = load(logo.appendingPathComponent("helpmereward-icon.png"))
let iconDark = load(logo.appendingPathComponent("helpmereward-icon-dark.png"))

// iOS: one 1024 icon per appearance; Xcode derives every other size. The
// App Store rejects a marketing icon with alpha, so both are flattened.
let appIcon = ios.appendingPathComponent("AppIcon.appiconset")
for name in try! FileManager.default.contentsOfDirectory(atPath: appIcon.path)
where name.hasSuffix(".png") {
  try! FileManager.default.removeItem(at: appIcon.appendingPathComponent(name))
}
save(flattened(icon, 1024), appIcon.appendingPathComponent("Icon-App-1024x1024@1x.png"))
save(flattened(iconDark, 1024), appIcon.appendingPathComponent("Icon-App-Dark-1024x1024@1x.png"))
write(
  """
  {
    "images" : [
      {
        "filename" : "Icon-App-1024x1024@1x.png",
        "idiom" : "universal",
        "platform" : "ios",
        "size" : "1024x1024"
      },
      {
        "appearances" : [
          {
            "appearance" : "luminosity",
            "value" : "dark"
          }
        ],
        "filename" : "Icon-App-Dark-1024x1024@1x.png",
        "idiom" : "universal",
        "platform" : "ios",
        "size" : "1024x1024"
      }
    ],
    "info" : {
      "author" : "xcode",
      "version" : 1
    }
  }

  """, appIcon.appendingPathComponent("Contents.json"))

// Android: the legacy icon per density, and the adaptive icon's layers. The
// ground is a gradient drawable; the glyph and its monochrome silhouette are
// cut out once at the largest size and scaled down.
let foreground = glyph(icon, 1024, white: false)
let monochrome = glyph(icon, 1024, white: true)
for (density, scale) in densities {
  let mipmap = res.appendingPathComponent("mipmap-\(density)")
  save(scaled(icon, Int(48 * scale)), mipmap.appendingPathComponent("ic_launcher.png"))
  let layer = Int(108 * scale)
  save(
    centred(foreground, layer, fraction: 72.0 / 108),
    mipmap.appendingPathComponent("ic_launcher_foreground.png"))
  save(
    centred(monochrome, layer, fraction: 72.0 / 108),
    mipmap.appendingPathComponent("ic_launcher_monochrome.png"))
}

func hex(_ c: (r: Int, g: Int, b: Int)) -> String {
  String(format: "#%02X%02X%02X", c.r, c.g, c.b)
}

write(
  """
  <?xml version="1.0" encoding="utf-8"?>
  <!-- Generated by apps/mobile/scripts/brand-icons.swift: the icon's ground. -->
  <shape xmlns:android="http://schemas.android.com/apk/res/android">
      <gradient
          android:angle="315"
          android:startColor="\(hex(groundStart))"
          android:endColor="\(hex(groundEnd))" />
  </shape>

  """, res.appendingPathComponent("drawable/ic_launcher_background.xml"))

write(
  """
  <?xml version="1.0" encoding="utf-8"?>
  <!-- Generated by apps/mobile/scripts/brand-icons.swift. -->
  <adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
      <background android:drawable="@drawable/ic_launcher_background" />
      <foreground android:drawable="@mipmap/ic_launcher_foreground" />
      <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
  </adaptive-icon>

  """, res.appendingPathComponent("mipmap-anydpi-v26/ic_launcher.xml"))

print("brand icons written under \(mobile.path)")
