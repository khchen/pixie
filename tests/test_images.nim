import pixie, chroma, vmath, os

proc writeAndCheck(image: Image, fileName: string) =
  image.writeFile(fileName)
  let masterFileName = fileName.changeFileExt(".master.png")
  if not existsFile(masterFileName):
    echo "Master file: " & masterFileName & " not found!"
    return
  var master = readImage(fileName)
  assert image.width == master.width
  assert image.height == master.height
  assert image.data == master.data

block:
  var a = newImage(100, 100)
  a.fill(rgba(0, 0, 0, 0))
  var b = newImage(50, 50)
  b.fill(rgba(255, 92, 0, 255))
  var c = a.drawFast3(
    b,
    translate(vec2(50, 50)) * rotationMat3(0.2789281382) * translate(vec2(-25, -25)),
    bmNormal
  )
  c.writeAndCheck("tests/images/centerRotation.png")

block:
  var a = newImage(100, 100)
  a.fill(rgba(255, 255, 255, 255))
  var b = newImage(50, 50)
  b.fill(rgba(255, 92, 0, 255))
  var c = a.drawFast3(
    b,
    translate(vec2(50, 50)) * rotationMat3(0.2789281382) * translate(vec2(-25, -25)),
    bmNormal
  )
  c.writeAndCheck("tests/images/centerRotationWhite.png")


block:
  var a = newImage(100, 100)
  a.fill(rgba(0, 0, 0, 0))
  var b = newImage(50, 50)
  b.fill(rgba(255, 92, 0, 255))
  var c = a.drawFast3(
    b,
    translate(vec2(50, 50)) * rotationMat3(0.2789281382) * translate(vec2(-25, -25)),
    bmNormal
  )
  c.writeAndCheck("tests/images/transCompose.c.png")
  var d = newImage(100, 100)
  d.fill(rgba(255, 255, 255, 255))
  var e = d.draw(c)
  e.writeAndCheck("tests/images/transCompose.png")

block:
  var image = newImage(10, 10)
  image[0, 0] = rgba(255, 255, 255, 255)
  doAssert image[0, 0] == rgba(255, 255, 255, 255)

block:
  var image = newImage(10, 10)
  image.fill(rgba(255, 0, 0, 255))
  doAssert image[0, 0] == rgba(255, 0, 0, 255)

block:
  var a = newImage(100, 100)
  a.fill(rgba(255, 0, 0, 255))
  var b = newImage(100, 100)
  b.fill(rgba(0, 255, 0, 255))
  var c = a.drawFast1(b, translate(vec2(25, 25)))
  c.writeAndCheck("tests/images/drawFast1.png")

block:
  var a = newImage(100, 100)
  a.fill(rgba(255, 0, 0, 255))
  var b = newImage(100, 100)
  b.fill(rgba(0, 255, 0, 255))
  var c = a.drawFast2(b, translate(vec2(25, 25)), bmCopy)
  c.writeAndCheck("tests/images/drawFast2.png")

block:
  var a = newImage(100, 100)
  a.fill(rgba(255, 0, 0, 255))
  var b = newImage(100, 100)
  b.fill(rgba(0, 255, 0, 255))
  var c = a.drawFast3(b, translate(vec2(25.15, 25.15)), bmCopy)
  c.writeAndCheck("tests/images/drawFast3.png")

block:
  var a = newImage(100, 100)
  a.fill(rgba(255, 0, 0, 255))
  var b = newImage(100, 100)
  b.fill(rgba(0, 255, 0, 255))

  var c = a.drawFast1(b, translate(vec2(25, 25)) * rotationMat3(PI/2))
  c.writeAndCheck("tests/images/drawFast1Rot.png")
