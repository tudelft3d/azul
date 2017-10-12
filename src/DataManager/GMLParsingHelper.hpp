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

#ifndef GMLParsingHelper_hpp
#define GMLParsingHelper_hpp

#include "DataModel.hpp"

#include <boost/spirit/home/x3.hpp>
#include <pugixml-1.8/pugixml.hpp>

class GMLParsingHelper {
  pugi::xml_document doc;
  
  void parseRing(const pugi::xml_node &node, AzulRing &parsedRing) {
    for (auto const &child: node.first_child().children()) {
      if (strcmp(child.name(), "gml:pos") == 0 ||
          strcmp(child.name(), "gml:posList") == 0) {
        
        const char *coordinates = child.child_value();
        while (isspace(*coordinates)) ++coordinates;
        unsigned int currentCoordinate = 0;
        while (strlen(coordinates) > 0) {
          if (currentCoordinate == 0) parsedRing.points.push_back(AzulPoint());
          const char *last = coordinates;
//          std::cout << "\"" << coordinates << "\"" << std::endl;
          while (!isspace(*last) && *last != '\0') ++last;
          if (!boost::spirit::x3::parse(coordinates, last, boost::spirit::x3::float_, parsedRing.points.back().coordinates[currentCoordinate])) {
            std::cout << "Invalid points: " << coordinates << ". Skipping..." << std::endl;
            parsedRing.points.clear();
            break;
          }
//          std::cout << "\t->" << parsedRing.points.back().coordinates[currentCoordinate] << std::endl;
          coordinates = last;
          while (isspace(*coordinates)) ++coordinates;
          currentCoordinate = (currentCoordinate+1)%3;
        } if (currentCoordinate != 0) {
          std::cout << "Wrong number of coordinates: not divisible by 3" << std::endl;
          parsedRing.points.clear();
        } //std::cout << "Created " << points.size() << " points" << std::endl;
      }
    }
  }
  
  void parsePolygon(const pugi::xml_node &node, AzulPolygon &parsedPolygon) {
    for (auto const &child: node.children()) {
      if (strcmp(child.name(), "gml:exterior") == 0) {
        parseRing(child, parsedPolygon.exteriorRing);
      } else if (strcmp(child.name(), "gml:interior") == 0) {
        AzulRing ring;
        parseRing(child, ring);
        parsedPolygon.interiorRings.push_back(ring);
      }
    }
  }
  
  void parseGML(const pugi::xml_node &node, AzulObject &parsedObject) {
//    std::cout << "Node: \"" << node.name() << "\"" << std::endl;
    
    // Get rid of namespaces
    const char *nodeType = node.name();
    const char *namespaceSeparator = strchr(nodeType, ':');
    if (namespaceSeparator != NULL) {
      nodeType = namespaceSeparator+1;
    }
    
    // CityModel -> CityGML
    if (strcmp(nodeType, "CityModel") == 0) {
      std::cout << "CityGML detected" << std::endl;
//      AzulObject newChild;
//      newChild.type = node.name();
//      newChild.id = node.attribute("gml:id").as_string();
//      for (auto const &attribute: node.attributes()) std::cout << attribute.name() << ": " << attribute.value() << std::endl;
      for (auto const &child: node.children()) parseCityGMLObject(child, parsedObject);
//      parsedObject.children.push_back(newChild);
    }
    
    else if (strcmp(nodeType, "IndoorFeatures") == 0) {
      std::cout << "IndoorGML detected" << std::endl;
      for (auto const &child: node.children()) parseIndoorGMLObject(child, parsedObject);
    }
    
    // Geometry -> plain GML
    else if (strcmp(nodeType, "Polygon") == 0 ||
             strcmp(nodeType, "Triangle") == 0) {
      AzulPolygon polygon;
      parsePolygon(node, polygon);
      parsedObject.polygons.push_back(polygon);
    }
    
    // Unknown still
    else {
      for (auto const &child: node.children()) parseGML(child, parsedObject);
    }
  }
  
