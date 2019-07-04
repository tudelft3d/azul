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
#include <unordered_map>

class GMLParsingHelper {
  pugi::xml_document doc;
  
  const char *typeWithoutNamespace(const char *type) {
    const char *namespaceSeparator = strchr(type, ':');
    if (namespaceSeparator != NULL) return namespaceSeparator+1;
    else return type;
  }
  
  void buildNodesIndex(const pugi::xml_node &node, std::unordered_map<std::string, pugi::xml_node> &nodesById) {
    for (auto const &attribute: node.attributes()) {
      const char *attributeType = typeWithoutNamespace(attribute.name());
      if (strcmp(attributeType, "id") == 0) nodesById[attribute.value()] = node;
      else if (strcmp(attributeType, "href") == 0) {
        const char *nodeType = typeWithoutNamespace(node.name());
        if (strcmp(nodeType, "relativeGMLGeometry") == 0 ||
            
            strcmp(nodeType, "appearance") == 0 ||
            strcmp(nodeType, "appearanceMember") == 0 ||
            strcmp(nodeType, "baseSurface") == 0 ||
            strcmp(nodeType, "curveMember") == 0 ||
            strcmp(nodeType, "curveMembers") == 0 ||
            strcmp(nodeType, "element") == 0 ||
            strcmp(nodeType, "exterior") == 0 ||
            strcmp(nodeType, "geometryMember") == 0 ||
            strcmp(nodeType, "interior") == 0 ||
            strcmp(nodeType, "patches") == 0||
            strcmp(nodeType, "pointMember") == 0 ||
            strcmp(nodeType, "pointMembers") == 0 ||
            strcmp(nodeType, "referencePoint") == 0 ||
            strcmp(nodeType, "segments") == 0 ||
            strcmp(nodeType, "solidMember") == 0 ||
            strcmp(nodeType, "solidMembers") == 0 ||
            strcmp(nodeType, "surfaceDataMember") == 0 ||
            strcmp(nodeType, "surfaceMember") == 0 ||
            strcmp(nodeType, "surfaceMembers") == 0 ||
            strcmp(nodeType, "target") == 0 ||
            strcmp(nodeType, "trianglePatches") == 0) {
        } else {
          std::cout << "Xlinked " << nodeType << std::endl;
        }
      }
    } for (auto const &child: node.children()) buildNodesIndex(child, nodesById);
  }
  
  void parseRing(const pugi::xml_node &node, AzulRing &parsedRing) {
    for (auto const &child: node.first_child().children()) {
      const char *childType = typeWithoutNamespace(child.name());
      if (strcmp(childType, "pos") == 0 ||
          strcmp(childType, "posList") == 0) {

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
      const char *childType = typeWithoutNamespace(child.name());
      if (strcmp(childType, "exterior") == 0) {
        parseRing(child, parsedPolygon.exteriorRing);
      } else if (strcmp(childType, "interior") == 0) {
        AzulRing ring;
        parseRing(child, ring);
        parsedPolygon.interiorRings.push_back(ring);
      }
    }
  }
  
  void parseGML(const pugi::xml_node &node, AzulObject &parsedObject) {
//    std::cout << "Node: \"" << node.name() << "\"" << std::endl;
    const char *nodeType = typeWithoutNamespace(node.name());
    std::string docType;
    std::string docVersion;
    
    // CityGML
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
      } if (strcmp(docType.c_str(), "CityGML") == 0) {
        std::cout << docType << " " << docVersion << " detected" << std::endl;
        if (strcmp(docVersion.c_str(), "1.0") == 0 ||
            strcmp(docVersion.c_str(), "2.0") == 0) {
          std::unordered_map<std::string, pugi::xml_node> nodesById;
          std::cout << "Building nodes index...";
          buildNodesIndex(node, nodesById);
          std::cout << " done (" << nodesById.size() << " entries)." << std::endl;
          parseCityGMLObject(node, parsedObject, nodesById);
        } else {
          std::cout << "Unsupported version" << std::endl;
        }
      }
    } 
    
