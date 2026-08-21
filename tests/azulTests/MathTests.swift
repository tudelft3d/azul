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

final class MathTests: XCTestCase {

  func testTranslationMatrix() {
    let m = matrix4x4_translation(shift: SIMD3<Float>(2, 3, 4))
    XCTAssertEqual(m.columns.3.x, 2)
    XCTAssertEqual(m.columns.3.y, 3)
    XCTAssertEqual(m.columns.3.z, 4)
    XCTAssertEqual(m.columns.3.w, 1)
  }

  func testUpperLeft3x3() {
    var m = matrix_identity_float4x4
    m.columns.0.x = 5
    m.columns.1.y = 6
    m.columns.2.z = 7
    let upperLeft = matrix_upper_left_3x3(matrix: m)
    XCTAssertEqual(upperLeft.columns.0.x, 5)
    XCTAssertEqual(upperLeft.columns.1.y, 6)
    XCTAssertEqual(upperLeft.columns.2.z, 7)
  }

  func testVectorSerialiseRoundTrip() {
    let original = SIMD3<Float>(1.5, -2.25, 3.125)
    let deserialised = deserialiseToFloat3(vector: serialise(vector: original))
    XCTAssertEqual(deserialised, original)
  }

  func testMatrixSerialiseRoundTrip() {
    let original = matrix4x4_rotation(angle: .pi / 3, axis: SIMD3<Float>(0, 0, 1)) * matrix4x4_translation(shift: SIMD3<Float>(1, 2, 3))
    let deserialised = deserialiseToMatrix4x4(matrix: serialise(matrix: original))
    for column in 0..<4 {
      for row in 0..<4 {
        XCTAssertEqual(deserialised[column][row], original[column][row], accuracy: 1e-6)
      }
    }
  }

  func testPerspectiveShorterDimConstrainsByHeight() {
    // Landscape view: height is shorter, so vertical FOV should equal fieldOfView
    let landscape = matrix4x4_perspective_shorter_dim(fieldOfView: 60, width: 200, height: 100, nearZ: 0.1, farZ: 100)
    let heightConstrained = matrix4x4_perspective(fieldOfView: 60, aspectRatio: 2, nearZ: 0.1, farZ: 100)
    XCTAssertEqual(landscape.columns.1.y, heightConstrained.columns.1.y, accuracy: 1e-5)

    // Portrait view: width is shorter, so the vertical FOV must be larger than fieldOfView
    let portrait = matrix4x4_perspective_shorter_dim(fieldOfView: 60, width: 100, height: 200, nearZ: 0.1, farZ: 100)
    XCTAssertGreaterThan(portrait.columns.1.y, heightConstrained.columns.1.y)
  }

  func testRotationMapsXToYForQuarterTurnAroundZ() {
    let rotation = matrix4x4_rotation(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
    let rotated = rotation * SIMD4<Float>(1, 0, 0, 1)
    XCTAssertEqual(rotated.x, 0, accuracy: 1e-6)
    XCTAssertEqual(rotated.y, 1, accuracy: 1e-6)
    XCTAssertEqual(rotated.z, 0, accuracy: 1e-6)
  }

  func testRotationIsOrthogonal() {
    let rotation = matrix4x4_rotation(angle: 0.7, axis: SIMD3<Float>(1, 2, 3))
    let upperLeft = matrix_upper_left_3x3(matrix: rotation)
    let product = upperLeft * upperLeft.transpose
    for column in 0..<3 {
      for row in 0..<3 {
        let expected: Float = column == row ? 1 : 0
        XCTAssertEqual(product[column][row], expected, accuracy: 1e-6)
      }
    }
  }

  func testLookAtPlacesCentreOnNegativeZAxis() {
    let view = matrix4x4_look_at(eye: SIMD3<Float>(2, 3, 5), centre: SIMD3<Float>(1, 1, 1), up: SIMD3<Float>(0, 1, 0))
    // The centre maps to a point straight ahead of the eye on the -z axis
    let centreInView = view * SIMD4<Float>(1, 1, 1, 1)
    XCTAssertEqual(centreInView.x, 0, accuracy: 1e-6)
    XCTAssertEqual(centreInView.y, 0, accuracy: 1e-6)
    XCTAssertLessThan(centreInView.z, 0)

    // The eye itself maps to the origin
    let eyeInView = view * SIMD4<Float>(2, 3, 5, 1)
    XCTAssertEqual(eyeInView.x, 0, accuracy: 1e-6)
    XCTAssertEqual(eyeInView.y, 0, accuracy: 1e-6)
    XCTAssertEqual(eyeInView.z, 0, accuracy: 1e-6)
  }

  func testProjectionMapsNearAndFarPlanesToNdcDepthRange() {
    let nearZ: Float = 0.1
    let farZ: Float = 100.0
    // Field of view is expressed in radians
    let projection = matrix4x4_perspective(fieldOfView: .pi / 3, aspectRatio: 1.5, nearZ: nearZ, farZ: farZ)

    func ndcDepth(_ z: Float) -> Float {
      let clip = projection * SIMD4<Float>(0, 0, z, 1)
      return clip.z / clip.w
    }
    XCTAssertEqual(ndcDepth(-nearZ), 0, accuracy: 1e-6)
    XCTAssertEqual(ndcDepth(-farZ), 1, accuracy: 1e-6)

    // The frustum edge at the near plane maps to NDC y = 1
    let halfHeight = tanf(.pi / 6) * nearZ
    let edgeClip = projection * SIMD4<Float>(0, halfHeight, -nearZ, 1)
    XCTAssertEqual(edgeClip.y / edgeClip.w, 1, accuracy: 1e-6)
  }

  func testTranslationComposesWithRotation() {
    let transform = matrix4x4_translation(shift: SIMD3<Float>(1, 0, 0)) * matrix4x4_rotation(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
    let transformed = transform * SIMD4<Float>(1, 0, 0, 1)
    XCTAssertEqual(transformed.x, 1, accuracy: 1e-6)
    XCTAssertEqual(transformed.y, 1, accuracy: 1e-6)
    XCTAssertEqual(transformed.z, 0, accuracy: 1e-6)
  }
}
