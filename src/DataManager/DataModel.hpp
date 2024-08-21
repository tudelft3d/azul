// azul
// Copyright © 2016-2024 Ken Arroyo Ohori
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

#ifndef DataModel_hpp
#define DataModel_hpp

#include <vector>
#include <map>

struct AzulPoint {
  float coordinates[3];
  AzulPoint() {}
  AzulPoint(const AzulPoint &other) {
    for (int i = 0; i < 3; ++i) coordinates[i] = other.coordinates[i];
  }
};

struct AzulVector {
  float components[3];
  AzulVector() {}
  AzulVector(const AzulVector &other) {
    for (int i = 0; i < 3; ++i) components[i] = other.components[i];
  }
};

struct AzulRing {
  std::vector<AzulPoint> points;
  AzulRing() {}
  AzulRing(const AzulRing &other) {
    for (auto const &point: other.points) points.push_back(AzulPoint(point));
  }
};

struct AzulPolygon {
  AzulRing exteriorRing;
  std::vector<AzulRing> interiorRings;
  AzulPolygon() {}
  AzulPolygon(const AzulPolygon &other) {
    for (auto const &point: other.exteriorRing.points) exteriorRing.points.push_back(AzulPoint(point));
    for (auto const &ring: other.interiorRings) interiorRings.push_back(AzulRing(ring));
  }
};

struct AzulTriangle {
  AzulPoint points[3];
  AzulVector normals[3];
  AzulTriangle() {}
  AzulTriangle(const AzulTriangle &other) {
    for (int i = 0; i < 3; ++i) points[i] = other.points[i];
    for (int i = 0; i < 3; ++i) normals[i] = other.normals[i];
  }
};

struct AzulEdge {
  AzulPoint points[2];
  AzulEdge() {}
  AzulEdge(const AzulEdge &other) {
    for (int i = 0; i < 2; ++i) for (int j = 0; j < 3; ++j) points[i].coordinates[j] = other.points[i].coordinates[j];
  }
};

struct AzulObject {
  std::string type;
  std::string id;
  bool selected;
  char visible; // 'Y'es, 'N'o, 'P'artly
  char matchesSearch; // 'Y'es, 'N'o, 'U'nknown
  std::vector<std::pair<std::string, std::string>> attributes;
  std::vector<AzulObject> children;
  std::vector<AzulPolygon> polygons;
  std::vector<AzulTriangle> triangles;
  std::vector<AzulEdge> edges;
  
  AzulObject() {
    selected = false;
    visible = 'Y';
    matchesSearch = 'U';
  }
  
  AzulObject(const AzulObject &other) {
    type = other.type;
    id = other.id;
    selected = other.selected;
    visible = other.visible;
    matchesSearch = other.matchesSearch;
    for (auto const &attribute: other.attributes) attributes.push_back(std::pair<std::string, std::string>(attribute.first, attribute.second));
    for (auto const &child: other.children) children.push_back(AzulObject(child));
    for (auto const &polygon: other.polygons) polygons.push_back(AzulPolygon(polygon));
    for (auto const &triangle: other.triangles) triangles.push_back(AzulTriangle(triangle));
    for (auto const &edge: other.edges) edges.push_back(AzulEdge(edge));
  }
};

struct TriangleBuffer {
  std::string type;
  float colour[4];
  std::vector<float> triangles;
};

struct EdgeBuffer {
  float colour[4];
  std::vector<float> edges;
};

struct CentroidComputation {
  float sum[3];
  std::size_t points;
};

#endif /* DataModel_hpp */
