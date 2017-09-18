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

#include "Parser.hpp"

Parser::Parser() {
  firstRing = true;
  std::cout.precision(std::numeric_limits<float>::max_digits10);
  attributesToPreserve.insert("class");
  attributesToPreserve.insert("function");
  attributesToPreserve.insert("usage");
  attributesToPreserve.insert("yearOfConstruction");
  attributesToPreserve.insert("yearOfDemolition");
  attributesToPreserve.insert("roofType");
  attributesToPreserve.insert("measuredHeight");
  attributesToPreserve.insert("storeysAboveGround");
  attributesToPreserve.insert("storeysBelowGround");
  attributesToPreserve.insert("storeyHeightsAboveGround");
  attributesToPreserve.insert("storeyHeightsBelowGround");
  attributesToPreserve.insert("isMovable");
  attributesToPreserve.insert("averageHeight");
  attributesToPreserve.insert("trunkDiameter");
  attributesToPreserve.insert("crownDiameter");
  attributesToPreserve.insert("species");
  attributesToPreserve.insert("height");
  attributesToPreserve.insert("name");
}

void Parser::parseCityGML(const char *filePath) {
  //  std::cout << "Parsing " << filePath << std::endl;
  
  pugi::xml_document doc;
  doc.load_file(filePath);
  
  std::cout << "Loaded CityGML file" << std::endl;
  
  // With single traversal
  ObjectsWalker objectsWalker;
  doc.traverse(objectsWalker);
  for (auto &object: objectsWalker.objects) {
    objects.push_back(ParsedObject());
    parseCityGMLObject(object, objects.back());
  }
  
  // Stats
  std::cout << "Parsed " << objects.size() << " objects" << std::endl;
  std::cout << "Bounds: min = (" << minCoordinates[0] << ", " << minCoordinates[1] << ", " << minCoordinates[2] << ") max = (" << maxCoordinates[0] << ", " << maxCoordinates[1] << ", " << maxCoordinates[2] << ")" << std::endl;
  
  std::cout << objects.size() << " objects" << std::endl;
  
  // Regenerate geometries
  regenerateGeometries();
}

void Parser::parseCityJSONObject(nlohmann::json::const_iterator &jsonObject, ParsedObject &object, std::vector<std::vector<double>> &vertices) {
  
  object.id = jsonObject.key();
//  std::cout << "ID: " << object.id << std::endl;
  object.type = jsonObject.value()["type"];
//  std::cout << "Type: " << object.type << std::endl;

  for (auto const &geometry: jsonObject.value()["geometry"]) {
    std::cout << "Geometry: " << geometry.dump(2) << std::endl;
    
    if (geometry["type"] == "MultiSurface" || geometry["type"] == "CompositeSurface") {
//        std::cout << "Surfaces: " << geometry["boundaries"].dump() << std::endl;
      for (unsigned int surfaceIndex = 0; surfaceIndex < geometry["boundaries"].size(); ++surfaceIndex) {
//          std::cout << "Surface: " << geometry["boundaries"][surfaceIndex].dump() << std::endl;
        std::vector<std::vector<std::size_t>> surface = geometry["boundaries"][surfaceIndex];
        std::string surfaceType;
        if (geometry.count("semantics")) {
          auto const &surfaceSemantics = geometry["semantics"][surfaceIndex];
//          std::cout << "Surface semantics: " << surfaceSemantics.dump() << std::endl;
          surfaceType = surfaceSemantics["type"];
//          std::cout << "Surface type: " << surfaceType << std::endl;
        } object.polygonsByType[surfaceType].push_back(ParsedPolygon());
        parseCityJSONPolygon(surface, object.polygonsByType[surfaceType].back(), vertices);
      }
    }
    
    else if (geometry["type"] == "Solid") {
//      std::cout << "Shells: " << geometry["boundaries"].dump() << std::endl;
      for (unsigned int shellIndex = 0; shellIndex < geometry["boundaries"].size(); ++shellIndex) {
//        std::cout << "Shell: " << geometry["boundaries"][shellIndex].dump() << std::endl;
        for (unsigned int surfaceIndex = 0; surfaceIndex < geometry["boundaries"][shellIndex].size(); ++surfaceIndex) {
//          std::cout << "Surface: " << geometry["boundaries"][shellIndex][surfaceIndex].dump() << std::endl;
          std::vector<std::vector<std::size_t>> surface = geometry["boundaries"][shellIndex][surfaceIndex];
          std::string surfaceType;
          if (geometry.count("semantics")) {
            auto const &surfaceSemantics = geometry["semantics"][shellIndex][surfaceIndex];
//            std::cout << "Surface semantics: " << surfaceSemantics.dump() << std::endl;
            surfaceType = surfaceSemantics["type"];
//            std::cout << "Surface type: " << surfaceType << std::endl;
          } object.polygonsByType[surfaceType].push_back(ParsedPolygon());
          parseCityJSONPolygon(surface, object.polygonsByType[surfaceType].back(), vertices);
        }
      }
    }
    
    else if (geometry["type"] == "MultiSolid" || geometry["type"] == "CompositeSolid") {
      for (unsigned int solidIndex = 0; solidIndex < geometry["boundaries"].size(); ++solidIndex) {
        for (unsigned int shellIndex = 0; shellIndex < geometry["boundaries"][solidIndex].size(); ++shellIndex) {
          for (unsigned int surfaceIndex = 0; surfaceIndex < geometry["boundaries"][solidIndex][shellIndex].size(); ++surfaceIndex) {
            std::vector<std::vector<std::size_t>> surface = geometry["boundaries"][solidIndex][shellIndex][surfaceIndex];
            std::string surfaceType;
            if (geometry.count("semantics")) {
              auto const &surfaceSemantics = geometry["semantics"][solidIndex][shellIndex][surfaceIndex];
              surfaceType = surfaceSemantics["type"];
            } object.polygonsByType[surfaceType].push_back(ParsedPolygon());
            parseCityJSONPolygon(surface, object.polygonsByType[surfaceType].back(), vertices);
          }
        }
      }
    }
    
    else {
      std::cout << "Unsupported geometry: " << geometry["type"] << std::endl;
    }
  }
}

