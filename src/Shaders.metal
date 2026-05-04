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

#include <metal_stdlib>
using namespace metal;

struct Constants {
  float4x4 modelMatrix;
  float4x4 modelViewProjectionMatrix;
  float3x3 modelMatrixInverseTransposed;
  float4x4 viewMatrixInverse;
  float4 colour;
};

constant float3 ambientLightIntensity(0.6, 0.6, 0.6);
constant float3 diffuseLightIntensity(0.65, 0.65, 0.65);
constant float3 specularLightIntensity(0.2, 0.2, 0.2);
constant float3 lightDirectionInCamera(0.267, 0.802, -0.535);
constant float3 skyColour(0.65, 0.7, 0.85);
constant float3 groundColour(0.35, 0.3, 0.25);
constant float3 selectionColour(1.0, 1.0, 0.0);
constant float shininess = 32.0;

struct VertexWithNormalIn {
  packed_float3 position;
  float objectId;
  packed_float3 normal;
};

struct VertexIn {
  float3 position;
};

struct VertexOutLit {
  float4 position [[position]];
  float3 worldNormal;
  float3 worldPosition;
  float objectId;
};

struct VertexOutUnlit {
  float4 position [[position]];
  float4 colour;
};

vertex VertexOutLit vertexLit(const device VertexWithNormalIn *vertices [[buffer(0)]],
                               constant Constants &uniforms [[buffer(1)]],
                               uint VertexId [[vertex_id]]) {
  
  VertexOutLit out;
  float3 position = float3(vertices[VertexId].position);
  float3 normal = float3(vertices[VertexId].normal);
  out.position = uniforms.modelViewProjectionMatrix * float4(position, 1.0);
  out.worldNormal = normalize(uniforms.modelMatrixInverseTransposed * normal);
  float4 worldPosition = uniforms.modelMatrix * float4(position, 1.0);
  out.worldPosition = worldPosition.xyz;
  out.objectId = vertices[VertexId].objectId;
  return out;
}

vertex VertexOutUnlit vertexUnlit(const device VertexIn *vertices [[buffer(0)]],
                                   constant Constants &uniforms [[buffer(1)]],
                                   uint VertexId [[vertex_id]]) {
  
  VertexOutUnlit out;
  out.position = uniforms.modelViewProjectionMatrix * float4(vertices[VertexId].position, 1.0);
  out.colour = uniforms.colour;
  return out;
}

fragment half4 fragmentLit(VertexOutLit fragmentIn [[stage_in]],
                            constant Constants &uniforms [[buffer(0)]],
                            const device float *selectionStates [[buffer(2)]]) {
  
  float3 normalDirection = normalize(fragmentIn.worldNormal);
  float3 viewDirection = normalize(float3(uniforms.viewMatrixInverse * float4(0.0, 0.0, 0.0, 1.0) - float4(fragmentIn.worldPosition, 1.0)));
  float3 lightDirection = normalize(float3(uniforms.viewMatrixInverse * float4(lightDirectionInCamera, 0.0)));
  int objectId = int(fragmentIn.objectId);
  float selected = selectionStates[objectId];
  float3 baseColour = mix(float3(uniforms.colour.r, uniforms.colour.g, uniforms.colour.b), selectionColour, selected);
  
  float hemiWeight = 0.5 + 0.5 * normalDirection.y;
  float3 ambient = mix(groundColour, skyColour, hemiWeight) * baseColour * ambientLightIntensity;
  
  float nDotL = dot(normalDirection, lightDirection);
  float diffuseWeight = 0.5 + 0.5 * nDotL;
  float3 diffuse = diffuseLightIntensity * baseColour * diffuseWeight;
  
  float3 r = reflect(-lightDirection, normalDirection);
  float rDotV = max(0.0, dot(r, viewDirection));
  float3 specular = specularLightIntensity * pow(rDotV, shininess);
  
  return half4(float4(ambient + diffuse + specular, uniforms.colour.a));
}

fragment half4 fragmentUnlit(VertexOutUnlit fragmentIn [[stage_in]]) {
  return half4(fragmentIn.colour);
}

struct VertexOutPicking {
  float4 position [[position]];
  float objectId;
};

vertex VertexOutPicking vertexPicking(const device VertexWithNormalIn *vertices [[buffer(0)]],
                                       constant Constants &uniforms [[buffer(1)]],
                                       uint VertexId [[vertex_id]]) {
  VertexOutPicking out;
  float3 position = float3(vertices[VertexId].position);
  out.position = uniforms.modelViewProjectionMatrix * float4(position, 1.0);
  out.objectId = vertices[VertexId].objectId;
  return out;
}

fragment half4 fragmentPicking(VertexOutPicking fragmentIn [[stage_in]]) {
  uint id = uint(fragmentIn.objectId) + 1;
  return half4(
    half(id & 0xFF) / 255.0h,
    half((id >> 8) & 0xFF) / 255.0h,
    half((id >> 16) & 0xFF) / 255.0h,
    half((id >> 24) & 0xFF) / 255.0h
  );
}

