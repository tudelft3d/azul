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

#include <set>
#include <algorithm>
#include <functional>
#include <cctype>
#include <cmath>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include "DataManager.hpp"

namespace {
// Rings up to this many vertices are triangulated with the fan fast path;
// larger rings fall back to CGAL. Covers quads/pentagons/hexagons etc., which
// dominate LoD2 building data, while keeping the projection on the stack.
constexpr std::size_t kMaxFastPathRingSize = 64;

struct PointKey {
  long long x;
  long long y;
  long long z;
  bool operator==(const PointKey &other) const {
    return x == other.x && y == other.y && z == other.z;
  }
};

struct PointKeyHasher {
  std::size_t operator()(const PointKey &key) const {
    std::size_t hx = std::hash<long long>{}(key.x);
    std::size_t hy = std::hash<long long>{}(key.y);
    std::size_t hz = std::hash<long long>{}(key.z);
    return hx ^ (hy << 1) ^ (hz << 2);
  }
};

long long roundCoordinate(double coord) {
  return static_cast<long long>(llround(coord * 1e9));
}

PointKey makePointKey(const AzulPoint &point) {
  return PointKey{
    roundCoordinate(point.coordinates[0]),
    roundCoordinate(point.coordinates[1]),
    roundCoordinate(point.coordinates[2])
  };
}

std::string triangleBufferKey(const std::string &type, const std::string &textureUri, const float colour[4]) {
  std::ostringstream key;
  key << type << "|" << textureUri << "|"
      << static_cast<unsigned int>(llround(colour[0] * 255.0f)) << ","
      << static_cast<unsigned int>(llround(colour[1] * 255.0f)) << ","
      << static_cast<unsigned int>(llround(colour[2] * 255.0f)) << ","
      << static_cast<unsigned int>(llround(colour[3] * 255.0f));
  return key.str();
}

constexpr const char *kAppearanceMaterialsOnly = "Materials";
constexpr const char *kAppearanceTexturesOnly = "Textures";

struct EdgeKey {
  PointKey points[2];
  bool operator==(const EdgeKey &other) const {
    return points[0] == other.points[0] && points[1] == other.points[1];
  }
};

struct EdgeKeyHasher {
  std::size_t operator()(const EdgeKey &key) const {
    std::uint64_t hash = 1469598103934665603ULL;
    for (int i = 0; i < 2; ++i) {
      hash ^= static_cast<std::uint64_t>(key.points[i].x);
      hash *= 1099511628211ULL;
      hash ^= static_cast<std::uint64_t>(key.points[i].y);
      hash *= 1099511628211ULL;
      hash ^= static_cast<std::uint64_t>(key.points[i].z);
      hash *= 1099511628211ULL;
    }
    return static_cast<std::size_t>(hash);
  }
};

bool pointKeyLess(const PointKey &a, const PointKey &b) {
  if (a.x < b.x) return true;
  if (a.x > b.x) return false;
  if (a.y < b.y) return true;
  if (a.y > b.y) return false;
  return a.z < b.z;
}

void generateEdgesForObject(AzulObject &object, std::unordered_set<EdgeKey, EdgeKeyHasher> &sharedEdges, bool isFileChild) {
  std::unordered_set<EdgeKey, EdgeKeyHasher> localEdges;
  std::unordered_set<EdgeKey, EdgeKeyHasher> *effectiveSet = &sharedEdges;
  if (isFileChild || object.type == "LoD") {
    effectiveSet = &localEdges;
  }
  for (auto &child: object.children) generateEdgesForObject(child, *effectiveSet, false);

  std::size_t estimatedSegments = 0;
  for (auto const &polygon: object.polygons) {
    if (polygon.exteriorRing.points.size() >= 4) estimatedSegments += polygon.exteriorRing.points.size() - 1;
  }

  if (effectiveSet->empty()) effectiveSet->reserve(estimatedSegments);

  std::vector<AzulEdge> edges;
  edges.reserve(estimatedSegments);
  for (auto const &polygon: object.polygons) {
    if (polygon.exteriorRing.points.size() < 4) {
      std::cout << "Polygon with < 4 points! Skipping..." << std::endl;
      continue;
    }
    const auto &points = polygon.exteriorRing.points;
    for (std::size_t i = 0; i + 1 < points.size(); ++i) {
      EdgeKey key;
      PointKey keyA = makePointKey(points[i]);
      PointKey keyB = makePointKey(points[i + 1]);
      if (pointKeyLess(keyA, keyB)) {
        key.points[0] = keyA;
        key.points[1] = keyB;
      } else {
        key.points[0] = keyB;
        key.points[1] = keyA;
      }
      auto insertion = effectiveSet->insert(key);
      if (!insertion.second) continue;
      edges.push_back(AzulEdge());
      for (int j = 0; j < 3; ++j) edges.back().points[0].coordinates[j] = points[i].coordinates[j];
      for (int j = 0; j < 3; ++j) edges.back().points[1].coordinates[j] = points[i + 1].coordinates[j];
    }
  }
  object.edges = edges;
}

// Fast path for triangulating a convex ring (no interior rings): a fan
// triangulation (shortest diagonal for quads) replaces the CGAL least-squares
// plane fit + constrained Delaunay triangulation + flood fill. Falls back by
// returning false whenever the ring is not strictly convex in its Newell
// plane, has holes, or is degenerate, in which case the caller uses CGAL.
bool fastTriangulateConvexRing(const AzulPolygon &polygon,
                               const std::unordered_map<PointKey, std::array<float, 2>, PointKeyHasher> &textureCoordinatesByPoint,
                               bool polygonHasTextureCoordinates,
                               std::vector<AzulTriangle> &triangles) {
  if (!polygon.interiorRings.empty()) return false;
  const std::vector<AzulPoint> &points = polygon.exteriorRing.points;
  if (points.size() < 5) return false; // triangles are handled by the caller; a quad has 4 distinct vertices + closing point
  const std::size_t ringSize = points.size() - 1;
  if (ringSize > kMaxFastPathRingSize) return false; // larger rings fall back to CGAL

  // Ring normal via Newell's method over the distinct vertices, normalised.
  double nx = 0.0, ny = 0.0, nz = 0.0;
  for (std::size_t i = 0; i < ringSize; ++i) {
    const AzulPoint &p = points[i];
    const AzulPoint &q = points[(i + 1) % ringSize];
    nx += (p.coordinates[1] - q.coordinates[1]) * (p.coordinates[2] + q.coordinates[2]);
    ny += (p.coordinates[2] - q.coordinates[2]) * (p.coordinates[0] + q.coordinates[0]);
    nz += (p.coordinates[0] - q.coordinates[0]) * (p.coordinates[1] + q.coordinates[1]);
  }
  const double normalLength = std::sqrt(nx * nx + ny * ny + nz * nz);
  if (normalLength == 0.0) return false;
  const double inverseNormalLength = 1.0 / normalLength;
  nx *= inverseNormalLength;
  ny *= inverseNormalLength;
  nz *= inverseNormalLength;

  // Orthonormal basis (u, v) spanning the plane, from the coordinate axis
  // least aligned with the normal so the basis is always well conditioned.
  double referenceAxis[3];
  if (std::abs(nx) <= std::abs(ny) && std::abs(nx) <= std::abs(nz)) {
    referenceAxis[0] = 1.0; referenceAxis[1] = 0.0; referenceAxis[2] = 0.0;
  } else if (std::abs(ny) <= std::abs(nz)) {
    referenceAxis[0] = 0.0; referenceAxis[1] = 1.0; referenceAxis[2] = 0.0;
  } else {
    referenceAxis[0] = 0.0; referenceAxis[1] = 0.0; referenceAxis[2] = 1.0;
  }
  double ux = ny * referenceAxis[2] - nz * referenceAxis[1];
  double uy = nz * referenceAxis[0] - nx * referenceAxis[2];
  double uz = nx * referenceAxis[1] - ny * referenceAxis[0];
  const double uLength = std::sqrt(ux * ux + uy * uy + uz * uz);
  if (uLength == 0.0) return false;
  ux /= uLength; uy /= uLength; uz /= uLength;
  const double vx = ny * uz - nz * uy;
  const double vy = nz * ux - nx * uz;
  const double vz = nx * uy - ny * ux;

  // Project the ring onto the plane. Consecutive points that coincide in the
  // projection (or are so close that a fan triangle would be degenerate) are
  // rejected by the strict convexity test below and fall back to CGAL.
  double projectedX[kMaxFastPathRingSize], projectedY[kMaxFastPathRingSize];
  for (std::size_t i = 0; i < ringSize; ++i) {
    projectedX[i] = ux * points[i].coordinates[0] + uy * points[i].coordinates[1] + uz * points[i].coordinates[2];
    projectedY[i] = vx * points[i].coordinates[0] + vy * points[i].coordinates[1] + vz * points[i].coordinates[2];
  }
  double maxEdgeLengthSquared = 0.0;
  for (std::size_t i = 0; i < ringSize; ++i) {
    const std::size_t previous = (i == 0) ? ringSize - 1 : i - 1;
    const double dx = projectedX[i] - projectedX[previous];
    const double dy = projectedY[i] - projectedY[previous];
    const double edgeLengthSquared = dx * dx + dy * dy;
    if (edgeLengthSquared > maxEdgeLengthSquared) maxEdgeLengthSquared = edgeLengthSquared;
  }
  if (maxEdgeLengthSquared == 0.0) return false;

  // Strict convexity of the projected ring: every consecutive edge pair must
  // turn the same way, i.e. the signed 2D cross products share a single
  // non-zero sign. The epsilon is well above the projection noise floor for
  // large-coordinate data so near-collinear vertices fall back to CGAL.
  const double epsilon = 1e-8 * maxEdgeLengthSquared;
  double firstTurnSign = 0.0;
  for (std::size_t i = 0; i < ringSize; ++i) {
    const std::size_t b = (i + 1) % ringSize;
    const std::size_t c = (i + 2) % ringSize;
    const double e1x = projectedX[b] - projectedX[i];
    const double e1y = projectedY[b] - projectedY[i];
    const double e2x = projectedX[c] - projectedX[b];
    const double e2y = projectedY[c] - projectedY[b];
    const double turn = e1x * e2y - e1y * e2x;
    if (std::abs(turn) <= epsilon) return false;
    const double turnSign = (turn > 0.0) ? 1.0 : -1.0;
    if (firstTurnSign == 0.0) {
      firstTurnSign = turnSign;
    } else if (turnSign != firstTurnSign) {
      return false;
    }
  }

  // Fan triangulation. A convex quad is split along its shorter diagonal; any
  // larger convex ring fans from the first vertex.
  std::size_t fanRoot = 0;
  if (ringSize == 4) {
    const double d02x = projectedX[2] - projectedX[0];
    const double d02y = projectedY[2] - projectedY[0];
    const double d13x = projectedX[3] - projectedX[1];
    const double d13y = projectedY[3] - projectedY[1];
    const double diagonal02Squared = d02x * d02x + d02y * d02y;
    const double diagonal13Squared = d13x * d13x + d13y * d13y;
    if (diagonal13Squared < diagonal02Squared) fanRoot = 1;
  }

  const std::size_t trianglesStart = triangles.size();
  for (std::size_t i = 1; i + 1 < ringSize; ++i) {
    const std::size_t v0 = fanRoot;
    const std::size_t v1 = (fanRoot + i) % ringSize;
    const std::size_t v2 = (fanRoot + i + 1) % ringSize;
    // Safety net: a fan triangle that is degenerate in the projection (e.g. a
    // ring pinched by a near-duplicate vertex, or a needle sliver) falls back
    // to CGAL. The threshold rejects triangles too thin to be meaningful
    // (aspect below ~1e-3), matching the flood-fill behaviour on such rings.
    const double area2 = std::abs((projectedX[v1] - projectedX[v0]) * (projectedY[v2] - projectedY[v0])
                                - (projectedY[v1] - projectedY[v0]) * (projectedX[v2] - projectedX[v0]));
    if (area2 <= 1e-3 * maxEdgeLengthSquared) {
      triangles.resize(trianglesStart);
      return false;
    }
    triangles.push_back(AzulTriangle());
    AzulTriangle &triangle = triangles.back();
    triangle.appearanceStyleId = polygon.appearanceStyleId;
    bool triangleHasTextureCoordinates = polygonHasTextureCoordinates;
    for (unsigned int currentVertexIndex = 0; currentVertexIndex < 3; ++currentVertexIndex) {
      const std::size_t currentVertex = (currentVertexIndex == 0) ? v0 : (currentVertexIndex == 1) ? v1 : v2;
      const AzulPoint &point = points[currentVertex];
      triangle.points[currentVertexIndex].coordinates[0] = point.coordinates[0];
      triangle.points[currentVertexIndex].coordinates[1] = point.coordinates[1];
      triangle.points[currentVertexIndex].coordinates[2] = point.coordinates[2];
      triangle.normals[currentVertexIndex].components[0] = static_cast<float>(nx);
      triangle.normals[currentVertexIndex].components[1] = static_cast<float>(ny);
      triangle.normals[currentVertexIndex].components[2] = static_cast<float>(nz);
      if (polygonHasTextureCoordinates) {
        auto foundTextureCoordinates = textureCoordinatesByPoint.find(makePointKey(point));
        if (foundTextureCoordinates != textureCoordinatesByPoint.end()) {
          triangle.textureCoordinates[currentVertexIndex][0] = foundTextureCoordinates->second[0];
          triangle.textureCoordinates[currentVertexIndex][1] = foundTextureCoordinates->second[1];
        } else {
          triangleHasTextureCoordinates = false;
        }
      }
    }
    triangle.hasTextureCoordinates = triangleHasTextureCoordinates;
  }
  return true;
}

}