void Parser::parseCityJSONPolygon(const std::vector<std::vector<std::size_t>> &jsonPolygon, ParsedPolygon &polygon, std::vector<std::vector<double>> &vertices) {
  bool outer = true;
  for (auto const &ring: jsonPolygon) {
    if (outer) {
      parseCityJSONRing(ring, polygon.exteriorRing, vertices);
      outer = false;
    } else {
      polygon.interiorRings.push_back(ParsedRing());
      parseCityJSONRing(ring, polygon.interiorRings.back(), vertices);
    }
  }
}

void Parser::parseCityJSONRing(const std::vector<std::size_t> &jsonRing, ParsedRing &ring, std::vector<std::vector<double>> &vertices) {
  for (auto const &point: jsonRing) {
    ring.points.push_back(ParsedPoint());
    for (int dimension = 0; dimension < 3; ++dimension) {
      ring.points.back().coordinates[dimension] = vertices[point][dimension];
      if (firstRing) {
        minCoordinates[dimension] = vertices[point][dimension];
        maxCoordinates[dimension] = vertices[point][dimension];
//        std::cout << "Start bounds: min = (" << minCoordinates[0] << ", " << minCoordinates[1] << ", " << minCoordinates[2] << ") max = (" << maxCoordinates[0] << ", " << maxCoordinates[1] << ", " << maxCoordinates[2] << ")" << std::endl;
      } else {
        if (vertices[point][dimension] < minCoordinates[dimension]) minCoordinates[dimension] = vertices[point][dimension];
        else if (vertices[point][dimension] > maxCoordinates[dimension]) maxCoordinates[dimension] = vertices[point][dimension];
      }
    } firstRing = false;
  } ring.points.push_back(ring.points.front());
}

