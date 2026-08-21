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

  private func triangleBufferTypesAndColours(_ dataManager: DataManagerWrapperWrapper) -> [(type: String, colour: [Float])] {
    var result: [(type: String, colour: [Float])] = []
    dataManager.initialiseTriangleBufferIterator()
    while !dataManager.triangleBufferIteratorEnded() {
      var length = 0
      var type = ""
      if let characters = dataManager.currentTriangleBufferType(withLength: &length), length > 0 {
        type = String(data: Data(bytes: characters, count: length), encoding: .utf8) ?? ""
      }
      let colour = dataManager.currentTriangleBufferColour()
      if let colour {
        result.append((type, Array(UnsafeBufferPointer(start: colour, count: 4))))
      } else {
        result.append((type, []))
      }
      dataManager.advanceTriangleBufferIterator()
    }
    return result
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

  // MARK: - Search

  func testSearchMatchesObjectId() {
    let dataManager = loadFixture("cube.city", "json")
    dataManager.setSearchString("cube-1")
    XCTAssertGreaterThan(numberOfParsedFiles(dataManager), 0)
  }
}
