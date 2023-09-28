// azul
// Copyright © 2016-2023 Ken Arroyo Ohori
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

#ifndef JSONParsingHelper_hpp
#define JSONParsingHelper_hpp

#include <any>

#include "DataModel.hpp"
#include "simdjson.h"

class JSONParsingHelper {
  std::string_view docType;
  std::string_view docVersion;
  
  void parseCityJSONObject(simdjson::ondemand::object jsonObject, AzulObject &object, std::vector<std::tuple<double, double, double>> &vertices, AzulObject *geometryTemplates) {

    // Type (mandatory)
    try {
      object.type = jsonObject["type"].get_string().value();
    } catch (simdjson::simdjson_error &e) {
      std::cout << "no type specified" << std::endl;
      return;
    } // std::cout << object.type << std::endl;
    
    // Geometry (optional)
    try {
      for (auto geometry: jsonObject["geometry"]) {
        parseCityJSONObjectGeometry(geometry.get_object(), object, vertices, geometryTemplates);
      }
    } catch (simdjson::simdjson_error &e) {
//      std::cout << "\tno geometry" << std::endl;
    }
//    std::cout << "\tgeometries:" << std::endl;
//    for (auto const &geometry: object.children) {
//      std::cout << "\t\t" << geometry.type << " " << geometry.id << std::endl;
//    }
    
    // Attributes (optional)
    try {
      for (auto attribute: jsonObject["attributes"].value().get_object()) {
        switch (attribute.value().type()) {
          case simdjson::ondemand::json_type::string:
            object.attributes.push_back(std::pair<std::string, std::string>(attribute.unescaped_key().value(), attribute.value().get_string().value()));
            break;
          case simdjson::ondemand::json_type::number:
            object.attributes.push_back(std::pair<std::string, std::string>(attribute.unescaped_key().value(), std::to_string(attribute.value().get_double())));
            break;
          case simdjson::ondemand::json_type::boolean:
            if (attribute.value().get_bool() == true) object.attributes.push_back(std::pair<std::string, std::string>(attribute.unescaped_key().value(), "true"));
            else object.attributes.push_back(std::pair<std::string, std::string>(attribute.unescaped_key().value(), "false"));
            break;
          case simdjson::ondemand::json_type::null:
            object.attributes.push_back(std::pair<std::string, std::string>(attribute.unescaped_key().value(), "null"));
            break;
          default:
            std::cout << attribute.unescaped_key().value() << ": unknown attribute type" << std::endl;
            break;
        }
      }
    } catch (simdjson::simdjson_error &e) {
      std::cout << "\terror parsing attributes" << std::endl;
    }
//    std::cout << "\tattributes:" << std::endl;
//    for (const auto &attribute: object.attributes) {
//      std::cout << "\t\t" << attribute.first << ": " << attribute.second << std::endl;
//    }
    
    // TODO: children, parents, geographicalExtent
  }