void DataManager::boundsOfAzulObjectAndItsChildren(const AzulObject &object, double *min, double *max) {
  for (const auto &child: object.children) boundsOfAzulObjectAndItsChildren(child, min, max);
  for (const auto &polygon: object.polygons) {
    for (const auto &point: polygon.exteriorRing.points) {
      for (int coordinate = 0; coordinate < 3; ++coordinate) {
        if (point.coordinates[coordinate] < min[coordinate]) min[coordinate] = point.coordinates[coordinate];
        if (point.coordinates[coordinate] > max[coordinate]) max[coordinate] = point.coordinates[coordinate];
      }
    }
  }
}

void DataManager::transformAzulObjectAndItsChildren(AzulObject &object, double centerLon, double centerLat, double cosCenterLat, double R) {
  for (auto &child: object.children) transformAzulObjectAndItsChildren(child, centerLon, centerLat, cosCenterLat, R);
  for (auto &polygon: object.polygons) {
    for (auto &point: polygon.exteriorRing.points) {
      double lon = point.coordinates[0];
      double lat = point.coordinates[1];
      point.coordinates[0] = R * cosCenterLat * (lon - centerLon) * (M_PI / 180.0);
      point.coordinates[1] = R * (lat - centerLat) * (M_PI / 180.0);
    }
    for (auto &ring: polygon.interiorRings) {
      for (auto &point: ring.points) {
        double lon = point.coordinates[0];
        double lat = point.coordinates[1];
        point.coordinates[0] = R * cosCenterLat * (lon - centerLon) * (M_PI / 180.0);
        point.coordinates[1] = R * (lat - centerLat) * (M_PI / 180.0);
      }
    }
  }
}

void DataManager::swapAzulObjectLatLon(AzulObject &object) {
  for (auto &child: object.children) swapAzulObjectLatLon(child);
  for (auto &polygon: object.polygons) {
    for (auto &point: polygon.exteriorRing.points) {
      std::swap(point.coordinates[0], point.coordinates[1]);
    }
    for (auto &ring: polygon.interiorRings) {
      for (auto &point: ring.points) {
        std::swap(point.coordinates[0], point.coordinates[1]);
      }
    }
  }
}

void DataManager::transformGeographicCoordinates() {
  auto &file = parsedFiles.back();
  if (file.crsIdentifier.empty()) return;

  // Extract EPSG code from identifier
  std::string code;
  auto epsgPos = file.crsIdentifier.find("EPSG:");
  if (epsgPos != std::string::npos) {
    code = file.crsIdentifier.substr(epsgPos + 5);
  } else {
    auto slashPos = file.crsIdentifier.rfind('/');
    if (slashPos != std::string::npos) {
      code = file.crsIdentifier.substr(slashPos + 1);
    }
  }
  if (code.empty()) return;

  int epsgCode;
  try {
    epsgCode = std::stoi(code);
  } catch (...) {
    return;
  }

  // Known geographic (angle-based) CRS codes
  static const std::set<int> geographicCodes = {
    4326, 4979,  // WGS84 (2D/3D)
    4258, 4937,  // ETRS89 (2D/3D)
    4269, 4966,  // NAD83 (2D/3D)
    4617, 4955,  // NAD83(CSRS) (2D/3D)
    4277, 7405,  // OSGB36 (2D/3D)
    7844, 7845,  // GDA2020 (2D/3D)
    4322, 4987,  // WGS72 (2D/3D)
    4230, 4938,  // ED50 (2D/3D)
    4674, 4989,  // SIRGAS2000 (2D/3D)
    4301,        // Tokyo
    4742, 4751,  // JGD2011 (2D/3D)
    4312,        // MGI (2D)
    4555,        // ETRS89 + Baltic 1957 height (3D)
    4259, 4940,  // OSGB70 / SN
    4171, 4965,  // RGR92 (2D/3D)
    7070, 7071,  // RGAF09 (2D/3D)
  };
  // Compute file bounds for projection center
  double fileMin[3] = {std::numeric_limits<double>::max(), std::numeric_limits<double>::max(), std::numeric_limits<double>::max()};
  double fileMax[3] = {std::numeric_limits<double>::lowest(), std::numeric_limits<double>::lowest(), std::numeric_limits<double>::lowest()};
  boundsOfAzulObjectAndItsChildren(file, fileMin, fileMax);

  bool isGeographic = geographicCodes.find(epsgCode) != geographicCodes.end();

  if (!isGeographic) {
    // Fallback: detect geographic coordinates by their value range.
    // Some files (e.g. Japanese PLATEAU) declare a projected CRS but
    // store geographic (lat/lon) coordinates in degrees.
    // CityGML 2.0 convention is (lon, lat, height) per GML 3.1.1.
    // But some data stores (lat, lon, height) following CRS axis order.
    // We check which arrangement fits geographic ranges.
    bool coord0InLonRange = fileMin[0] >= -180.0 && fileMax[0] <= 180.0;
    bool coord0InLatRange = fileMin[0] >= -90.0 && fileMax[0] <= 90.0;
    bool coord1InLonRange = fileMin[1] >= -180.0 && fileMax[1] <= 180.0;
    bool coord1InLatRange = fileMin[1] >= -90.0 && fileMax[1] <= 90.0;

    if (coord0InLonRange && coord1InLatRange) {
      // (lon, lat) order — standard CityGML convention
      isGeographic = true;
      std::cout << "Coordinates appear geographic (lon, lat order). CRS: " << file.crsIdentifier << ". Applying plate carrée projection." << std::endl;
    } else if (coord0InLatRange && coord1InLonRange && !coord1InLatRange) {
      // (lat, lon) order — follows CRS axis order, swap to match convention
      isGeographic = true;
      std::cout << "Coordinates appear geographic (lat, lon order). Swapping axes. CRS: " << file.crsIdentifier << ". Applying plate carrée projection." << std::endl;
      swapAzulObjectLatLon(file);
      std::swap(fileMin[0], fileMin[1]);
      std::swap(fileMax[0], fileMax[1]);
    }
  }

  if (!isGeographic) return;

  // Use a single projection center across all loaded geographic files
  // so they maintain their relative spatial offsets.
  if (!projectionCenterSet) {
    projectionCenter[0] = (fileMin[0] + fileMax[0]) / 2.0;
    projectionCenter[1] = (fileMin[1] + fileMax[1]) / 2.0;
    projectionCenterSet = true;
  }

  double centerLon = projectionCenter[0];
  double centerLat = projectionCenter[1];
  double cosCenterLat = std::cos(centerLat * M_PI / 180.0);
  double R = 6378137.0; // WGS84 semi-major axis

  transformAzulObjectAndItsChildren(file, centerLon, centerLat, cosCenterLat, R);

  statusMessage += " (projected from geographic CRS)";
}

void DataManager::printAzulObject(const AzulObject &object, unsigned int tabs) {
  for (unsigned int tab = 0; tab < tabs; ++tab) std::cout << "\t";
  std::cout << object.type << " " << object.id << std::endl;
  for (auto const &attribute: object.attributes) {
    for (unsigned int tab = 0; tab <= tabs; ++tab) std::cout << "\t";
    std::cout << attribute.first << ": " << attribute.second << std::endl;
  } if (!object.polygons.empty()) {
    for (unsigned int tab = 0; tab <= tabs; ++tab) std::cout << "\t";
    std::cout << object.polygons.size() << " polygon(s)" << std::endl;
  } for (auto const &child: object.children) printAzulObject(child, tabs+1);
}

