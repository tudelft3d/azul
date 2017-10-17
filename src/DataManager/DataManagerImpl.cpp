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

#include "DataManagerImpl.hpp"

void DataManagerImpl::printAzulObject(const AzulObject &object, unsigned int tabs) {
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

void DataManagerImpl::triangulateAzulObjectAndItsChildren(AzulObject &object) {
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
    
    // Triangle: no need to triangulate
    else if (polygon.exteriorRing.points.size() == 4 && polygon.interiorRings.size() == 0) {
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
      for (unsigned int currentPoint = 0; currentPoint < 3; ++currentPoint) {
        for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
          triangles.back().points[currentPoint].coordinates[currentCoordinate] = polygon.exteriorRing.points[currentPoint].coordinates[currentCoordinate];
          triangles.back().normals[currentPoint].components[currentCoordinate] = plane.orthogonal_vector().cartesian(currentCoordinate);
        }
      }
    }
    
    // Polygon
    else {
      
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
      double normal[] = {0.0, 0.0, 0.0};
      for (std::vector<AzulPoint>::const_iterator currentPointInPolygon = polygon.exteriorRing.points.begin();
           currentPointInPolygon != polygon.exteriorRing.points.end();
           ++currentPointInPolygon) {
        std::vector<AzulPoint>::const_iterator nextPointInPolygon = currentPointInPolygon;
        ++nextPointInPolygon;
        if (nextPointInPolygon == polygon.exteriorRing.points.end()) nextPointInPolygon = polygon.exteriorRing.points.begin();
        normal[0] += (currentPointInPolygon->coordinates[1]-nextPointInPolygon->coordinates[1]) * (currentPointInPolygon->coordinates[2]+nextPointInPolygon->coordinates[2]);
        normal[1] += (currentPointInPolygon->coordinates[2]-nextPointInPolygon->coordinates[2]) * (currentPointInPolygon->coordinates[0]+nextPointInPolygon->coordinates[0]);
        normal[2] += (currentPointInPolygon->coordinates[0]-nextPointInPolygon->coordinates[0]) * (currentPointInPolygon->coordinates[1]+nextPointInPolygon->coordinates[1]);
      } Kernel::Point_3 pointInPlane(polygon.exteriorRing.points[0].coordinates[0],
                                     polygon.exteriorRing.points[0].coordinates[1],
                                     polygon.exteriorRing.points[0].coordinates[2]);
      Kernel::Vector_3 normalVector(normal[0], normal[1], normal[2]);
      Kernel::Plane_3 bestPlane(pointInPlane, normalVector);
      
      // Find the best fitting plane (least squares)
//      std::list<Kernel::Point_3> pointsInPolygon;
//      for (auto const &point: polygon.exteriorRing.points) {
//        pointsInPolygon.push_back(Kernel::Point_3(point.coordinates[0], point.coordinates[1], point.coordinates[2]));
//      } for (auto const &ring: polygon.interiorRings) {
//        for (auto const &point: ring.points) {
//          pointsInPolygon.push_back(Kernel::Point_3(point.coordinates[0], point.coordinates[1], point.coordinates[2]));
//        }
//      } Kernel::Plane_3 bestPlane;
//      linear_least_squares_fitting_3(pointsInPolygon.begin(), pointsInPolygon.end(), bestPlane, CGAL::Dimension_tag<0>());
      
      //        std::cout << "\tBest: Plane_3(" << bestPlane << ")" << std::endl;
      
      // Triangulate the projection of the edges to the plane
      Triangulation triangulation;
      std::vector<AzulPoint>::const_iterator currentPoint = polygon.exteriorRing.points.begin();
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
        continue;
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
//            if (triangulation.is_constrained(Triangulation::Edge(toCheck.front(), neighbour))) CGAL_assertion(toCheck.front()->neighbor(neighbour)->info().second != toCheck.front()->info().second);
//            else CGAL_assertion(toCheck.front()->neighbor(neighbour)->info().second == toCheck.front()->info().second);
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
          triangles.push_back(AzulTriangle());
          for (unsigned int currentVertexIndex = 0; currentVertexIndex < 3; ++currentVertexIndex) {
            Kernel::Point_3 point3 = bestPlane.to_3d(currentFace->vertex(currentVertexIndex)->point());
            //          std::cout << "\t\tPoint_3(" << point3 << ")" << std::endl;
            for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
              triangles.back().points[currentVertexIndex].coordinates[currentCoordinate] = point3[currentCoordinate];
              triangles.back().normals[currentVertexIndex].components[currentCoordinate] = bestPlane.orthogonal_vector().cartesian(currentCoordinate);
            }
          }
        }
      }
    }
  }
  
  object.triangles = triangles;
}