  void parseCityJSONObjectGeometry(simdjson::ondemand::object currentGeometry, AzulObject &object, std::vector<std::tuple<double, double, double>> &vertices, AzulObject *geometryTemplates) {
    std::vector<std::map<std::string_view, std::string_view>> semanticSurfaces;
    std::string geometryType, geometryLod;
    std::vector<double> transformationMatrix;
    unsigned long long templateIndex;
    bool withSemantics = false;

//    std::cout << currentGeometry << std::endl;

    // Mandatory
    try {
      geometryType = currentGeometry["type"].get_string().value();
    } catch (simdjson::simdjson_error &e) {
      std::cout << "no geometry type specified" << std::endl;
      return;
    } // std::cout << "\tgeometry type: " << geometryType << std::endl;

    try {
      switch (currentGeometry["lod"].type()) {
        case simdjson::ondemand::json_type::string:
          geometryLod = currentGeometry["lod"].get_string().value();
          break;
        case simdjson::ondemand::json_type::number:
          geometryLod = std::to_string(currentGeometry["lod"].get_double()); // invalid but common error
          break;
        default:
          std::cout << "unknown lod type" << std::endl;
          break;
      }
    } catch (simdjson::simdjson_error &e) {
      if (geometryType != "GeometryInstance") std::cout << "no LoD specified" << std::endl;
      geometryLod = "unknown";
    } // std::cout << "\tLoD: " << geometryLod << std::endl;

    std::vector<std::any> boundaries;
    parseNestedArray(currentGeometry["boundaries"].get_array(), boundaries);
//    std::cout << "boundaries: ";
//    dump(boundaries);
//    std::cout << std::endl;

    // Optional
    std::vector<std::any> semantics;
    simdjson::ondemand::object element;
    auto error = currentGeometry["semantics"].get(element);
    if (!error) {
      withSemantics = true;
      for (simdjson::ondemand::object surface: element["surfaces"]) {
        semanticSurfaces.push_back(std::map<std::string_view, std::string_view>());
        for (auto attribute: surface) {
          switch (attribute.value().type()) {
            case simdjson::ondemand::json_type::string:
              semanticSurfaces.back()[attribute.unescaped_key().value()] = attribute.value().get_string().value();
              break;
            case simdjson::ondemand::json_type::number:
              semanticSurfaces.back()[attribute.unescaped_key().value()] = std::to_string(attribute.value().get_double());
              break;
            case simdjson::ondemand::json_type::boolean:
              if (attribute.value().get_bool() == true) semanticSurfaces.back()[attribute.unescaped_key().value()] = "true";
              else semanticSurfaces.back()[attribute.unescaped_key().value()] = "false";
              break;
            case simdjson::ondemand::json_type::null:
              semanticSurfaces.back()[attribute.unescaped_key().value()] = "null";
              break;
            default:
              std::cout << "unknown attribute type" << std::endl;
              break;
          }
        }
      } parseNestedArray(element["values"].get_array(), semantics);
//      std::cout << "semantic surfaces: " << std::endl;
//      for (auto &surface: semanticSurfaces) {
//        for (auto &property: surface) {
//          std::cout << "\t" << property.first << ": " << property.second << "    ";
//        } std::cout << std::endl;
//      } std::cout << "semantics: ";
//      dump(semantics);
//      std::cout << std::endl;
    } // else std::cout << "no semantics found" << std::endl;
    error = currentGeometry["template"].get_uint64().get(templateIndex);
    if (error) templateIndex = 0;
    simdjson::ondemand::array transformationMatrixArray;
    error = currentGeometry["transformationMatrix"].get_array().get(transformationMatrixArray);
    if (!error) for (auto matrixElement: transformationMatrixArray) transformationMatrix.push_back(matrixElement.get_double().value());

    if (!geometryType.empty()) {
      std::any semanticsAsAny(semantics);

      if (geometryType == "MultiSurface" ||
          geometryType == "CompositeSurface") {
        object.children.push_back(AzulObject());
        object.children.back().type = "LoD";
        object.children.back().id = geometryLod;
        parseCityJSONGeometry(boundaries, semanticsAsAny, withSemantics, semanticSurfaces, 2, object.children.back(), vertices);
      }

      else if (geometryType == "Solid") {
        object.children.push_back(AzulObject());
        object.children.back().type = "LoD";
        object.children.back().id = geometryLod;
        parseCityJSONGeometry(boundaries, semanticsAsAny, withSemantics, semanticSurfaces, 3, object.children.back(), vertices);
      }

      else if (geometryType == "MultiSolid" ||
               geometryType == "CompositeSolid") {
        object.children.push_back(AzulObject());
        object.children.back().type = "LoD";
        object.children.back().id = geometryLod;
        parseCityJSONGeometry(boundaries, semanticsAsAny, withSemantics, semanticSurfaces, 4, object.children.back(), vertices);
      }

      else if (geometryType == "GeometryInstance") {
        if (geometryTemplates != NULL && templateIndex < geometryTemplates->children.size() && transformationMatrix.size() == 16) {
          unsigned long long anchorPoint = std::any_cast<unsigned long long>(boundaries[0]);
          object.children.push_back(AzulObject(geometryTemplates->children[templateIndex]));
          for (auto &polygon: object.children.back().polygons) {
            for (auto &point: polygon.exteriorRing.points) {
              float homogeneousCoordinate = (transformationMatrix[12]*point.coordinates[0] +
                                             transformationMatrix[13]*point.coordinates[1] +
                                             transformationMatrix[14]*point.coordinates[2] +
                                             transformationMatrix[15]);
              float x = (transformationMatrix[0]*point.coordinates[0] +
                         transformationMatrix[1]*point.coordinates[1] +
                         transformationMatrix[2]*point.coordinates[2] +
                         transformationMatrix[3])/homogeneousCoordinate + std::get<0>(vertices[anchorPoint]);
              float y = (transformationMatrix[4]*point.coordinates[0] +
                         transformationMatrix[5]*point.coordinates[1] +
                         transformationMatrix[6]*point.coordinates[2] +
                         transformationMatrix[7])/homogeneousCoordinate + std::get<1>(vertices[anchorPoint]);
              float z = (transformationMatrix[8]*point.coordinates[0] +
                         transformationMatrix[9]*point.coordinates[1] +
                         transformationMatrix[10]*point.coordinates[2] +
                         transformationMatrix[11])/homogeneousCoordinate + std::get<2>(vertices[anchorPoint]);
              point.coordinates[0] = x;
              point.coordinates[1] = y;
              point.coordinates[2] = z;
            } for (auto &ring: polygon.interiorRings) {
              for (auto &point: ring.points) {
                float homogeneousCoordinate = (transformationMatrix[12]*point.coordinates[0] +
                                               transformationMatrix[13]*point.coordinates[1] +
                                               transformationMatrix[14]*point.coordinates[2] +
                                               transformationMatrix[15]);
                float x = (transformationMatrix[0]*point.coordinates[0] +
                           transformationMatrix[1]*point.coordinates[1] +
                           transformationMatrix[2]*point.coordinates[2] +
                           transformationMatrix[3])/homogeneousCoordinate + std::get<0>(vertices[anchorPoint]);
                float y = (transformationMatrix[4]*point.coordinates[0] +
                           transformationMatrix[5]*point.coordinates[1] +
                           transformationMatrix[6]*point.coordinates[2] +
                           transformationMatrix[7])/homogeneousCoordinate + std::get<1>(vertices[anchorPoint]);
                float z = (transformationMatrix[8]*point.coordinates[0] +
                           transformationMatrix[9]*point.coordinates[1] +
                           transformationMatrix[10]*point.coordinates[2] +
                           transformationMatrix[11])/homogeneousCoordinate + std::get<2>(vertices[anchorPoint]);
                point.coordinates[0] = x;
                point.coordinates[1] = y;
                point.coordinates[2] = z;
              }
            }
          }
        }

      }
    }
  }