void Parser::parseCityJSON(const char *filePath) {
  
  std::ifstream inputStream(filePath);
  nlohmann::json json;
  inputStream >> json;
  
  std::vector<std::vector<double>> vertices = json["vertices"];
  
  for (nlohmann::json::const_iterator cityObject = json["CityObjects"].begin();
       cityObject != json["CityObjects"].end();
       ++cityObject) {
    objects.push_back(ParsedObject());
    parseCityJSONObject(cityObject, objects.back(), vertices);
  }
  
  std::cout << "Loaded CityJSON file" << std::endl;
  
  // Stats
  std::cout << "Parsed " << objects.size() << " objects" << std::endl;
  std::cout << "Bounds: min = (" << minCoordinates[0] << ", " << minCoordinates[1] << ", " << minCoordinates[2] << ") max = (" << maxCoordinates[0] << ", " << maxCoordinates[1] << ", " << maxCoordinates[2] << ")" << std::endl;
  
  std::cout << objects.size() << " objects" << std::endl;
  
  // Regenerate geometries
  regenerateGeometries();
  
  // See what's in here
//  for (auto const &object: objects) {
//    std::cout << "Object " << object.id << std::endl;
//    for (auto const &polygonsOfType: object.polygonsByType) {
//      std::cout << "\tPolygons of type " << polygonsOfType.first << std::endl;
//      for (auto const &polygon: polygonsOfType.second) {
//        std::cout << "\t\tPolygon" << std::endl << "\t\t\tExterior ring" << std::endl;
//        for (auto const &point: polygon.exteriorRing.points) {
//          std::cout << "\t\t\t\t";
//          for (unsigned int dimension = 0; dimension < 3; ++dimension) std::cout << point.coordinates[dimension] << " ";
//          std::cout << std::endl;
//        } for (auto const &ring: polygon.interiorRings) {
//          std::cout << "\t\t\tInterior ring" << std::endl;
//          for (auto const &point: ring.points) {
//            std::cout << "\t\t\t\t";
//            for (unsigned int dimension = 0; dimension < 3; ++dimension) std::cout << point.coordinates[dimension] << " ";
//            std::cout << std::endl;
//          }
//        }
//      }
//    }
//  }
}

void Parser::clear() {
  objects.clear();
  firstRing = true;
}

void Parser::parseCityGMLObject(pugi::xml_node &node, ParsedObject &object) {
//  std::cout << "Parsing object " << node.name() << " with id " << node.attribute("gml:id").value() << std::endl;
  const char *nodeType = node.name();
  const char *namespaceSeparator = strchr(nodeType, ':');
  if (namespaceSeparator != NULL) {
    nodeType = namespaceSeparator+1;
  }
  
  object.id = node.attribute("gml:id").value();
  object.type = nodeType;
  
  for (auto const &child: node.children()) {
    const char *childType = child.name();
    namespaceSeparator = strchr(childType, ':');
    if (namespaceSeparator != NULL) {
      childType = namespaceSeparator+1;
    } if (attributesToPreserve.count(childType)) {
//      std::cout << childType << ": " << child.child_value() << std::endl;
      object.attributes[childType] = child.child_value();
    }
  }
  
  PolygonsWalker polygonsWalker;
  node.traverse(polygonsWalker);
  for (auto &polygonsByType: polygonsWalker.polygonsByType) {
    for (auto &polygon: polygonsByType.second) {
      object.polygonsByType[polygonsByType.first].push_back(ParsedPolygon());
      parseCityGMLPolygon(polygon, object.polygonsByType[polygonsByType.first].back());
    }
  }
}

void Parser::parseCityGMLPolygon(pugi::xml_node &node, ParsedPolygon &polygon) {
  //  std::cout << "\tParsing polygon" << std::endl;
  RingsWalker ringsWalker;
  node.traverse(ringsWalker);
  parseCityGMLRing(ringsWalker.exteriorRing, polygon.exteriorRing);
  for (auto &ring: ringsWalker.interiorRings) {
    polygon.interiorRings.push_back(ParsedRing());
    parseCityGMLRing(ring, polygon.interiorRings.back());
  }
}

void Parser::parseCityGMLRing(pugi::xml_node &node, ParsedRing &ring) {
  //  std::cout << "\t\tParsing ring" << std::endl;
  PointsWalker pointsWalker;
  node.traverse(pointsWalker);
  ring.points.splice(ring.points.begin(), pointsWalker.points);
  if (firstRing) {
    for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      minCoordinates[currentCoordinate] = ring.points.front().coordinates[currentCoordinate];
      maxCoordinates[currentCoordinate] = ring.points.front().coordinates[currentCoordinate];
    } firstRing = false;
  } for (auto const &point: ring.points) {
    for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      if (point.coordinates[currentCoordinate] < minCoordinates[currentCoordinate]) minCoordinates[currentCoordinate] = point.coordinates[currentCoordinate];
      else if (point.coordinates[currentCoordinate] > maxCoordinates[currentCoordinate]) maxCoordinates[currentCoordinate] = point.coordinates[currentCoordinate];
    }
  }
}

