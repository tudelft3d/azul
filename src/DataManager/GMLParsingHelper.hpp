// azul
// Copyright © 2016-2019 Ken Arroyo Ohori
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
#include <pugixml-1.9/pugixml.hpp>

class GMLParsingHelper {
  pugi::xml_document doc;
  std::string docType;
  std::string docVersion;
  
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
      for (auto const &attribute: node.attributes()) {
//        std::cout << attribute.name() << ": " << attribute.value() << std::endl;
        if (strncmp(attribute.name(), "xmlns", 5) == 0) {
          if (strcmp(attribute.value(), "http://www.opengis.net/citygml/1.0") == 0) {
            docType = "CityGML";
            docVersion = "1.0";
          } else if (strcmp(attribute.value(), "http://www.opengis.net/citygml/2.0") == 0) {
            docType = "CityGML";
            docVersion = "2.0";
          } else if (strcmp(attribute.value(), "http://www.opengis.net/citygml/3.0") == 0) {
            docType = "CityGML";
            docVersion = "3.0";
          }
        }
      }
    } if (strcmp(docType.c_str(), "CityGML") == 0) {
      std::cout << docType << " " << docVersion << " detected" << std::endl;
      if (strcmp(docVersion.c_str(), "1.0") == 0 ||
          strcmp(docVersion.c_str(), "2.0") == 0) {
        for (auto const &child: node.children()) parseCityGMLObject(child, parsedObject);
      }
    }
    
    // IndoorFeatures -> IndoorGML
    if (docType.empty() && strcmp(nodeType, "IndoorFeatures") == 0) {
      for (auto const &attribute: node.attributes()) {
//        std::cout << attribute.name() << ": " << attribute.value() << std::endl;
        if (strncmp(attribute.name(), "xmlns", 5) == 0) {
          if (strcmp(attribute.value(), "http://www.opengis.net/indoorgml/1.0/core") == 0) {
            docType = "IndoorGML";
            docVersion = "1.0";
          }
        }
      }
    } if (strcmp(docType.c_str(), "IndoorGML") == 0) {
      std::cout << docType << " " << docVersion << " detected" << std::endl;
      if (strcmp(docVersion.c_str(), "1.0") == 0) {
        for (auto const &child: node.children()) parseIndoorGMLObject(child, parsedObject);
      }
    }
    
    // Unknown -> try plain GML or continue with children
    if (docType.empty()) {
      if (strcmp(nodeType, "Polygon") == 0 ||
          strcmp(nodeType, "Triangle") == 0) {
        AzulPolygon polygon;
        parsePolygon(node, polygon);
        parsedObject.polygons.push_back(polygon);
      } else {
        for (auto const &child: node.children()) parseGML(child, parsedObject);
      }
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

    // Get rid of namespaces
    const char *nodeType = node.name();
    const char *namespaceSeparator = strchr(nodeType, ':');
    if (namespaceSeparator != NULL) {
      nodeType = namespaceSeparator+1;
    }
    
    // Unsupported types
    if (strcmp(nodeType, "appearanceMember") == 0 ||
        strcmp(nodeType, "Envelope") == 0) {
    }
    
    // Objects to flatten (not useful in hierarchy)
    else if (strcmp(nodeType, "boundedBy") == 0 ||
             strcmp(nodeType, "cityObjectMember") == 0 ||
             strcmp(nodeType, "groupMember") == 0 ||
             strcmp(nodeType, "reliefComponent") == 0 ||
             strcmp(nodeType, "surfaceMember") == 0 ||
             strcmp(nodeType, "tin") == 0 ||
             strcmp(nodeType, "trianglePatches") == 0) {
      for (auto const &child: node.children()) parseCityGMLObject(child, parsedObject);
    }
    
    // Objects to put in hierarchy
    else if (strcmp(nodeType, "BreaklineRelief") == 0 || // Relief
             strcmp(nodeType, "MassPointRelief") == 0 ||
             strcmp(nodeType, "RasterRelief") == 0 ||
             strcmp(nodeType, "ReliefFeature") == 0 ||
             strcmp(nodeType, "TINRelief") == 0 ||
             
             strcmp(nodeType, "Building") == 0 || // Building
             strcmp(nodeType, "BuildingFurniture") == 0 ||
             strcmp(nodeType, "BuildingInstallation") == 0 ||
             strcmp(nodeType, "BuildingPart") == 0 ||
             strcmp(nodeType, "IntBuildingInstallation") == 0 ||
             strcmp(nodeType, "Room") == 0 ||
             
             strcmp(nodeType, "HollowSpace") == 0 || // Tunnel
             strcmp(nodeType, "IntTunnelInstallation") == 0 ||
             strcmp(nodeType, "RoofSurface") == 0 ||
             strcmp(nodeType, "Tunnel") == 0 ||
             strcmp(nodeType, "TunnelInstallation") == 0 ||
             strcmp(nodeType, "TunnelFurniture") == 0 ||
             strcmp(nodeType, "TunnelPart") == 0 ||
             
             strcmp(nodeType, "Bridge") == 0 || // Bridge
             strcmp(nodeType, "BridgeConstructionElement") == 0 ||
             strcmp(nodeType, "BridgeFurniture") == 0 ||
             strcmp(nodeType, "BridgeInstallation") == 0 ||
             strcmp(nodeType, "BridgePart") == 0 ||
             strcmp(nodeType, "BridgeRoom") == 0 ||
             strcmp(nodeType, "IntBridgeInstallation") == 0 ||
             
             strcmp(nodeType, "WaterBody") == 0 || // WaterBody
             strcmp(nodeType, "WaterClosureSurface") == 0 ||
             strcmp(nodeType, "WaterGroundSurface") == 0 ||
             strcmp(nodeType, "WaterSurface") == 0 ||
             
             strcmp(nodeType, "AuxiliaryTrafficArea") == 0 || // Transportation
             strcmp(nodeType, "Railway") == 0 ||
             strcmp(nodeType, "Road") == 0 ||
             strcmp(nodeType, "Square") == 0 ||
             strcmp(nodeType, "Track") == 0 ||
             strcmp(nodeType, "TrafficArea") == 0 ||
             strcmp(nodeType, "TransportationComplex") == 0 ||
             
             strcmp(nodeType, "PlantCover") == 0 || // Vegetation
             strcmp(nodeType, "SolitaryVegetationObject") == 0 ||
             
             strcmp(nodeType, "CityFurniture") == 0 || // CityFurniture
             
             strcmp(nodeType, "LandUse") == 0 || // LandUse
             
             strcmp(nodeType, "CityObjectGroup") == 0 || // CityObjectGroup
             
             strcmp(nodeType, "GenericCityObject") == 0 || // GenericCityObject
             
             strcmp(nodeType, "CeilingSurface") == 0 || // Surface types for Building, Bridge and Tunnel
             strcmp(nodeType, "ClosureSurface") == 0 ||
             strcmp(nodeType, "Door") == 0 ||
             strcmp(nodeType, "FloorSurface") == 0 ||
             strcmp(nodeType, "GroundSurface") == 0 ||
             strcmp(nodeType, "InteriorWallSurface") == 0 ||
             strcmp(nodeType, "RoofSurface") == 0 ||
             strcmp(nodeType, "OuterCeilingSurface") == 0 ||
             strcmp(nodeType, "OuterFloorSurface") == 0 ||
             strcmp(nodeType, "WallSurface") == 0 ||
             strcmp(nodeType, "Window") == 0 ||
             
             strcmp(nodeType, "CompositeSurface") == 0 ||
             strcmp(nodeType, "TriangulatedSurface") == 0 ||
             
             strcmp(nodeType, "lod2Surface") == 0 ||
             strcmp(nodeType, "lod3Surface") == 0 ||
             strcmp(nodeType, "lod4Surface") == 0) {

      AzulObject newChild;
      newChild.type = nodeType;
      newChild.id = node.attribute("gml:id").as_string();
      
      for (auto const &child: node.children()) {
        const char *childType = child.name();
        namespaceSeparator = strchr(childType, ':');
        if (namespaceSeparator != NULL) {
          childType = namespaceSeparator+1;
        } std::size_t numberOfChildren = std::distance(child.children().begin(), child.children().end());
        
        if (numberOfChildren == 1) {
          std::size_t numberOfGrandChildren = std::distance(child.first_child().children().begin(), child.first_child().children().end());
          if (numberOfGrandChildren == 0) {
            if (strlen(child.first_child().value()) > 0) {
              newChild.attributes.push_back(std::pair<std::string, std::string>(childType, child.first_child().value()));
            }
          } else parseCityGMLObject(child, newChild);
        } else parseCityGMLObject(child, newChild);
      }
      
      parsedObject.children.push_back(newChild);
    }
    
    // Geometry
    else if (strcmp(nodeType, "Polygon") == 0 ||
             strcmp(nodeType, "Triangle") == 0) {
      AzulPolygon polygon;
      parsePolygon(node, polygon);
      parsedObject.polygons.push_back(polygon);
    }
    
    else {
      std::cout << "Unknown node: \"" << nodeType << "\"" << std::endl;
    }
  }
  
public:
  GMLParsingHelper() {
    docType = "";
    docVersion = "";
  }
  
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
