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

#ifndef JSONParsingHelper_hpp
#define JSONParsingHelper_hpp

#include "DataModel.hpp"
#include "simdjson/jsonparser.h"

class JSONParsingHelper {
  
  void parseCityJSONObject(ParsedJson::iterator &jsonObject, AzulObject &object, std::vector<std::tuple<double, double, double>> &vertices) {
    ParsedJson::iterator currentCityObject(jsonObject);
    if (!currentCityObject.is_object()) return;
    currentCityObject.down();
    
    do {
      if (currentCityObject.get_string_length() == 4 && memcmp(currentCityObject.get_string(), "type", 4) == 0) {
        currentCityObject.next();
        object.type = currentCityObject.get_string();
      }
      
      else if (currentCityObject.get_string_length() == 10 && memcmp(currentCityObject.get_string(), "attributes", 10) == 0) {
        currentCityObject.next();
        ParsedJson::iterator currentAttribute(currentCityObject);
        if (currentAttribute.is_object() && currentAttribute.down()) {
          do {
            const char *attributeName = currentAttribute.get_string();
            currentAttribute.next();
            if (currentAttribute.is_string()) object.attributes.push_back(std::pair<std::string, std::string>(attributeName, currentAttribute.get_string()));
            else if (currentAttribute.is_double()) object.attributes.push_back(std::pair<std::string, std::string>(attributeName, std::to_string(currentAttribute.get_double())));
            else if (currentAttribute.is_integer()) object.attributes.push_back(std::pair<std::string, std::string>(attributeName, std::to_string(currentAttribute.get_integer())));
          } while (currentAttribute.next());
        }
      }
      
      else if (currentCityObject.get_string_length() == 8 && memcmp(currentCityObject.get_string(), "geometry", 8) == 0) {
        currentCityObject.next();
        ParsedJson::iterator currentGeometry(currentCityObject);
        if (currentGeometry.is_array() && currentGeometry.down()) {
          do {
            parseCityJSONObjectGeometry(currentGeometry, object, vertices, geometryTemplates);
          } while (currentGeometry.next());
        }
      }
      
      else currentCityObject.next();
    } while (currentCityObject.next());
  }
  
