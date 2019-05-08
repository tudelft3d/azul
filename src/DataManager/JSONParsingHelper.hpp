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
#include "json.hpp"

class JSONParsingHelper {
  nlohmann::json json;
  
  void parseCityJSONObject(nlohmann::json::const_iterator &jsonObject, AzulObject &object, std::vector<std::vector<double>> &vertices) {
    
    object.id = jsonObject.key();
    //  std::cout << "ID: " << object.id << std::endl;
    object.type = jsonObject.value()["type"];
    //  std::cout << "Type: " << object.type << std::endl;
    
    for (auto const &geometry: jsonObject.value()["geometry"]) {
//      std::cout << "Geometry: " << geometry.dump(2) << std::endl;
      
      if (geometry["type"] == "MultiSurface" || geometry["type"] == "CompositeSurface") {
//        std::cout << "Surfaces: " << geometry["boundaries"].dump() << std::endl;
        for (unsigned int surfaceIndex = 0; surfaceIndex < geometry["boundaries"].size(); ++surfaceIndex) {
//          std::cout << "Surface: " << geometry["boundaries"][surfaceIndex].dump() << std::endl;
          std::vector<std::vector<std::size_t>> surface = geometry["boundaries"][surfaceIndex];
          std::string surfaceType;
          if (geometry.count("semantics")) {
//            std::cout << "Surface semantics: " << geometry["semantics"] << std::endl;
            if (geometry["semantics"]["values"].size() > surfaceIndex &&
                !geometry["semantics"]["values"][surfaceIndex].is_null()) {
              std::size_t semanticSurfaceIndex = geometry["semantics"]["values"][surfaceIndex];
              auto const &surfaceSemantics = geometry["semantics"]["surfaces"][semanticSurfaceIndex];
              surfaceType = surfaceSemantics["type"];
              std::cout << "Surface type: " << surfaceType << std::endl;
              AzulObject newChild;
              newChild.type = surfaceType;
              AzulPolygon newPolygon;
              parseCityJSONPolygon(surface, newPolygon, vertices);
              newChild.polygons.push_back(newPolygon);
              object.children.push_back(newChild);
            } else {
              AzulPolygon newPolygon;
              parseCityJSONPolygon(surface, newPolygon, vertices);
              object.polygons.push_back(newPolygon);
            }
          } else {
            AzulPolygon newPolygon;
            parseCityJSONPolygon(surface, newPolygon, vertices);
            object.polygons.push_back(newPolygon);
          }
        }
      }
      
      else if (geometry["type"] == "Solid") {
//        std::cout << "Shells: " << geometry["boundaries"].dump() << std::endl;
        for (unsigned int shellIndex = 0; shellIndex < geometry["boundaries"].size(); ++shellIndex) {
//          std::cout << "Shell: " << geometry["boundaries"][shellIndex].dump() << std::endl;
          for (unsigned int surfaceIndex = 0; surfaceIndex < geometry["boundaries"][shellIndex].size(); ++surfaceIndex) {
//            std::cout << "Surface: " << geometry["boundaries"][shellIndex][surfaceIndex].dump() << std::endl;
            std::vector<std::vector<std::size_t>> surface = geometry["boundaries"][shellIndex][surfaceIndex];
            std::string surfaceType;
            if (geometry.count("semantics")) {
//              std::cout << "Surface semantics: " << geometry["semantics"] << std::endl;
              if (geometry["semantics"]["values"].size() > shellIndex &&
                  !geometry["semantics"]["values"][shellIndex].is_null()) {
                if (geometry["semantics"]["values"][shellIndex].size() > surfaceIndex &&
                    !geometry["semantics"]["values"][shellIndex][surfaceIndex].is_null()) {
                  std::size_t semanticSurfaceIndex = geometry["semantics"]["values"][shellIndex][surfaceIndex];
                  auto const &surfaceSemantics = geometry["semantics"]["surfaces"][semanticSurfaceIndex];
                  surfaceType = surfaceSemantics["type"];
                  std::cout << "Surface type: " << surfaceType << std::endl;
                  AzulObject newChild;
                  newChild.type = surfaceType;
                  AzulPolygon newPolygon;
                  parseCityJSONPolygon(surface, newPolygon, vertices);
                  newChild.polygons.push_back(newPolygon);
                  object.children.push_back(newChild);
                } else {
                  AzulPolygon newPolygon;
                  parseCityJSONPolygon(surface, newPolygon, vertices);
                  object.polygons.push_back(newPolygon);
                }
              } else {
                AzulPolygon newPolygon;
                parseCityJSONPolygon(surface, newPolygon, vertices);
                object.polygons.push_back(newPolygon);
              }
            } else {
              AzulPolygon newPolygon;
              parseCityJSONPolygon(surface, newPolygon, vertices);
              object.polygons.push_back(newPolygon);
            }
          }
        }
      }
      
      else if (geometry["type"] == "MultiSolid" || geometry["type"] == "CompositeSolid") {
//        std::cout << "Solids: " << geometry["boundaries"].dump() << std::endl;
        for (unsigned int solidIndex = 0; solidIndex < geometry["boundaries"].size(); ++solidIndex) {
//          std::cout << "Shells: " << geometry["boundaries"][solidIndex].dump() << std::endl;
          for (unsigned int shellIndex = 0; shellIndex < geometry["boundaries"][solidIndex].size(); ++shellIndex) {
//            std::cout << "Shell: " << geometry["boundaries"][solidIndex][shellIndex].dump() << std::endl;
            for (unsigned int surfaceIndex = 0; surfaceIndex < geometry["boundaries"][solidIndex][shellIndex].size(); ++surfaceIndex) {
//              std::cout << "Surface: " << geometry["boundaries"][solidIndex][shellIndex][surfaceIndex].dump() << std::endl;
              std::vector<std::vector<std::size_t>> surface = geometry["boundaries"][solidIndex][shellIndex][surfaceIndex];
              std::string surfaceType;
              if (geometry.count("semantics")) {
//                std::cout << "Surface semantics: " << geometry["semantics"] << std::endl;
                if (geometry["semantics"]["values"].size() > solidIndex &&
                    !geometry["semantics"]["values"][solidIndex].is_null()) {
                  if (geometry["semantics"]["values"].size() > shellIndex &&
                      !geometry["semantics"]["values"][solidIndex][shellIndex].is_null()) {
                    if (geometry["semantics"]["values"][solidIndex][shellIndex].size() > surfaceIndex &&
                        !geometry["semantics"]["values"][solidIndex][shellIndex][surfaceIndex].is_null()) {
                      std::size_t semanticSurfaceIndex = geometry["semantics"]["values"][solidIndex][shellIndex][surfaceIndex];
                      auto const &surfaceSemantics = geometry["semantics"]["surfaces"][semanticSurfaceIndex];
                      surfaceType = surfaceSemantics["type"];
                      std::cout << "Surface type: " << surfaceType << std::endl;
                      AzulObject newChild;
                      newChild.type = surfaceType;
                      AzulPolygon newPolygon;
                      parseCityJSONPolygon(surface, newPolygon, vertices);
                      newChild.polygons.push_back(newPolygon);
                      object.children.push_back(newChild);
                    } else {
                      AzulPolygon newPolygon;
                      parseCityJSONPolygon(surface, newPolygon, vertices);
                      object.polygons.push_back(newPolygon);
                    }
                  } else {
                    AzulPolygon newPolygon;
                    parseCityJSONPolygon(surface, newPolygon, vertices);
                    object.polygons.push_back(newPolygon);
                  }
                } else {
                  AzulPolygon newPolygon;
                  parseCityJSONPolygon(surface, newPolygon, vertices);
                  object.polygons.push_back(newPolygon);
                }
              } else {
                AzulPolygon newPolygon;
                parseCityJSONPolygon(surface, newPolygon, vertices);
                object.polygons.push_back(newPolygon);
              }
            }
          }
        }
      }
      
      else {
        std::cout << "Unsupported geometry: " << geometry["type"] << std::endl;
      }
    }
  }
  
