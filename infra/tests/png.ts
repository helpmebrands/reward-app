import { readFileSync } from 'node:fs'
import { inflateSync } from 'node:zlib'

// A minimal PNG reader for the brand asset tests: the header, whether the
// file carries alpha, and 8-bit pixels as RGBA. No package: node's zlib
// inflates the data and the five scanline filters are undone here.

export interface Png {
  width: number
  height: number
  /** PNG colour type: 0 grey, 2 RGB, 3 palette, 4 grey+alpha, 6 RGBA. */
  colourType: number
  bitDepth: number
  hasAlpha: boolean
  /** RGBA, four bytes per pixel, row by row. */
  pixels(): Uint8Array
}

const channels: Record<number, number> = { 0: 1, 2: 3, 4: 2, 6: 4 }

export function readPng(path: string): Png {
  const buf = readFileSync(path)
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error(`${path} is not a PNG`)
  let offset = 8
  let width = 0
  let height = 0
  let bitDepth = 0
  let colourType = 0
  let transparency = false
  const data: Buffer[] = []
  while (offset < buf.length) {
    const length = buf.readUInt32BE(offset)
    const type = buf.toString('ascii', offset + 4, offset + 8)
    const body = buf.subarray(offset + 8, offset + 8 + length)
    if (type === 'IHDR') {
      width = body.readUInt32BE(0)
      height = body.readUInt32BE(4)
      bitDepth = body[8]
      colourType = body[9]
    } else if (type === 'tRNS') {
      transparency = true
    } else if (type === 'IDAT') {
      data.push(body)
    }
    offset += 12 + length
  }
  return {
    width,
    height,
    colourType,
    bitDepth,
    hasAlpha: colourType === 4 || colourType === 6 || transparency,
    pixels: () => decode(Buffer.concat(data), width, height, colourType, bitDepth, path),
  }
}

function decode(
  compressed: Buffer,
  width: number,
  height: number,
  colourType: number,
  bitDepth: number,
  path: string,
): Uint8Array {
  const bpp = channels[colourType]
  if (bpp === undefined || bitDepth !== 8) {
    throw new Error(`${path}: colour type ${colourType} at ${bitDepth} bits is not read here`)
  }
  const raw = inflateSync(compressed)
  const stride = width * bpp
  const rows = new Uint8Array(height * stride)
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)]
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1))
    const row = rows.subarray(y * stride, (y + 1) * stride)
    const prev = y > 0 ? rows.subarray((y - 1) * stride, y * stride) : new Uint8Array(stride)
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? row[x - bpp] : 0
      const b = prev[x]
      const c = x >= bpp ? prev[x - bpp] : 0
      let v = src[x]
      if (filter === 1) v += a
      else if (filter === 2) v += b
      else if (filter === 3) v += (a + b) >> 1
      else if (filter === 4) {
        const p = a + b - c
        const pa = Math.abs(p - a)
        const pb = Math.abs(p - b)
        const pc = Math.abs(p - c)
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c
      }
      row[x] = v & 0xff
    }
  }
  const out = new Uint8Array(width * height * 4)
  for (let i = 0; i < width * height; i++) {
    const p = rows.subarray(i * bpp, i * bpp + bpp)
    const [r, g, b, a] =
      bpp === 1 ? [p[0], p[0], p[0], 255]
      : bpp === 2 ? [p[0], p[0], p[0], p[1]]
      : bpp === 3 ? [p[0], p[1], p[2], 255]
      : [p[0], p[1], p[2], p[3]]
    out.set([r, g, b, a], i * 4)
  }
  return out
}
