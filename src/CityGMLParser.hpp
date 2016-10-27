//
//  CityGMLParser.hpp
//  Azul
//
//  Copyright © 2016 Ken Arroyo Ohori. All rights reserved.
//

#ifndef CityGMLParser_hpp
#define CityGMLParser_hpp

#include <iostream>
#include <sstream>
#include <list>
#include <vector>
#include <OpenGL/OpenGL.h>
#include <pugixml.hpp>

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
  enum Type: unsigned int {Building = 1, Road = 2, ReliefFeature = 3, WaterBody = 4, PlantCover = 5, GenericCityObject = 6, Bridge = 7};
  Type type;
  std::list<CityGMLPolygon> polygons, polygons2;
  std::vector<GLfloat> triangles, triangles2;
  std::vector<GLfloat> edges;
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
          points.back().coordinates[currentCoordinate] = std::stof(substring);
          currentCoordinate = (currentCoordinate+1)%3;
        }
      } while (iss);
      if (currentCoordinate != 0) {
        std::cout << "Wrong number of coordinates: not divisible by 3" << std::endl;
        points.pop_back();
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
  std::list<pugi::xml_node> polygons, polygons2;
  bool secondary = false;
  unsigned int depthToStop;
  virtual bool for_each(pugi::xml_node &node) {
    if (secondary && depth() <= depthToStop) {
      secondary = false;
    } if (strcmp(node.name(), "bldg:RoofSurface") == 0) {
      secondary = true;
      depthToStop = depth();
    } else if (strcmp(node.name(), "gml:Polygon") == 0 ||
               strcmp(node.name(), "gml:Triangle") == 0) {
      if (!secondary) {
        polygons.push_back(node);
      } else {
        polygons2.push_back(node);
      }
    } return true;
  }
};

struct ObjectsWalker: pugi::xml_tree_walker {
  std::list<pugi::xml_node> objects;
  virtual bool for_each(pugi::xml_node &node) {
    if (strcmp(node.name(), "bldg:Building") == 0 ||
        strcmp(node.name(), "tran:Road") == 0 ||
        strcmp(node.name(), "dem:ReliefFeature") == 0 ||
        strcmp(node.name(), "wtr:WaterBody") == 0 ||
        strcmp(node.name(), "veg:PlantCover") == 0 ||
        strcmp(node.name(), "gen:GenericCityObject") == 0 ||
        strcmp(node.name(), "brg:Bridge") == 0) {
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
  
  std::list<CityGMLObject>::const_iterator currentObject;
  
  CityGMLParser();
  void parse(const char *filePath);
  void clear();
  
  void parseObject(pugi::xml_node &node, CityGMLObject &object);
  void parsePolygon(pugi::xml_node &node, CityGMLPolygon &polygon);
  void parseRing(pugi::xml_node &node, CityGMLRing &ring);
  
  void centroidOf(CityGMLRing &ring, CityGMLPoint &centroid);
  void regenerateTrianglesFor(CityGMLObject &object);
  void regenerateEdgesFor(CityGMLObject &object);
  void regenerateGeometries();
};

#endif /* CityGMLParser_hpp */