  void parseIndoorGMLObject(const pugi::xml_node &node, AzulObject &parsedObject) {
    //    std::cout << "Node: \"" << node.name() << "\"" << std::endl;
    
    // Get rid of namespaces
    const char *nodeType = node.name();
    const char *namespaceSeparator = strchr(nodeType, ':');
    if (namespaceSeparator != NULL) {
      nodeType = namespaceSeparator+1;
    }
    
    // Objects: create in hierachy and parse attributes
    if (strcmp(nodeType, "CellSpace") == 0) {
      AzulObject newChild;
      newChild.type = nodeType;
      newChild.id = node.attribute("gml:id").as_string();
      for (auto const &child: node.children()) {
        parseIndoorGMLObject(child, newChild);
      } parsedObject.children.push_back(newChild);
    }
    
    // Geometry
    else if (strcmp(nodeType, "Polygon") == 0 ||
             strcmp(nodeType, "Triangle") == 0) {
      AzulPolygon polygon;
      parsePolygon(node, polygon);
      parsedObject.polygons.push_back(polygon);
    }
    
    // Objects to flatten
    else {
      for (auto const &child: node.children()) parseIndoorGMLObject(child, parsedObject);
    }
  }
  
  void parseCityGMLObject(const pugi::xml_node &node, AzulObject &parsedObject) {
//    std::cout << "Node: \"" << node.name() << "\"" << std::endl;
    
    // Get rid of namespaces
    const char *nodeType = node.name();
    const char *namespaceSeparator = strchr(nodeType, ':');
    if (namespaceSeparator != NULL) {
      nodeType = namespaceSeparator+1;
    }
    
    // Objects: create in hierachy and parse attributes
    if (strcmp(nodeType, "AuxiliaryTrafficArea") == 0 ||
        strcmp(nodeType, "Bridge") == 0 ||
        strcmp(nodeType, "Building") == 0 ||
        strcmp(nodeType, "BuildingPart") == 0 ||
        strcmp(nodeType, "BuildingInstallation") == 0 ||
        strcmp(nodeType, "CityFurniture") == 0 ||
        strcmp(nodeType, "GenericCityObject") == 0 ||
        strcmp(nodeType, "LandUse") == 0 ||
        strcmp(nodeType, "PlantCover") == 0 ||
        strcmp(nodeType, "Railway") == 0 ||
        strcmp(nodeType, "ReliefFeature") == 0 ||
        strcmp(nodeType, "Road") == 0 ||
        strcmp(nodeType, "SolitaryVegetationObject") == 0 ||
        strcmp(nodeType, "Square") == 0 ||
        strcmp(nodeType, "Track") == 0 ||
        strcmp(nodeType, "TrafficArea") == 0 ||
        strcmp(nodeType, "Tunnel") == 0 ||
        strcmp(nodeType, "WaterBody") == 0 ||
        
        strcmp(nodeType, "lod1Geometry") == 0 ||
        strcmp(nodeType, "lod2Geometry") == 0 ||
        strcmp(nodeType, "lod3Geometry") == 0 ||
        strcmp(nodeType, "lod4Geometry") == 0 ||
        strcmp(nodeType, "lod1MultiCurve") == 0 ||
        strcmp(nodeType, "lod2MultiCurve") == 0 ||
        strcmp(nodeType, "lod3MultiCurve") == 0 ||
        strcmp(nodeType, "lod4MultiCurve") == 0 ||
        strcmp(nodeType, "lod1MultiSurface") == 0 ||
        strcmp(nodeType, "lod2MultiSurface") == 0 ||
        strcmp(nodeType, "lod3MultiSurface") == 0 ||
        strcmp(nodeType, "lod4MultiSurface") == 0 ||
        strcmp(nodeType, "lod1Solid") == 0 ||
        strcmp(nodeType, "lod2Solid") == 0 ||
        strcmp(nodeType, "lod3Solid") == 0 ||
        strcmp(nodeType, "lod4Solid") == 0 ||
        strcmp(nodeType, "lod1TerrainIntersection") == 0 ||
        strcmp(nodeType, "lod2TerrainIntersection") == 0 ||
        strcmp(nodeType, "lod3TerrainIntersection") == 0 ||
        strcmp(nodeType, "lod4TerrainIntersection") == 0 ||
        
        strcmp(nodeType, "Door") == 0 ||
        strcmp(nodeType, "GroundSurface") == 0 ||
        strcmp(nodeType, "RoofSurface") == 0 ||
        strcmp(nodeType, "WallSurface") == 0 ||
        strcmp(nodeType, "Window") == 0) {
      AzulObject newChild;
      newChild.type = nodeType;
      newChild.id = node.attribute("gml:id").as_string();
      for (auto const &child: node.children()) {
        const char *childType = child.name();
        namespaceSeparator = strchr(childType, ':');
        if (namespaceSeparator != NULL) {
          childType = namespaceSeparator+1;
        } if (strcmp(childType, "address") == 0 ||
              strcmp(childType, "averageHeight") == 0 ||
              strcmp(childType, "class") == 0 ||
              strcmp(childType, "crownDiameter") == 0 ||
              strcmp(childType, "function") == 0 ||
              strcmp(childType, "height") == 0 ||
              strcmp(childType, "isMovable") == 0 ||
              strcmp(childType, "measuredHeight") == 0 ||
              strcmp(childType, "name") == 0 ||
              strcmp(childType, "roofType") == 0 ||
              strcmp(childType, "species") == 0 ||
              strcmp(childType, "storeysAboveGround") == 0 ||
              strcmp(childType, "storeysBelowGround") == 0 ||
              strcmp(childType, "storeysHeightsAboveGround") == 0 ||
              strcmp(childType, "storeysHeightsBelowGround") == 0 ||
              strcmp(childType, "trunkDiameter") == 0 ||
              strcmp(childType, "usage") == 0 ||
              strcmp(childType, "yearOfConstruction") == 0 ||
              strcmp(childType, "yearOfDemolition") == 0) {
          std::size_t numberOfChildren = std::distance(child.children().begin(), child.children().end());
          if (numberOfChildren != 1) {
            std::cout << "Attribute " << childType << " has " << numberOfChildren << " children. Skipping..." << std::endl;
            continue;
          } else {
            numberOfChildren = std::distance(child.first_child().children().begin(), child.first_child().children().end());
            if (numberOfChildren != 0) {
              std::cout << "Attribute " << childType << " is not a simple type (" << numberOfChildren << " children). Skipping..." << std::endl;
              continue;
            }
          } if (strlen(child.first_child().value()) > 0) {
            newChild.attributes.push_back(std::pair<std::string, std::string>(childType, child.first_child().value()));
          }
//          std::cout << newChild.attributes.back().first << ": " << newChild.attributes.back().second << std::endl;
          
        } else parseCityGMLObject(child, newChild);
      } parsedObject.children.push_back(newChild);
    }
    
    // Geometry
    else if (strcmp(nodeType, "Polygon") == 0 ||
             strcmp(nodeType, "Triangle") == 0) {
      AzulPolygon polygon;
      parsePolygon(node, polygon);
      parsedObject.polygons.push_back(polygon);
    }
    
    // Objects to flatten
    else {
      for (auto const &child: node.children()) parseCityGMLObject(child, parsedObject);
    }

//    if (strlen(nodeToCheck.value()) > 0) std::cout << " -> (" << nodeToCheck.value() << ")";
//    std::cout << std::endl;
//    for (auto const &attribute: nodeToCheck.attributes()) std::cout << "\t" << attribute.name() << ": " << attribute.as_string() << std::endl;
    
//    for (auto const &child: nodeToCheck.children()) checkNode(child, parsedObject);
  }
  
public:
  void parse(const char *filePath, AzulObject &parsedFile) {
    
    parsedFile.type = "File";
    parsedFile.id = filePath;
    doc.load_file(filePath);
    parseGML(doc.root(), parsedFile);
  }
  
  void clearDOM() {
    doc.reset();
  }
};

#endif /* GMLParsingHelper_hpp */
