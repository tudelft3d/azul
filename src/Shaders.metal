// azul
// Copyright © 2016-2019 Ken Arroyo Ohori
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
  float4 colour;
};

constant float3 ambientLightIntensity(0.8, 0.8, 0.8);
constant float3 diffuseLightIntensity(0.2, 0.2, 0.2);
constant float3 specularLightIntensity(0.2, 0.2, 0.2);
constant float3 lightPosition(0.5, 0.5, -1.0);

struct VertexWithNormalIn {
  float3 position;
  float3 normal;
};

struct VertexIn {
  float3 position;
};

struct VertexOut {
  float4 position [[position]];
  float4 colour;
};

vertex VertexOut vertexLit(device VertexWithNormalIn *vertices [[buffer(0)]],
                           constant Constants &uniforms [[buffer(1)]],
                           uint VertexId [[vertex_id]]) {
  
  float3 normalDirection = normalize(uniforms.modelMatrixInverseTransposed * vertices[VertexId].normal);
  float3 viewDirection = normalize(float3(uniforms.viewMatrixInverse * float4(0.0, 0.0, 0.0, 1.0) - uniforms.modelMatrix * float4(vertices[VertexId].position, 1.0)));
  float3 lightDirection = normalize(lightPosition);
  
  float3 ambient = ambientLightIntensity * float3(uniforms.colour.r, uniforms.colour.g, uniforms.colour.b);
  float3 diffuse = diffuseLightIntensity * float3(uniforms.colour.r, uniforms.colour.g, uniforms.colour.b) * max(0.0, dot(normalDirection, lightDirection));
  float3 specular = specularLightIntensity * float3(uniforms.colour.r, uniforms.colour.g, uniforms.colour.b) * max(0.0, dot(reflect(-lightDirection, normalDirection), viewDirection));
  
  VertexOut out;
  out.position = uniforms.modelViewProjectionMatrix * float4(vertices[VertexId].position, 1.0);
  out.colour = float4(ambient + diffuse + specular, uniforms.colour.a);
  return out;
}

vertex VertexOut vertexUnlit(device VertexIn *vertices [[buffer(0)]],
                             constant Constants &uniforms [[buffer(1)]],
                             uint VertexId [[vertex_id]]) {
  
  VertexOut out;
  out.position = uniforms.modelViewProjectionMatrix * float4(vertices[VertexId].position, 1.0);
  out.colour = uniforms.colour;
  return out;
}

fragment half4 fragmentLit(VertexOut fragmentIn [[stage_in]]) {
  return half4(fragmentIn.colour);
}

