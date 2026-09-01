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

/// Tests for object state (visibility, attributes, selection), buffer
/// splitting, malformed input handling, degenerate geometry and parser
/// parity — all through the ObjC++ bridge.
final class DataManagerStateTests: DataManagerTestCase {

  // MARK: - Visibility

  func testHidingChildUpdatesAncestorToPartlyVisible() {
    // semisurf: file > Building > LoD > one child per semantic surface
    // (GroundSurface, RoofSurface, then four WallSurfaces)
    let dataManager = loadFixture("semisurf", "city.json")
    let building = firstChild(dataManager, of: firstChild(dataManager, of: nil))
    XCTAssertNotNil(building)
    let lod = firstChild(dataManager, of: building!)
    XCTAssertNotNil(lod)
    XCTAssertEqual(dataManager.outlineView(nil, numberOfChildrenOfItem: lod!), 6)
    XCTAssertEqual(visibilityCharacter(dataManager.visibleState(ofItem: lod!)), "Y")

    // Hide one of the wall surfaces (index 5)
    guard let wallItem = dataManager.outlineView(nil, child: 5, ofItem: lod!) else {
      return XCTFail("Missing WallSurface child")
    }

    dataManager.setVisibleState(DataManagerTestCase.visibleNo, forItem: wallItem)
    XCTAssertEqual(visibilityCharacter(dataManager.visibleState(ofItem: wallItem)), "N")
    XCTAssertEqual(visibilityCharacter(dataManager.visibleState(ofItem: lod!)), "P",
                   "Parent with a hidden child should be partly visible")

    // Showing it again restores the parent
    dataManager.setVisibleState(DataManagerTestCase.visibleYes, forItem: wallItem)
    XCTAssertEqual(visibilityCharacter(dataManager.visibleState(ofItem: wallItem)), "Y")
    XCTAssertEqual(visibilityCharacter(dataManager.visibleState(ofItem: lod!)), "Y")
  }

  func testHidingObjectFlagsItInvisibleInGpuState() {
    // lods: two buildings "low" (LoD 1) and "high" (LoD 2), one quad each.
    // Hidden geometry stays in the buffers but is flagged invisible in the
    // GPU visibility state array, which the vertex shader uses to cull it.
    let dataManager = loadFixture("lods", "city.json")
    XCTAssertEqual(totalTriangles(dataManager), 4)

    let low = firstChild(dataManager, of: firstChild(dataManager, of: nil))
    XCTAssertNotNil(low)
    dataManager.setVisibleState(DataManagerTestCase.visibleNo, forItem: low!)

    // The whole subtree is now invisible
    XCTAssertEqual(visibilityCharacter(dataManager.visibleState(ofItem: low!)), "N")
    if let lodChild = firstChild(dataManager, of: low!) {
      XCTAssertEqual(visibilityCharacter(dataManager.visibleState(ofItem: lodChild)), "N")
    }

    // Regenerating keeps buffers unchanged but flags hidden objects on the GPU
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
    XCTAssertEqual(totalTriangles(dataManager), 4)
    let states = visibleStateValues(dataManager)
    XCTAssertEqual(states.count, Int(dataManager.selectionStateCount()))
    XCTAssertTrue(states.contains(0.0), "Expected a hidden entry in \(states)")
    XCTAssertTrue(states.allSatisfy { $0 == 0.0 || $0 == 1.0 })

    // Unhiding clears the flags again
    dataManager.setVisibleState(DataManagerTestCase.visibleYes, forItem: low!)
    let restored = visibleStateValues(dataManager)
    XCTAssertTrue(restored.allSatisfy { $0 == 1.0 }, "Expected all objects visible in \(restored)")
  }

  func testVisibleStatesAllOneAfterLoad() {
    let dataManager = loadFixture("cube.city", "json")
    let states = visibleStateValues(dataManager)
    XCTAssertGreaterThan(states.count, 0)
    for state in states {
      XCTAssertEqual(state, 1.0)
    }
  }