  void parseCityJSONPolygon(const std::vector<std::vector<std::size_t>> &jsonPolygon, AzulPolygon &polygon, std::vector<std::vector<double>> &vertices) {
    bool outer = true;
    for (auto const &ring: jsonPolygon) {
      if (outer) {
        parseCityJSONRing(ring, polygon.exteriorRing, vertices);
        outer = false;
      } else {
        polygon.interiorRings.push_back(AzulRing());
        parseCityJSONRing(ring, polygon.interiorRings.back(), vertices);
      }
    }
  }
  
  void parseCityJSONRing(const std::vector<std::size_t> &jsonRing, AzulRing &ring, std::vector<std::vector<double>> &vertices) {
    for (auto const &point: jsonRing) {
      ring.points.push_back(AzulPoint());
      for (int dimension = 0; dimension < 3; ++dimension) ring.points.back().coordinates[dimension] = vertices[point][dimension];
    } ring.points.push_back(ring.points.front());
  }

public:
  void parse(const char *filePath, AzulObject &parsedFile) {
    
    std::ifstream inputStream(filePath);
    inputStream >> json;
    parsedFile.type = "File";
    parsedFile.id = filePath;
    
    std::vector<std::vector<double>> vertices = json["vertices"];
    for (nlohmann::json::const_iterator cityObject = json["CityObjects"].begin();
         cityObject != json["CityObjects"].end();
         ++cityObject) {
      parsedFile.children.push_back(AzulObject());
      parseCityJSONObject(cityObject, parsedFile.children.back(), vertices);
    }
  }
  
  void clearDOM() {
    json.clear();
  }
};

#endif /* JSONParsingHelper_hpp */
