//
//  CityGMLParser.cpp
//  Azul
//
//  Copyright © 2016 Ken Arroyo Ohori. All rights reserved.
//

#include "CityGMLParser.hpp"

CityGMLParser::CityGMLParser() {
  firstRing = true;
  std::cout.precision(std::numeric_limits<float>::max_digits10);
}

void CityGMLParser::parse(const char *filePath) {
  //  std::cout << "Parsing " << filePath << std::endl;
  
  pugi::xml_document doc;
  doc.load_file(filePath);
  
  // With single traversal
  ObjectsWalker objectsWalker;
  doc.traverse(objectsWalker);
  for (auto &object: objectsWalker.objects) {
    objects.push_back(CityGMLObject());
    parseObject(object, objects.back());
  }
  
  // Stats
  std::cout << "Parsed " << objects.size() << " objects" << std::endl;
  std::cout << "Bounds: min = (" << minCoordinates[0] << ", " << minCoordinates[1] << ", " << minCoordinates[2] << ") max = (" << maxCoordinates[0] << ", " << maxCoordinates[1] << ", " << maxCoordinates[2] << ")" << std::endl;
  
  std::cout << objects.size() << " objects" << std::endl;
  //  for (auto &object: objects) {
  //    std::cout << "\t" << object.polygons.size() << " polygons" << std::endl;
  //    for (auto &polygon: object.polygons) {
  //      std::cout << "\t\texterior ring and " << polygon.interiorRings.size() << " interior rings" << std::endl;
  //      std::cout << "\t\t\t" << polygon.exteriorRing.points.size() << " points" << std::endl;
  //      for (auto &ring: polygon.interiorRings) {
  //        std::cout << "\t\t\t" << ring.points.size() << " points" << std::endl;
  //      }
  //    } for (auto &polygon2: object.polygons2) {
  //      std::cout << "\t\tPOLYGON 2: exterior ring and " << polygon2.interiorRings.size() << " interior rings" << std::endl;
  //      std::cout << "\t\t\t" << polygon2.exteriorRing.points.size() << " points" << std::endl;
  //      for (auto &ring: polygon2.interiorRings) {
  //        std::cout << "\t\t\t" << ring.points.size() << " points" << std::endl;
  //      }
  //    }
  //  }
  
  // Regenerate geometries
  regenerateGeometries();
}

void CityGMLParser::clear() {
  objects.clear();
  firstRing = true;
}

void CityGMLParser::parseObject(pugi::xml_node &node, CityGMLObject &object) {
  //  std::cout << "Parsing object " << node.name() << std::endl;
  const char *nodeType = node.name();
  const char *namespaceSeparator = strchr(nodeType, ':');
  if (namespaceSeparator != NULL) {
    nodeType = namespaceSeparator+1;
  }
  
  if (strcmp(nodeType, "Building") == 0) {
    object.type = CityGMLObject::Type::Building;
  } else if (strcmp(nodeType, "Road") == 0) {
    object.type = CityGMLObject::Type::Road;
  } else if (strcmp(nodeType, "ReliefFeature") == 0) {
    object.type = CityGMLObject::Type::ReliefFeature;
  } else if (strcmp(nodeType, "WaterBody") == 0) {
    object.type = CityGMLObject::Type::WaterBody;
  } else if (strcmp(nodeType, "PlantCover") == 0) {
    object.type = CityGMLObject::Type::PlantCover;
  } else if (strcmp(nodeType, "GenericCityObject") == 0) {
    object.type = CityGMLObject::Type::GenericCityObject;
  } else if (strcmp(nodeType, "Bridge") == 0) {
    object.type = CityGMLObject::Type::Bridge;
  } else if (strcmp(nodeType, "LandUse") == 0) {
    object.type = CityGMLObject::Type::LandUse;
  }
  
  PolygonsWalker polygonsWalker;
  node.traverse(polygonsWalker);
  for (auto &polygon: polygonsWalker.polygons) {
    object.polygons.push_back(CityGMLPolygon());
    parsePolygon(polygon, object.polygons.back());
  } for (auto &polygon2: polygonsWalker.polygons2) {
    object.polygons2.push_back(CityGMLPolygon());
    parsePolygon(polygon2, object.polygons2.back());
  }
}