  // MARK: - Attributes

  func testAttributesOfItem() {
    let dataManager = loadFixture("attrs", "city.json")
    let building = firstChild(dataManager, of: firstChild(dataManager, of: nil))
    XCTAssertNotNil(building)

    // Strings, numbers, booleans and nulls are kept; nested objects/arrays skipped
    XCTAssertEqual(dataManager.numberOfAttributes(ofItem: building!), 4)
    XCTAssertEqual(dataManager.attributeKey(ofItem: building!, at: 0), "function")
    XCTAssertEqual(dataManager.attributeValue(ofItem: building!, at: 0), "office")
    XCTAssertEqual(dataManager.attributeKey(ofItem: building!, at: 1), "measuredHeight")
    XCTAssertEqual(dataManager.attributeValue(ofItem: building!, at: 1), "12.500000")
    XCTAssertEqual(dataManager.attributeKey(ofItem: building!, at: 2), "roofType")
    XCTAssertEqual(dataManager.attributeValue(ofItem: building!, at: 2), "true")
    XCTAssertEqual(dataManager.attributeKey(ofItem: building!, at: 3), "notes")
    XCTAssertEqual(dataManager.attributeValue(ofItem: building!, at: 3), "null")

    // Out-of-range access returns empty strings rather than crashing
    XCTAssertEqual(dataManager.attributeKey(ofItem: building!, at: -1), "")
    XCTAssertEqual(dataManager.attributeKey(ofItem: building!, at: 99), "")
    XCTAssertEqual(dataManager.attributeValue(ofItem: building!, at: 99), "")
  }

  // MARK: - Selection state

  func testSelectionStateDataReflectsSelection() {
    let dataManager = loadFixture("lods", "city.json")
    XCTAssertGreaterThan(dataManager.selectionStateCount(), 0)

    // Nothing selected after clearing
    dataManager.clearSelection()
    for state in selectionStateValues(dataManager) {
      XCTAssertEqual(state, 0.0)
    }

    // Selecting an object flags exactly one entry
    XCTAssertEqual(dataManager.setBestHitFromObjectId(0), 0)
    dataManager.selectBestHitObject()
    let states = selectionStateValues(dataManager)
    XCTAssertEqual(states.filter { $0 == 1.0 }.count, 1, "Expected exactly one selected entry in \(states)")
    XCTAssertEqual(states.filter { $0 == 0.0 }.count, states.count - 1)

    // Clearing resets every entry
    dataManager.clearSelection()
    for state in selectionStateValues(dataManager) {
      XCTAssertEqual(state, 0.0)
    }
  }

  // MARK: - Buffer splitting

  func testTriangleBufferSplittingByMaximumBufferSize() {
    let dataManager = loadFixture("cube.city", "json")
    XCTAssertEqual(countTriangleBuffers(dataManager), 1, "A single-coloured cube fits in one large buffer")
    XCTAssertEqual(totalTriangles(dataManager), 12)

    // A small maximum splits the same triangles over multiple buffers
    let maxBufferSize = 256
    dataManager.regenerateTriangleBuffers(withMaximumSize: maxBufferSize)
    let bufferCount = countTriangleBuffers(dataManager)
    XCTAssertGreaterThan(bufferCount, 1, "Expected the small buffer size to force splitting")
    XCTAssertEqual(totalTriangles(dataManager), 12, "Splitting must not lose triangles")

    // No buffer exceeds the cap by more than one triangle's footprint
    // (27 floats of vertex data + 3 indices ≈ 120 bytes)
    for size in triangleBufferByteSizes(dataManager) {
      XCTAssertLessThanOrEqual(size, maxBufferSize + 128, "Buffer of \(size) bytes ignores the cap")
    }

    // Restoring the large cap collapses back to a single buffer
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
    XCTAssertEqual(countTriangleBuffers(dataManager), 1)
  }

  // MARK: - Malformed input

