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

#ifndef CityGMLParser_hpp
#define CityGMLParser_hpp

#include <iostream>
#include <sstream>
#include <list>
#include <vector>
#include <map>
#include <limits>

#include <pugixml.hpp>

#include <CGAL/Exact_predicates_inexact_constructions_kernel.h>
#include <CGAL/Constrained_Delaunay_triangulation_2.h>
#include <CGAL/Triangulation_face_base_with_info_2.h>
#include <CGAL/linear_least_squares_fitting_3.h>

typedef CGAL::Exact_predicates_inexact_constructions_kernel Kernel;
typedef CGAL::Exact_predicates_tag Tag;
typedef CGAL::Triangulation_vertex_base_2<Kernel> VertexBase;
typedef CGAL::Constrained_triangulation_face_base_2<Kernel> FaceBase;
typedef CGAL::Triangulation_face_base_with_info_2<std::pair<bool, bool>, Kernel, FaceBase> FaceBaseWithInfo;
typedef CGAL::Triangulation_data_structure_2<VertexBase, FaceBaseWithInfo> TriangulationDataStructure;
typedef CGAL::Constrained_Delaunay_triangulation_2<Kernel, TriangulationDataStructure, Tag> Triangulation;

struct CityGMLPoint {
  float coordinates[3];
};

struct CityGMLRing {
  std::list<CityGMLPoint> points;
};

struct CityGMLPolygon {
  CityGMLRing exteriorRing;
  std::list<CityGMLRing> interiorRings;
};

struct CityGMLObject {
  std::string type;
  std::string id;
  std::map<std::string, std::string> attributes;
  std::map<std::string, std::list<CityGMLPolygon>> polygonsByType;
  std::map<std::string, std::vector<float>> trianglesByType;
  std::vector<float> edges;
};

struct PointsWalker: pugi::xml_tree_walker {
  std::list<CityGMLPoint> points;
  virtual bool for_each(pugi::xml_node &node) {
    if (strcmp(node.name(), "gml:pos") == 0 ||
        strcmp(node.name(), "gml:posList") == 0) {
      //      std::cout << node.name() << " " << node.child_value() << std::endl;
      std::string coordinates(node.child_value());
      std::istringstream iss(coordinates);
      unsigned int currentCoordinate = 0;
      do {
        std::string substring;
        iss >> substring;
        if (substring.length() > 0) {
          if (currentCoordinate == 0) points.push_back(CityGMLPoint());
          try {
            points.back().coordinates[currentCoordinate] = std::stof(substring);
          } catch (const std::invalid_argument& ia) {
            std::cout << "Invalid point: " << substring << ". Skipping..." << std::endl;
            points.clear();
            return true;
          } currentCoordinate = (currentCoordinate+1)%3;
        }
      } while (iss);
      if (currentCoordinate != 0) {
        std::cout << "Wrong number of coordinates: not divisible by 3" << std::endl;
        points.clear();
      } //std::cout << "Created " << points.size() << " points" << std::endl;
    } return true;
  }
};

struct RingsWalker: pugi::xml_tree_walker {
  pugi::xml_node exteriorRing;
  std::list<pugi::xml_node> interiorRings;
  virtual bool for_each(pugi::xml_node &node) {
    if (strcmp(node.name(), "gml:exterior") == 0) {
      exteriorRing = node;
    } else if (strcmp(node.name(), "gml:interior") == 0) {
      interiorRings.push_back(node);
    } return true;
  }
};

struct PolygonsWalker: pugi::xml_tree_walker {
  std::map<std::string, std::list<pugi::xml_node>> polygonsByType;
  std::string inDefinedType = "";  // "" = undefined
  unsigned int depthToStop;
  virtual bool for_each(pugi::xml_node &node) {
    const char *nodeType = node.name();
    const char *namespaceSeparator = strchr(nodeType, ':');
    if (namespaceSeparator != NULL) {
      nodeType = namespaceSeparator+1;
    }
    
    if (inDefinedType != "" && depth() <= depthToStop) {
      inDefinedType = "";
    } if (strcmp(nodeType, "Door") == 0 ||
          strcmp(nodeType, "GroundSurface") == 0 ||
          strcmp(nodeType, "RoofSurface") == 0 ||
          strcmp(nodeType, "Window") == 0) {
      inDefinedType = nodeType;
      depthToStop = depth();
    } else if (strcmp(nodeType, "Polygon") == 0 ||
               strcmp(nodeType, "Triangle") == 0) {
      polygonsByType[inDefinedType].push_back(node);
    } return true;
  }
};

struct ObjectsWalker: pugi::xml_tree_walker {
  std::list<pugi::xml_node> objects;
  virtual bool for_each(pugi::xml_node &node) {
    const char *nodeType = node.name();
    const char *namespaceSeparator = strchr(nodeType, ':');
    if (namespaceSeparator != NULL) {
      nodeType = namespaceSeparator+1;
    }
    
    if (strcmp(nodeType, "Bridge") == 0 ||
        strcmp(nodeType, "Building") == 0 ||
        strcmp(nodeType, "CityFurniture") == 0 ||
        strcmp(nodeType, "GenericCityObject") == 0 ||
        strcmp(nodeType, "LandUse") == 0 ||
        strcmp(nodeType, "PlantCover") == 0 ||
        strcmp(nodeType, "Railway") == 0 ||
        strcmp(nodeType, "ReliefFeature") == 0 ||
        strcmp(nodeType, "Road") == 0 ||
        strcmp(nodeType, "SolitaryVegetationObject") == 0 ||
        strcmp(nodeType, "Tunnel") == 0 ||
        strcmp(nodeType, "WaterBody") == 0) {
      objects.push_back(node);
    } return true;
  }
};

class CityGMLParser {
public:
  std::list<CityGMLObject> objects;
  
  bool firstRing;
  float minCoordinates[3];
  float maxCoordinates[3];
  
  std::set<std::string> attributesToPreserve;
  
  std::list<CityGMLObject>::const_iterator currentObject;
  std::map<std::string, std::vector<float>>::const_iterator currentTrianglesBuffer;
  std::map<std::string, std::string>::const_iterator currentAttribute;
  
  CityGMLParser();
  void parse(const char *filePath);
  void clear();
  
  void parseObject(pugi::xml_node &node, CityGMLObject &object);
  void parsePolygon(pugi::xml_node &node, CityGMLPolygon &polygon);
  void parseRing(pugi::xml_node &node, CityGMLRing &ring);
  
  void centroidOf(CityGMLRing &ring, CityGMLPoint &centroid);
  void addTrianglesFromTheConstrainedTriangulationOfPolygon(CityGMLPolygon &polygon, std::vector<float> &triangles);
  void regenerateTrianglesFor(CityGMLObject &object);
  void regenerateEdgesFor(CityGMLObject &object);
  void regenerateGeometries();
};

#endif /* CityGMLParser_hpp */