void CityGMLParser::parsePolygon(pugi::xml_node &node, CityGMLPolygon &polygon) {
  //  std::cout << "\tParsing polygon" << std::endl;
  RingsWalker ringsWalker;
  node.traverse(ringsWalker);
  parseRing(ringsWalker.exteriorRing, polygon.exteriorRing);
  for (auto &ring: ringsWalker.interiorRings) {
    polygon.interiorRings.push_back(CityGMLRing());
    parseRing(ring, polygon.interiorRings.back());
  }
}

void CityGMLParser::parseRing(pugi::xml_node &node, CityGMLRing &ring) {
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

void CityGMLParser::centroidOf(CityGMLRing &ring, CityGMLPoint &centroid) {
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

void CityGMLParser::addTrianglesFromTheBarycentricTriangulationOfPolygon(CityGMLPolygon &polygon, std::vector<GLfloat> &triangles) {
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
    std::list<CityGMLPoint>::const_iterator point1 = polygon.exteriorRing.points.begin();
    std::list<CityGMLPoint>::const_iterator point2 = point1;
    ++point2;
    std::list<CityGMLPoint>::const_iterator point3 = point2;
    ++point3;
    for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      triangles.push_back((point1->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
    } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      triangles.push_back((point2->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
    } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      triangles.push_back((point3->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
    }
  }
  
  // Polygon
  else {
    CityGMLPoint centroid;
    centroidOf(polygon.exteriorRing, centroid);
    std::list<CityGMLPoint>::const_iterator currentPoint = polygon.exteriorRing.points.begin();
    std::list<CityGMLPoint>::const_iterator nextPoint = currentPoint;
    ++nextPoint;
    while (nextPoint != polygon.exteriorRing.points.end()) {
      for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
        triangles.push_back((centroid.coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
      } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
        triangles.push_back((currentPoint->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
      } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
        triangles.push_back((nextPoint->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
      } ++currentPoint;
      ++nextPoint;
    }
  }
}

void CityGMLParser::addTrianglesFromTheConstrainedTriangulationOfPolygon(CityGMLPolygon &polygon, std::vector<GLfloat> &triangles) {
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
    std::list<CityGMLPoint>::const_iterator point1 = polygon.exteriorRing.points.begin();
    std::list<CityGMLPoint>::const_iterator point2 = point1;
    ++point2;
    std::list<CityGMLPoint>::const_iterator point3 = point2;
    ++point3;
    for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      triangles.push_back((point1->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
    } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      triangles.push_back((point2->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
    } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
      triangles.push_back((point3->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
    }
  }
  
  // Polygon
  else {
    
//    std::cout << "Triangulating polygon with " << polygon.exteriorRing.points.size() << " vertices and " << polygon.interiorRings.size() << " inner rings..." << std::endl;
    
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
    std::list<CityGMLPoint>::const_iterator currentPoint = polygon.exteriorRing.points.begin();
//    std::cout << "\tAdding Point_3(" << Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2]) << ") as Point_2(" << bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])) << ")" << std::endl;
    Triangulation::Vertex_handle currentVertex = triangulation.insert(bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])));
    ++currentPoint;
    Triangulation::Vertex_handle previousVertex;
    while (currentPoint != polygon.exteriorRing.points.end()) {
      previousVertex = currentVertex;
//      std::cout << "\tAdding Point_3(" << Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2]) << ") as Point_2(" << bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])) << ")" << std::endl;
      currentVertex = triangulation.insert(bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])));
      if (previousVertex != currentVertex) triangulation.insert_constraint(previousVertex, currentVertex);
      ++currentPoint;
    } for (auto const &ring: polygon.interiorRings) {
      if (ring.points.size() < 4) {
//        std::cout << "\tRing with < 4 points! Skipping..." << std::endl;
        continue;
      } currentPoint = ring.points.begin();
//      std::cout << "\tAdding Point_3(" << Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2]) << ") as Point_2(" << bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])) << ")" << std::endl;
      currentVertex = triangulation.insert(bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])));
      while (currentPoint != ring.points.end()) {
        previousVertex = currentVertex;
//        std::cout << "\tAdding Point_3(" << Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2]) << ") as Point_2(" << bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])) << ")" << std::endl;
        currentVertex = triangulation.insert(bestPlane.to_2d(Kernel::Point_3(currentPoint->coordinates[0], currentPoint->coordinates[1], currentPoint->coordinates[2])));
        if (previousVertex != currentVertex) triangulation.insert_constraint(previousVertex, currentVertex);
        ++currentPoint;
      }
    }
    
    // Label the triangles to find out interior/exterior
//    std::cout << "\tTriangulation has " << triangulation.number_of_faces() << " faces." << std::endl;
    if (triangulation.number_of_faces() == 0) {
//      std::cout << "Degenerate face. Skipping..." << std::endl;
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
          if (triangulation.is_constrained(Triangulation::Edge(toCheck.front(), neighbour))) CGAL_assertion(toCheck.front()->neighbor(neighbour)->info().second != toCheck.front()->info().second);
          else CGAL_assertion(toCheck.front()->neighbor(neighbour)->info().second == toCheck.front()->info().second);
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
          triangles.push_back((point3.x()-midCoordinates[0])/maxRange);
          triangles.push_back((point3.y()-midCoordinates[1])/maxRange);
          triangles.push_back((point3.z()-midCoordinates[2])/maxRange);
        }
      }
    }
  }
  
}