  func testParseTruncatedCityJSON() {
    let dataManager = loadFixture("truncated", "city.json")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    XCTAssertEqual(totalTriangles(dataManager), 0)
  }

  func testParseInvalidCityGML() {
    let dataManager = loadFixture("invalid", "gml")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    XCTAssertEqual(totalTriangles(dataManager), 0)
  }

  func testParseTruncatedFlatCityBuf() {
    let dataManager = loadFixture("truncated", "fcb")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    XCTAssertEqual(totalTriangles(dataManager), 0)
    XCTAssertEqual(dataManager.statusMessage(), "Failed to parse FlatCityBuf file")
  }

  // MARK: - Degenerate geometry

  func testDegeneratePolygonsAreHandledGracefully() {
    // One valid triangle + duplicate consecutive point, collinear,
    // all-identical and non-planar quads. The pipeline must complete
    // without crashing and keep the valid geometry: the valid triangle (1),
    // the duplicate-point quad which collapses to a triangle (1) and the
    // non-planar quad triangulated against its least-squares plane (2).
    // The collinear and all-identical quads produce nothing.
    let dataManager = loadFixture("degenerate", "city.json")
    XCTAssertEqual(numberOfParsedFiles(dataManager), 1)
    XCTAssertEqual(totalTriangles(dataManager), 4)
    XCTAssertTrue(hasEdges(dataManager))
    XCTAssertTrue(dataManager.maxRange().isFinite)
  }

  // MARK: - Parser parity with appearances, attributes and LoDs

  func testThemedFlatCityBufMatchesCityJSONOutput() {
    let fcbDataManager = loadFixture("themed", "fcb")
    let jsonDataManager = loadFixture("themed.city", "json")

    // Geometry parity
    XCTAssertEqual(totalTriangles(fcbDataManager), totalTriangles(jsonDataManager))
    XCTAssertEqual(totalEdgeFloats(fcbDataManager), totalEdgeFloats(jsonDataManager))
    XCTAssertEqual(fcbDataManager.maxRange(), jsonDataManager.maxRange(), accuracy: 1e-9)

    // LoD detection parity
    XCTAssertEqual(Set(fcbDataManager.availableLods() ?? []),
                   Set(jsonDataManager.availableLods() ?? []))

    // Attribute parity on the building item
    let fcbBuilding = firstChild(fcbDataManager, of: firstChild(fcbDataManager, of: nil))
    let jsonBuilding = firstChild(jsonDataManager, of: firstChild(jsonDataManager, of: nil))
    XCTAssertNotNil(fcbBuilding)
    XCTAssertNotNil(jsonBuilding)
    XCTAssertEqual(fcbDataManager.numberOfAttributes(ofItem: fcbBuilding!),
                   jsonDataManager.numberOfAttributes(ofItem: jsonBuilding!))
    for index in 0..<jsonDataManager.numberOfAttributes(ofItem: jsonBuilding!) {
      XCTAssertEqual(fcbDataManager.attributeKey(ofItem: fcbBuilding!, at: index),
                     jsonDataManager.attributeKey(ofItem: jsonBuilding!, at: index))
      XCTAssertEqual(fcbDataManager.attributeValue(ofItem: fcbBuilding!, at: index),
                     jsonDataManager.attributeValue(ofItem: jsonBuilding!, at: index))
    }

    // Appearance theme parity
    XCTAssertEqual(Set(fcbDataManager.availableAppearanceThemes() ?? []),
                   Set(jsonDataManager.availableAppearanceThemes() ?? []))

    // Buffer contents must match per theme (order-independent comparison)
    func bufferKeys(_ dataManager: DataManagerWrapperWrapper) -> [String] {
      triangleBufferTypesAndColours(dataManager).map { buffer in
        let colour = buffer.colour.map { String(format: "%.5f", $0) }.joined(separator: ",")
        return "\(buffer.type)|\(colour)|\(buffer.uri)"
      }.sorted()
    }
    for theme in ["TestTheme", "Materials", "Textures"] {
      for dataManager in [fcbDataManager, jsonDataManager] {
        dataManager.setUseAppearances(true)
        dataManager.setAppearanceTheme(theme.cString(using: .utf8))
        dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
      }
      XCTAssertEqual(bufferKeys(fcbDataManager), bufferKeys(jsonDataManager),
                     "Buffers differ for theme \(theme)")
    }

    // LoD filtering parity
    for lod in ["1", "2"] {
      for dataManager in [fcbDataManager, jsonDataManager] {
        dataManager.setUseAppearances(false)
        dataManager.setAppearanceTheme("")
        dataManager.setLodFilter(lod.cString(using: .utf8))
        dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
      }
      XCTAssertEqual(totalTriangles(fcbDataManager), totalTriangles(jsonDataManager),
                     "LoD \(lod) filtering differs between parsers")
    }
  }

