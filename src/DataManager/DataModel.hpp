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

#pragma once

#include <vector>
#include <map>
#include "BasicTypes.h"
#import <simd/simd.h>

struct AzulRing {
  std::vector<AzulPoint> points;
};

struct AzulPolygon {
  AzulRing exteriorRing;
  std::vector<AzulRing> interiorRings;
};

struct AzulObject {
  std::string type;
  std::string id;
  bool selected;
  char matchesSearch; // 'Y'es, 'N'o, 'U'nknown
  std::vector<std::pair<std::string, std::string>> attributes;
  std::vector<AzulObject> children;
  std::vector<AzulPolygon> polygons;
  std::vector<AzulTriangle> triangles;
  std::vector<AzulEdge> edges;
  AzulObject() {
    selected = false;
    matchesSearch = 'U';
  }
};

struct TriangleBuffer {
  std::string type;
  vector_float4 colour;
  std::vector<float> triangles;
};

struct EdgeBuffer {
  vector_float4 colour;
  std::vector<float> edges;
};

struct CentroidComputation {
  vector_float3 sum;
  std::size_t points;
};

