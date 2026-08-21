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

/// Shared helpers for tests that drive the C++ DataManager through the
/// ObjC++ bridge. Subclasses parse small fixtures from tests/Fixtures and run
/// the standard loading pipeline (triangulation, edges, buffer generation).
class DataManagerTestCase: XCTestCase {

  // MARK: - Constants

  static let visibleYes: CChar = 89 // 'Y'
  static let visibleNo: CChar = 78 // 'N'
  static let visiblePartly: CChar = 80 // 'P'

  // MARK: - Fixtures

  func fixtureURL(_ name: String, _ `extension`: String) -> URL {
    let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: `extension`, subdirectory: "Fixtures")
    XCTAssertNotNil(url, "Missing fixture \(name).\(`extension`)")
    return url!
  }

  /// Runs the same pipeline as Controller.loadData(from:) / MainViewController.loadFile(url:)
  func loadFixture(_ name: String, _ `extension`: String) -> DataManagerWrapperWrapper {
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

  // MARK: - Tree navigation

  func numberOfParsedFiles(_ dataManager: DataManagerWrapperWrapper) -> Int {
    dataManager.outlineView(nil, numberOfChildrenOfItem: nil)
  }

  func firstChild(_ dataManager: DataManagerWrapperWrapper, of item: Any?) -> Any? {
    dataManager.outlineView(nil, child: 0, ofItem: item)
  }

  // MARK: - Triangle buffers

  func totalTriangles(_ dataManager: DataManagerWrapperWrapper) -> Int {
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

  func countTriangleBuffers(_ dataManager: DataManagerWrapperWrapper) -> Int {
    var count = 0
    dataManager.initialiseTriangleBufferIterator()
    while !dataManager.triangleBufferIteratorEnded() {
      count += 1
      dataManager.advanceTriangleBufferIterator()
    }
    return count
  }

  func triangleBufferByteSizes(_ dataManager: DataManagerWrapperWrapper) -> [Int] {
    var sizes: [Int] = []
    dataManager.initialiseTriangleBufferIterator()
    while !dataManager.triangleBufferIteratorEnded() {
      var bytes = 0
      _ = dataManager.currentTriangleBufferIndices(withSize: &bytes)
      if bytes == 0 { _ = dataManager.currentTriangleBuffer(withSize: &bytes) }
      sizes.append(bytes)
      dataManager.advanceTriangleBufferIterator()
    }
    return sizes
  }

  func hasEdges(_ dataManager: DataManagerWrapperWrapper) -> Bool {
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

  func triangleBufferTypesAndColours(_ dataManager: DataManagerWrapperWrapper) -> [(type: String, colour: [Float], uri: String)] {
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

  func totalEdgeFloats(_ dataManager: DataManagerWrapperWrapper) -> Int {
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

  // MARK: - GPU state arrays

  func selectionStateValues(_ dataManager: DataManagerWrapperWrapper) -> [Float] {
    let count = Int(dataManager.selectionStateCount())
    guard count > 0, let data = dataManager.selectionStateData() else { return [] }
    return Array(UnsafeBufferPointer(start: data, count: count))
  }

  func visibleStateValues(_ dataManager: DataManagerWrapperWrapper) -> [Float] {
    let count = Int(dataManager.visibleStateCount())
    guard count > 0, let data = dataManager.visibleStateData() else { return [] }
    return Array(UnsafeBufferPointer(start: data, count: count))
  }

  func visibilityCharacter(_ state: CChar) -> String {
    String(UnicodeScalar(UInt8(bitPattern: state)))
  }
}