void CityGMLParser::regenerateTrianglesFor(CityGMLObject &object) {
  object.triangles.clear();
  object.triangles2.clear();
  
  float range[3];
  for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
    range[currentCoordinate] = maxCoordinates[currentCoordinate]-minCoordinates[currentCoordinate];
    midCoordinates[currentCoordinate] = minCoordinates[currentCoordinate]+range[currentCoordinate]/2.0;
  }

  maxRange = range[0];
  if (range[1] > maxRange) maxRange = range[1];
  if (range[2] > maxRange) maxRange = range[2];
  
  for (auto &polygon: object.polygons) {
//    addTrianglesFromTheBarycentricTriangulationOfPolygon(polygon, object.triangles);
    addTrianglesFromTheConstrainedTriangulationOfPolygon(polygon, object.triangles);
  } for (auto &polygon2: object.polygons2) {
//    addTrianglesFromTheBarycentricTriangulationOfPolygon(polygon2, object.triangles2);
    addTrianglesFromTheConstrainedTriangulationOfPolygon(polygon2, object.triangles2);
  }
}

void CityGMLParser::regenerateEdgesFor(CityGMLObject &object) {
  object.edges.clear();
  
  float range[3];
  for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
    range[currentCoordinate] = maxCoordinates[currentCoordinate]-minCoordinates[currentCoordinate];
    midCoordinates[currentCoordinate] = minCoordinates[currentCoordinate]+range[currentCoordinate]/2.0;
  }
  
  maxRange = range[0];
  if (range[1] > maxRange) maxRange = range[1];
  if (range[2] > maxRange) maxRange = range[2];
  
  for (auto const &polygon: object.polygons) {
    if (polygon.exteriorRing.points.size() < 4) {
      std::cout << "Polygon with < 4 points! Skipping..." << std::endl;
      continue;
    } std::list<CityGMLPoint>::const_iterator currentPoint = polygon.exteriorRing.points.begin();
    std::list<CityGMLPoint>::const_iterator nextPoint = currentPoint;
    ++nextPoint;
    while (nextPoint != polygon.exteriorRing.points.end()) {
      for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
        object.edges.push_back((currentPoint->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
      } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
        object.edges.push_back((nextPoint->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
      } ++currentPoint;
      ++nextPoint;
    }
  } for (auto const &polygon2: object.polygons2) {
    if (polygon2.exteriorRing.points.size() < 4) {
      std::cout << "Polygon with < 4 points! Skipping..." << std::endl;
      continue;
    } std::list<CityGMLPoint>::const_iterator currentPoint = polygon2.exteriorRing.points.begin();
    std::list<CityGMLPoint>::const_iterator nextPoint = currentPoint;
    ++nextPoint;
    while (nextPoint != polygon2.exteriorRing.points.end()) {
      for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
        object.edges.push_back((currentPoint->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
      } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
        object.edges.push_back((nextPoint->coordinates[currentCoordinate]-midCoordinates[currentCoordinate])/maxRange);
      } ++currentPoint;
      ++nextPoint;
    }
  }
}

void CityGMLParser::regenerateGeometries() {
  for (auto &object: objects) {
    regenerateTrianglesFor(object);
    regenerateEdgesFor(object);
  }
}