void DataManager::triangulateAzulObjectAndItsChildren(AzulObject &object) {
  for (auto &child: object.children) triangulateAzulObjectAndItsChildren(child);
  
  std::vector<AzulTriangle> triangles;
  for (auto &polygon: object.polygons) {
    
    // Degenerate: skip
    if (polygon.exteriorRing.points.size() < 3) {
      std::cout << "Polygon with < 3 points! Skipping..." << std::endl;
      continue;
    }
    
    // Check if last == first: fix if not
    if (polygon.exteriorRing.points.back().coordinates[0] != polygon.exteriorRing.points.front().coordinates[0] ||
        polygon.exteriorRing.points.back().coordinates[1] != polygon.exteriorRing.points.front().coordinates[1] ||
        polygon.exteriorRing.points.back().coordinates[2] != polygon.exteriorRing.points.front().coordinates[2]) {
      std::cout << "Warning: Last point != first. Adding it again at the end..." << std::endl;
      polygon.exteriorRing.points.push_back(polygon.exteriorRing.points.front());
    } for (auto &ring: polygon.interiorRings) {
      if (ring.points.back().coordinates[0] != ring.points.front().coordinates[0] ||
          ring.points.back().coordinates[1] != ring.points.front().coordinates[1] ||
          ring.points.back().coordinates[2] != ring.points.front().coordinates[2]) {
        std::cout << "Warning: Last point != first. Adding it again at the end..." << std::endl;
        ring.points.push_back(ring.points.front());
      }
    }
    
    // Degenerate: skip
    if (polygon.exteriorRing.points.size() < 4) {
      std::cout << "Polygon with < 4 points! Skipping..." << std::endl;
      continue;
    }

    std::unordered_map<PointKey, std::array<float, 2>, PointKeyHasher> textureCoordinatesByPoint;
    bool polygonHasTextureCoordinates = false;
    auto addRingTextureCoordinates = [&](const AzulRing &ring) {
      if (!ring.hasTextureCoordinates) return;
      if (ring.points.size() != ring.textureCoordinates.size()) return;
      polygonHasTextureCoordinates = true;
      for (std::size_t pointIndex = 0; pointIndex < ring.points.size(); ++pointIndex) {
        textureCoordinatesByPoint[makePointKey(ring.points[pointIndex])] = ring.textureCoordinates[pointIndex];
      }
    };
    addRingTextureCoordinates(polygon.exteriorRing);
    for (auto const &ring: polygon.interiorRings) addRingTextureCoordinates(ring);
    
    // Triangle: no need to triangulate
    if (polygon.exteriorRing.points.size() == 4 && polygon.interiorRings.size() == 0) {
      Kernel::Plane_3 plane(Kernel::Point_3(polygon.exteriorRing.points[0].coordinates[0],
                                            polygon.exteriorRing.points[0].coordinates[1],
                                            polygon.exteriorRing.points[0].coordinates[2]),
                            Kernel::Point_3(polygon.exteriorRing.points[1].coordinates[0],
                                            polygon.exteriorRing.points[1].coordinates[1],
                                            polygon.exteriorRing.points[1].coordinates[2]),
                            Kernel::Point_3(polygon.exteriorRing.points[2].coordinates[0],
                                            polygon.exteriorRing.points[2].coordinates[1],
                                            polygon.exteriorRing.points[2].coordinates[2]));
      triangles.push_back(AzulTriangle());
      triangles.back().appearanceStyleId = polygon.appearanceStyleId;
      for (unsigned int currentPoint = 0; currentPoint < 3; ++currentPoint) {
        for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
          triangles.back().points[currentPoint].coordinates[currentCoordinate] = polygon.exteriorRing.points[currentPoint].coordinates[currentCoordinate];
          triangles.back().normals[currentPoint].components[currentCoordinate] = CGAL::to_double(plane.orthogonal_vector().cartesian(currentCoordinate));
        }
        auto foundTextureCoordinates = textureCoordinatesByPoint.find(makePointKey(polygon.exteriorRing.points[currentPoint]));
        if (foundTextureCoordinates != textureCoordinatesByPoint.end()) {
          triangles.back().textureCoordinates[currentPoint][0] = foundTextureCoordinates->second[0];
          triangles.back().textureCoordinates[currentPoint][1] = foundTextureCoordinates->second[1];
        } else {
          polygonHasTextureCoordinates = false;
        }
      }
      triangles.back().hasTextureCoordinates = polygonHasTextureCoordinates;
    }
    
    // Polygon
    else {
      
      // Fast path: strictly convex ring without holes → fan/shortest-diagonal.
      // Falls back to CGAL below for concave, holed or degenerate rings.
      if (fastTriangulateConvexRing(polygon, textureCoordinatesByPoint, polygonHasTextureCoordinates, triangles)) {
        continue;
      }
      
      // Find the best fitting plane (first 3 points)
//      Kernel::Plane_3 bestPlane(Kernel::Point_3(polygon.exteriorRing.points[0].coordinates[0],
//                                                polygon.exteriorRing.points[0].coordinates[1],
//                                                polygon.exteriorRing.points[0].coordinates[2]),
//                                Kernel::Point_3(polygon.exteriorRing.points[1].coordinates[0],
//                                                polygon.exteriorRing.points[1].coordinates[1],
//                                                polygon.exteriorRing.points[1].coordinates[2]),
//                                Kernel::Point_3(polygon.exteriorRing.points[2].coordinates[0],
//                                                polygon.exteriorRing.points[2].coordinates[1],
//                                                polygon.exteriorRing.points[2].coordinates[2]));
      
      // Find the best fitting plane (from normal using Newell's Method)
//      double normal[] = {0.0, 0.0, 0.0};
//      for (std::vector<AzulPoint>::const_iterator currentPointInPolygon = polygon.exteriorRing.points.begin();
//           currentPointInPolygon != polygon.exteriorRing.points.end();
//           ++currentPointInPolygon) {
//        std::vector<AzulPoint>::const_iterator nextPointInPolygon = currentPointInPolygon;
//        ++nextPointInPolygon;
//        if (nextPointInPolygon == polygon.exteriorRing.points.end()) nextPointInPolygon = polygon.exteriorRing.points.begin();
//        normal[0] += (currentPointInPolygon->coordinates[1]-nextPointInPolygon->coordinates[1]) * (currentPointInPolygon->coordinates[2]+nextPointInPolygon->coordinates[2]);
//        normal[1] += (currentPointInPolygon->coordinates[2]-nextPointInPolygon->coordinates[2]) * (currentPointInPolygon->coordinates[0]+nextPointInPolygon->coordinates[0]);
//        normal[2] += (currentPointInPolygon->coordinates[0]-nextPointInPolygon->coordinates[0]) * (currentPointInPolygon->coordinates[1]+nextPointInPolygon->coordinates[1]);
//      } Kernel::Point_3 pointInPlane(polygon.exteriorRing.points[0].coordinates[0],
//                                     polygon.exteriorRing.points[0].coordinates[1],
//                                     polygon.exteriorRing.points[0].coordinates[2]);
//      Kernel::Vector_3 normalVector(normal[0], normal[1], normal[2]);
//      Kernel::Plane_3 bestPlane(pointInPlane, normalVector);
      
      // Find the best fitting plane (least squares)
      std::list<Kernel::Point_3> pointsInPolygon;
      for (auto const &point: polygon.exteriorRing.points) {
        pointsInPolygon.push_back(Kernel::Point_3(point.coordinates[0], point.coordinates[1], point.coordinates[2]));
      } for (auto const &ring: polygon.interiorRings) {
        for (auto const &point: ring.points) {
          pointsInPolygon.push_back(Kernel::Point_3(point.coordinates[0], point.coordinates[1], point.coordinates[2]));
        }
      } Kernel::Plane_3 bestPlane;
      linear_least_squares_fitting_3(pointsInPolygon.begin(), pointsInPolygon.end(), bestPlane, CGAL::Dimension_tag<0>());
      
      //        std::cout << "\tBest: Plane_3(" << bestPlane << ")" << std::endl;
      
      // Triangulate the projection of the edges to the plane
      Triangulation triangulation;
      std::vector<AzulPoint>::const_iterator currentPoint = polygon.exteriorRing.points.begin();
      Kernel::Point_3 newPoint(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2]);
      Triangulation::Vertex_handle currentVertex = triangulation.insert(bestPlane.to_2d(newPoint));
      currentVertex->info().hasPoint = true;
      currentVertex->info().point = newPoint;
      ++currentPoint;
      Triangulation::Vertex_handle previousVertex;
      while (currentPoint != polygon.exteriorRing.points.end()) {
        previousVertex = currentVertex;
        Kernel::Point_3 newPoint(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2]);
        currentVertex = triangulation.insert(bestPlane.to_2d(newPoint));
        currentVertex->info().hasPoint = true;
        currentVertex->info().point = newPoint;
        if (previousVertex != currentVertex) triangulation.even_odd_insert_constraint(previousVertex, currentVertex);
        ++currentPoint;
      } for (auto const &ring: polygon.interiorRings) {
        if (ring.points.size() < 4) {
          std::cout << "\tRing with < 4 points! Skipping..." << std::endl;
          continue;
        } currentPoint = ring.points.begin();
        Kernel::Point_3 newPoint(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2]);
        currentVertex = triangulation.insert(bestPlane.to_2d(newPoint));
        currentVertex->info().hasPoint = true;
        currentVertex->info().point = newPoint;
        while (currentPoint != ring.points.end()) {
          previousVertex = currentVertex;
          Kernel::Point_3 newPoint(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2]);
          currentVertex = triangulation.insert(bestPlane.to_2d(newPoint));
          currentVertex->info().hasPoint = true;
          currentVertex->info().point = newPoint;
          if (previousVertex != currentVertex) triangulation.even_odd_insert_constraint(previousVertex, currentVertex);
          ++currentPoint;
        }
      }
      
      // Label the triangles to find out interior/exterior
      if (triangulation.number_of_faces() == 0) {
        continue;
      }
      
      for (auto face: triangulation.all_face_handles()) {
        face->label() = 0;
        face->processed() = false;
      }
      
      std::list<Triangulation::Face_handle> to_check;
      std::list<int> to_check_added_by;
      triangulation.infinite_face()->label() = -1;
      triangulation.infinite_face()->processed() = true;
      to_check.push_back(triangulation.infinite_face());
      to_check_added_by.push_back(-1);
      
      while (!to_check.empty()) {
        int current_label = to_check.front()->label();
        for (int neighbour = 0; neighbour < 3; ++neighbour) {
          if (!to_check.front()->neighbor(neighbour)->processed()) {
            to_check.front()->neighbor(neighbour)->processed() = true;
            if (triangulation.is_constrained(Triangulation::Edge(to_check.front(), neighbour))) {
              to_check.front()->neighbor(neighbour)->label() = -current_label;
              to_check.push_back(to_check.front()->neighbor(neighbour));
              to_check_added_by.push_back(current_label);
            } else {
              to_check.front()->neighbor(neighbour)->label() = current_label;
              to_check.push_back(to_check.front()->neighbor(neighbour));
              to_check_added_by.push_back(current_label);
            }
          }
        } to_check.pop_front();
        to_check_added_by.pop_front();
      }
      
      // Project the triangles back to 3D (if necessary) and add
      for (Triangulation::Finite_faces_iterator currentFace = triangulation.finite_faces_begin(); currentFace != triangulation.finite_faces_end(); ++currentFace) {
        if (currentFace->label() > 0) {
          //        std::cout << "\tCreated triangle with points:" << std::endl;
          triangles.push_back(AzulTriangle());
          triangles.back().appearanceStyleId = polygon.appearanceStyleId;
          bool triangleHasTextureCoordinates = polygonHasTextureCoordinates;
          for (unsigned int currentVertexIndex = 0; currentVertexIndex < 3; ++currentVertexIndex) {
//            std::cout << "Point_2: " << currentFace->vertex(currentVertexIndex)->point() << " info: " << currentFace->vertex(currentVertexIndex)->info() << std::endl;
            Kernel::Point_3 point3;
            if (currentFace->vertex(currentVertexIndex)->info().hasPoint == true) {
//              std::cout << "Reused " << currentFace->vertex(currentVertexIndex)->info().point << std::endl;
              point3 = currentFace->vertex(currentVertexIndex)->info().point;
            } else {
//              std::cout << "New " << bestPlane.to_3d(currentFace->vertex(currentVertexIndex)->point()) << std::endl;
              point3 = bestPlane.to_3d(currentFace->vertex(currentVertexIndex)->point());
            }
            //          std::cout << "\t\tPoint_3(" << point3 << ")" << std::endl;
            for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
              triangles.back().points[currentVertexIndex].coordinates[currentCoordinate] = CGAL::to_double(point3[currentCoordinate]);
              triangles.back().normals[currentVertexIndex].components[currentCoordinate] = CGAL::to_double(bestPlane.orthogonal_vector().cartesian(currentCoordinate));
            }
            if (polygonHasTextureCoordinates) {
              AzulPoint point;
              point.coordinates[0] = triangles.back().points[currentVertexIndex].coordinates[0];
              point.coordinates[1] = triangles.back().points[currentVertexIndex].coordinates[1];
              point.coordinates[2] = triangles.back().points[currentVertexIndex].coordinates[2];
              auto foundTextureCoordinates = textureCoordinatesByPoint.find(makePointKey(point));
              if (foundTextureCoordinates != textureCoordinatesByPoint.end()) {
                triangles.back().textureCoordinates[currentVertexIndex][0] = foundTextureCoordinates->second[0];
                triangles.back().textureCoordinates[currentVertexIndex][1] = foundTextureCoordinates->second[1];
              } else {
                triangleHasTextureCoordinates = false;
              }
            }
          }
          triangles.back().hasTextureCoordinates = triangleHasTextureCoordinates;
        }
      }
    }
  }
  
  object.triangles = triangles;
}