  // MARK: - Sorting

  /// Reads the IDs of an item's children in display order through the outline
  /// view data source, i.e. exactly the order the sidebar would show.
  private func childIds(_ dataManager: DataManagerWrapperWrapper, of item: Any?) -> [String] {
    let count = dataManager.outlineView(nil, numberOfChildrenOfItem: item)
    return (0..<count).compactMap { index in
      guard let child = dataManager.outlineView(nil, child: index, ofItem: item) else { return nil }
      return dataManager.objectId(forItem: child)
    }
  }

  func testSortChildrenByIdNaturalOrder() {
    // sorting: 4 objects in document order bld-10, tree-1, bld-2, bld-1
    let dataManager = loadFixture("sorting", "city.json")
    let file = firstChild(dataManager, of: nil)
    XCTAssertNotNil(file)
    XCTAssertEqual(childIds(dataManager, of: file!), ["bld-10", "tree-1", "bld-2", "bld-1"])

    // Natural order: bld-2 before bld-10 (lexicographic would give bld-1, bld-10, bld-2)
    dataManager.setSortOrder(key: "id", descending: false)
    XCTAssertEqual(childIds(dataManager, of: file!), ["bld-1", "bld-2", "bld-10", "tree-1"])

    dataManager.setSortOrder(key: "id", descending: true)
    XCTAssertEqual(childIds(dataManager, of: file!), ["tree-1", "bld-10", "bld-2", "bld-1"])

    // Back to document order
    dataManager.setSortOrder(key: "", descending: false)
    XCTAssertEqual(childIds(dataManager, of: file!), ["bld-10", "tree-1", "bld-2", "bld-1"])
  }

  func testSortChildrenByTypeThenId() {
    let dataManager = loadFixture("sorting", "city.json")
    let file = firstChild(dataManager, of: nil)
    XCTAssertNotNil(file)

    dataManager.setSortOrder(key: "type", descending: false)
    XCTAssertEqual(childIds(dataManager, of: file!), ["bld-1", "bld-2", "bld-10", "tree-1"])

    dataManager.setSortOrder(key: "type", descending: true)
    XCTAssertEqual(childIds(dataManager, of: file!), ["tree-1", "bld-10", "bld-2", "bld-1"])
  }

  func testSortComposesWithSearch() {
    let dataManager = loadFixture("sorting", "city.json")
    let file = firstChild(dataManager, of: nil)
    XCTAssertNotNil(file)

    dataManager.setSearchString("bld")
    dataManager.setSortOrder(key: "id", descending: false)
    XCTAssertEqual(childIds(dataManager, of: file!), ["bld-1", "bld-2", "bld-10"])

    dataManager.setSearchString("")
    XCTAssertEqual(childIds(dataManager, of: file!), ["bld-1", "bld-2", "bld-10", "tree-1"])
  }

