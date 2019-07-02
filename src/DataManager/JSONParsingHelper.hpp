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

  void parseCityJSONObject(ParsedJson &parsedJson, AzulObject &object) {
    
//    object.id = jsonObject.key();
//    //  std::cout << "ID: " << object.id << std::endl;
//    object.type = jsonObject.value()["type"];
//    //  std::cout << "Type: " << object.type << std::endl;
//
//    for (auto const &geometry: jsonObject.value()["geometry"]) {
////      std::cout << "Geometry: " << geometry.dump(2) << std::endl;
//
//      if (geometry["type"] == "MultiSurface" || geometry["type"] == "CompositeSurface") {
////        std::cout << "Surfaces: " << geometry["boundaries"].dump() << std::endl;
//        for (unsigned int surfaceIndex = 0; surfaceIndex < geometry["boundaries"].size(); ++surfaceIndex) {
////          std::cout << "Surface: " << geometry["boundaries"][surfaceIndex].dump() << std::endl;
//          std::vector<std::vector<std::size_t>> surface = geometry["boundaries"][surfaceIndex];
//          std::string surfaceType;
//          if (geometry.count("semantics")) {
////            std::cout << "Surface semantics: " << geometry["semantics"] << std::endl;
//            if (geometry["semantics"]["values"].size() > surfaceIndex &&
//                !geometry["semantics"]["values"][surfaceIndex].is_null()) {
//              std::size_t semanticSurfaceIndex = geometry["semantics"]["values"][surfaceIndex];
//              auto const &surfaceSemantics = geometry["semantics"]["surfaces"][semanticSurfaceIndex];
//              surfaceType = surfaceSemantics["type"];
//              std::cout << "Surface type: " << surfaceType << std::endl;
//              AzulObject newChild;
//              newChild.type = surfaceType;
//              AzulPolygon newPolygon;
//              parseCityJSONPolygon(surface, newPolygon, vertices);
//              newChild.polygons.push_back(newPolygon);
//              object.children.push_back(newChild);
//            } else {
//              AzulPolygon newPolygon;
//              parseCityJSONPolygon(surface, newPolygon, vertices);
//              object.polygons.push_back(newPolygon);
//            }
//          } else {
//            AzulPolygon newPolygon;
//            parseCityJSONPolygon(surface, newPolygon, vertices);
//            object.polygons.push_back(newPolygon);
//          }
//        }
//      }
//
//      else if (geometry["type"] == "Solid") {
////        std::cout << "Shells: " << geometry["boundaries"].dump() << std::endl;
//        for (unsigned int shellIndex = 0; shellIndex < geometry["boundaries"].size(); ++shellIndex) {
////          std::cout << "Shell: " << geometry["boundaries"][shellIndex].dump() << std::endl;
//          for (unsigned int surfaceIndex = 0; surfaceIndex < geometry["boundaries"][shellIndex].size(); ++surfaceIndex) {
////            std::cout << "Surface: " << geometry["boundaries"][shellIndex][surfaceIndex].dump() << std::endl;
//            std::vector<std::vector<std::size_t>> surface = geometry["boundaries"][shellIndex][surfaceIndex];
//            std::string surfaceType;
//            if (geometry.count("semantics")) {
////              std::cout << "Surface semantics: " << geometry["semantics"] << std::endl;
//              if (geometry["semantics"]["values"].size() > shellIndex &&
//                  !geometry["semantics"]["values"][shellIndex].is_null()) {
//                if (geometry["semantics"]["values"][shellIndex].size() > surfaceIndex &&
//                    !geometry["semantics"]["values"][shellIndex][surfaceIndex].is_null()) {
//                  std::size_t semanticSurfaceIndex = geometry["semantics"]["values"][shellIndex][surfaceIndex];
//                  auto const &surfaceSemantics = geometry["semantics"]["surfaces"][semanticSurfaceIndex];
//                  surfaceType = surfaceSemantics["type"];
//                  std::cout << "Surface type: " << surfaceType << std::endl;
//                  AzulObject newChild;
//                  newChild.type = surfaceType;
//                  AzulPolygon newPolygon;
//                  parseCityJSONPolygon(surface, newPolygon, vertices);
//                  newChild.polygons.push_back(newPolygon);
//                  object.children.push_back(newChild);
//                } else {
//                  AzulPolygon newPolygon;
//                  parseCityJSONPolygon(surface, newPolygon, vertices);
//                  object.polygons.push_back(newPolygon);
//                }
//              } else {
//                AzulPolygon newPolygon;
//                parseCityJSONPolygon(surface, newPolygon, vertices);
//                object.polygons.push_back(newPolygon);
//              }
//            } else {
//              AzulPolygon newPolygon;
//              parseCityJSONPolygon(surface, newPolygon, vertices);
//              object.polygons.push_back(newPolygon);
//            }
//          }
//        }
//      }
//
//      else if (geometry["type"] == "MultiSolid" || geometry["type"] == "CompositeSolid") {
////        std::cout << "Solids: " << geometry["boundaries"].dump() << std::endl;
//        for (unsigned int solidIndex = 0; solidIndex < geometry["boundaries"].size(); ++solidIndex) {
////          std::cout << "Shells: " << geometry["boundaries"][solidIndex].dump() << std::endl;
//          for (unsigned int shellIndex = 0; shellIndex < geometry["boundaries"][solidIndex].size(); ++shellIndex) {
////            std::cout << "Shell: " << geometry["boundaries"][solidIndex][shellIndex].dump() << std::endl;
//            for (unsigned int surfaceIndex = 0; surfaceIndex < geometry["boundaries"][solidIndex][shellIndex].size(); ++surfaceIndex) {
////              std::cout << "Surface: " << geometry["boundaries"][solidIndex][shellIndex][surfaceIndex].dump() << std::endl;
//              std::vector<std::vector<std::size_t>> surface = geometry["boundaries"][solidIndex][shellIndex][surfaceIndex];
//              std::string surfaceType;
//              if (geometry.count("semantics")) {
////                std::cout << "Surface semantics: " << geometry["semantics"] << std::endl;
//                if (geometry["semantics"]["values"].size() > solidIndex &&
//                    !geometry["semantics"]["values"][solidIndex].is_null()) {
//                  if (geometry["semantics"]["values"].size() > shellIndex &&
//                      !geometry["semantics"]["values"][solidIndex][shellIndex].is_null()) {
//                    if (geometry["semantics"]["values"][solidIndex][shellIndex].size() > surfaceIndex &&
//                        !geometry["semantics"]["values"][solidIndex][shellIndex][surfaceIndex].is_null()) {
//                      std::size_t semanticSurfaceIndex = geometry["semantics"]["values"][solidIndex][shellIndex][surfaceIndex];
//                      auto const &surfaceSemantics = geometry["semantics"]["surfaces"][semanticSurfaceIndex];
//                      surfaceType = surfaceSemantics["type"];
//                      std::cout << "Surface type: " << surfaceType << std::endl;
//                      AzulObject newChild;
//                      newChild.type = surfaceType;
//                      AzulPolygon newPolygon;
//                      parseCityJSONPolygon(surface, newPolygon, vertices);
//                      newChild.polygons.push_back(newPolygon);
//                      object.children.push_back(newChild);
//                    } else {
//                      AzulPolygon newPolygon;
//                      parseCityJSONPolygon(surface, newPolygon, vertices);
//                      object.polygons.push_back(newPolygon);
//                    }
//                  } else {
//                    AzulPolygon newPolygon;
//                    parseCityJSONPolygon(surface, newPolygon, vertices);
//                    object.polygons.push_back(newPolygon);
//                  }
//                } else {
//                  AzulPolygon newPolygon;
//                  parseCityJSONPolygon(surface, newPolygon, vertices);
//                  object.polygons.push_back(newPolygon);
//                }
//              } else {
//                AzulPolygon newPolygon;
//                parseCityJSONPolygon(surface, newPolygon, vertices);
//                object.polygons.push_back(newPolygon);
//              }
//            }
//          }
//        }
//      }
//
//      else {
//        std::cout << "Unsupported geometry: " << geometry["type"] << std::endl;
//      }
//    }
//
////    for (auto const &attribute: jsonObject.value()["attributes"]) {
////      object.attributes.append(std::pair<std::string, std::string>(attribute.k,));
////    }
  }
