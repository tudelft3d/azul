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

  // MARK: - Search

  func testSearchMatchesObjectId() {
    let dataManager = loadFixture("cube.city", "json")
    dataManager.setSearchString("cube-1")
    XCTAssertGreaterThan(numberOfParsedFiles(dataManager), 0)
  }
}