  func testSortFilesById() {
    let dataManager = DataManagerWrapperWrapper()!
    for (name, `extension`) in [("lods", "city.json"), ("cube", "city.json")] {
      dataManager.parse(fixtureURL(name, `extension`).path.cString(using: .utf8))
      dataManager.clearHelpers()
      dataManager.updateBoundsWithLastFile()
      dataManager.triangulateLastFile()
      dataManager.generateEdgesForLastFile()
      dataManager.clearPolygonsOfLastFile()
    }
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
    dataManager.regenerateEdgeBuffers(withMaximumSize: 16 * 1024 * 1024)

    // Document order = load order; file IDs are full paths
    let loadedIds = childIds(dataManager, of: nil)
    XCTAssertEqual(loadedIds.count, 2)
    XCTAssertTrue(loadedIds[0].hasSuffix("lods.city.json"))
    XCTAssertTrue(loadedIds[1].hasSuffix("cube.city.json"))

    dataManager.setSortOrder(key: "id", descending: false)
    let sortedIds = childIds(dataManager, of: nil)
    XCTAssertTrue(sortedIds[0].hasSuffix("cube.city.json"))
    XCTAssertTrue(sortedIds[1].hasSuffix("lods.city.json"))
  }

  // MARK: - Type filtering

  func testTypeFilterShowsOnlySelectedTypes() {
    // sorting: bld-10 (Building), tree-1 (Plant), bld-2 (Building), bld-1 (Building)
    let dataManager = loadFixture("sorting", "city.json")
    let file = firstChild(dataManager, of: nil)
    XCTAssertNotNil(file)

    dataManager.setObjectTypeFilter(["Building"])
    XCTAssertEqual(childIds(dataManager, of: file!), ["bld-10", "bld-2", "bld-1"])

    dataManager.setObjectTypeFilter(["Plant"])
    XCTAssertEqual(childIds(dataManager, of: file!), ["tree-1"])

    // An empty filter shows everything again
    dataManager.setObjectTypeFilter([])
    XCTAssertEqual(childIds(dataManager, of: file!), ["bld-10", "tree-1", "bld-2", "bld-1"])
  }

  func testTypeFilterKeepsAncestorsOfMatches() {
    // semisurf: file > Building > LoD > GroundSurface, RoofSurface, 4× WallSurface.
    // Filtering on WallSurface must keep the Building and LoD ancestors for
    // context, but hide the non-matching surface siblings.
    let dataManager = loadFixture("semisurf", "city.json")
    let file = firstChild(dataManager, of: nil)
    XCTAssertNotNil(file)
    let building = firstChild(dataManager, of: file!)
    XCTAssertNotNil(building)
    let buildingId = dataManager.objectId(forItem: building!)
    let lod = firstChild(dataManager, of: building!)
    XCTAssertNotNil(lod)

    dataManager.setObjectTypeFilter(["WallSurface"])
    XCTAssertEqual(childIds(dataManager, of: file!), [buildingId])
    XCTAssertEqual(dataManager.outlineView(nil, numberOfChildrenOfItem: building!), 1)
    XCTAssertEqual(dataManager.outlineView(nil, numberOfChildrenOfItem: lod!), 4)
  }

  func testTypeFilterComposesWithSort() {
    let dataManager = loadFixture("sorting", "city.json")
    let file = firstChild(dataManager, of: nil)
    XCTAssertNotNil(file)

    dataManager.setObjectTypeFilter(["Building"])
    dataManager.setSortOrder(key: "id", descending: false)
    XCTAssertEqual(childIds(dataManager, of: file!), ["bld-1", "bld-2", "bld-10"])

    dataManager.setSortOrder(key: "id", descending: true)
    XCTAssertEqual(childIds(dataManager, of: file!), ["bld-10", "bld-2", "bld-1"])
  }

  func testAvailableTypesWithCounts() {
    let dataManager = loadFixture("sorting", "city.json")
    let counts = dataManager.availableObjectTypesWithCounts() as? [String: Int]
    XCTAssertEqual(counts?["Building"], 3)
    XCTAssertEqual(counts?["Plant"], 1)
    // Structural rows (file, LoD groupings) must not be offered
    XCTAssertNil(counts?["File"])
    XCTAssertNil(counts?["LoD"])
  }
}