  void parseCityJSONObjectGeometry(ParsedJson::iterator &currentGeometry, AzulObject &object, std::vector<std::tuple<double, double, double>> &vertices, AzulObject *geometryTemplates) {
    if (currentGeometry.is_object()) {
      ParsedJson::iterator currentGeometryMember(currentGeometry);
      ParsedJson::iterator *boundariesIterator = NULL, *semanticsIterator = NULL;
      std::vector<std::map<std::string, std::string>> semanticSurfaces;
      std::string geometryType, geometryLod;
      std::size_t templateIndex = 0;
      std::vector<double> transformationMatrix;
      if (currentGeometryMember.down()) {
        do {
          if (currentGeometryMember.get_string_length() == 4 && memcmp(currentGeometryMember.get_string(), "type", 4) == 0) {
            currentGeometryMember.next();
            if (currentGeometryMember.is_string()) geometryType = currentGeometryMember.get_string();
          } else if (currentGeometryMember.get_string_length() == 3 && memcmp(currentGeometryMember.get_string(), "lod", 3) == 0) {
            currentGeometryMember.next();
            if (currentGeometryMember.is_string()) geometryLod = currentGeometryMember.get_string();
            else if (currentGeometryMember.is_double()) geometryLod = std::to_string(currentGeometryMember.get_double());
            else if (currentGeometryMember.is_integer()) geometryLod = std::to_string(currentGeometryMember.get_integer());
          } else if (currentGeometryMember.get_string_length() == 10 && memcmp(currentGeometryMember.get_string(), "boundaries", 10) == 0) {
            currentGeometryMember.next();
            boundariesIterator = new ParsedJson::iterator(currentGeometryMember);
          } else if (currentGeometryMember.get_string_length() == 9 && memcmp(currentGeometryMember.get_string(), "semantics", 9) == 0) {
            currentGeometryMember.next();
            ParsedJson::iterator currentSemantics(currentGeometryMember);
            if (currentSemantics.is_object() && currentSemantics.down()) {
              do {
                if (currentSemantics.get_string_length() == 8 && memcmp(currentSemantics.get_string(), "surfaces", 8) == 0) {
                  currentSemantics.next();
                  ParsedJson::iterator currentSemanticSurface(currentSemantics);
                  if (currentSemanticSurface.is_array() && currentSemanticSurface.down()) {
                    do {
                      semanticSurfaces.push_back(std::map<std::string, std::string>());
                      ParsedJson::iterator currentAttribute(currentSemanticSurface);
                      if (currentAttribute.is_object() && currentAttribute.down()) {
                        do {
                          if (currentAttribute.is_string()) {
                            const char *attributeName = currentAttribute.get_string();
                            currentAttribute.next();
                            if (currentAttribute.is_string()) semanticSurfaces.back()[attributeName] = currentAttribute.get_string();
                            else if (currentAttribute.is_double()) semanticSurfaces.back()[attributeName] = std::to_string(currentAttribute.get_double());
                            else if (currentAttribute.is_integer()) semanticSurfaces.back()[attributeName] = std::to_string(currentAttribute.get_integer());
                          } else currentAttribute.next();
                        } while (currentAttribute.next());
                      }
                    } while (currentSemanticSurface.next());
                  }
                } else if (currentSemantics.get_string_length() == 6 && memcmp(currentSemantics.get_string(), "values", 6) == 0) {
                  currentSemantics.next();
                  semanticsIterator = new ParsedJson::iterator(currentSemantics);
                } else currentSemantics.next();
              } while (currentSemantics.next());
            }
          } else if (currentGeometryMember.get_string_length() == 8 && memcmp(currentGeometryMember.get_string(), "template", 8) == 0) {
            currentGeometryMember.next();
            if (currentGeometryMember.is_integer()) templateIndex = currentGeometryMember.get_integer();
          } else if (currentGeometryMember.get_string_length() == 20 &&
                     memcmp(currentGeometryMember.get_string(), "transformationMatrix", 20) == 0) {
            currentGeometryMember.next();
            ParsedJson::iterator currentValue(currentGeometryMember);
            if (currentValue.is_array() && currentValue.down()) {
              do {
                if (currentValue.is_double()) transformationMatrix.push_back(currentValue.get_double());
                else if (currentValue.is_integer()) transformationMatrix.push_back(currentValue.get_integer());
              } while (currentValue.next());
            }
          } else currentGeometryMember.next();
        } while (currentGeometryMember.next());
      }
      
      if (!geometryType.empty() && boundariesIterator != NULL) {
        
        if (strcmp(geometryType.c_str(), "MultiSurface") == 0 ||
            strcmp(geometryType.c_str(), "CompositeSurface") == 0) {
          object.children.push_back(AzulObject());
          object.children.back().type = "LoD";
          object.children.back().id = geometryLod;
          parseCityJSONGeometry(boundariesIterator, semanticsIterator, semanticSurfaces, 2, object.children.back(), vertices);
        }
        
        else if (strcmp(geometryType.c_str(), "Solid") == 0) {
          object.children.push_back(AzulObject());
          object.children.back().type = "LoD";
          object.children.back().id = geometryLod;
          parseCityJSONGeometry(boundariesIterator, semanticsIterator, semanticSurfaces, 3, object.children.back(), vertices);
        }
        
        else if (strcmp(geometryType.c_str(), "MultiSolid") == 0 ||
                 strcmp(geometryType.c_str(), "CompositeSolid") == 0) {
          object.children.push_back(AzulObject());
          object.children.back().type = "LoD";
          object.children.back().id = geometryLod;
          parseCityJSONGeometry(boundariesIterator, semanticsIterator, semanticSurfaces, 4, object.children.back(), vertices);
        }
        
        else if (strcmp(geometryType.c_str(), "GeometryInstance") == 0) {
          if (geometryTemplates != NULL && templateIndex < geometryTemplates->children.size() && boundariesIterator != NULL && boundariesIterator->is_array() && boundariesIterator->down() && transformationMatrix.size() == 16) {
            std::size_t anchorPoint = 0;
            if (boundariesIterator->is_double()) anchorPoint = boundariesIterator->get_double();
            else if (boundariesIterator->is_integer()) anchorPoint = boundariesIterator->get_integer();
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
      
      if (boundariesIterator != NULL) delete boundariesIterator;
      if (semanticsIterator != NULL) delete semanticsIterator;
    }
  }
  
  void parseCityJSONGeometry(ParsedJson::iterator *jsonBoundaries, ParsedJson::iterator *jsonSemantics, std::vector<std::map<std::string, std::string>> &semanticSurfaces, int nesting, AzulObject &object, std::vector<std::tuple<double, double, double>> &vertices) {
//    std::cout << "jsonBoundaries: ";
//    dump(*jsonBoundaries);
//    std::cout << std::endl;
//    std::cout << "jsonSemantics: ";
//    dump(*jsonSemantics);
//    std::cout << std::endl;
//    std::cout << "semanticSurfaces: ";
//    dump(semanticSurfaces);
//    std::cout << std::endl;
//    std::cout << "nesting: " << nesting << std::endl;
    if (jsonBoundaries == NULL) return;
    
    if (nesting > 1) {
      ParsedJson::iterator currentBoundary(*jsonBoundaries);
      if (!currentBoundary.is_array() || !currentBoundary.down()) return;
      if (jsonSemantics != NULL && jsonSemantics->is_array()) {
        ParsedJson::iterator currentSemantics(*jsonSemantics);
        if (currentSemantics.down()) {
          do {
            parseCityJSONGeometry(&currentBoundary, &currentSemantics, semanticSurfaces, nesting-1, object, vertices);
            if (!currentBoundary.next()) break;
            if (!currentSemantics.next()) break;
          } while (true);
        } else {
          do {
            parseCityJSONGeometry(&currentBoundary, NULL, semanticSurfaces, nesting-1, object, vertices);
          } while (currentBoundary.next());
        }
      } else {
        do {
          parseCityJSONGeometry(&currentBoundary, NULL, semanticSurfaces, nesting-1, object, vertices);
        } while (currentBoundary.next());
      }
    }
    
    else if (nesting == 1) {
      ParsedJson::iterator currentBoundary(*jsonBoundaries);
      if (jsonSemantics != NULL && jsonSemantics->is_integer()) {
        if (jsonSemantics->is_integer() && jsonSemantics->get_integer() < semanticSurfaces.size()) {
          object.children.push_back(AzulObject());
          for (auto const &attribute: semanticSurfaces[jsonSemantics->get_integer()]) {
            if (strcmp(attribute.first.c_str(), "type") == 0) {
//              std::cout << attribute.first << ": " << attribute.second << std::endl;
              object.children.back().type = attribute.second;
            } else object.children.back().attributes.push_back(std::pair<std::string, std::string>(attribute.first, attribute.second));
          } object.children.back().polygons.push_back(AzulPolygon());
          parseCityJSONPolygon(currentBoundary, object.children.back().polygons.back(), vertices);
        } else {
          object.polygons.push_back(AzulPolygon());
          parseCityJSONPolygon(currentBoundary, object.polygons.back(), vertices);
        }
      } else {
        object.polygons.push_back(AzulPolygon());
        parseCityJSONPolygon(currentBoundary, object.polygons.back(), vertices);
      }
    }
  }

  void parseCityJSONPolygon(ParsedJson::iterator &jsonPolygon, AzulPolygon &polygon, std::vector<std::tuple<double, double, double>> &vertices) {
    bool outer = true;
    ParsedJson::iterator jsonRing(jsonPolygon);
    if (jsonRing.is_array() && jsonRing.down()) {
      do {
        if (outer) {
          parseCityJSONRing(jsonRing, polygon.exteriorRing, vertices);
          outer = false;
        } else {
          polygon.interiorRings.push_back(AzulRing());
          parseCityJSONRing(jsonRing, polygon.interiorRings.back(), vertices);
        }
      } while (jsonRing.next());
    }
  }

  void parseCityJSONRing(ParsedJson::iterator &jsonRing, AzulRing &ring, std::vector<std::tuple<double, double, double>> &vertices) {
    ParsedJson::iterator jsonVertex(jsonRing);
    if (jsonVertex.is_array() && jsonVertex.down()) {
      do {
        if (jsonVertex.is_integer() && jsonVertex.get_integer() < vertices.size()) {
          ring.points.push_back(AzulPoint());
          ring.points.back().coordinates[0] = std::get<0>(vertices[jsonVertex.get_integer()]);
          ring.points.back().coordinates[1] = std::get<1>(vertices[jsonVertex.get_integer()]);
          ring.points.back().coordinates[2] = std::get<2>(vertices[jsonVertex.get_integer()]);
        }
      } while (jsonVertex.next());
      ring.points.push_back(ring.points.front());
    }
  }

public:
  void parse(const char *filePath, AzulObject &parsedFile) {
    ParsedJson parsedJson = build_parsed_json(get_corpus(filePath));
    if(!parsedJson.isValid()) {
      std::cout << "Invalid JSON file" << std::endl;
      return;
    } parsedFile.type = "File";
    parsedFile.id = filePath;
    
    const char *docType;
    const char *docVersion;
    
    // Check what we have
    ParsedJson::iterator iterator(parsedJson);
    ParsedJson::iterator *verticesIterator = NULL, *cityObjectsIterator = NULL, *metadataIterator = NULL, *geometryTemplatesIterator = NULL;
    if (!iterator.is_object() || !iterator.down()) return;
    do {
      if (iterator.get_string_length() == 4 && memcmp(iterator.get_string(), "type", 4) == 0) {
        iterator.next();
        docType = iterator.get_string();
      } else if (iterator.get_string_length() == 7 && memcmp(iterator.get_string(), "version", 7) == 0) {
        iterator.next();
        docVersion = iterator.get_string();
      } else if (iterator.get_string_length() == 10 && memcmp(iterator.get_string(), "extensions", 10) == 0) {
        iterator.next();
      } else if (iterator.get_string_length() == 8 && memcmp(iterator.get_string(), "metadata", 8) == 0) {
        iterator.next();
        metadataIterator = new ParsedJson::iterator(iterator);
      } else if (iterator.get_string_length() == 9 && memcmp(iterator.get_string(), "transform", 9) == 0) {
        iterator.next();
      } else if (iterator.get_string_length() == 11 && memcmp(iterator.get_string(), "CityObjects", 11) == 0) {
        iterator.next();
        cityObjectsIterator = new ParsedJson::iterator(iterator);
      } else if (iterator.get_string_length() == 8 && memcmp(iterator.get_string(), "vertices", 8) == 0) {
        iterator.next();
        verticesIterator = new ParsedJson::iterator(iterator);
      } else if (iterator.get_string_length() == 10 && memcmp(iterator.get_string(), "appearance", 10) == 0) {
        iterator.next();
      } else if (iterator.get_string_length() == 18 && memcmp(iterator.get_string(), "geometry-templates", 18) == 0) {
        iterator.next();
        geometryTemplatesIterator = new ParsedJson::iterator(iterator);
      }
    } while (iterator.next());
    
    if (strcmp(docType, "CityJSON") == 0) {
      std::cout << docType << " " << docVersion << " detected" << std::endl;
      if (strcmp(docVersion, "1.0") == 0) {
        
        // Metadata
        if (metadataIterator != NULL && metadataIterator->is_object() && metadataIterator->down()) {
          do {
            const char *attributeName = metadataIterator->get_string();
            metadataIterator->next();
            if (metadataIterator->is_string()) {
              const char *attributeValue = metadataIterator->get_string();
              parsedFile.attributes.push_back(std::pair<std::string, std::string>(attributeName, attributeValue));
            } else {
              std::cout << attributeName << " is a complex attribute. Skipped." << std::endl;
            }
          } while (metadataIterator->next());
        }
        
        // Transform object
        std::vector<double> scale;
        std::vector<double> translation;
        if (transformIterator != NULL && transformIterator->is_object() && transformIterator->down()) {
          do {
            if (transformIterator->get_string_length() == 5 && memcmp(transformIterator->get_string(), "scale", 5) == 0) {
              transformIterator->next();
              if (transformIterator->is_array() && transformIterator->down()) {
                do {
                  if (transformIterator->is_double()) scale.push_back(transformIterator->get_double());
                  else if (transformIterator->is_integer()) scale.push_back(transformIterator->get_integer());
                } while (transformIterator->next());
                transformIterator->up();
              }
            } else if (transformIterator->get_string_length() == 9 && memcmp(transformIterator->get_string(), "translate", 9) == 0) {
              transformIterator->next();
              if (transformIterator->is_array() && transformIterator->down()) {
                do {
                  if (transformIterator->is_double()) translation.push_back(transformIterator->get_double());
                  else if (transformIterator->is_integer()) translation.push_back(transformIterator->get_integer());
                } while (transformIterator->next());
                transformIterator->up();
              }
            } else transformIterator->next();
          } while (transformIterator->next());
        } if (scale.size() != 3) {
          scale.clear();
          for (int i = 0; i < 3; ++i) scale.push_back(1.0);
        } if (translation.size() != 3) {
          translation.clear();
          for (int i = 0; i < 3; ++i) scale.push_back(0.0);
        }
//        std::cout << "Scale: (" << scale[0] << ", " << scale[1] << ", " << scale[2] << ")" << std::endl;
//        std::cout << "Translation: (" << translation[0] << ", " << translation[1] << ", " << translation[2] << ")" << std::endl;
        
        // Geometry templates
        std::vector<AzulObject> geometryTemplates;
        std::vector<std::tuple<double, double, double>> geometryTemplatesVertices;
        if (geometryTemplatesIterator != NULL && geometryTemplatesIterator->is_object() && geometryTemplatesIterator->down()) {
          ParsedJson::iterator *templatesIterator = NULL, *templatesVerticesIterator = NULL;
          do {
            if (geometryTemplatesIterator->get_string_length() == 9 && memcmp(geometryTemplatesIterator->get_string(), "templates", 9) == 0) {
              geometryTemplatesIterator->next();
              templatesIterator = new ParsedJson::iterator(*geometryTemplatesIterator);
            } else if (geometryTemplatesIterator->get_string_length() == 18 &&
                       memcmp(geometryTemplatesIterator->get_string(), "vertices-templates", 18) == 0) {
              geometryTemplatesIterator->next();
              templatesVerticesIterator = new ParsedJson::iterator(*geometryTemplatesIterator);
            } else geometryTemplatesIterator->next();
          } while (geometryTemplatesIterator->next());

          // Template vertices
          if (templatesVerticesIterator != NULL && templatesVerticesIterator->is_array() && templatesVerticesIterator->down()) {
            do {
              ParsedJson::iterator currentVertex(*templatesVerticesIterator);
              if (currentVertex.is_array()) {
                currentVertex.down();
                double x, y, z;
                if (currentVertex.is_double()) x = currentVertex.get_double();
                else if (currentVertex.is_integer()) x = currentVertex.get_integer();
                else continue;
                if (!currentVertex.next()) continue;
                if (currentVertex.is_double()) y = currentVertex.get_double();
                else if (currentVertex.is_integer()) y = currentVertex.get_integer();
                else continue;
                if (!currentVertex.next()) continue;
                if (currentVertex.is_double()) z = currentVertex.get_double();
                else if (currentVertex.is_integer()) z = currentVertex.get_integer();
                else continue;
                geometryTemplatesVertices.push_back(std::tuple<double, double, double>(x, y, z));
              }
            } while (templatesVerticesIterator->next());
          }

          // Templates
          if (templatesIterator != NULL && templatesIterator->is_array() && templatesIterator->down()) {
            do {
              geometryTemplates.push_back(AzulObject());
              parseCityJSONObject(*templatesIterator, geometryTemplates.back(), geometryTemplatesVertices);
            } while (templatesIterator->next());
//            std::cout << "Parsed " << geometryTemplates.size() << " templates" << std::endl;
          }

          if (templatesIterator != NULL) delete templatesIterator;
          if (templatesVerticesIterator != NULL) delete templatesVerticesIterator;
        }
        
        // Vertices
        std::vector<std::tuple<double, double, double>> vertices;
        if (verticesIterator != NULL && verticesIterator->is_array() && verticesIterator->down()) {
          do {
            ParsedJson::iterator currentVertex(*verticesIterator);
            if (currentVertex.is_array()) {
              currentVertex.down();
              double x, y, z;
              if (currentVertex.is_double()) x = currentVertex.get_double();
              else if (currentVertex.is_integer()) x = currentVertex.get_integer();
              else continue;
              x = scale[0]*x+translation[0];
              if (!currentVertex.next()) continue;
              if (currentVertex.is_double()) y = currentVertex.get_double();
              else if (currentVertex.is_integer()) y = currentVertex.get_integer();
              else continue;
              y = scale[1]*y+translation[1];
              if (!currentVertex.next()) continue;
              if (currentVertex.is_double()) z = currentVertex.get_double();
              else if (currentVertex.is_integer()) z = currentVertex.get_integer();
              else continue;
              z = scale[2]*z+translation[2];
              vertices.push_back(std::tuple<double, double, double>(x, y, z));
              //          std::cout << "Parsed (" << x << ", " << y << ", " << z << ")" << std::endl;
            }
          } while (verticesIterator->next());
        }
        
        // CityObjects
        if (cityObjectsIterator != NULL && cityObjectsIterator->is_object() && cityObjectsIterator->down()) {
          do {
            parsedFile.children.push_back(AzulObject());
            const char *objectId = cityObjectsIterator->get_string();
            parsedFile.children.back().id = objectId;
            cityObjectsIterator->next();
            parseCityJSONObject(*cityObjectsIterator, parsedFile.children.back(), vertices);
          } while (cityObjectsIterator->next());
        }

      } else {
        std::cout << "Unsupported version" << std::endl;
      }
    }

    if (verticesIterator != NULL) delete verticesIterator;
    if (cityObjectsIterator != NULL) delete cityObjectsIterator;
    if (metadataIterator != NULL) delete metadataIterator;
    if (geometryTemplatesIterator != NULL) delete geometryTemplatesIterator;
    if (transformIterator != NULL) delete transformIterator;
  }
  
  void dump(ParsedJson::iterator &iterator) {
    if (iterator.is_string()) std::cout << iterator.get_string();
    else if (iterator.is_integer()) std::cout << iterator.get_integer();
    else if (iterator.is_double()) std::cout << iterator.get_double();
    else if (iterator.is_array()) {
      std::cout << "[";
      if (iterator.down()) {
        dump(iterator);
        while (iterator.next()) {
          std::cout << ",";
          dump(iterator);
        } iterator.up();
      } std::cout << "]";
    } else if (iterator.is_object()) {
      std::cout << "{";
      if (iterator.down()) {
        std::cout << iterator.get_string();
        std::cout << ":";
        iterator.next();
        dump(iterator);
        while (iterator.next()) {
          std::cout << ",";
          std::cout << iterator.get_string();
          std::cout << ":";
          iterator.next();
          dump(iterator);
        } iterator.up();
      } std::cout << "}";
    }
  }
  
  void dump(const std::vector<std::map<std::string, std::string>> &semanticSurfaces) {
    std::cout << "[";
    for (auto const &surface: semanticSurfaces) {
      std::cout << "{";
      for (auto const &attribute: surface) {
        std::cout << attribute.first << ":" << attribute.second;
      } std::cout << "}";
    } std::cout << "]";
  }
  
  void dump(const AzulObject &object) {
    std::cout << "AzulObject(";
    std::cout << "type=" << object.type;
    std::cout << ",id=" << object.id;
    std::cout << ",selected=";
    if (object.selected) std::cout << "true";
    else std::cout << "false";
    std::cout << ",visible=" << object.visible;
    std::cout << ",matchesSearch=" << object.matchesSearch;
    std::cout << ",attributes=";
    for (auto const &attribute: object.attributes) std::cout << "<" << attribute.first << "," << attribute.second << ">";
    std::cout << ",children[" << object.children.size() << "]=";
    for (auto const &child: object.children) dump(child);
    std::cout << ",polygons[" << object.polygons.size() << "]";
    std::cout << ",triangles[" << object.triangles.size() << "]";
    std::cout << ")";
  }
  
  void clearDOM() {
//    json.clear();
  }
};

#endif /* JSONParsingHelper_hpp */