  void parseNestedArray(simdjson::ondemand::array jsonNestedArray, std::vector<std::any> &nestedArray) {
    nestedArray.clear();
    for (auto array: jsonNestedArray) {
      switch (array.type()) {
        case simdjson::ondemand::json_type::array: {
          std::vector<std::any> newArray;
          parseNestedArray(array.get_array(), newArray);
          nestedArray.push_back(newArray);
          break;
        } case simdjson::ondemand::json_type::number:
          nestedArray.push_back((unsigned long long)array.get_uint64());
          break;
        case simdjson::ondemand::json_type::null:
          nestedArray.push_back(std::any());
          break;
        default:
          nestedArray.push_back(std::any());
          break;
      }
    }
  }

  void parseCityJSONGeometry(std::vector<std::any> &boundaries, std::any &semantics, bool withSemantics, std::vector<std::map<std::string_view, std::string_view>> &semanticSurfaces, int nesting, AzulObject &object, std::vector<std::tuple<double, double, double>> &vertices) {

//    std::cout << "nesting: " << nesting << std::endl;
//    std::cout << "boundaries: "; dump(boundaries); std::cout << std::endl;
//    std::cout << "semantics: "; dump(semantics); std::cout << std::endl;

    if (nesting > 1) {
      if (semantics.has_value()) {

        // Vector
        try {
          std::vector<std::any> semanticsAsVector = std::any_cast<std::vector<std::any>>(semantics);
          if (!semanticsAsVector.empty()) {
            auto boundary = boundaries.begin();
            auto semantic = semanticsAsVector.begin();
            while (boundary != boundaries.end() && semantic != semanticsAsVector.end()) {
              std::vector<std::any> boundaryAsVector = std::any_cast<std::vector<std::any>>(*boundary);
              parseCityJSONGeometry(boundaryAsVector, *semantic, true, semanticSurfaces, nesting-1, object, vertices);
              ++boundary;
              ++semantic;
            }
          }
          
          // Empty vector
          else {
            for (auto boundary: boundaries) {
              std::vector<std::any> boundaryAsVector = std::any_cast<std::vector<std::any>>(boundary);
              std::any empty;
              parseCityJSONGeometry(boundaryAsVector, empty, false, semanticSurfaces, nesting-1, object, vertices);
            }
          }
          
        } catch (const std::bad_any_cast &e) {}

        // Index (that applies to whole list)
        try {
          unsigned long long semanticsAsIndex = std::any_cast<unsigned long long>(semantics);
#pragma unused(semanticsAsIndex)
          for (auto boundary: boundaries) {
            std::vector<std::any> boundaryAsVector = std::any_cast<std::vector<std::any>>(boundary);
            parseCityJSONGeometry(boundaryAsVector, semantics, true, semanticSurfaces, nesting-1, object, vertices);
          }
        } catch (const std::bad_any_cast &e) {}
      }

      // Null
      else {
        for (auto boundary: boundaries) {
          std::vector<std::any> boundaryAsVector = std::any_cast<std::vector<std::any>>(boundary);
          std::any empty;
          parseCityJSONGeometry(boundaryAsVector, empty, false, semanticSurfaces, nesting-1, object, vertices);
        }
      }
    }

    else if (nesting == 1) {
      if (withSemantics) {
        try {
          unsigned long long surfaceIndex = std::any_cast<unsigned long long>(semantics);
          if (surfaceIndex < semanticSurfaces.size()) {
            object.children.push_back(AzulObject());
            for (auto attribute: semanticSurfaces[surfaceIndex]) {
              if (attribute.first == "type") {
                object.children.back().type = attribute.second;
              } else object.children.back().attributes.push_back(std::pair<std::string, std::string>(attribute.first, attribute.second));
            } object.children.back().polygons.push_back(AzulPolygon());
            parseCityJSONPolygon(boundaries, object.children.back().polygons.back(), vertices);
          } else {
            object.polygons.push_back(AzulPolygon());
            parseCityJSONPolygon(boundaries, object.polygons.back(), vertices);
          }
        } catch (const std::bad_any_cast &e) {}
      } else {
        object.polygons.push_back(AzulPolygon());
        parseCityJSONPolygon(boundaries, object.polygons.back(), vertices);
      }
    }
  }

