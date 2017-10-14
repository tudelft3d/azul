// azul
// Copyright © 2016-2017 Ken Arroyo Ohori
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

import Metal
import MetalKit

func matrix4x4_perspective(fieldOfView: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
  let ys: Float = 1.0 / tanf(fieldOfView*0.5)
  let xs: Float = ys / aspectRatio
  let zs: Float = farZ / (nearZ-farZ)
  return simd_float4x4(vector4(xs, 0.0, 0.0, 0.0),
                       vector4(0.0, ys, 0.0, 0.0),
                       vector4(0.0, 0.0, zs, -1.0),
                       vector4(0.0, 0.0, zs*nearZ, 0.0))
}

func matrix4x4_look_at(eye: float3, centre: float3, up: float3) -> matrix_float4x4 {
  let z = normalize(eye-centre)
  let x = normalize(cross(up, z))
  let y = cross(z, x)
  let t = vector3(-dot(x, eye), -dot(y, eye), -dot(z, eye))
  return simd_float4x4(vector4(x.x, y.x, z.x, 0.0),
                       vector4(x.y, y.y, z.y, 0.0),
                       vector4(x.z, y.z, z.z, 0.0),
                       vector4(t.x, t.y, t.z, 1.0))
}

extension float3 {
  var isNaN : Bool {
    return x.isNaN || y.isNaN || z.isNaN
  }
}

func matrix4x4_rotation(angle: Float, axis: float3) -> matrix_float4x4 {
  let normalisedAxis = normalize(axis)

  if normalisedAxis.isNaN {
    return .identity
  }
  let ct = cosf(angle)
  let st = sinf(angle)
  let ci = 1 - ct
  let x = normalisedAxis.x
  let y = normalisedAxis.y
  let z = normalisedAxis.z
  return simd_float4x4(vector4(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                       vector4(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0),
                       vector4(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0),
                       vector4(0.0, 0.0, 0.0, 1.0))
}

func matrix4x4_translation(shift: float3) -> matrix_float4x4 {
  return simd_float4x4(vector4(1.0, 0.0, 0.0, 0.0),
                       vector4(0.0, 1.0, 0.0, 0.0),
                       vector4(0.0, 0.0, 1.0, 0.0),
                       vector4(shift.x, shift.y, shift.z, 1.0))
}

func matrix_upper_left_3x3(matrix: matrix_float4x4) -> matrix_float3x3 {
  return simd_float3x3(vector3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
                       vector3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
                       vector3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
}

func serialise(vector: float3) -> [Float] {
  return [vector.x, vector.y, vector.z]
}

func deserialiseToFloat3(vector: [Float]) -> float3 {
  return float3(vector[0], vector[1], vector[2])
}

func serialise(matrix: matrix_float4x4) -> [Float] {
  return [matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
          matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
          matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
          matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w]
}

func deserialiseToMatrix4x4(matrix: [Float]) -> matrix_float4x4 {
  return simd_float4x4(float4(matrix[0], matrix[1], matrix[2], matrix[3]),
                       float4(matrix[4], matrix[5], matrix[6], matrix[7]),
                       float4(matrix[8], matrix[9], matrix[10], matrix[11]),
                       float4(matrix[12], matrix[13], matrix[14], matrix[15]))
}