void DataManager::updateBoundsWithAzulObjectAndItsChildren(const AzulObject &object) {
  for (const auto &child: object.children) updateBoundsWithAzulObjectAndItsChildren(child);
  for (const auto &polygon: object.polygons) {
    for (const auto &point: polygon.exteriorRing.points) {
      for (int coordinate = 0; coordinate < 3; ++coordinate) {
        if (point.coordinates[coordinate] < minCoordinates[coordinate]) minCoordinates[coordinate] = point.coordinates[coordinate];
        if (point.coordinates[coordinate] > maxCoordinates[coordinate]) maxCoordinates[coordinate] = point.coordinates[coordinate];
      }
    }
  }
}

void DataManager::clearPolygonsOfAzulObjectAndItsChildren(AzulObject &object) {
  for (auto &child: object.children) clearPolygonsOfAzulObjectAndItsChildren(child);
  object.polygons.clear();
}

void DataManager::putAzulObjectAndItsChildrenIntoTriangleBuffers(const AzulObject &object, const std::vector<AzulAppearanceStyle> &appearanceStyles, const std::string &typeWithColour, const long maxBufferSize, bool underMatchingLod, bool buildingHasNonLodGeometry) {
  bool childUnderMatchingLod;
  if (lodFilter == "__highest__") {
    childUnderMatchingLod = underMatchingLod || (object.lodMatch == 'Y' && !lodOfObject(object).empty());
  } else {
    childUnderMatchingLod = underMatchingLod || (!lodFilter.empty() && directlyMatchesLodFilter(object));
  }

  // Compute whether this building has non-lod-shell children with geometry.
  // This is used to only skip lod shells when thematic surfaces are present.
  // The caller's buildingHasNonLodGeometry is passed through for the isLodShell check.
  bool childHasNonLodGeometry = buildingHasNonLodGeometry;
  if ((object.type == "Building" || object.type == "BuildingPart") && !object.children.empty()) {
    childHasNonLodGeometry = false;
    for (const auto &child : object.children) {
      bool childIsLodShell = child.type.rfind("lod", 0) == 0;
      if (!childIsLodShell && (!child.triangles.empty() || !child.polygons.empty())) {
        childHasNonLodGeometry = true;
        break;
      }
    }
  }

  for (auto &child: object.children) {
    if (colourForType.count(child.type)) putAzulObjectAndItsChildrenIntoTriangleBuffers(child, appearanceStyles, child.type, maxBufferSize, childUnderMatchingLod, childHasNonLodGeometry);
    else putAzulObjectAndItsChildrenIntoTriangleBuffers(child, appearanceStyles, typeWithColour, maxBufferSize, childUnderMatchingLod, childHasNonLodGeometry);
  }
  
  if (object.triangles.empty()) return;
  if (lodFilter == "__highest__") {
    if (!underMatchingLod && object.lodMatch != 'Y') return;
  } else if (!lodFilter.empty() && !underMatchingLod && !directlyMatchesLodFilter(object)) return;

  // Avoid drawing duplicate lod* shells under building contexts.
  // These shells wash out default roof/wall semantic colours, especially for BuildingParts.
  // Only skip when the building has actual non-lod-shell children (thematic surfaces).
  // When all geometry is in lod shells (e.g. PLATEAU data), keep them visible.
  bool inBuildingContext = (typeWithColour == "Building" || typeWithColour == "BuildingPart");
  bool isLodShell = object.type.rfind("lod", 0) == 0 &&
                    (object.type.find("Solid") != std::string::npos ||
                     object.type.find("MultiSurface") != std::string::npos);
  if (inBuildingContext && isLodShell && buildingHasNonLodGeometry) {
    return;
  }
  
  // Assign a unique objectId for selection and visibility tracking
  int objectId = static_cast<int>(objectsById.size());
  objectsById.push_back(const_cast<AzulObject *>(&object));
  const_cast<AzulObject &>(object).objectId = objectId;

  auto typeColourIterator = colourForType.find(typeWithColour);
  auto defaultColourIterator = colourForType.find("");
  std::tuple<float, float, float, float> fallbackTypeColour = defaultColourIterator != colourForType.end() ? defaultColourIterator->second : std::tuple<float, float, float, float>(0.75f, 0.75f, 0.75f, 1.0f);
  if (typeColourIterator != colourForType.end()) fallbackTypeColour = typeColourIterator->second;

  for (auto const &triangle: object.triangles) {
    std::string textureUri;
    float colour[4] = {
      std::get<0>(fallbackTypeColour),
      std::get<1>(fallbackTypeColour),
      std::get<2>(fallbackTypeColour),
      std::get<3>(fallbackTypeColour)
    };

    if (useAppearances &&
        triangle.appearanceStyleId >= 0 &&
        triangle.appearanceStyleId < static_cast<int>(appearanceStyles.size())) {
      const auto &appearanceStyle = appearanceStyles[triangle.appearanceStyleId];
      bool materialsOnly = appearanceTheme == kAppearanceMaterialsOnly;
      bool texturesOnly = appearanceTheme == kAppearanceTexturesOnly;
      bool themeMatches = appearanceTheme.empty() ||
                          materialsOnly ||
                          texturesOnly ||
                          appearanceStyle.theme == appearanceTheme;
      if (themeMatches && appearanceStyle.hasMaterial && !texturesOnly) {
        colour[0] = appearanceStyle.materialColour[0];
        colour[1] = appearanceStyle.materialColour[1];
        colour[2] = appearanceStyle.materialColour[2];
        colour[3] = appearanceStyle.materialColour[3];
      }
      if (themeMatches &&
          appearanceStyle.hasTexture &&
          !materialsOnly &&
          triangle.hasTextureCoordinates &&
          !appearanceStyle.textureUri.empty()) {
        textureUri = appearanceStyle.textureUri;
      }
    } else if (!useAppearances &&
               triangle.appearanceStyleId >= 0 &&
               triangle.appearanceStyleId < static_cast<int>(appearanceStyles.size())) {
      const auto &appearanceStyle = appearanceStyles[triangle.appearanceStyleId];
      if (appearanceStyle.hasMaterial) {
        colour[0] = appearanceStyle.materialColour[0];
        colour[1] = appearanceStyle.materialColour[1];
        colour[2] = appearanceStyle.materialColour[2];
        colour[3] = appearanceStyle.materialColour[3];
      }
    }

    std::string bufferKey = triangleBufferKey(typeWithColour, textureUri, colour);
    long triangleBufferFootprint = static_cast<long>((3 * 9 * sizeof(float)) + (3 * sizeof(std::uint32_t)));
    std::list<TriangleBuffer>::iterator currentBuffer;
    if (lastTriangleBufferByKey.count(bufferKey) == 0 ||
        (lastTriangleBufferByKey[bufferKey]->triangles.size() * sizeof(float) +
         lastTriangleBufferByKey[bufferKey]->indices.size() * sizeof(std::uint32_t) +
         triangleBufferFootprint) > maxBufferSize) {
      triangleBuffers.push_front(TriangleBuffer());
      currentBuffer = triangleBuffers.begin();
      currentBuffer->type = typeWithColour;
      currentBuffer->textureUri = textureUri;
      currentBuffer->colour[0] = colour[0];
      currentBuffer->colour[1] = colour[1];
      currentBuffer->colour[2] = colour[2];
      currentBuffer->colour[3] = colour[3];
      lastTriangleBufferByKey[bufferKey] = currentBuffer;
    } else {
      currentBuffer = lastTriangleBufferByKey[bufferKey];
    }

    std::uint32_t vertexIndex = static_cast<std::uint32_t>(currentBuffer->triangles.size() / 9);
    for (int pointIndex = 0; pointIndex < 3; ++pointIndex) {
      for (int coordinate = 0; coordinate < 3; ++coordinate)
        currentBuffer->triangles.push_back((triangle.points[pointIndex].coordinates[coordinate]-midCoordinates[coordinate])/maxRange);
      currentBuffer->triangles.push_back(static_cast<float>(objectId));
      for (int component = 0; component < 3; ++component)
        currentBuffer->triangles.push_back(triangle.normals[pointIndex].components[component]);
      if (!textureUri.empty()) {
        currentBuffer->triangles.push_back(triangle.textureCoordinates[pointIndex][0]);
        currentBuffer->triangles.push_back(triangle.textureCoordinates[pointIndex][1]);
      } else {
        currentBuffer->triangles.push_back(0.0f);
        currentBuffer->triangles.push_back(0.0f);
      }
      currentBuffer->indices.push_back(vertexIndex++);
    }
  }
}