  void parseCityJSONPolygon(std::vector<std::any> &jsonPolygon, AzulPolygon &polygon, std::vector<std::tuple<double, double, double>> &vertices) {
    bool outer = true;
    for (auto ring: jsonPolygon) {
      try {
        std::vector<std::any> jsonRing = std::any_cast<std::vector<std::any>>(ring);
        if (outer) {
          parseCityJSONRing(jsonRing, polygon.exteriorRing, vertices);
          outer = false;
        } else {
          polygon.interiorRings.push_back(AzulRing());
          parseCityJSONRing(jsonRing, polygon.interiorRings.back(), vertices);
        }
      } catch (const std::bad_any_cast &e) {
        std::cout << "Ring is not an array" << std::endl;
      }
    }
  }

  void parseCityJSONRing(std::vector<std::any> &jsonRing, AzulRing &ring, std::vector<std::tuple<double, double, double>> &vertices) {
    for (auto jsonVertex: jsonRing) {
      try {
        unsigned long long vertexIndex = std::any_cast<unsigned long long>(jsonVertex);
        if (vertexIndex < vertices.size()) {
          ring.points.push_back(AzulPoint());
          ring.points.back().coordinates[0] = std::get<0>(vertices[vertexIndex]);
          ring.points.back().coordinates[1] = std::get<1>(vertices[vertexIndex]);
          ring.points.back().coordinates[2] = std::get<2>(vertices[vertexIndex]);
        }
      } catch (const std::bad_any_cast &e) {
        std::cout << "Vertex index is not an integer" << std::endl;
      }
    } ring.points.push_back(ring.points.front());
  }

public:
  std::string statusMessage;
  