void DataManagerImpl::generateEdgesForAzulObjectAndItsChildren(AzulObject &object) {
  for (auto &child: object.children) generateEdgesForAzulObjectAndItsChildren(child);
  
  std::vector<AzulEdge> edges;
  for (auto const &polygon: object.polygons) {
    if (polygon.exteriorRing.points.size() < 4) {
      std::cout << "Polygon with < 4 points! Skipping..." << std::endl;
      continue;
    } std::vector<AzulPoint>::const_iterator currentPoint = polygon.exteriorRing.points.begin();
    std::vector<AzulPoint>::const_iterator nextPoint = currentPoint;
    ++nextPoint;
    while (nextPoint != polygon.exteriorRing.points.end()) {
      edges.push_back(AzulEdge());
      for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
        edges.back().points[0].coordinates[currentCoordinate] = currentPoint->coordinates[currentCoordinate];
      } for (unsigned int currentCoordinate = 0; currentCoordinate < 3; ++currentCoordinate) {
        edges.back().points[1].coordinates[currentCoordinate] = nextPoint->coordinates[currentCoordinate];
      } ++currentPoint;
      ++nextPoint;
    }
  } object.edges = edges;
}

void DataManagerImpl::updateBoundsWithAzulObjectAndItsChildren(const AzulObject &object) {
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

void DataManagerImpl::clearPolygonsOfAzulObjectAndItsChildren(AzulObject &object) {
  for (auto &child: object.children) clearPolygonsOfAzulObjectAndItsChildren(child);
  object.polygons.clear();
}

void DataManagerImpl::putAzulObjectAndItsChildrenIntoTriangleBuffers(const AzulObject &object, const std::string &typeWithColour, const long maxBufferSize) {
  //    std::cout << "makeTriangleBuffersContainingAzulObjectAndItsChildren with type " << typeWithColour << std::endl;
  for (auto &child: object.children) {
    //      std::cout << "\tchild type " << child.type << std::endl;
    if (colourForType.count(child.type)) putAzulObjectAndItsChildrenIntoTriangleBuffers(child, child.type, maxBufferSize);
    else putAzulObjectAndItsChildrenIntoTriangleBuffers(child, typeWithColour, maxBufferSize);
  }
  
  if (object.triangles.empty()) return;
  std::list<TriangleBuffer>::iterator currentBuffer;
  
  // Make new buffer if necessary (selected)
  if (object.selected) {
//    std::cout << "AzulObject<" << &object << "> selected" << std::endl;
    if (lastTriangleBufferBySelection.count(true) == 0 ||
        (lastTriangleBufferBySelection[true]->triangles.size()+object.triangles.size()) * sizeof(float) > maxBufferSize) {
      TriangleBuffer newBuffer;
      newBuffer.colour[0] = std::get<0>(selectedTrianglesColour);
      newBuffer.colour[1] = std::get<1>(selectedTrianglesColour);
      newBuffer.colour[2] = std::get<2>(selectedTrianglesColour);
      newBuffer.colour[3] = std::get<3>(selectedTrianglesColour);
      triangleBuffers.push_front(newBuffer);
      lastTriangleBufferBySelection[true] = triangleBuffers.begin();
      currentBuffer = triangleBuffers.begin();
    } else {
      currentBuffer = lastTriangleBufferBySelection[true];
    }
  }
  
  // Make new buffer if necessary (not selected)
  else {
    if (lastTriangleBufferOfType.count(typeWithColour) == 0 ||
        (lastTriangleBufferOfType[typeWithColour]->triangles.size()+object.triangles.size())*sizeof(float) > maxBufferSize) {
      //      std::cout << "Making new buffer for " << typeWithColour << "..." << std::endl;
      TriangleBuffer newBuffer;
      newBuffer.type = typeWithColour;
      newBuffer.colour[0] = std::get<0>(colourForType[typeWithColour]);
      newBuffer.colour[1] = std::get<1>(colourForType[typeWithColour]);
      newBuffer.colour[2] = std::get<2>(colourForType[typeWithColour]);
      newBuffer.colour[3] = std::get<3>(colourForType[typeWithColour]);
      triangleBuffers.push_front(newBuffer);
      lastTriangleBufferOfType[typeWithColour] = triangleBuffers.begin();
      currentBuffer = triangleBuffers.begin();
    } else {
      currentBuffer = lastTriangleBufferOfType[typeWithColour];
    }
  }
  
  for (auto const &triangle: object.triangles) {
    //      std::cout << "Triangle" << std::endl;
    for (int pointIndex = 0; pointIndex < 3; ++pointIndex) {
      //        std::cout << "\tPoint[" << pointIndex << "](" << triangle.points[pointIndex].coordinates[0] << ", " << triangle.points[pointIndex].coordinates[1] << ", " << triangle.points[pointIndex].coordinates[2] << ")" << std::endl;
      //        std::cout << "\tNormal[" << pointIndex << "](" << triangle.normals[pointIndex].components[0] << ", " << triangle.normals[pointIndex].components[1] << ", " << triangle.normals[pointIndex].components[2] << ")" << std::endl;
      for (int coordinate = 0; coordinate < 3; ++coordinate) currentBuffer->triangles.push_back((triangle.points[pointIndex].coordinates[coordinate]-midCoordinates[coordinate])/maxRange);
      currentBuffer->triangles.push_back(0.0); // to match Metal float3 16 byte size
      for (int component = 0; component < 3; ++component) currentBuffer->triangles.push_back(triangle.normals[pointIndex].components[component]);
      currentBuffer->triangles.push_back(0.0); // to match Metal float3 16 byte size
    }
  }
}

void DataManagerImpl::putAzulObjectAndItsChildrenIntoEdgeBuffers(const AzulObject &object, const long maxBufferSize) {
  for (auto &child: object.children) putAzulObjectAndItsChildrenIntoEdgeBuffers(child, maxBufferSize);
  
  if (object.edges.empty()) return;
  std::list<EdgeBuffer>::iterator currentBuffer;
  
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
      currentBuffer->edges.push_back(0.0); // to match Metal float3 16 byte size
    }
  }
}