void DataManager::putAzulObjectAndItsChildrenIntoEdgeBuffers(const AzulObject &object, const long maxBufferSize, bool underMatchingLod) {
  bool childUnderMatchingLod;
  if (lodFilter == "__highest__") {
    childUnderMatchingLod = underMatchingLod || (object.lodMatch == 'Y' && !lodOfObject(object).empty());
  } else {
    childUnderMatchingLod = underMatchingLod || (!lodFilter.empty() && directlyMatchesLodFilter(object));
  }
  for (auto &child: object.children) putAzulObjectAndItsChildrenIntoEdgeBuffers(child, maxBufferSize, childUnderMatchingLod);
  
  if (object.edges.empty()) return;
  std::list<EdgeBuffer>::iterator currentBuffer;
  
  if (lodFilter == "__highest__") {
    if (!underMatchingLod && object.lodMatch != 'Y') return;
  } else if (!lodFilter.empty() && !underMatchingLod && !directlyMatchesLodFilter(object)) return;
  
  // Make new buffer if necessary (selected)
  if (object.selected) {
    if (lastEdgeBufferBySelection.count(true) == 0 ||
        (lastEdgeBufferBySelection[true]->edges.size()+object.edges.size())*sizeof(float) > maxBufferSize) {
      EdgeBuffer newBuffer;
      newBuffer.colour[0] = std::get<0>(selectedEdgesColour);
      newBuffer.colour[1] = std::get<1>(selectedEdgesColour);
      newBuffer.colour[2] = std::get<2>(selectedEdgesColour);
      newBuffer.colour[3] = std::get<3>(selectedEdgesColour);
      edgeBuffers.push_front(newBuffer);
      lastEdgeBufferBySelection[true] = edgeBuffers.begin();
      currentBuffer = edgeBuffers.begin();
    } else {
      currentBuffer = lastEdgeBufferBySelection[true];
    }
  }
  
  // Make new buffer if necessary (not selected)
  else {
    if (lastEdgeBufferBySelection.count(false) == 0 ||
        (lastEdgeBufferBySelection[false]->edges.size()+object.edges.size())*sizeof(float) > maxBufferSize) {
      EdgeBuffer newBuffer;
      newBuffer.colour[0] = std::get<0>(black);
      newBuffer.colour[1] = std::get<1>(black);
      newBuffer.colour[2] = std::get<2>(black);
      newBuffer.colour[3] = std::get<3>(black);
      edgeBuffers.push_front(newBuffer);
      lastEdgeBufferBySelection[false] = edgeBuffers.begin();
      currentBuffer = edgeBuffers.begin();
    } else {
      currentBuffer = lastEdgeBufferBySelection[false];
    }
  }
  
  for (auto const &edge: object.edges) {
    for (int pointIndex = 0; pointIndex < 2; ++pointIndex) {
      for (int coordinate = 0; coordinate < 3; ++coordinate) currentBuffer->edges.push_back((edge.points[pointIndex].coordinates[coordinate]-midCoordinates[coordinate])/maxRange);
      currentBuffer->edges.push_back(static_cast<float>(object.objectId));
    }
  }
}

namespace {

// Case-insensitive natural comparison: digit runs compare by numeric value,
// so "b2" sorts before "b10". Returns <0, 0 or >0 like strcmp.
int naturalCompare(const std::string &a, const std::string &b) {
  std::size_t i = 0, j = 0;
  while (i < a.size() && j < b.size()) {
    bool digitA = isdigit(static_cast<unsigned char>(a[i])) != 0;
    bool digitB = isdigit(static_cast<unsigned char>(b[j])) != 0;
    if (digitA && digitB) {
      std::size_t startA = i, startB = j;
      while (i < a.size() && a[i] == '0') ++i;
      while (j < b.size() && b[j] == '0') ++j;
      std::size_t endA = i, endB = j;
      while (endA < a.size() && isdigit(static_cast<unsigned char>(a[endA]))) ++endA;
      while (endB < b.size() && isdigit(static_cast<unsigned char>(b[endB]))) ++endB;
      if (endA-i != endB-j) return endA-i < endB-j ? -1 : 1;
      while (i < endA) {
        if (a[i] != b[j]) return a[i] < b[j] ? -1 : 1;
        ++i; ++j;
      }
      // Same numeric value; tie-break on leading zeros ("01" < "1"), then move on
      if (endA-startA != endB-startB) return endA-startA < endB-startB ? -1 : 1;
      i = endA; j = endB;
    } else {
      int charA = tolower(static_cast<unsigned char>(a[i]));
      int charB = tolower(static_cast<unsigned char>(b[j]));
      if (charA != charB) return charA < charB ? -1 : 1;
      ++i; ++j;
    }
  }
  if (i < a.size()) return 1;
  if (j < b.size()) return -1;
  return 0;
}

// Fills order with the display permutation of children for the current sort
// settings. Equal keys keep document order (stable sort). Objects without an
// ID always group at the end regardless of direction.
void sortDisplayOrder(std::vector<long> &order,
                      const std::vector<AzulObject> &children,
                      const std::string &sortKey,
                      bool descending) {
  auto compareById = [&](long indexA, long indexB) {
    const std::string &idA = children[indexA].id;
    const std::string &idB = children[indexB].id;
    if (idA.empty() || idB.empty()) return !idA.empty(); // empty IDs last
    int result = naturalCompare(idA, idB);
    return descending ? result > 0 : result < 0;
  };
  auto compareByTypeThenId = [&](long indexA, long indexB) {
    int result = children[indexA].type.compare(children[indexB].type);
    if (result != 0) return descending ? result > 0 : result < 0;
    const std::string &idA = children[indexA].id;
    const std::string &idB = children[indexB].id;
    if (idA.empty() || idB.empty()) return !idA.empty();
    result = naturalCompare(idA, idB);
    return descending ? result > 0 : result < 0;
  };
  if (sortKey == "id") std::stable_sort(order.begin(), order.end(), compareById);
  else if (sortKey == "type") std::stable_sort(order.begin(), order.end(), compareByTypeThenId);
}

}

