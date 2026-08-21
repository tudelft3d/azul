// azul
// Copyright © 2016-2026 Ken Arroyo Ohori
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import XCTest

/// Tests for the C++ DataManager through the ObjC++ bridge.
/// Each test parses a small fixture from tests/Fixtures and runs the
/// standard loading pipeline (triangulation, edges, buffer generation).
final class DataManagerParsingTests: XCTestCase {

  // MARK: - Helpers

  private func fixtureURL(_ name: String, _ `extension`: String) -> URL {
    let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: `extension`, subdirectory: "Fixtures")
    XCTAssertNotNil(url, "Missing fixture \(name).\(`extension`)")
    return url!
  }

  /// Runs the same pipeline as Controller.loadData(from:) / MainViewController.loadFile(url:)
  private func loadFixture(_ name: String, _ `extension`: String) -> DataManagerWrapperWrapper {
    let dataManager = DataManagerWrapperWrapper()!
    let path = fixtureURL(name, `extension`).path
    dataManager.parse(path.cString(using: .utf8))
    dataManager.clearHelpers()
    dataManager.updateBoundsWithLastFile()
    dataManager.triangulateLastFile()
    dataManager.generateEdgesForLastFile()
    dataManager.clearPolygonsOfLastFile()
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
    dataManager.regenerateEdgeBuffers(withMaximumSize: 16 * 1024 * 1024)
    return dataManager
  }

  private func numberOfParsedFiles(_ dataManager: DataManagerWrapperWrapper) -> Int {
    dataManager.outlineView(nil, numberOfChildrenOfItem: nil)
  }

  private func totalTriangles(_ dataManager: DataManagerWrapperWrapper) -> Int {
    var total = 0
    dataManager.initialiseTriangleBufferIterator()
    while !dataManager.triangleBufferIteratorEnded() {
      var bytes = 0
      let indices = dataManager.currentTriangleBufferIndices(withSize: &bytes)
      if bytes > 0 {
        total += bytes / MemoryLayout<UInt32>.size / 3
      } else {
        _ = dataManager.currentTriangleBuffer(withSize: &bytes)
        if bytes > 0 { total += bytes / MemoryLayout<Float>.size / 3 }
        else { _ = indices }
      }
      dataManager.advanceTriangleBufferIterator()
    }
    return total
  }

  private func hasEdges(_ dataManager: DataManagerWrapperWrapper) -> Bool {
    var any = false
    dataManager.initialiseEdgeBufferIterator()
    while !dataManager.edgeBufferIteratorEnded() {
      var bytes = 0
      _ = dataManager.currentEdgeBuffer(withSize: &bytes)
      if bytes > 0 { any = true }
      dataManager.advanceEdgeBufferIterator()
    }
    return any
  }

  private func triangleBufferTypesAndColours(_ dataManager: DataManagerWrapperWrapper) -> [(type: String, colour: [Float], uri: String)] {
    var result: [(type: String, colour: [Float], uri: String)] = []
    dataManager.initialiseTriangleBufferIterator()
    while !dataManager.triangleBufferIteratorEnded() {
      var length = 0
      var type = ""
      if let characters = dataManager.currentTriangleBufferType(withLength: &length), length > 0 {
        type = String(data: Data(bytes: characters, count: length), encoding: .utf8) ?? ""
      }
      var uri = ""
      if let characters = dataManager.currentTriangleBufferTextureURI(withLength: &length), length > 0 {
        uri = String(data: Data(bytes: characters, count: length), encoding: .utf8) ?? ""
      }
      let colour = dataManager.currentTriangleBufferColour()
      if let colour {
        result.append((type, Array(UnsafeBufferPointer(start: colour, count: 4)), uri))
      } else {
        result.append((type, [], uri))
      }
      dataManager.advanceTriangleBufferIterator()
    }
    return result
  }

  private func totalEdgeFloats(_ dataManager: DataManagerWrapperWrapper) -> Int {
    var total = 0
    dataManager.initialiseEdgeBufferIterator()
    while !dataManager.edgeBufferIteratorEnded() {
      var bytes = 0
      _ = dataManager.currentEdgeBuffer(withSize: &bytes)
      total += bytes / MemoryLayout<Float>.size
      dataManager.advanceEdgeBufferIterator()
    }
    return total
  }

  // MARK: - CityJSON

  func testParseCityJSONCube() {
    let dataManager = loadFixture("cube.city", "json")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    // A cube has 6 quadrilateral faces -> 12 triangles
    XCTAssertEqual(totalTriangles(dataManager), 12)
    XCTAssertTrue(hasEdges(dataManager))
    // Unit cube: max extent is 1
    XCTAssertEqual(dataManager.maxRange(), 1.0, accuracy: 1e-9)
  }

  func testLodDetection() {
    let dataManager = loadFixture("lods.city", "json")
    let lods = dataManager.availableLods() ?? []
    XCTAssertTrue(lods.contains("1"), "Expected LoD 1 in \(lods)")
    XCTAssertTrue(lods.contains("2"), "Expected LoD 2 in \(lods)")

    // Filtering on LoD 1 must leave exactly one object visible
    dataManager.setLodFilter("1")
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
    XCTAssertEqual(totalTriangles(dataManager), 2, "LoD 1 filter should keep only one quad")
  }

  // MARK: - CityJSONL

  func testParseCityJSONLines() {
    let dataManager = loadFixture("features.city", "jsonl")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    XCTAssertGreaterThan(totalTriangles(dataManager), 0)
    XCTAssertTrue(hasEdges(dataManager))
  }

  // MARK: - OBJ

  func testParseOBJTetrahedron() {
    let dataManager = loadFixture("tetrahedron", "obj")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    XCTAssertEqual(totalTriangles(dataManager), 4)
    XCTAssertTrue(hasEdges(dataManager))
  }

  // MARK: - OFF

  func testParseOFFTetrahedron() {
    let dataManager = loadFixture("tetrahedron", "off")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    XCTAssertEqual(totalTriangles(dataManager), 4)
    XCTAssertTrue(hasEdges(dataManager))
  }

  // MARK: - POLY

  func testParsePOLYTetrahedron() {
    let dataManager = loadFixture("tetrahedron", "poly")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    XCTAssertEqual(totalTriangles(dataManager), 4)
    XCTAssertTrue(hasEdges(dataManager))
  }

  // MARK: - CityGML

  func testParseCityGMLBuilding() {
    let dataManager = loadFixture("one_building", "gml")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    // One rectangular ground surface -> 2 triangles
    XCTAssertEqual(totalTriangles(dataManager), 2)
    XCTAssertTrue(hasEdges(dataManager))
  }

  // MARK: - FlatCityBuf

  func testParseFlatCityBufCube() {
    let dataManager = loadFixture("cube", "fcb")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    // Same cube as cube.city.json: 6 quadrilateral faces -> 12 triangles
    XCTAssertEqual(totalTriangles(dataManager), 12)
    XCTAssertTrue(hasEdges(dataManager))
    XCTAssertEqual(dataManager.maxRange(), 1.0, accuracy: 1e-9)
  }

  // MARK: - Semantic surfaces

  func testSemanticSurfaces() {
    let dataManager = loadFixture("semisurf", "city.json")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    // The cube is unchanged: 6 quads -> 12 triangles
    XCTAssertEqual(totalTriangles(dataManager), 12)

    // Each semantic surface type gets its own buffer with its own colour
    let buffers = triangleBufferTypesAndColours(dataManager)
    let types = Set(buffers.map { $0.type })
    XCTAssertTrue(types.contains("GroundSurface"), "Expected GroundSurface in \(types)")
    XCTAssertTrue(types.contains("RoofSurface"), "Expected RoofSurface in \(types)")
    XCTAssertTrue(types.contains("WallSurface"), "Expected WallSurface in \(types)")

    // Default semantic colours: ground grey, roof red, wall white
    for buffer in buffers {
      switch buffer.type {
      case "GroundSurface":
        XCTAssertEqual(buffer.colour[0], 0.7, accuracy: 1e-5)
      case "RoofSurface":
        XCTAssertEqual(buffer.colour[0], 1.0, accuracy: 1e-5)
        XCTAssertEqual(buffer.colour[1], 0.2, accuracy: 1e-5)
      case "WallSurface":
        XCTAssertEqual(buffer.colour[0], 1.0, accuracy: 1e-5)
        XCTAssertEqual(buffer.colour[1], 1.0, accuracy: 1e-5)
      default:
        XCTFail("Unexpected buffer type \(buffer.type)")
      }
    }
  }

  // MARK: - Triangulation edge cases

  func testTriangulateConcavePolygonAndPolygonWithHole() {
    let dataManager = loadFixture("concave_hole", "city.json")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    // L-shape (6 vertices -> 4 triangles) + square with square hole (8 vertices, 1 hole -> 8 triangles)
    XCTAssertEqual(totalTriangles(dataManager), 12)
    XCTAssertTrue(hasEdges(dataManager))
  }

  // MARK: - Error handling

  func testParseNonexistentFile() {
    let dataManager = DataManagerWrapperWrapper()!
    let path = NSTemporaryDirectory() + "azul-tests-nonexistent-\(UUID().uuidString).city.json"
    dataManager.parse(path.cString(using: .utf8))
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    XCTAssertEqual(totalTriangles(dataManager), 0)
  }

  func testParseEmptyFile() {
    let dataManager = loadFixture("empty", "city.json")
    XCTAssertEqual(totalTriangles(dataManager), 0)
  }

  func testParseUnsupportedFileType() {
    let dataManager = loadFixture("bogus", "txt")
    XCTAssertEqual(dataManager.statusMessage(), "Unrecognised file type")
    XCTAssertEqual(totalTriangles(dataManager), 0)
  }

  // MARK: - Multiple files

  func testLoadMultipleFiles() {
    let dataManager = DataManagerWrapperWrapper()!
    for (name, `extension`) in [("cube.city", "json"), ("lods.city", "json")] {
      let path = fixtureURL(name, `extension`).path
      dataManager.parse(path.cString(using: .utf8))
      dataManager.clearHelpers()
      dataManager.updateBoundsWithLastFile()
      dataManager.triangulateLastFile()
      dataManager.generateEdgesForLastFile()
      dataManager.clearPolygonsOfLastFile()
      dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
      dataManager.regenerateEdgeBuffers(withMaximumSize: 16 * 1024 * 1024)
    }
    XCTAssertEqual(numberOfParsedFiles(dataManager), 2)
    // cube: 12 triangles, lods: 2 quads -> 4 triangles
    XCTAssertEqual(totalTriangles(dataManager), 16)
    // Combined bounds span from the cube origin to the second LoD quad at x = 6
    XCTAssertEqual(dataManager.maxRange(), 6.0, accuracy: 1e-9)

    // LoD filtering still applies across both files
    dataManager.setLodFilter("2")
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
    XCTAssertEqual(totalTriangles(dataManager), 2)
  }

  // MARK: - Appearance themes

  func testAppearanceThemes() {
    let dataManager = loadFixture("appearance", "city.json")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)

    // The file defines TestTheme; Materials/Textures are always offered when both exist
    let themes = Set(dataManager.availableAppearanceThemes() ?? [])
    XCTAssertTrue(themes.contains("TestTheme"), "Expected TestTheme in \(themes)")
    XCTAssertTrue(themes.contains("Materials"), "Expected Materials in \(themes)")
    XCTAssertTrue(themes.contains("Textures"), "Expected Textures in \(themes)")

    dataManager.setUseAppearances(true)

    // Matching theme: red (alpha 0.5) and green materials, both textured
    dataManager.setAppearanceTheme("TestTheme")
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
    var buffers = triangleBufferTypesAndColours(dataManager)
    XCTAssertEqual(buffers.count, 2)
    XCTAssertTrue(buffers.contains { $0.colour == [1.0, 0.0, 0.0, 0.5] }, "Missing red material buffer in \(buffers)")
    XCTAssertTrue(buffers.contains { $0.colour == [0.0, 1.0, 0.0, 1.0] }, "Missing green material buffer in \(buffers)")
    for buffer in buffers {
      XCTAssertTrue(buffer.uri.hasSuffix("facade.png"), "Expected facade.png texture URI, got \(buffer.uri)")
    }

    // Non-matching theme: falls back to semantic colour, texture suppressed
    dataManager.setAppearanceTheme("OtherTheme")
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
    buffers = triangleBufferTypesAndColours(dataManager)
    XCTAssertEqual(buffers.count, 1)
    XCTAssertEqual(buffers[0].uri, "")
    XCTAssertEqual(buffers[0].colour[0], 1.0, accuracy: 1e-5)
    XCTAssertEqual(buffers[0].colour[1], 1.0, accuracy: 1e-5)

    // Materials mode: material colours without textures
    dataManager.setAppearanceTheme("Materials")
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
    buffers = triangleBufferTypesAndColours(dataManager)
    XCTAssertEqual(buffers.count, 2)
    for buffer in buffers {
      XCTAssertEqual(buffer.uri, "")
      XCTAssertNotEqual(buffer.colour, [1.0, 1.0, 1.0, 1.0])
    }

    // Textures mode: textures without material colours
    dataManager.setAppearanceTheme("Textures")
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
    buffers = triangleBufferTypesAndColours(dataManager)
    XCTAssertEqual(buffers.count, 1)
    XCTAssertTrue(buffers[0].uri.hasSuffix("facade.png"))
    XCTAssertEqual(buffers[0].colour, [1.0, 1.0, 1.0, 1.0])
  }

  // MARK: - Edge deduplication

  func testSharedEdgeStoredOnce() {
    // Two adjacent squares sharing one edge: 4 + 4 - 1 = 7 unique edges,
    // each edge being 2 EdgeVertices of 4 floats = 56 floats total
    let adjacent = loadFixture("adjacent", "city.json")
    XCTAssertEqual(totalEdgeFloats(adjacent), 56)

    // Two disjoint quads have no shared edge: 8 unique edges = 64 floats
    let disjoint = loadFixture("lods", "city.json")
    XCTAssertEqual(totalEdgeFloats(disjoint), 64)
  }

  // MARK: - Selection

  func testSelectionByObjectId() {
    let dataManager = loadFixture("lods", "city.json")

    // Object 0 is the LoD child of building "low"
    XCTAssertEqual(dataManager.setBestHitFromObjectId(0), 0)
    var item = dataManager.bestHitObjectIterator()
    XCTAssertNotNil(item)
    XCTAssertEqual(dataManager.objectId(forItem: item!), "low")

    // Object 1 is the LoD child of building "high"
    XCTAssertEqual(dataManager.setBestHitFromObjectId(1), 0)
    item = dataManager.bestHitObjectIterator()
    XCTAssertNotNil(item)
    XCTAssertEqual(dataManager.objectId(forItem: item!), "high")

    // Out-of-range ids are rejected
    XCTAssertEqual(dataManager.setBestHitFromObjectId(-1), -1)
    XCTAssertEqual(dataManager.setBestHitFromObjectId(99), -1)
  }

  // MARK: - Implicit geometry

  func testImplicitGeometryExpansion() {
    let dataManager = loadFixture("implicit_vegetation", "gml")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    // Template polygon (2 triangles) + expanded vegetation instance (2 triangles)
    XCTAssertEqual(totalTriangles(dataManager), 4)
    // The instance must be translated to the reference point (10, 20, 30):
    // combined bounds then span x: 0..11, y: 0..21, z: 0..30 -> maxRange 30
    XCTAssertEqual(dataManager.maxRange(), 30.0, accuracy: 1e-9)
  }

  // MARK: - Type colours

  func testTypeColourRoundTrip() {
    let dataManager = DataManagerWrapperWrapper()!
    let originalCount = dataManager.colourTypeCount()

    dataManager.setColourWithRed(0.1, green: 0.2, blue: 0.3, alpha: 0.4, forType: "TestType")
    XCTAssertEqual(dataManager.colourTypeCount(), originalCount + 1)

    var found = false
    for index in 0..<dataManager.colourTypeCount() where dataManager.colourTypeName(at: index) == "TestType" {
      var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
      dataManager.getRed(&r, green: &g, blue: &b, alpha: &a, forColourTypeAt: index)
      XCTAssertEqual(r, 0.1, accuracy: 1e-5)
      XCTAssertEqual(g, 0.2, accuracy: 1e-5)
      XCTAssertEqual(b, 0.3, accuracy: 1e-5)
      XCTAssertEqual(a, 0.4, accuracy: 1e-5)
      found = true
    }
    XCTAssertTrue(found, "TestType not found in colour types")

    dataManager.resetTypeColours()
    XCTAssertEqual(dataManager.colourTypeCount(), originalCount)
  }

  // MARK: - Search

  func testSearchMatchesAttributes() {
    let dataManager = loadFixture("cube.city", "json")
    let fileItem = dataManager.outlineView(nil, child: 0, ofItem: nil)
    XCTAssertNotNil(fileItem)

    // No filter: the file has one child object
    dataManager.setSearchString("")
    XCTAssertEqual(dataManager.outlineView(nil, numberOfChildrenOfItem: fileItem!), 1)

    // Match on attribute value ("function": "office") and on object id
    dataManager.setSearchString("office")
    XCTAssertEqual(dataManager.outlineView(nil, numberOfChildrenOfItem: fileItem!), 1)
    dataManager.setSearchString("cube-1")
    XCTAssertEqual(dataManager.outlineView(nil, numberOfChildrenOfItem: fileItem!), 1)

    // No match at all
    dataManager.setSearchString("zzz-no-match")
    XCTAssertEqual(dataManager.outlineView(nil, numberOfChildrenOfItem: fileItem!), 0)
  }

  // MARK: - Format aliases and parser parity

  func testXmlAliasForCityGML() {
    let dataManager = loadFixture("one_building", "xml")
    XCTAssertEqual(totalTriangles(dataManager), 2)
  }

  func testFlatCityBufMatchesCityJSONOutput() {
    let fcbDataManager = loadFixture("cube", "fcb")
    let jsonDataManager = loadFixture("cube.city", "json")
    XCTAssertEqual(totalTriangles(fcbDataManager), totalTriangles(jsonDataManager))
    XCTAssertEqual(fcbDataManager.maxRange(), jsonDataManager.maxRange(), accuracy: 1e-9)
    XCTAssertEqual(totalEdgeFloats(fcbDataManager), totalEdgeFloats(jsonDataManager))
  }
}