    // IndoorGML
    else if (strcmp(nodeType, "IndoorFeatures") == 0) {
      for (auto const &attribute: node.attributes()) {
//        std::cout << attribute.name() << ": " << attribute.value() << std::endl;
        if (strncmp(attribute.name(), "xmlns", 5) == 0) {
          if (strcmp(attribute.value(), "http://www.opengis.net/indoorgml/1.0/core") == 0) {
            docType = "IndoorGML";
            docVersion = "1.0";
          }
        }
      } if (strcmp(docType.c_str(), "IndoorGML") == 0) {
        std::cout << docType << " " << docVersion << " detected" << std::endl;
        if (strcmp(docVersion.c_str(), "1.0") == 0) {
          std::unordered_map<std::string, pugi::xml_node> nodesById;
          std::cout << "Building nodes index...";
          buildNodesIndex(node, nodesById);
          std::cout << " done." << std::endl;
          parseIndoorGMLObject(node, parsedObject, nodesById);
        }
      }
    }
    
    // Unknown yet -> continue with children
    else for (auto const &child: node.children()) parseGML(child, parsedObject);
  }
  
  void parseIndoorGMLObject(const pugi::xml_node &node, AzulObject &parsedObject, std::unordered_map<std::string, pugi::xml_node> &nodesById) {
    //    std::cout << "Node: \"" << node.name() << "\"" << std::endl;

    // Get rid of namespaces
    const char *nodeType = typeWithoutNamespace(node.name());

    // Objects: create in hierachy and parse attributes
    if (strcmp(nodeType, "CellSpace") == 0) {
      AzulObject newChild;
      newChild.type = nodeType;
      for (auto const &attribute: node.attributes()) {
        const char *attributeType = typeWithoutNamespace(attribute.name());
        if (strcmp(attributeType, "id") == 0) newChild.id = attribute.value();
      } for (auto const &child: node.children()) {
        parseIndoorGMLObject(child, newChild, nodesById);
      } parsedObject.children.push_back(newChild);
    }

    // Geometry
    else if (strcmp(nodeType, "Polygon") == 0 ||
             strcmp(nodeType, "Rectangle") == 0 ||
             strcmp(nodeType, "Triangle") == 0) {
      AzulPolygon polygon;
      parsePolygon(node, polygon);
      parsedObject.polygons.push_back(polygon);
    }

    // Objects to flatten
    else {
      for (auto const &child: node.children()) parseIndoorGMLObject(child, parsedObject, nodesById);
    }
  }
  
  void parseCityGMLObject(const pugi::xml_node &node, AzulObject &parsedObject, std::unordered_map<std::string, pugi::xml_node> &nodesById) {

    // Get rid of namespaces
    const char *nodeType = typeWithoutNamespace(node.name());
//    std::cout << "Node: \"" << nodeType << "\"" << std::endl;
    
    // Ignored types
    if (strcmp(nodeType, "address") == 0 || // Complex type
        strcmp(nodeType, "appearance") == 0 ||  // Unsupported
        strcmp(nodeType, "appearanceMember") == 0 ||  // Unsupported
        strcmp(nodeType, "extent") == 0 ||  // Would cover other geometries, maybe render as edges later?
        strcmp(nodeType, "externalReference") == 0 || // Complex type
        strcmp(nodeType, "generalizesTo") == 0 || // Circular reference
        strcmp(nodeType, "genericAttributeSet") == 0 || // Complex type
        strcmp(nodeType, "measureAttribute") == 0 || // Complex type (but maybe just append units?)
        strcmp(nodeType, "parent") == 0 || // Circular reference
        strcmp(nodeType, "Envelope") == 0) {  // Would cover other geometries, maybe render as edges later?
    }
    
    // Put attributes in same object and parse children
    else if (strcmp(nodeType, "CityModel") == 0) {
      for (auto const &child: node.children()) {
        const char *childType = typeWithoutNamespace(child.name());
        std::size_t numberOfChildren = std::distance(child.children().begin(), child.children().end());
        
        if (numberOfChildren == 1) {
          std::size_t numberOfGrandChildren = std::distance(child.first_child().children().begin(), child.first_child().children().end());
          if (numberOfGrandChildren == 0) {
            if (strlen(child.first_child().value()) > 0) {
              parsedObject.attributes.push_back(std::pair<std::string, std::string>(childType, child.first_child().value()));
            }
          } else parseCityGMLObject(child, parsedObject, nodesById);
        } else if (numberOfChildren > 1) parseCityGMLObject(child, parsedObject, nodesById);
      }
    }
    
    // Custom attributes
    else if (strcmp(nodeType, "stringAttribute") == 0 ||
             strcmp(nodeType, "intAttribute") == 0 ||
             strcmp(nodeType, "doubleAttribute") == 0 ||
             strcmp(nodeType, "dateAttribute") == 0 ||
             strcmp(nodeType, "uriAttribute") == 0) {
      const char *name = node.attribute("name").value();
      const char *value = node.first_child().child_value();
      parsedObject.attributes.push_back(std::pair<std::string, std::string>(name, value));
    }
    
    // Objects to flatten (not useful in hierarchy)
    else if (strcmp(nodeType, "auxiliaryTrafficArea") == 0 || // Redundant elements from CityGML
             strcmp(nodeType, "boundedBy") == 0 ||
             strcmp(nodeType, "breaklines") == 0 ||
             strcmp(nodeType, "bridgeRoomInstallation") == 0 ||
             strcmp(nodeType, "cityObjectMember") == 0 ||
             strcmp(nodeType, "consistsOfBridgePart") == 0 ||
             strcmp(nodeType, "consistsOfBuildingPart") == 0 ||
             strcmp(nodeType, "consistsOfTunnelPart") == 0 ||
             strcmp(nodeType, "grid") == 0 ||
             strcmp(nodeType, "groupMember") == 0 ||
             strcmp(nodeType, "hollowSpaceInstallation") == 0 ||
             strcmp(nodeType, "interiorBridgeInstallation") == 0 ||
             strcmp(nodeType, "interiorBridgeRoom") == 0 ||
             strcmp(nodeType, "interiorBuildingInstallation") == 0 ||
             strcmp(nodeType, "interiorFurniture") == 0 ||
             strcmp(nodeType, "interiorHollowSpace") == 0 ||
             strcmp(nodeType, "interiorRoom") == 0 ||
             strcmp(nodeType, "interiorTunnelInstallation") == 0 ||
             strcmp(nodeType, "opening") == 0 ||
             strcmp(nodeType, "outerBridgeConstruction") == 0 ||
             strcmp(nodeType, "outerBridgeInstallation") == 0 ||
             strcmp(nodeType, "outerBuildingInstallation") == 0 ||
             strcmp(nodeType, "outerTunnelInstallation") == 0 ||
             strcmp(nodeType, "reliefComponent") == 0 ||
             strcmp(nodeType, "reliefPoints") == 0 ||
             strcmp(nodeType, "ridgeOrValleyLines") == 0 ||
             strcmp(nodeType, "roomInstallation") == 0 ||
             strcmp(nodeType, "tin") == 0 ||
             strcmp(nodeType, "trafficArea") == 0 ||
             
             strcmp(nodeType, "CompositeCurve") == 0 || // Geometry types (not necessary to show)
             strcmp(nodeType, "CompositeSolid") == 0 ||
             strcmp(nodeType, "CompositeSurface") == 0 ||
             strcmp(nodeType, "Curve") == 0 ||
             strcmp(nodeType, "GeometricComplex") == 0 ||
             strcmp(nodeType, "LineString") == 0 ||
             strcmp(nodeType, "MultiCurve") == 0 ||
             strcmp(nodeType, "MultiPoint") == 0 ||
             strcmp(nodeType, "MultiGeometry") == 0 ||
             strcmp(nodeType, "MultiSolid") == 0 ||
             strcmp(nodeType, "MultiSurface") == 0 ||
             strcmp(nodeType, "OrientableCurve") == 0 ||
             strcmp(nodeType, "OrientableSurface") == 0 ||
             strcmp(nodeType, "Shell") == 0 ||
             strcmp(nodeType, "Solid") == 0 ||
             strcmp(nodeType, "Surface") == 0 ||
             strcmp(nodeType, "TIN") == 0 ||
             strcmp(nodeType, "TriangulatedSurface") == 0) {
      for (auto const &child: node.children()) parseCityGMLObject(child, parsedObject, nodesById);
    }
    
    // Objects to flatten (not useful in hierarchy), representing redundant info from GML, but with potential xlinks
    else if (strcmp(nodeType, "baseSurface") == 0 ||
             strcmp(nodeType, "curveMember") == 0 ||
             strcmp(nodeType, "curveMembers") == 0 ||
             strcmp(nodeType, "element") == 0 ||
             strcmp(nodeType, "exterior") == 0 ||
             strcmp(nodeType, "geometryMember") == 0 ||
             strcmp(nodeType, "interior") == 0 ||
             strcmp(nodeType, "patches") == 0||
             strcmp(nodeType, "pointMember") == 0 ||
             strcmp(nodeType, "pointMembers") == 0 ||
             strcmp(nodeType, "segments") == 0 ||
             strcmp(nodeType, "solidMember") == 0 ||
             strcmp(nodeType, "solidMembers") == 0 ||
             strcmp(nodeType, "surfaceMember") == 0 ||
             strcmp(nodeType, "surfaceMembers") == 0 ||
             strcmp(nodeType, "trianglePatches") == 0) {
      for (auto const &child: node.children()) parseCityGMLObject(child, parsedObject, nodesById);
      const char *xlink = NULL;
      for (auto const &attribute: node.attributes()) {
        const char *attributeType = typeWithoutNamespace(attribute.name());
        if (strcmp(attributeType, "href") == 0) xlink = attribute.value();
      } if (xlink != NULL) {
        if (xlink[0] == '#') ++xlink;
        std::unordered_map<std::string, pugi::xml_node>::const_iterator xlinkNode = nodesById.find(xlink);
        if (xlinkNode != nodesById.end()) {
//          const char *xlinkType = typeWithoutNamespace(xlinkNode->second.name());
//          std::cout << xlinkType << " with xlink " << xlink << " found. Putting it in " << parsedObject.type << "." << std::endl;
          parseCityGMLObject(xlinkNode->second, parsedObject, nodesById);
        } else {
          std::cout << "Geometry with xlink " << xlink << " not found. Skipped." << std::endl;
        }
      }
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
             
             strcmp(nodeType, "geometry") == 0 || // Geometry types (in case of multiple and to know which LoD is used)
             strcmp(nodeType, "lod0FootPrint") == 0 ||
             strcmp(nodeType, "lod1FootPrint") == 0 ||
             strcmp(nodeType, "lod2FootPrint") == 0 ||
             strcmp(nodeType, "lod3FootPrint") == 0 ||
             strcmp(nodeType, "lod4FootPrint") == 0 ||
             strcmp(nodeType, "lod0Geometry") == 0 ||
             strcmp(nodeType, "lod1Geometry") == 0 ||
             strcmp(nodeType, "lod2Geometry") == 0 ||
             strcmp(nodeType, "lod3Geometry") == 0 ||
             strcmp(nodeType, "lod4Geometry") == 0 ||
             strcmp(nodeType, "lod0ImplicitRepresentation") == 0 ||
             strcmp(nodeType, "lod1ImplicitRepresentation") == 0 ||
             strcmp(nodeType, "lod2ImplicitRepresentation") == 0 ||
             strcmp(nodeType, "lod3ImplicitRepresentation") == 0 ||
             strcmp(nodeType, "lod4ImplicitRepresentation") == 0 ||
             strcmp(nodeType, "lod0MultiCurve") == 0 ||
             strcmp(nodeType, "lod1MultiCurve") == 0 ||
             strcmp(nodeType, "lod2MultiCurve") == 0 ||
             strcmp(nodeType, "lod3MultiCurve") == 0 ||
             strcmp(nodeType, "lod4MultiCurve") == 0 ||
             strcmp(nodeType, "lod0MultiSolid") == 0 ||
             strcmp(nodeType, "lod1MultiSolid") == 0 ||
             strcmp(nodeType, "lod2MultiSolid") == 0 ||
             strcmp(nodeType, "lod3MultiSolid") == 0 ||
             strcmp(nodeType, "lod4MultiSolid") == 0 ||
             strcmp(nodeType, "lod0MultiSurface") == 0 ||
             strcmp(nodeType, "lod1MultiSurface") == 0 ||
             strcmp(nodeType, "lod2MultiSurface") == 0 ||
             strcmp(nodeType, "lod3MultiSurface") == 0 ||
             strcmp(nodeType, "lod4MultiSurface") == 0 ||
             strcmp(nodeType, "lod0Network") == 0 ||
             strcmp(nodeType, "lod1Network") == 0 ||
             strcmp(nodeType, "lod2Network") == 0 ||
             strcmp(nodeType, "lod3Network") == 0 ||
             strcmp(nodeType, "lod4Network") == 0 ||
             strcmp(nodeType, "lod0TerrainIntersection") == 0 ||
             strcmp(nodeType, "lod1TerrainIntersection") == 0 ||
             strcmp(nodeType, "lod2TerrainIntersection") == 0 ||
             strcmp(nodeType, "lod3TerrainIntersection") == 0 ||
             strcmp(nodeType, "lod4TerrainIntersection") == 0 ||
             strcmp(nodeType, "lod0RoofEdge") == 0 ||
             strcmp(nodeType, "lod1RoofEdge") == 0 ||
             strcmp(nodeType, "lod2RoofEdge") == 0 ||
             strcmp(nodeType, "lod3RoofEdge") == 0 ||
             strcmp(nodeType, "lod4RoofEdge") == 0 ||
             strcmp(nodeType, "lod0Solid") == 0 ||
             strcmp(nodeType, "lod1Solid") == 0 ||
             strcmp(nodeType, "lod2Solid") == 0 ||
             strcmp(nodeType, "lod3Solid") == 0 ||
             strcmp(nodeType, "lod4Solid") == 0 ||
             strcmp(nodeType, "lod0Surface") == 0 ||
             strcmp(nodeType, "lod1Surface") == 0 ||
             strcmp(nodeType, "lod2Surface") == 0 ||
             strcmp(nodeType, "lod3Surface") == 0 ||
             strcmp(nodeType, "lod4Surface") == 0) {

      AzulObject newChild;
      newChild.type = nodeType;
      for (auto const &attribute: node.attributes()) {
        const char *attributeType = typeWithoutNamespace(attribute.name());
        if (strcmp(attributeType, "id") == 0) newChild.id = attribute.value();
      }
      
      for (auto const &child: node.children()) {
        const char *childType = typeWithoutNamespace(child.name());
        std::size_t numberOfChildren = std::distance(child.children().begin(), child.children().end());
        
        if (numberOfChildren == 1) {
          std::size_t numberOfGrandChildren = std::distance(child.first_child().children().begin(), child.first_child().children().end());
          if (numberOfGrandChildren == 0) {
            if (strlen(child.first_child().value()) > 0) {
              newChild.attributes.push_back(std::pair<std::string, std::string>(childType, child.first_child().value()));
            }
          } else parseCityGMLObject(child, newChild, nodesById);
        } else if (numberOfChildren > 1) parseCityGMLObject(child, newChild, nodesById);
      }
      
      parsedObject.children.push_back(newChild);
    }
    
    // Explicit geometry
    else if (strcmp(nodeType, "Polygon") == 0 ||
             strcmp(nodeType, "Triangle") == 0) {
      AzulPolygon polygon;
      parsePolygon(node, polygon);
      parsedObject.polygons.push_back(polygon);
    }
    
    // Implicit geometry
    else if (strcmp(nodeType, "ImplicitGeometry") == 0) {
//      std::cout << "Implicit geometry" << std::endl;
      std::vector<float> transformationMatrix;
      std::vector<float> anchorPointCoordinates;
      
      AzulObject transformedChild;
      for (auto const &child: node.children()) {
        const char *childType = typeWithoutNamespace(child.name());
        
        if (strcmp(childType, "transformationMatrix") == 0) {
          const char *values = child.child_value();
          while (isspace(*values)) ++values;
          while (strlen(values) > 0) {
            const char *last = values;
            while (!isspace(*last) && *last != '\0') ++last;
            float parsedValue;
            if (!boost::spirit::x3::parse(values, last, boost::spirit::x3::float_, parsedValue)) {
              std::cout << "Invalid value: " << values << ". Skipping..." << std::endl;
            } else {
              transformationMatrix.push_back(parsedValue);
            }
            values = last;
            while (isspace(*values)) ++values;
          }
        }
        
        else if (strcmp(childType, "relativeGMLGeometry") == 0) {
          for (auto const &grandchild: child.children()) parseCityGMLObject(grandchild, transformedChild, nodesById);
          const char *xlink = NULL;
          for (auto const &attribute: child.attributes()) {
            const char *attributeType = typeWithoutNamespace(attribute.name());
            if (strcmp(attributeType, "href") == 0) xlink = attribute.value();
          } if (xlink != NULL) {
            if (xlink[0] == '#') ++xlink;
            std::unordered_map<std::string, pugi::xml_node>::const_iterator xlinkNode = nodesById.find(xlink);
            if (xlinkNode != nodesById.end()) {
              parseCityGMLObject(xlinkNode->second, transformedChild, nodesById);
            } else {
              std::cout << "Geometry with xlink " << xlink << " not found" << std::endl;
            }
          }
        }
        
        else if (strcmp(childType, "referencePoint") == 0) {
          for (auto const &point: child.children()) {
            const char *pointType = typeWithoutNamespace(point.name());
            if (strcmp(pointType, "Point") == 0) {
              for (auto const &pos: point.children()) {
                const char *posType = typeWithoutNamespace(pos.name());
                if (strcmp(posType, "pos") == 0) {
                  const char *coordinates = pos.child_value();
                  while (isspace(*coordinates)) ++coordinates;
                  while (strlen(coordinates) > 0) {
                    const char *last = coordinates;
                    while (!isspace(*last) && *last != '\0') ++last;
                    anchorPointCoordinates.push_back(0.0);
                    if (!boost::spirit::x3::parse(coordinates, last, boost::spirit::x3::float_, anchorPointCoordinates.back())) {
                      std::cout << "Invalid coordinates: " << coordinates << ". Skipping..." << std::endl;
                    } coordinates = last;
                    while (isspace(*coordinates)) ++coordinates;
                  } 
                }
              }
            }
          }
        }
      }
      
      if (transformationMatrix.size() == 16 && anchorPointCoordinates.size() == 3) {
//        std::cout << "Transformation matrix:";
//        for (auto const &value: transformationMatrix) std::cout << " " << value;
//        std::cout << std::endl;
        for (auto const &polygon: transformedChild.polygons) {
          parsedObject.polygons.push_back(AzulPolygon());
          for (auto const &point: polygon.exteriorRing.points) {
            parsedObject.polygons.back().exteriorRing.points.push_back(AzulPoint());
//            std::cout << "Point: " << point.coordinates[0] << " " << point.coordinates[1] << " " << point.coordinates[2] << std::endl;
            float homogeneousCoordinate = (transformationMatrix[12]*point.coordinates[0] +
                                           transformationMatrix[13]*point.coordinates[1] +
                                           transformationMatrix[14]*point.coordinates[2] +
                                           transformationMatrix[15]);
            parsedObject.polygons.back().exteriorRing.points.back().coordinates[0] = (transformationMatrix[0]*point.coordinates[0] +
                                                                                      transformationMatrix[1]*point.coordinates[1] +
                                                                                      transformationMatrix[2]*point.coordinates[2] +
                                                                                      transformationMatrix[3])/homogeneousCoordinate + anchorPointCoordinates[0];
            parsedObject.polygons.back().exteriorRing.points.back().coordinates[1] = (transformationMatrix[4]*point.coordinates[0] +
                                                                                      transformationMatrix[5]*point.coordinates[1] +
                                                                                      transformationMatrix[6]*point.coordinates[2] +
                                                                                      transformationMatrix[7])/homogeneousCoordinate + anchorPointCoordinates[1];
            parsedObject.polygons.back().exteriorRing.points.back().coordinates[2] = (transformationMatrix[8]*point.coordinates[0] +
                                                                                      transformationMatrix[9]*point.coordinates[1] +
                                                                                      transformationMatrix[10]*point.coordinates[2] +
                                                                                      transformationMatrix[11])/homogeneousCoordinate + anchorPointCoordinates[2];
          } for (auto const &ring: polygon.interiorRings) {
            parsedObject.polygons.back().interiorRings.push_back(AzulRing());
            for (auto const &point: ring.points) {
              parsedObject.polygons.back().interiorRings.back().points.push_back(AzulPoint());
              float homogeneousCoordinate = (transformationMatrix[12]*point.coordinates[0] +
                                             transformationMatrix[13]*point.coordinates[1] +
                                             transformationMatrix[14]*point.coordinates[2] +
                                             transformationMatrix[15]);
              parsedObject.polygons.back().interiorRings.back().points.back().coordinates[0] = (transformationMatrix[0]*point.coordinates[0] +
                                                                                                transformationMatrix[1]*point.coordinates[1] +
                                                                                                transformationMatrix[2]*point.coordinates[2] +
                                                                                                transformationMatrix[3])/homogeneousCoordinate;
              parsedObject.polygons.back().interiorRings.back().points.back().coordinates[1] = (transformationMatrix[4]*point.coordinates[0] +
                                                                                                transformationMatrix[5]*point.coordinates[1] +
                                                                                                transformationMatrix[6]*point.coordinates[2] +
                                                                                                transformationMatrix[7])/homogeneousCoordinate;
              parsedObject.polygons.back().interiorRings.back().points.back().coordinates[2] = (transformationMatrix[8]*point.coordinates[0] +
                                                                                                transformationMatrix[9]*point.coordinates[1] +
                                                                                                transformationMatrix[10]*point.coordinates[2] +
                                                                                                transformationMatrix[11])/homogeneousCoordinate;
            }
          }
        }
      } else std::cout << "Wrong size of transformation matrix: not 4x4" << std::endl;
    }
    
    else {
      std::cout << "Unknown node: \"" << node.name() << "\"" << std::endl;
      pugi::xml_node currentNode = node;
      std::list<std::string> hierarchy;
      while (currentNode.type() != pugi::node_null) {
        hierarchy.push_front(currentNode.name());
        currentNode = currentNode.parent();
      } std::cout << "  hierarchy:";
      for (auto const &currentName: hierarchy) std::cout << " -> " << currentName;
      std::cout << std::endl;
    }
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