DataManager::DataManager() {
  useAppearances = false;
  appearanceTheme.clear();
  sortKey.clear();
  sortDescending = false;
  sortOrdersCurrent = false;
  projectionCenterSet = false;
  projectionCenter[0] = projectionCenter[1] = 0.0;
  for (int coordinate = 0; coordinate < 3; ++coordinate) {
    minCoordinates[coordinate] = std::numeric_limits<double>::max();
    maxCoordinates[coordinate] = std::numeric_limits<double>::lowest();
    centroid[coordinate] = 0.0;
  } // std::cout << "Min: " << minCoordinates[0] << " max: " << maxCoordinates[0];
  
  // Default
  colourForType[""] = std::tuple<float, float, float, float>(0.75, 0.75, 0.75, 1.0);
  
  // CityGML types
  colourForType["AuxiliaryTrafficArea"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["Bridge"] = std::tuple<float, float, float, float>(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0);
  colourForType["Building"] = std::tuple<float, float, float, float>(1.0, 1.0, 1.0, 1.0);
  colourForType["BuildingInstallation"] = std::tuple<float, float, float, float>(1.0, 1.0, 1.0, 1.0);
  colourForType["BuildingPart"] = std::tuple<float, float, float, float>(1.0, 1.0, 1.0, 1.0);
  colourForType["CityFurniture"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["Door"] = std::tuple<float, float, float, float>(0.482352941176471, 0.376470588235294, 0.231372549019608, 1.0);
  colourForType["GenericCityObject"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["GroundSurface"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["LandUse"] = std::tuple<float, float, float, float>(0.3, 0.3, 0.3, 1.0);
  colourForType["PlantCover"] = std::tuple<float, float, float, float>(0.02, 0.65, 0.16, 1.0);
  colourForType["Railway"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["ReliefFeature"] = std::tuple<float, float, float, float>(0.85, 0.92, 0.48, 1.0);
  colourForType["Road"] = std::tuple<float, float, float, float>(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0);
  colourForType["RoofSurface"] = std::tuple<float, float, float, float>(1.0, 0.2, 0.2, 1.0);
  colourForType["SolitaryVegetationObject"] = std::tuple<float, float, float, float>(0.4, 0.882352941176471, 0.333333333333333, 1.0);
  colourForType["Track"] = std::tuple<float, float, float, float>(0.66, 0.49, 0.3, 1.0);
  colourForType["TrafficArea"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["Tunnel"] = std::tuple<float, float, float, float>(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0);
  colourForType["WallSurface"] = std::tuple<float, float, float, float>(1.0, 1.0, 1.0, 1.0);
  colourForType["WaterBody"] = std::tuple<float, float, float, float>(0.36, 0.78, 1.0, 1.0);
  colourForType["Window"] = std::tuple<float, float, float, float>(0.584313725490196, 0.917647058823529, 1.0, 0.3);
  
  // CityJSON
  colourForType["TINRelief"] = std::tuple<float, float, float, float>(0.85, 0.92, 0.48, 1.0);
  
  black = std::tuple<float, float, float, float>(0.0, 0.0, 0.0, 1.0);
  selectedEdgesColour = std::tuple<float, float, float, float>(1.0, 0.0, 0.0, 1.0);
}

void DataManager::setSelectedEdgesColour(float r, float g, float b, float a) {
  selectedEdgesColour = std::tuple<float, float, float, float>(r, g, b, a);
}

void DataManager::getSelectedEdgesColour(float &r, float &g, float &b, float &a) {
  r = std::get<0>(selectedEdgesColour);
  g = std::get<1>(selectedEdgesColour);
  b = std::get<2>(selectedEdgesColour);
  a = std::get<3>(selectedEdgesColour);
}

void DataManager::setTypeColour(const std::string &type, float r, float g, float b, float a) {
  colourForType[type] = std::tuple<float, float, float, float>(r, g, b, a);
}

int DataManager::getTypeCount() {
  return static_cast<int>(colourForType.size());
}

std::string DataManager::getTypeName(int index) {
  auto it = colourForType.begin();
  std::advance(it, index);
  return it->first;
}

void DataManager::getTypeColour(int index, float &r, float &g, float &b, float &a) {
  auto it = colourForType.begin();
  std::advance(it, index);
  r = std::get<0>(it->second);
  g = std::get<1>(it->second);
  b = std::get<2>(it->second);
  a = std::get<3>(it->second);
}

void DataManager::resetTypeColours() {
  colourForType.clear();
  colourForType[""] = std::tuple<float, float, float, float>(0.75, 0.75, 0.75, 1.0);
  colourForType["AuxiliaryTrafficArea"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["Bridge"] = std::tuple<float, float, float, float>(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0);
  colourForType["Building"] = std::tuple<float, float, float, float>(1.0, 1.0, 1.0, 1.0);
  colourForType["BuildingInstallation"] = std::tuple<float, float, float, float>(1.0, 1.0, 1.0, 1.0);
  colourForType["BuildingPart"] = std::tuple<float, float, float, float>(1.0, 1.0, 1.0, 1.0);
  colourForType["CityFurniture"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["Door"] = std::tuple<float, float, float, float>(0.482352941176471, 0.376470588235294, 0.231372549019608, 1.0);
  colourForType["GenericCityObject"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["GroundSurface"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["LandUse"] = std::tuple<float, float, float, float>(0.3, 0.3, 0.3, 1.0);
  colourForType["PlantCover"] = std::tuple<float, float, float, float>(0.02, 0.65, 0.16, 1.0);
  colourForType["Railway"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["ReliefFeature"] = std::tuple<float, float, float, float>(0.85, 0.92, 0.48, 1.0);
  colourForType["Road"] = std::tuple<float, float, float, float>(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0);
  colourForType["RoofSurface"] = std::tuple<float, float, float, float>(1.0, 0.2, 0.2, 1.0);
  colourForType["SolitaryVegetationObject"] = std::tuple<float, float, float, float>(0.4, 0.882352941176471, 0.333333333333333, 1.0);
  colourForType["Track"] = std::tuple<float, float, float, float>(0.66, 0.49, 0.3, 1.0);
  colourForType["TrafficArea"] = std::tuple<float, float, float, float>(0.7, 0.7, 0.7, 1.0);
  colourForType["Tunnel"] = std::tuple<float, float, float, float>(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0);
  colourForType["WallSurface"] = std::tuple<float, float, float, float>(1.0, 1.0, 1.0, 1.0);
  colourForType["WaterBody"] = std::tuple<float, float, float, float>(0.36, 0.78, 1.0, 1.0);
  colourForType["Window"] = std::tuple<float, float, float, float>(0.584313725490196, 0.917647058823529, 1.0, 0.3);
  colourForType["TINRelief"] = std::tuple<float, float, float, float>(0.85, 0.92, 0.48, 1.0);
}

void DataManager::parse(const char *filePath) {
  //    std::cout << "Parsing " << filePath << "..." << std::endl;
  parsedFiles.push_back(AzulObject());
  if (boost::algorithm::ends_with(filePath, ".gml") ||
      boost::algorithm::ends_with(filePath, ".xml")) {
    gmlParsingHelper.parse(filePath, parsedFiles.back());
    statusMessage = gmlParsingHelper.statusMessage;
  } else if (boost::algorithm::ends_with(filePath, ".city.json") ||
             boost::algorithm::ends_with(filePath, ".cityjson")) {
    jsonParsingHelper.parse(filePath, parsedFiles.back(), true);
    statusMessage = jsonParsingHelper.statusMessage;
  } else if (boost::algorithm::ends_with(filePath, ".json")) {
    jsonParsingHelper.parse(filePath, parsedFiles.back(), false);
    statusMessage = jsonParsingHelper.statusMessage;
  } else if (boost::algorithm::ends_with(filePath, ".jsonl")) {
    jsonLinesParsingHelper.parse(filePath, parsedFiles.back());
    statusMessage = jsonLinesParsingHelper.statusMessage;
  } else if (boost::algorithm::ends_with(filePath, ".fcb")) {
    fcbParsingHelper.parse(filePath, parsedFiles.back());
    statusMessage = fcbParsingHelper.statusMessage;
  } else if (boost::algorithm::ends_with(filePath, ".obj")) {
    objParsingHelper.parse(filePath, parsedFiles.back());
    statusMessage = "";
  } else if (boost::algorithm::ends_with(filePath, ".poly")) {
    polyParsingHelper.parse(filePath, parsedFiles.back());
    statusMessage = "";
  } else if (boost::algorithm::ends_with(filePath, ".off")) {
    offParsingHelper.parse(filePath, parsedFiles.back());
    statusMessage = "";
  } else {
    statusMessage = "Unrecognised file type";
  }
  sortOrdersCurrent = false;
}

void DataManager::updateBoundsWithLastFile() {
  updateBoundsWithAzulObjectAndItsChildren(parsedFiles.back());
  double range[3];
  for (int coordinate = 0; coordinate < 3; ++coordinate) {
    midCoordinates[coordinate] = (minCoordinates[coordinate]+maxCoordinates[coordinate])/2.0;
    range[coordinate] = maxCoordinates[coordinate]-minCoordinates[coordinate];
  } maxRange = range[0];
  if (range[1] > maxRange) maxRange = range[1];
  if (range[2] > maxRange) maxRange = range[2];
  std::cout << "Bounds: min = (" << minCoordinates[0] << ", " << minCoordinates[1] << ", " << minCoordinates[2] << ") max = (" << maxCoordinates[0] << ", " << maxCoordinates[1] << ", " << maxCoordinates[2] << ")" << std::endl;
}

void DataManager::triangulateLastFile() {
  triangulateAzulObjectAndItsChildren(parsedFiles.back());
}

void DataManager::generateEdgesForLastFile() {
  std::unordered_set<EdgeKey, EdgeKeyHasher> sharedEdges;
  generateEdgesForObject(parsedFiles.back(), sharedEdges, false);
}

void DataManager::clearPolygonsOfLastFile() {
  clearPolygonsOfAzulObjectAndItsChildren(parsedFiles.back());
}

void DataManager::regenerateTriangleBuffers(long maxBufferSize) {
  std::string defaultType = "";
  triangleBuffers.clear();
  lastTriangleBufferByKey.clear();
  objectsById.clear();
  
  for (auto &file: parsedFiles) putAzulObjectAndItsChildrenIntoTriangleBuffers(file, file.appearanceStyles, defaultType, maxBufferSize);
  std::cout << "Created " << triangleBuffers.size() << " triangle buffers with " << objectsById.size() << " objects" << std::endl;
  
  // Initialize selection and visibility states from current object states
  selectionStates.resize(objectsById.size());
  visibleStates.resize(objectsById.size());
  for (int i = 0; i < objectsById.size(); ++i) {
    selectionStates[i] = objectsById[i]->selected ? 1.0f : 0.0f;
    visibleStates[i] = objectsById[i]->visible != 'N' ? 1.0f : 0.0f;
  }
}

void DataManager::regenerateEdgeBuffers(long maxBufferSize) {
  edgeBuffers.clear();
  lastEdgeBufferBySelection.clear();
  
  for (auto &file: parsedFiles)  putAzulObjectAndItsChildrenIntoEdgeBuffers(file, maxBufferSize);
  std::cout << "Created " << edgeBuffers.size() << " edge buffers" << std::endl;
}

void DataManager::clearHelpers() {
  gmlParsingHelper.clearDOM();
  jsonParsingHelper.clearDOM();
  jsonLinesParsingHelper.clearDOM();
}

void DataManager::clear() {
  clearHelpers();
  parsedFiles.clear();
  triangleBuffers.clear();
  lastTriangleBufferByKey.clear();
  objectsById.clear();
  selectionStates.clear();
  visibleStates.clear();
  edgeBuffers.clear();
  lastEdgeBufferBySelection.clear();
  useAppearances = false;
  appearanceTheme.clear();
  fileDisplayOrder.clear();
  sortOrdersCurrent = false;
  projectionCenterSet = false;
  projectionCenter[0] = projectionCenter[1] = 0.0;
  
  for (int coordinate = 0; coordinate < 3; ++coordinate) {
    minCoordinates[coordinate] = std::numeric_limits<double>::max();
    maxCoordinates[coordinate] = std::numeric_limits<double>::lowest();
  }
}

std::vector<std::string> DataManager::availableAppearanceThemes() {
  std::set<std::string> themes;
  bool hasAnyMaterial = false;
  bool hasAnyTexture = false;
  for (const auto &file : parsedFiles) {
    for (const auto &theme : file.appearanceThemes) {
      if (!theme.empty()) themes.insert(theme);
    }
    for (const auto &style : file.appearanceStyles) {
      hasAnyMaterial = hasAnyMaterial || style.hasMaterial;
      hasAnyTexture = hasAnyTexture || style.hasTexture;
    }
  }
  if (hasAnyMaterial && hasAnyTexture) {
    themes.erase("visual");
    themes.insert(kAppearanceMaterialsOnly);
    themes.insert(kAppearanceTexturesOnly);
  }
  return std::vector<std::string>(themes.begin(), themes.end());
}

void DataManager::setUseAppearances(bool enabled) {
  useAppearances = enabled;
}

void DataManager::setAppearanceTheme(const std::string &theme) {
  appearanceTheme = theme;
}

void DataManager::printParsedFiles() {
  for (auto const &file: parsedFiles) printAzulObject(file, 0);
}

void DataManager::updateSelectionStates() {
  selectionStates.resize(objectsById.size());
  for (int i = 0; i < objectsById.size(); ++i) {
    selectionStates[i] = objectsById[i]->selected ? 1.0f : 0.0f;
  }
}

const float *DataManager::getSelectionStateData() {
  return selectionStates.data();
}

int DataManager::getSelectionStateCount() {
  return static_cast<int>(selectionStates.size());
}

void DataManager::updateVisibleStates() {
  visibleStates.resize(objectsById.size());
  for (int i = 0; i < objectsById.size(); ++i) {
    visibleStates[i] = objectsById[i]->visible != 'N' ? 1.0f : 0.0f;
  }
}

const float *DataManager::getVisibleStateData() {
  return visibleStates.data();
}

int DataManager::getVisibleStateCount() {
  return static_cast<int>(visibleStates.size());
}

bool DataManager::containsObject(AzulObject &parent, AzulObject *target) {
  for (auto &child: parent.children) {
    if (&child == target || containsObject(child, target)) return true;
  }
  return false;
}

std::vector<AzulObject>::iterator DataManager::findContainingDirectChild(AzulObject &file, AzulObject *target) {
  for (auto child = file.children.begin(); child != file.children.end(); ++child) {
    if (&*child == target || containsObject(*child, target)) return child;
  }
  return file.children.end();
}

int DataManager::setBestHitFromObjectId(int objectId) {
  if (objectId < 0 || objectId >= static_cast<int>(objectsById.size())) return -1;
  AzulObject *object = objectsById[objectId];
  for (auto file = parsedFiles.begin(); file != parsedFiles.end(); ++file) {
    if (&*file == object) {
      bestHitFile = file;
      bestHitObject = file->children.end();
      return 0;
    }
    auto child = findContainingDirectChild(*file, object);
    if (child != file->children.end()) {
      bestHitFile = file;
      bestHitObject = child;
      return 0;
    }
  }
  return -1;
}

void DataManager::setSelection(AzulObject &object, bool selected) {
  for (auto &child: object.children) setSelection(child, selected);
  object.selected = selected;
}

void DataManager::setVisible(AzulObject &object, char visible) {
  for (auto &child: object.children) setVisible(child, visible);
  object.visible = visible;
}

void DataManager::checkVisibility(AzulObject &object) {
  bool hasVisibleStuff = false;
  bool hasInvisibleStuff = false;
  if (!object.triangles.empty()) {
    if (object.visible == 'Y') hasVisibleStuff = true;
    if (object.visible == 'N') hasInvisibleStuff = true;
  } for (auto &child: object.children) {
    if (child.visible == 'Y') hasVisibleStuff = true;
    if (child.visible == 'N') hasInvisibleStuff = true;
  } if (hasVisibleStuff && hasInvisibleStuff) object.visible = 'P';
  else if (hasVisibleStuff) object.visible = 'Y';
  else object.visible = 'N';
  std::cout << object.type << " visibility: " << object.visible << std::endl;
}

float DataManager::click(const float currentX, const float currentY, const simd_float4x4 &modelMatrix, const simd_float4x4 &viewMatrix, const simd_float4x4 &projectionMatrix) {
  
  // Compute two points on the ray represented by the mouse position at the near and far planes
  simd_float4x4 mvpInverse = matrix_invert(matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix)));
  simd_float4 pointOnNearPlaneInProjectionCoordinates = simd_make_float4(currentX, currentY, -1.0, 1.0);
  simd_float4 pointOnNearPlaneInObjectCoordinates = matrix_multiply(mvpInverse, pointOnNearPlaneInProjectionCoordinates);
  simd_float4 pointOnFarPlaneInProjectionCoordinates = simd_make_float4(currentX, currentY, 1.0, 1.0);
  simd_float4 pointOnFarPlaneInObjectCoordinates = matrix_multiply(mvpInverse, pointOnFarPlaneInProjectionCoordinates);
  
  // Compute ray
  simd_float3 rayOrigin = simd_make_float3(pointOnNearPlaneInObjectCoordinates.x/pointOnNearPlaneInObjectCoordinates.w,
                                           pointOnNearPlaneInObjectCoordinates.y/pointOnNearPlaneInObjectCoordinates.w,
                                           pointOnNearPlaneInObjectCoordinates.z/pointOnNearPlaneInObjectCoordinates.w);
  simd_float3 rayDestination = simd_make_float3(pointOnFarPlaneInObjectCoordinates.x/pointOnFarPlaneInObjectCoordinates.w,
                                                pointOnFarPlaneInObjectCoordinates.y/pointOnFarPlaneInObjectCoordinates.w,
                                                pointOnFarPlaneInObjectCoordinates.z/pointOnFarPlaneInObjectCoordinates.w);
  simd_float3 rayDirection = rayDestination - rayOrigin;
  
  simd_float4x4 objectToCamera = matrix_multiply(viewMatrix, modelMatrix);
  
  // Test intersections with triangles
  float bestHit = -1.0;
  for (std::vector<AzulObject>::iterator currentFile = parsedFiles.begin(); currentFile != parsedFiles.end(); ++currentFile) {
    if (currentFile->children.empty()) {
      float thisHit = hit(*currentFile, rayOrigin, rayDirection, objectToCamera);
      if (thisHit > bestHit) {
        bestHit = thisHit;
        bestHitFile = currentFile;
      }
    } else for (std::vector<AzulObject>::iterator currentObject = currentFile->children.begin(); currentObject != currentFile->children.end(); ++currentObject) {
      float thisHit = hit(*currentObject, rayOrigin, rayDirection, objectToCamera);
      if (thisHit > bestHit) {
        bestHit = thisHit;
        bestHitFile = currentFile;
        bestHitObject = currentObject;
      }
    }
  }
  
  return bestHit;
}

float DataManager::hit(const AzulObject &object, const simd_float3 &rayOrigin, const simd_float3 &rayDirection, const simd_float4x4 &objectToCamera) {
  float bestHit = -1.0;
  for (auto &child: object.children) {
    float thisHit = hit(child, rayOrigin, rayDirection, objectToCamera);
    if (thisHit > bestHit) bestHit = thisHit;
  }
  
  float epsilon = 0.000001;
  
  // Moller-Trumbore algorithm for triangle-ray intersection (non-culling)
  // u,v are the barycentric coordinates of the intersection point
  // t is the distance from rayOrigin to the intersection point
  for (auto const &triangle: object.triangles) {
    simd_float3 vertex[3];
    for (int point = 0; point < 3; ++point) {
    vertex[point] = simd_make_float3((triangle.points[point].coordinates[0]-midCoordinates[0])/maxRange,
                                     (triangle.points[point].coordinates[1]-midCoordinates[1])/maxRange,
                                     (triangle.points[point].coordinates[2]-midCoordinates[2])/maxRange);
    } simd_float3 edge1 = vertex[1] - vertex[0];
    simd_float3 edge2 = vertex[2] - vertex[0];
    simd_float3 pvec = simd_cross(rayDirection, edge2);
    float determinant = simd_dot(edge1, pvec);
    if (determinant > -epsilon && determinant < epsilon) continue; // if determinant is near zero  ray lies in plane of triangle
    float inverseDeterminant = 1.0 / determinant;
    simd_float3 tvec = rayOrigin - vertex[0]; // distance from vertex0 to rayOrigin
    float u = simd_dot(tvec, pvec) * inverseDeterminant;
    if (u < 0.0 || u > 1.0) continue;
    simd_float3 qvec = simd_cross(tvec, edge1);
    float v = simd_dot(rayDirection, qvec) * inverseDeterminant;
    if (v < 0.0 || u + v > 1.0) continue;
    float t = simd_dot(edge2, qvec) * inverseDeterminant;
    if (t > epsilon) {
      simd_float3 intersectionPointInObjectCoordinates = (vertex[0] * (1.0-u-v)) + (vertex[1] * u) + (vertex[2] * v);
      simd_float3 intersectionPointInCameraCoordinates = matrix_multiply(matrix_upper_left_3x3(objectToCamera), intersectionPointInObjectCoordinates);
      float distance = intersectionPointInCameraCoordinates.z;
//      std::cout << "Hit " << object.id << " at distance " << distance << std::endl;
      if (distance > bestHit) bestHit = distance;
    }
  }
  
  return bestHit;
}

simd_float3x3 DataManager::matrix_upper_left_3x3(const simd_float4x4 &matrix) {
  return simd_matrix(simd_make_float3(matrix.columns[0].x, matrix.columns[0].y, matrix.columns[0].z),
                     simd_make_float3(matrix.columns[1].x, matrix.columns[1].y, matrix.columns[1].z),
                     simd_make_float3(matrix.columns[2].x, matrix.columns[2].y, matrix.columns[2].z));
}

simd_float4x4 DataManager::matrix4x4_translation(const simd_float3 &shift) {
  return simd_matrix(simd_make_float4(1.0, 0.0, 0.0, 0.0),
                     simd_make_float4(0.0, 1.0, 0.0, 0.0),
                     simd_make_float4(0.0, 0.0, 1.0, 0.0),
                     simd_make_float4(shift.x, shift.y, shift.z, 1.0));
}

void DataManager::addAzulObjectAndItsChildrenToCentroidComputation(const AzulObject &object, CentroidComputation &centroidComputation) {
  for (auto const &child: object.children) addAzulObjectAndItsChildrenToCentroidComputation(child, centroidComputation);
  for (auto const &triangle: object.triangles) {
    for (auto const &point: triangle.points) {
      for (int coordinate = 0; coordinate < 3; ++coordinate) centroidComputation.sum[coordinate] += point.coordinates[coordinate];
      ++centroidComputation.points;
    }
  }
}

void DataManager::clearSearch() {
  for (auto &file: parsedFiles) setMatchesSearch(file, 'U');
}

void DataManager::setMatchesSearch(AzulObject &object, char matches) {
  for (auto &child: object.children) setMatchesSearch(child, matches);
  object.matchesSearch = matches;
}

bool DataManager::matchesSearch(AzulObject &object) {
  
  // Empty
  if (searchString.empty()) {
    object.matchesSearch = 'Y';
    return true;
  }
  
  // Already known
  if (object.matchesSearch == 'Y') return true;
  if (object.matchesSearch == 'N') return false;
  
  // Check here
  if (object.id.find(searchString) != std::string::npos ||
      object.type.find(searchString) != std::string::npos) {
    object.matchesSearch = 'Y';
    return true;
  } for (auto const &attribute: object.attributes) {
    if (attribute.first.find(searchString) != std::string::npos ||
        attribute.second.find(searchString) != std::string::npos) {
      object.matchesSearch = 'Y';
      return true;
    }
  }
  
  // Check children
  for (auto &child: object.children) {
    if (matchesSearch(child)) {
      object.matchesSearch = 'Y';
      return true;
    }
  }

  return false;
}

void DataManager::setMatchesTypeFilter(AzulObject &object, char matches) {
  for (auto &child: object.children) setMatchesTypeFilter(child, matches);
  object.matchesTypeFilter = matches;
}

bool DataManager::matchesTypeFilter(AzulObject &object) {

  // No filter
  if (objectTypeFilter.empty()) return true;

  // Already known
  if (object.matchesTypeFilter == 'Y') return true;
  if (object.matchesTypeFilter == 'N') return false;

  // Check here
  if (objectTypeFilter.count(object.type) > 0) {
    object.matchesTypeFilter = 'Y';
    return true;
  }

  // Check children
  for (auto &child: object.children) {
    if (matchesTypeFilter(child)) {
      object.matchesTypeFilter = 'Y';
      return true;
    }
  }

  object.matchesTypeFilter = 'N';
  return false;
}

bool DataManager::matchesDisplayFilters(AzulObject &object) {
  return (searchString.empty() || matchesSearch(object)) &&
         (objectTypeFilter.empty() || matchesTypeFilter(object)) &&
         (lodFilter.empty() || object.lodMatch == 'Y');
}

void DataManager::setObjectTypeFilter(const std::vector<std::string> &types) {
  for (auto &file: parsedFiles) setMatchesTypeFilter(file, 'U');
  objectTypeFilter.clear();
  for (auto const &type: types) objectTypeFilter.insert(type);
}

std::vector<std::pair<std::string, int>> DataManager::availableTypesWithCounts() {
  std::map<std::string, int> counts;
  std::function<void(const AzulObject &)> collect = [&](const AzulObject &object) {
    // Skip structural rows that carry no semantic type (file rows and LoD groupings)
    bool structural = object.type.empty() ||
                      object.type == "File" ||
                      object.type == "LoD" ||
                      (object.type.size() > 3 &&
                       object.type.substr(0, 3) == "lod" &&
                       isdigit(object.type[3]));
    if (!structural) ++counts[object.type];
    for (auto const &child: object.children) collect(child);
  };
  for (auto const &file: parsedFiles) collect(file);
  return std::vector<std::pair<std::string, int>>(counts.begin(), counts.end());
}

std::vector<std::string> DataManager::getAvailableLods() {
  std::set<std::string> lods;
  for (const auto &file : parsedFiles) {
    std::function<void(const AzulObject &)> collect = [&](const AzulObject &obj) {
      if (obj.type == "LoD" && !obj.id.empty()) {
        lods.insert(obj.id);
      } else if (obj.type.size() > 3 &&
                 obj.type.substr(0, 3) == "lod" &&
                 obj.type.size() > 3 && isdigit(obj.type[3])) {
        size_t end = 3;
        while (end < obj.type.size() && isdigit(obj.type[end])) ++end;
        lods.insert(obj.type.substr(3, end - 3));
      }
      for (const auto &child : obj.children) collect(child);
    };
    collect(file);
  }
  return std::vector<std::string>(lods.begin(), lods.end());
}

std::string DataManager::lodOfObject(const AzulObject &object) {
  if (object.type == "LoD" && !object.id.empty() && isdigit(object.id[0])) {
    return object.id;
  }
  if (object.type.size() > 3 &&
      object.type.substr(0, 3) == "lod" &&
      isdigit(object.type[3])) {
    size_t end = 3;
    while (end < object.type.size() && isdigit(object.type[end])) ++end;
    return object.type.substr(3, end - 3);
  }
  return "";
}

void DataManager::setLodMatchRecursive(AzulObject &object, char value) {
  object.lodMatch = value;
  for (auto &child : object.children) setLodMatchRecursive(child, value);
}

std::string DataManager::computeLodMatches(AzulObject &object) {
  std::string highestLod;
  
  for (auto &child: object.children) {
    std::string childHighestLod = computeLodMatches(child);
    if (!childHighestLod.empty()) {
      if (highestLod.empty() || std::stod(childHighestLod) > std::stod(highestLod)) {
        highestLod = childHighestLod;
      }
    }
  }
  
  if (lodFilter == "__highest__") {
    std::string directLod = lodOfObject(object);
    if (!directLod.empty()) {
      if (highestLod.empty() || std::stod(directLod) > std::stod(highestLod)) {
        highestLod = directLod;
      }
    }
    
    if (!highestLod.empty()) {
      for (auto &child : object.children) {
        std::string childLod = lodOfObject(child);
        if (!childLod.empty() && childLod != highestLod) {
          setLodMatchRecursive(child, 'N');
        }
      }
    }
    
    if (!directLod.empty()) {
      object.lodMatch = (directLod == highestLod) ? 'Y' : 'N';
    } else {
      object.lodMatch = 'N';
      for (auto &child: object.children) {
        if (child.lodMatch == 'Y') { object.lodMatch = 'Y'; break; }
      }
      // Keep non-LoD leaf geometry visible when filtering by highest LoD.
      // This covers datasets where thematic surfaces carry polygons but no explicit LoD tag.
      if (object.lodMatch != 'Y' &&
          highestLod.empty() &&
          (!object.polygons.empty() || !object.triangles.empty())) {
        object.lodMatch = 'Y';
      }
    }
  } else if (lodFilter.empty() || directlyMatchesLodFilter(object)) {
    object.lodMatch = 'Y';
  } else {
    object.lodMatch = 'N';
    for (auto &child: object.children) {
      if (child.lodMatch == 'Y') { object.lodMatch = 'Y'; break; }
    }
  }
  
  return highestLod;
}

void DataManager::setLodFilter(const char *lod) {
  lodFilter = std::string(lod);
  for (auto &file: parsedFiles) computeLodMatches(file);
}

bool DataManager::matchesLodFilter(const AzulObject &object) {
  if (lodFilter.empty()) return true;
  if (lodFilter == "__highest__") return true;
  
  if (object.type == "LoD" && object.id == lodFilter) return true;
  
  std::string prefix = "lod" + lodFilter;
  if (object.type.size() >= prefix.size() &&
      object.type.substr(0, prefix.size()) == prefix) return true;
  
  for (const auto &child : object.children) {
    if (matchesLodFilter(child)) return true;
  }
  
  return false;
}

bool DataManager::directlyMatchesLodFilter(const AzulObject &object) {
  if (lodFilter.empty()) return false;
  if (object.type == "LoD" && object.id == lodFilter) return true;
  std::string prefix = "lod" + lodFilter;
  if (object.type.size() >= prefix.size() &&
      object.type.substr(0, prefix.size()) == prefix) return true;
  return false;
}

bool DataManager::isExpandable(AzulObject &object) {
  if (object.children.empty()) return false;
  if (searchString.empty() && lodFilter.empty() && objectTypeFilter.empty()) return true;
  for (auto &child: object.children) {
    if (matchesDisplayFilters(child)) return true;
  }
  return false;
}

int DataManager::numberOfChildren(AzulObject &object) {
  if (searchString.empty() && lodFilter.empty() && objectTypeFilter.empty()) {
    return (int)object.children.size();
  }
  int matchingChildren = 0;
  for (auto &child: object.children) {
    if (matchesDisplayFilters(child)) ++matchingChildren;
  }
  return matchingChildren;
}

std::vector<AzulObject>::iterator DataManager::child(AzulObject &object, long index) {
  if (sortKey.empty()) {
    if (searchString.empty() && lodFilter.empty() && objectTypeFilter.empty()) {
      return object.children.begin()+index;
    }
    int matchingChildren = 0;
    for (std::vector<AzulObject>::iterator child = object.children.begin();
         child != object.children.end();
         ++child) {
      if (matchesDisplayFilters(*child)) {
        if (matchingChildren == index) return child;
        ++matchingChildren;
      }
    }
    return object.children.begin();
  }
  if (!sortOrdersCurrent) computeSortOrders();
  int matchingChildren = 0;
  for (long position: object.displayOrder) {
    std::vector<AzulObject>::iterator child = object.children.begin()+position;
    if (matchesDisplayFilters(*child)) {
      if (matchingChildren == index) return child;
      ++matchingChildren;
    }
  }
  return object.children.begin();
}

std::vector<AzulObject>::iterator DataManager::fileChild(long index) {
  if (sortKey.empty() ||
      index < 0 ||
      index >= static_cast<long>(parsedFiles.size())) {
    return parsedFiles.begin()+index;
  }
  if (!sortOrdersCurrent) computeSortOrders();
  return parsedFiles.begin()+fileDisplayOrder[index];
}

void DataManager::setSortOrder(const char *key, bool descending) {
  sortKey = key != nullptr ? std::string(key) : std::string();
  if (sortKey != "id" && sortKey != "type") sortKey.clear();
  sortDescending = descending;
  sortOrdersCurrent = false;
}

void DataManager::computeSortOrders() {
  fileDisplayOrder.resize(parsedFiles.size());
  for (long index = 0; index < static_cast<long>(parsedFiles.size()); ++index) fileDisplayOrder[index] = index;
  if (!sortKey.empty()) sortDisplayOrder(fileDisplayOrder, parsedFiles, sortKey, sortDescending);
  for (auto &file: parsedFiles) computeSortOrders(file);
  sortOrdersCurrent = true;
}

void DataManager::computeSortOrders(AzulObject &object) {
  if (object.children.empty()) {
    object.displayOrder.clear();
    return;
  }
  object.displayOrder.resize(object.children.size());
  for (long index = 0; index < static_cast<long>(object.children.size()); ++index) object.displayOrder[index] = index;
  if (!sortKey.empty()) sortDisplayOrder(object.displayOrder, object.children, sortKey, sortDescending);
  for (auto &child: object.children) computeSortOrders(child);
}
