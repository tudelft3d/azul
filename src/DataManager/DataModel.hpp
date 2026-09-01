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

#ifndef DataModel_hpp
#define DataModel_hpp

#include <vector>
#include <map>
#include <array>
#include <cstdint>
#include <string>

struct AzulPoint {
  double coordinates[3];
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
  std::vector<std::array<float, 2>> textureCoordinates;
  bool hasTextureCoordinates;
  AzulRing() {
    hasTextureCoordinates = false;
  }
  AzulRing(const AzulRing &other) {
    for (auto const &point: other.points) points.push_back(AzulPoint(point));
    for (auto const &textureCoordinate: other.textureCoordinates) textureCoordinates.push_back(textureCoordinate);
    hasTextureCoordinates = other.hasTextureCoordinates;
  }
};

struct AzulPolygon {
  int appearanceStyleId;
  AzulRing exteriorRing;
  std::vector<AzulRing> interiorRings;
  AzulPolygon() {
    appearanceStyleId = -1;
  }
  AzulPolygon(const AzulPolygon &other) {
    appearanceStyleId = other.appearanceStyleId;
    for (auto const &point: other.exteriorRing.points) exteriorRing.points.push_back(AzulPoint(point));
    for (auto const &textureCoordinate: other.exteriorRing.textureCoordinates) exteriorRing.textureCoordinates.push_back(textureCoordinate);
    exteriorRing.hasTextureCoordinates = other.exteriorRing.hasTextureCoordinates;
    for (auto const &ring: other.interiorRings) interiorRings.push_back(AzulRing(ring));
  }
};

struct AzulTriangle {
  AzulPoint points[3];
  AzulVector normals[3];
  float textureCoordinates[3][2];
  bool hasTextureCoordinates;
  int appearanceStyleId;
  AzulTriangle() {
    hasTextureCoordinates = false;
    appearanceStyleId = -1;
    for (int i = 0; i < 3; ++i) {
      textureCoordinates[i][0] = 0.0f;
      textureCoordinates[i][1] = 0.0f;
    }
  }
  AzulTriangle(const AzulTriangle &other) {
    for (int i = 0; i < 3; ++i) points[i] = other.points[i];
    for (int i = 0; i < 3; ++i) normals[i] = other.normals[i];
    for (int i = 0; i < 3; ++i) {
      textureCoordinates[i][0] = other.textureCoordinates[i][0];
      textureCoordinates[i][1] = other.textureCoordinates[i][1];
    }
    hasTextureCoordinates = other.hasTextureCoordinates;
    appearanceStyleId = other.appearanceStyleId;
  }
};

struct AzulEdge {
  AzulPoint points[2];
  AzulEdge() {}
  AzulEdge(const AzulEdge &other) {
    for (int i = 0; i < 2; ++i) for (int j = 0; j < 3; ++j) points[i].coordinates[j] = other.points[i].coordinates[j];
  }
};

struct AzulAppearanceStyle {
  bool hasTexture;
  std::string textureUri;
  bool hasMaterial;
  std::string theme;
  float materialColour[4];
  AzulAppearanceStyle() {
    hasTexture = false;
    hasMaterial = false;
    theme = "";
    materialColour[0] = 0.0f;
    materialColour[1] = 0.0f;
    materialColour[2] = 0.0f;
    materialColour[3] = 1.0f;
  }
  AzulAppearanceStyle(const AzulAppearanceStyle &other) {
    hasTexture = other.hasTexture;
    textureUri = other.textureUri;
    hasMaterial = other.hasMaterial;
    theme = other.theme;
    for (int i = 0; i < 4; ++i) materialColour[i] = other.materialColour[i];
  }
};

struct AzulObject {
  std::string type;
  std::string id;
  std::string crsIdentifier;
  bool selected;
  int objectId;
  char visible; // 'Y'es, 'N'o, 'P'artly
  char matchesSearch; // 'Y'es, 'N'o, 'U'nknown
  char lodMatch; // 'Y'es, 'N'o, 'U'nknown
  char matchesTypeFilter; // 'Y'es, 'N'o, 'U'nknown
  char geometryTypeMatch; // 'Y'es, 'N'o, 'U'nknown — 3D type filter match incl. structural nodes inheriting their nearest semantic ancestor
  std::vector<std::pair<std::string, std::string>> attributes;
  std::vector<AzulObject> children;
  std::vector<long> displayOrder; // sidebar display order of children (indices into children, only used when sorting is active)
  std::vector<AzulPolygon> polygons;
  std::vector<AzulTriangle> triangles;
  std::vector<AzulEdge> edges;
  std::vector<AzulAppearanceStyle> appearanceStyles;
  std::vector<std::string> appearanceThemes;
  
  AzulObject() {
    selected = false;
    objectId = -1;
    visible = 'Y';
    matchesSearch = 'U';
    lodMatch = 'U';
    matchesTypeFilter = 'U';
    geometryTypeMatch = 'U';
  }
  
  AzulObject(const AzulObject &other) {
    type = other.type;
    id = other.id;
    crsIdentifier = other.crsIdentifier;
    selected = other.selected;
    objectId = other.objectId;
    visible = other.visible;
    matchesSearch = other.matchesSearch;
    lodMatch = other.lodMatch;
    matchesTypeFilter = other.matchesTypeFilter;
    geometryTypeMatch = other.geometryTypeMatch;
    for (auto const &attribute: other.attributes) attributes.push_back(std::pair<std::string, std::string>(attribute.first, attribute.second));
    for (auto const &child: other.children) children.push_back(AzulObject(child));
    displayOrder = other.displayOrder;
    for (auto const &polygon: other.polygons) polygons.push_back(AzulPolygon(polygon));
    for (auto const &triangle: other.triangles) triangles.push_back(AzulTriangle(triangle));
    for (auto const &edge: other.edges) edges.push_back(AzulEdge(edge));
    for (auto const &appearanceStyle: other.appearanceStyles) appearanceStyles.push_back(AzulAppearanceStyle(appearanceStyle));
    for (auto const &appearanceTheme: other.appearanceThemes) appearanceThemes.push_back(appearanceTheme);
  }
};

struct TriangleBuffer {
  std::string type;
  std::string textureUri;
  float colour[4];
  std::vector<float> triangles;
  std::vector<std::uint32_t> indices;
};

struct EdgeBuffer {
  float colour[4];
  std::vector<float> edges;
};

struct CentroidComputation {
  double sum[3];
  std::size_t points;
};

#endif /* DataModel_hpp */
