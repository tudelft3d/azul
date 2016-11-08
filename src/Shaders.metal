// azul
// Copyright © 2016 Ken Arroyo Ohori
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

#include <metal_stdlib>
using namespace metal;

struct Constants {
  float4x4 modelMatrix;
  float4x4 modelViewProjectionMatrix;
  float3x3 modelMatrixInverseTransposed;
  float4x4 viewMatrixInverse;
  float3 colour;
};

constant float3 ambientLightIntensity(1.0, 1.0, 1.0);
constant float3 diffuseLightIntensity(0.2, 0.2, 0.2);
constant float3 specularLightIntensity(0.2, 0.2, 0.2);
constant float3 lightPosition(0.0, 0.0, -1.0);

struct VertexIn {
  float3 position;
  float3 normal;
};

struct VertexOut {
  float4 position [[position]];
  float3 colour;
};

vertex VertexOut vertexTransform(device VertexIn *vertices [[buffer(0)]],
                                 constant Constants &uniforms [[buffer(1)]],
                                 uint VertexId [[vertex_id]]) {
  
  float3 normalDirection = normalize(uniforms.modelMatrixInverseTransposed * vertices[VertexId].normal);
  float3 viewDirection = normalize(float3(uniforms.viewMatrixInverse * float4(0.0, 0.0, 0.0, 1.0) - uniforms.modelMatrix * float4(vertices[VertexId].position, 1.0)));
  float3 lightDirection = normalize(lightPosition);
  
  float3 ambient = ambientLightIntensity * uniforms.colour;
  float3 diffuse = diffuseLightIntensity * uniforms.colour * max(0.0, dot(normalDirection, lightDirection));
  float3 specular = specularLightIntensity * uniforms.colour * max(0.0, dot(reflect(-lightDirection, normalDirection), viewDirection));
  
  VertexOut out;
  out.position = uniforms.modelViewProjectionMatrix * float4(vertices[VertexId].position, 1.0);
  out.colour = ambient + diffuse + specular;
  return out;
}

fragment half4 fragmentLit(VertexOut fragmentIn [[stage_in]]) {
  return half4(half3(fragmentIn.colour), 1.0);
}