//
//  void parseCityJSONPolygon(const std::vector<std::vector<std::size_t>> &jsonPolygon, AzulPolygon &polygon, std::vector<std::vector<double>> &vertices) {
//    bool outer = true;
//    for (auto const &ring: jsonPolygon) {
//      if (outer) {
//        parseCityJSONRing(ring, polygon.exteriorRing, vertices);
//        outer = false;
//      } else {
//        polygon.interiorRings.push_back(AzulRing());
//        parseCityJSONRing(ring, polygon.interiorRings.back(), vertices);
//      }
//    }
//  }
//
//  void parseCityJSONRing(const std::vector<std::size_t> &jsonRing, AzulRing &ring, std::vector<std::vector<double>> &vertices) {
//    for (auto const &point: jsonRing) {
//      ring.points.push_back(AzulPoint());
//      for (int dimension = 0; dimension < 3; ++dimension) ring.points.back().coordinates[dimension] = vertices[point][dimension];
//    } ring.points.push_back(ring.points.front());
//  }

public:
  void parse(const char *filePath, AzulObject &parsedFile) {
    ParsedJson parsedJson = build_parsed_json(get_corpus(filePath));
    if(!parsedJson.isValid()) {
      std::cout << "Invalid JSON file" << std::endl;
    } else {
      parsedFile.type = "File";
      parsedFile.id = filePath;
      parseCityJSONObject(parsedJson, parsedFile);
    }
    
    std::string docType;
    std::string docVersion;
    
    // Check what we have
    ParsedJson::iterator iterator(parsedJson);
    ParsedJson::iterator *verticesIterator = NULL, *cityObjectsIterator = NULL, *metadataIterator = NULL;
    if (!iterator.is_object()) return;
    if (!iterator.down()) return;
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
      } else {
//        std::cout << "Unknown type: ";
//        iterator.print(std::cout);
//        std::cout << "=";
//        iterator.next();
//        iterator.print(std::cout);
//        std::cout << std::endl;
      }
    } while (iterator.next());
    
    if (strcmp(docType.c_str(), "CityJSON") != 0) return;
    std::cout << docType << " " << docVersion << " detected" << std::endl;
    if (strcmp(docVersion.c_str(), "1.0") != 0) return;
    
    if (metadataIterator != NULL && metadataIterator->is_object() && metadataIterator->down()) {
      do {
        
      } while (metadataIterator->next());
    }
  }
  
  void clearDOM() {
//    json.clear();
  }
};

#endif /* JSONParsingHelper_hpp */
