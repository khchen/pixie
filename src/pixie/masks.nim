import common, internal, system/memory, vmath

when defined(amd64) and not defined(pixieNoSimd):
  import nimsimd/sse2

type
  Mask* = ref object
    ## Mask object that holds mask opacity data.
    width*, height*: int
    data*: seq[uint8]

when defined(release):
  {.push checks: off.}

proc newMask*(width, height: int): Mask =
  ## Creates a new mask with the parameter dimensions.
  if width <= 0 or height <= 0:
    raise newException(PixieError, "Mask width and height must be > 0")

  result = Mask()
  result.width = width
  result.height = height
  result.data = newSeq[uint8](width * height)

proc wh*(mask: Mask): Vec2 {.inline.} =
  ## Return with and height as a size vector.
  vec2(mask.width.float32, mask.height.float32)

proc copy*(mask: Mask): Mask =
  ## Copies the image data into a new image.
  result = newMask(mask.width, mask.height)
  result.data = mask.data

proc `$`*(mask: Mask): string =
  ## Prints the mask size.
  "<Mask " & $mask.width & "x" & $mask.height & ">"

proc inside*(mask: Mask, x, y: int): bool {.inline.} =
  ## Returns true if (x, y) is inside the mask.
  x >= 0 and x < mask.width and y >= 0 and y < mask.height

proc dataIndex*(mask: Mask, x, y: int): int {.inline.} =
  mask.width * y + x

proc getValueUnsafe*(mask: Mask, x, y: int): uint8 {.inline.} =
  ## Gets a value from (x, y) coordinates.
  ## * No bounds checking *
  ## Make sure that x, y are in bounds.
  ## Failure in the assumptions will case unsafe memory reads.
  result = mask.data[mask.width * y + x]

proc `[]`*(mask: Mask, x, y: int): uint8 {.inline.} =
  ## Gets a pixel at (x, y) or returns transparent black if outside of bounds.
  if mask.inside(x, y):
    return mask.getValueUnsafe(x, y)

proc setValueUnsafe*(mask: Mask, x, y: int, value: uint8) {.inline.} =
  ## Sets a value from (x, y) coordinates.
  ## * No bounds checking *
  ## Make sure that x, y are in bounds.
  ## Failure in the assumptions will case unsafe memory writes.
  mask.data[mask.dataIndex(x, y)] = value

proc `[]=`*(mask: Mask, x, y: int, value: uint8) {.inline.} =
  ## Sets a value at (x, y) or does nothing if outside of bounds.
  if mask.inside(x, y):
    mask.setValueUnsafe(x, y, value)

proc minifyBy2*(mask: Mask, power = 1): Mask =
  ## Scales the mask down by an integer scale.
  if power < 0:
    raise newException(PixieError, "Cannot minifyBy2 with negative power")
  if power == 0:
    return mask.copy()

  for i in 1 .. power:
    result = newMask(mask.width div 2, mask.height div 2)
    for y in 0 ..< result.height:
      for x in 0 ..< result.width:
        let value =
          mask.getValueUnsafe(x * 2 + 0, y * 2 + 0).uint32 +
          mask.getValueUnsafe(x * 2 + 1, y * 2 + 0) +
          mask.getValueUnsafe(x * 2 + 1, y * 2 + 1) +
          mask.getValueUnsafe(x * 2 + 0, y * 2 + 1)
        result.setValueUnsafe(x, y, (value div 4).uint8)

proc fillUnsafe*(data: var seq[uint8], value: uint8, start, len: int) =
  ## Fills the mask data with the parameter value starting at index start and
  ## continuing for len indices.
  nimSetMem(data[start].addr, value.cint, len)

proc fill*(mask: Mask, value: uint8) {.inline.} =
  ## Fills the mask with the parameter value.
  fillUnsafe(mask.data, value, 0, mask.data.len)

proc getValueSmooth*(mask: Mask, x, y: float32): uint8 =
  ## Gets a interpolated value with float point coordinates.
  let
    minX = floor(x)
    minY = floor(y)
    diffX = x - minX
    diffY = y - minY
    x = minX.int
    y = minY.int

    x0y0 = mask[x + 0, y + 0]
    x1y0 = mask[x + 1, y + 0]
    x0y1 = mask[x + 0, y + 1]
    x1y1 = mask[x + 1, y + 1]

    bottomMix = lerp(x0y0, x1y0, diffX)
    topMix = lerp(x0y1, x1y1, diffX)

  lerp(bottomMix, topMix, diffY)

proc spread*(mask: Mask, spread: float32) =
  ## Grows the mask by spread.
  if spread == 0:
    return
  if spread < 0:
    raise newException(PixieError, "Cannot apply negative spread")

  let
    copy = mask.copy()
    spread = round(spread).int
  for y in 0 ..< mask.height:
    for x in 0 ..< mask.width:
      var maxValue: uint8
      block blurBox:
        for by in max(y - spread, 0) .. min(y + spread, mask.height - 1):
          for bx in max(x - spread, 0) .. min(x + spread, mask.width - 1):
            let value = copy.getValueUnsafe(bx, by)
            if value > maxValue:
              maxValue = value
            if maxValue == 255:
              break blurBox
      mask.setValueUnsafe(x, y, maxValue)

proc ceil*(mask: Mask) =
  ## A value of 0 stays 0. Anything else turns into 255.
  var i: int
  when defined(amd64) and not defined(pixieNoSimd):
    let
      vZero = mm_setzero_si128()
      vMax = mm_set1_epi32(cast[int32](uint32.high))
    for _ in countup(0, mask.data.len - 16, 16):
      var values = mm_loadu_si128(mask.data[i].addr)
      values = mm_cmpeq_epi8(values, vZero)
      values = mm_andnot_si128(values, vMax)
      mm_storeu_si128(mask.data[i].addr, values)
      i += 16

  for j in i ..< mask.data.len:
    if mask.data[j] != 0:
      mask.data[j] = 255

proc blur*(mask: Mask, radius: float32, outOfBounds: uint8 = 0) =
  ## Applies Gaussian blur to the image given a radius.
  let radius = round(radius).int
  if radius == 0:
    return
  if radius < 0:
    raise newException(PixieError, "Cannot apply negative blur")

  let kernel = gaussianKernel(radius)

  # Blur in the X direction. Store with dimensions swapped for reading later.
  let blurX = newMask(mask.height, mask.width)
  for y in 0 ..< mask.height:
    for x in 0 ..< mask.width:
      var value: uint32
      for xx in x - radius ..< min(x + radius, 0):
        value += outOfBounds * kernel[xx - x + radius]

      for xx in max(x - radius, 0) .. min(x + radius, mask.width - 1):
        value += mask.getValueUnsafe(xx, y) * kernel[xx - x + radius]

      for xx in max(x - radius, mask.width) .. x + radius:
        value += outOfBounds * kernel[xx - x + radius]

      blurX.setValueUnsafe(y, x, (value div 1024 div 255).uint8)

  # Blur in the Y direction and modify image.
  for y in 0 ..< mask.height:
    for x in 0 ..< mask.width:
      var value: uint32
      for yy in y - radius ..< min(y + radius, 0):
        value += outOfBounds * kernel[yy - y + radius]

      for yy in max(y - radius, 0) .. min(y + radius, mask.height - 1):
        value += blurX.getValueUnsafe(yy, x) * kernel[yy - y + radius]

      for yy in max(y - radius, mask.height) .. y + radius:
        value += outOfBounds * kernel[yy - y + radius]

      mask.setValueUnsafe(x, y, (value div 1024 div 255).uint8)

when defined(release):
  {.pop.}