void Parser::centroidOf(ParsedRing &ring, ParsedPoint &centroid) {
  for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
    centroid.coordinates[currentCoordinate] = 0.0;
  } for (auto const &point: ring.points) {
    for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      centroid.coordinates[currentCoordinate] += point.coordinates[currentCoordinate];
    }
  } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
    centroid.coordinates[currentCoordinate] /= ring.points.size();
  }
}

void Parser::addTrianglesFromTheConstrainedTriangulationOfPolygon(ParsedPolygon &polygon, std::vector<float> &triangles) {
  // Check if last == first
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
  
  // Degenerate
  if (polygon.exteriorRing.points.size() < 4) {
    std::cout << "Polygon with < 4 points! Skipping..." << std::endl;
    return;
  }
  
  // Triangle
  else if (polygon.exteriorRing.points.size() == 4 && polygon.interiorRings.size() == 0) {
    std::list<ParsedPoint>::const_iterator point1 = polygon.exteriorRing.points.begin();
    std::list<ParsedPoint>::const_iterator point2 = point1;
    ++point2;
    std::list<ParsedPoint>::const_iterator point3 = point2;
    ++point3;
    Kernel::Plane_3 plane(Kernel::Point_3(point1->coordinates[0], point1->coordinates[1], point1->coordinates[2]),
                          Kernel::Point_3(point2->coordinates[0], point2->coordinates[1], point2->coordinates[2]),
                          Kernel::Point_3(point3->coordinates[0], point3->coordinates[1], point3->coordinates[2]));
    for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      triangles.push_back(point1->coordinates[currentCoordinate]);
    } triangles.push_back(plane.orthogonal_vector().x());
    triangles.push_back(plane.orthogonal_vector().y());
    triangles.push_back(plane.orthogonal_vector().z());
    for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      triangles.push_back(point2->coordinates[currentCoordinate]);
    } triangles.push_back(plane.orthogonal_vector().x());
    triangles.push_back(plane.orthogonal_vector().y());
    triangles.push_back(plane.orthogonal_vector().z());
    for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      triangles.push_back(point3->coordinates[currentCoordinate]);
    } triangles.push_back(plane.orthogonal_vector().x());
    triangles.push_back(plane.orthogonal_vector().y());
    triangles.push_back(plane.orthogonal_vector().z());
  }
  
  // Polygon
  else {
    
    // Find the best fitting plane
    std::list<Kernel::Point_3> pointsInPolygon;
    for (auto const &point: polygon.exteriorRing.points) {
      pointsInPolygon.push_back(Kernel::Point_3(point.coordinates[0], point.coordinates[1], point.coordinates[2]));
    } for (auto const &ring: polygon.interiorRings) {
      for (auto const &point: ring.points) {
        pointsInPolygon.push_back(Kernel::Point_3(point.coordinates[0], point.coordinates[1], point.coordinates[2]));
      }
    } Kernel::Plane_3 bestPlane;
    linear_least_squares_fitting_3(pointsInPolygon.begin(), pointsInPolygon.end(), bestPlane, CGAL::Dimension_tag<0>());
//    std::cout << "\tBest: Plane_3(" << bestPlane << ")" << std::endl;
    
    // Triangulate the projection of the edges to the plane
    Triangulation triangulation;
    std::list<ParsedPoint>::const_iterator currentPoint = polygon.exteriorRing.points.begin();
    Triangulation::Vertex_handle currentVertex = triangulation.insert(bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])));
    ++currentPoint;
    Triangulation::Vertex_handle previousVertex;
    while (currentPoint != polygon.exteriorRing.points.end()) {
      previousVertex = currentVertex;
      currentVertex = triangulation.insert(bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])));
      if (previousVertex != currentVertex) triangulation.insert_constraint(previousVertex, currentVertex);
      ++currentPoint;
    } for (auto const &ring: polygon.interiorRings) {
      if (ring.points.size() < 4) {
        std::cout << "\tRing with < 4 points! Skipping..." << std::endl;
        continue;
      } currentPoint = ring.points.begin();
      currentVertex = triangulation.insert(bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])));
      while (currentPoint != ring.points.end()) {
        previousVertex = currentVertex;
        currentVertex = triangulation.insert(bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])));
        if (previousVertex != currentVertex) triangulation.insert_constraint(previousVertex, currentVertex);
        ++currentPoint;
      }
    }
    
    // Label the triangles to find out interior/exterior
    if (triangulation.number_of_faces() == 0) {
//      std::cout << "Degenerate face produced no triangles. Skipping..." << std::endl;
      return;
    } for (Triangulation::All_faces_iterator currentFace = triangulation.all_faces_begin(); currentFace != triangulation.all_faces_end(); ++currentFace) {
      currentFace->info() = std::pair<bool, bool>(false, false);
    } std::list<Triangulation::Face_handle> toCheck;
    triangulation.infinite_face()->info() = std::pair<bool, bool>(true, false);
    CGAL_assertion(triangulation.infinite_face()->info().first == true);
    CGAL_assertion(triangulation.infinite_face()->info().second == false);
    toCheck.push_back(triangulation.infinite_face());
    while (!toCheck.empty()) {
      CGAL_assertion(toCheck.front()->info().first);
      for (int neighbour = 0; neighbour < 3; ++neighbour) {
        if (toCheck.front()->neighbor(neighbour)->info().first) {
          // Note: validation code. But here we assume that some triangulations will be invalid anyway.
//          if (triangulation.is_constrained(Triangulation::Edge(toCheck.front(), neighbour))) CGAL_assertion(toCheck.front()->neighbor(neighbour)->info().second != toCheck.front()->info().second);
//          else CGAL_assertion(toCheck.front()->neighbor(neighbour)->info().second == toCheck.front()->info().second);
        } else {
          toCheck.front()->neighbor(neighbour)->info().first = true;
          CGAL_assertion(toCheck.front()->neighbor(neighbour)->info().first == true);
          if (triangulation.is_constrained(Triangulation::Edge(toCheck.front(), neighbour))) {
            toCheck.front()->neighbor(neighbour)->info().second = !toCheck.front()->info().second;
            toCheck.push_back(toCheck.front()->neighbor(neighbour));
          } else {
            toCheck.front()->neighbor(neighbour)->info().second = toCheck.front()->info().second;
            toCheck.push_back(toCheck.front()->neighbor(neighbour));
          }
        }
      } toCheck.pop_front();
    }
    
    // Project the triangles back to 3D and add
    for (Triangulation::Finite_faces_iterator currentFace = triangulation.finite_faces_begin(); currentFace != triangulation.finite_faces_end(); ++currentFace) {
      if (currentFace->info().second) {
//        std::cout << "\tCreated triangle with points:" << std::endl;
        for (unsigned int currentVertexIndex = 0; currentVertexIndex < 3; ++currentVertexIndex) {
          Kernel::Point_3 point3 = bestPlane.to_3d(currentFace->vertex(currentVertexIndex)->point());
//          std::cout << "\t\tPoint_3(" << point3 << ")" << std::endl;
          triangles.push_back(point3.x());
          triangles.push_back(point3.y());
          triangles.push_back(point3.z());
          triangles.push_back(bestPlane.orthogonal_vector().x());
          triangles.push_back(bestPlane.orthogonal_vector().y());
          triangles.push_back(bestPlane.orthogonal_vector().z());
        }
      }
    }
  }
  
}