DataManagerImpl::DataManagerImpl() {
  for (int coordinate = 0; coordinate < 3; ++coordinate) {
    minCoordinates[coordinate] = std::numeric_limits<float>::max();
    maxCoordinates[coordinate] = std::numeric_limits<float>::lowest();
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
  selectedTrianglesColour = std::tuple<float, float, float, float>(1.0, 1.0, 0.0, 1.0);
  selectedEdgesColour = std::tuple<float, float, float, float>(1.0, 0.0, 0.0, 1.0);
}

void DataManagerImpl::parse(const char *filePath) {
  //    std::cout << "Parsing " << filePath << "..." << std::endl;
  parsedFiles.push_back(AzulObject());
  if (boost::algorithm::ends_with(filePath, ".gml") ||
      boost::algorithm::ends_with(filePath, ".xml")) {
    gmlParsingHelper.parse(filePath, parsedFiles.back());
  } else if (boost::algorithm::ends_with(filePath, ".json")) {
    jsonParsingHelper.parse(filePath, parsedFiles.back());
  } else if (boost::algorithm::ends_with(filePath, ".obj")) {
    objParsingHelper.parse(filePath, parsedFiles.back());
  } else if (boost::algorithm::ends_with(filePath, ".poly")) {
    polyParsingHelper.parse(filePath, parsedFiles.back());
  } else if (boost::algorithm::ends_with(filePath, ".off")) {
    offParsingHelper.parse(filePath, parsedFiles.back());
  } else {
    std::cout << "Unrecognised file type. Ignored." << std::endl;
  }
}

void DataManagerImpl::updateBoundsWithLastFile() {
  updateBoundsWithAzulObjectAndItsChildren(parsedFiles.back());
  float range[3];
  for (int coordinate = 0; coordinate < 3; ++coordinate) {
    midCoordinates[coordinate] = (minCoordinates[coordinate]+maxCoordinates[coordinate])/2.0;
    range[coordinate] = maxCoordinates[coordinate]-minCoordinates[coordinate];
  } maxRange = range[0];
  if (range[1] > maxRange) maxRange = range[1];
  if (range[2] > maxRange) maxRange = range[2];
  std::cout << "Bounds: min = (" << minCoordinates[0] << ", " << minCoordinates[1] << ", " << minCoordinates[2] << ") max = (" << maxCoordinates[0] << ", " << maxCoordinates[1] << ", " << maxCoordinates[2] << ")" << std::endl;
}

void DataManagerImpl::triangulateLastFile() {
  triangulateAzulObjectAndItsChildren(parsedFiles.back());
}

void DataManagerImpl::generateEdgesForLastFile() {
  generateEdgesForAzulObjectAndItsChildren(parsedFiles.back());
}

void DataManagerImpl::clearPolygonsOfLastFile() {
  clearPolygonsOfAzulObjectAndItsChildren(parsedFiles.back());
}

void DataManagerImpl::regenerateTriangleBuffers(long maxBufferSize) {
  std::string defaultType = "";
  triangleBuffers.clear();
  lastTriangleBufferOfType.clear();
  lastTriangleBufferBySelection.clear();
  
  for (auto &file: parsedFiles) putAzulObjectAndItsChildrenIntoTriangleBuffers(file, defaultType, maxBufferSize);
  std::cout << "Created " << triangleBuffers.size() << " triangle buffers" << std::endl;
}

void DataManagerImpl::regenerateEdgeBuffers(long maxBufferSize) {
  edgeBuffers.clear();
  lastEdgeBufferBySelection.clear();
  
  for (auto &file: parsedFiles)  putAzulObjectAndItsChildrenIntoEdgeBuffers(file, maxBufferSize);
  std::cout << "Created " << edgeBuffers.size() << " edge buffers" << std::endl;
}

void DataManagerImpl::clearHelpers() {
  gmlParsingHelper.clearDOM();
  jsonParsingHelper.clearDOM();
}

void DataManagerImpl::clear() {
  clearHelpers();
  parsedFiles.clear();
  triangleBuffers.clear();
  lastTriangleBufferOfType.clear();
  lastTriangleBufferBySelection.clear();
  edgeBuffers.clear();
  lastEdgeBufferBySelection.clear();
  
  for (int coordinate = 0; coordinate < 3; ++coordinate) {
    minCoordinates[coordinate] = std::numeric_limits<float>::max();
    maxCoordinates[coordinate] = std::numeric_limits<float>::lowest();
  }
}

void DataManagerImpl::printParsedFiles() {
  for (auto const &file: parsedFiles) printAzulObject(file, 0);
}

void DataManagerImpl::setSelection(AzulObject &object, bool selected) {
  for (auto &child: object.children) setSelection(child, selected);
  object.selected = selected;
}

float DataManagerImpl::click(const float currentX, const float currentY, const simd_float4x4 &modelMatrix, const simd_float4x4 &viewMatrix, const simd_float4x4 &projectionMatrix) {
  
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

float DataManagerImpl::hit(const AzulObject &object, const simd_float3 &rayOrigin, const simd_float3 &rayDirection, const simd_float4x4 &objectToCamera) {
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

simd_float3x3 DataManagerImpl::matrix_upper_left_3x3(const simd_float4x4 &matrix) {
  return simd_matrix(simd_make_float3(matrix.columns[0].x, matrix.columns[0].y, matrix.columns[0].z),
                     simd_make_float3(matrix.columns[1].x, matrix.columns[1].y, matrix.columns[1].z),
                     simd_make_float3(matrix.columns[2].x, matrix.columns[2].y, matrix.columns[2].z));
}

simd_float4x4 DataManagerImpl::matrix4x4_translation(const simd_float3 &shift) {
  return simd_matrix(simd_make_float4(1.0, 0.0, 0.0, 0.0),
                     simd_make_float4(0.0, 1.0, 0.0, 0.0),
                     simd_make_float4(0.0, 0.0, 1.0, 0.0),
                     simd_make_float4(shift.x, shift.y, shift.z, 1.0));
}

void DataManagerImpl::addAzulObjectAndItsChildrenToCentroidComputation(const AzulObject &object, CentroidComputation &centroidComputation) {
  for (auto const &child: object.children) addAzulObjectAndItsChildrenToCentroidComputation(child, centroidComputation);
  for (auto const &triangle: object.triangles) {
    for (auto const &point: triangle.points) {
      for (int coordinate = 0; coordinate < 3; ++coordinate) centroidComputation.sum[coordinate] += point.coordinates[coordinate];
      ++centroidComputation.points;
    }
  }
}

void DataManagerImpl::clearSearch() {
  for (auto &file: parsedFiles) setMatchesSearch(file, 'U');
}

void DataManagerImpl::setMatchesSearch(AzulObject &object, char matches) {
  for (auto &child: object.children) setMatchesSearch(child, matches);
  object.matchesSearch = matches;
}

bool DataManagerImpl::matchesSearch(AzulObject &object) {
  
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

bool DataManagerImpl::isExpandable(AzulObject &object) {
  if (searchString.empty()) {
    if (!object.children.empty()) return true;
    return false;
  } else {
    for (auto &child: object.children) {
      if (matchesSearch(child)) return true;
    } return false;
  }
}

int DataManagerImpl::numberOfChildren(AzulObject &object) {
  if (searchString.empty()) {
    return (int)object.children.size();
  } else {
    int matchingChildren = 0;
    for (auto &child: object.children) {
      if (matchesSearch(child)) ++matchingChildren;
    } return matchingChildren;
  }
}

std::vector<AzulObject>::iterator DataManagerImpl::child(AzulObject &object, long index) {
  if (searchString.empty()) {
    return object.children.begin()+index;
  } else {
    int matchingChildren = 0;
    for (std::vector<AzulObject>::iterator child = object.children.begin();
         child != object.children.end();
         ++child) {
      if (matchesSearch(*child)) {
        if (matchingChildren == index) return child;
        ++matchingChildren;
      }
    } return object.children.begin();
  }
}