  void parse(const char *filePath, AzulObject &parsedFile) {
    simdjson::ondemand::parser parser;
    simdjson::padded_string json;
    simdjson::ondemand::document doc;
    auto error = simdjson::padded_string::load(filePath).get(json);
    if (error) {
      std::cout << "Invalid file" << std::endl;
      return;
    } error = parser.iterate(json).get(doc);
    if (error) {
      std::cout << "Invalid JSON" << std::endl;
      return;
    } parsedFile.type = "File";
    parsedFile.id = filePath;

    // Check what we have
    if (doc.type() != simdjson::ondemand::json_type::object) return;
    for (auto element: doc.get_object()) {
      if (element.key().value().is_equal("type")) {
        docType = element.value().get_string();
      } else if (element.key().value().is_equal("version")) {
        docVersion = element.value().get_string();
      }
    }

    if (docType == "CityJSON") {
      std::cout << docType << " " << docVersion << " detected" << std::endl;
      if (docVersion == "1.0" ||
          docVersion == "1.1" ||
          docVersion == "2.0") {

        simdjson::ondemand::object object;

        // Metadata
        error = doc["metadata"].get(object);
        if (!error) {
          for (auto element: object) {
            std::string_view attributeName = element.unescaped_key();
            if (element.value().type() == simdjson::ondemand::json_type::string) {
              std::string_view attributeValue = element.value().get_string();
              parsedFile.attributes.push_back(std::pair<std::string, std::string>(attributeName, attributeValue));
            } else {
              std::cout << attributeName << " is a complex attribute. Skipped." << std::endl;
            }
          }
        }

        // Transform object
        std::vector<double> scale;
        std::vector<double> translation;
        error = doc["transform"].get(object);
        if (!error) {
          for (auto element: object) {
            if (element.key().value().is_equal("scale")) {
              for (auto axis: element.value()) {
                scale.push_back(axis.get_double().value());
              }
            } else if (element.key().value().is_equal("translate")) {
              for (auto axis: element.value()) {
                translation.push_back(axis.get_double().value());
              }
            }
          } if (scale.size() != 3) {
            scale.clear();
            for (int i = 0; i < 3; ++i) scale.push_back(1.0);
            std::cout << "Transform scale incorrect: set to " << scale[0] << ", " << scale[1] << ", " << scale[2] << std::endl;
          } else std::cout << "Transform scale: " << scale[0] << ", " << scale[1] << ", " << scale[2] << std::endl;
          if (translation.size() != 3) {
            translation.clear();
            for (int i = 0; i < 3; ++i) translation.push_back(0.0);
            std::cout << "Transform translation incorrect: set to " << translation[0] << ", " << translation[1] << ", " << translation[2] << std::endl;
          } else std::cout << "Transform translation: " << translation[0] << ", " << translation[1] << ", " << translation[2] << std::endl;
        } else {
          for (int i = 0; i < 3; ++i) scale.push_back(1.0);
          std::cout << "Transform scale not provided: set to " << scale[0] << ", " << scale[1] << ", " << scale[2] << std::endl;
          for (int i = 0; i < 3; ++i) translation.push_back(0.0);
          std::cout << "Transform translation not provided: set to " << translation[0] << ", " << translation[1] << ", " << translation[2] << std::endl;
        }

        // Geometry templates
        AzulObject geometryTemplates;
        std::vector<std::tuple<double, double, double>> geometryTemplatesVertices;
        error = doc["geometry-templates"].get(object);
        if (!error) {

          // Template vertices
          for (auto vertex: object["vertices-templates"].get_array()) {
            std::vector<double> coordinates;
            for (auto coordinate: vertex) coordinates.push_back(coordinate.get_double().value());
            if (coordinates.size() == 3) geometryTemplatesVertices.push_back(std::tuple<double, double, double>(coordinates[0], coordinates[1], coordinates[2]));
            else {
              std::cout << "Template vertex has " << coordinates.size() << " coordinates" << std::endl;
              geometryTemplatesVertices.push_back(std::tuple<double, double, double>(0, 0, 0));
            }
          }

          // Templates
          for (auto t: object["templates"].get_array()) {
            parseCityJSONObjectGeometry(t.get_object(), geometryTemplates, geometryTemplatesVertices, NULL);
          }
        }

        // Vertices
        std::vector<std::tuple<double, double, double>> vertices;
        for (auto vertex: doc["vertices"].get_array()) {
          std::vector<double> coordinates;
          for (auto coordinate: vertex) coordinates.push_back(coordinate.get_double().value());
          if (coordinates.size() == 3) vertices.push_back(std::tuple<double, double, double>(scale[0]*coordinates[0]+translation[0],
                                                                                             scale[1]*coordinates[1]+translation[1],
                                                                                             scale[2]*coordinates[2]+translation[2]));
          else {
            std::cout << "Vertex has " << coordinates.size() << " coordinates" << std::endl;
            vertices.push_back(std::tuple<double, double, double>(0, 0, 0));
          }
        }

        // CityObjects
        for (auto object: doc["CityObjects"].get_object()) {
          parsedFile.children.push_back(AzulObject());
          std::string_view objectId = object.unescaped_key();
          parsedFile.children.back().id = objectId;
          parseCityJSONObject(object.value().get_object(), parsedFile.children.back(), vertices, &geometryTemplates);
        }

        statusMessage = "Loaded CityJSON " + std::string(docVersion) + " file";
      } else {
        statusMessage = "CityJSON " + std::string(docVersion) + " is not supported";
      }
    } else {
      statusMessage = "JSON files other than CityJSON are not supported";
    }
  }

  void dump(const std::any &any) {
    if (any.has_value()) {
      try {
        std::cout << std::any_cast<unsigned long long>(any);
      } catch (const std::bad_any_cast &e) {}
      try {
        dump(std::any_cast<std::vector<std::any>>(any));
      } catch (const std::bad_any_cast &e) {}
      std::cout << " ";
    } else {
      std::cout << "null ";
    }
  }

  void dump(const std::vector<std::any> &list) {
    std::cout << "[";
    for (auto const &element: list) dump(element);
    std::cout << "]";
  }

  void clearDOM() {
//    json.clear();
  }
};

#endif /* JSONParsingHelper_hpp */