void Parser::regenerateTrianglesFor(ParsedObject &object) {
  object.trianglesByType.clear();
  
  for (auto &polygonsByType: object.polygonsByType) {
    for (auto &polygon: polygonsByType.second) {
      addTrianglesFromTheConstrainedTriangulationOfPolygon(polygon, object.trianglesByType[polygonsByType.first]);
    }
  }
}

void Parser::regenerateEdgesFor(ParsedObject &object) {
  object.edges.clear();
  
  for (auto const &polygonsByType: object.polygonsByType) {
    for (auto const &polygon: polygonsByType.second) {
      if (polygon.exteriorRing.points.size() < 4) {
        std::cout << "Polygon with < 4 points! Skipping..." << std::endl;
        continue;
      } std::list<ParsedPoint>::const_iterator currentPoint = polygon.exteriorRing.points.begin();
      std::list<ParsedPoint>::const_iterator nextPoint = currentPoint;
      ++nextPoint;
      while (nextPoint != polygon.exteriorRing.points.end()) {
        for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
          object.edges.push_back(currentPoint->coordinates[currentCoordinate]);
        } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
          object.edges.push_back(nextPoint->coordinates[currentCoordinate]);
        } ++currentPoint;
        ++nextPoint;
      }
    }
  }
}

void Parser::regenerateGeometries() {
  for (auto &object: objects) {
    regenerateTrianglesFor(object);
    regenerateEdgesFor(object);
  }
}
