// azul
// Copyright © 2016-2024 Ken Arroyo Ohori
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

#ifndef JSONLinesParsingHelper_hpp
#define JSONLinesParsingHelper_hpp

#include "JSONParsingHelper.hpp"

class JSONLinesParsingHelper : public JSONParsingHelper {
  std::string_view lineType;
  std::string cityJsonVersion;
public:
  void parse(const char *filePath, AzulObject &parsedFile) {
    
    std::ifstream inputStream(filePath);
    std::string line;
    getline(inputStream, line);
    simdjson::ondemand::parser parser;
    simdjson::padded_string json(line);
    simdjson::ondemand::document doc;
    auto error = parser.iterate(json).get(doc);
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
        cityJsonVersion = docVersion;
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
        
        while (getline(inputStream, line)) {
          json = simdjson::padded_string(line);
          auto error = parser.iterate(json).get(doc);
          if (error) {
            std::cout << "Invalid JSON" << std::endl;
            continue;
          }
          
          // Check what we have
          if (doc.type() != simdjson::ondemand::json_type::object) return;
          for (auto element: doc.get_object()) {
            if (element.key().value().is_equal("type")) {
              lineType = element.value().get_string();
            }
          }
          
          if (lineType == "CityJSONFeature") {
            
            // Vertices
            std::vector<std::tuple<double, double, double>> lineVertices;
            for (auto vertex: doc["vertices"].get_array()) {
              std::cout << vertex << std::endl;
              std::vector<double> coordinates;
//              for (auto coordinate: vertex) std::cout << coordinate << std::endl;
//              for (auto coordinate: vertex) coordinates.push_back(coordinate.get_double().value());
//              if (coordinates.size() == 3) lineVertices.push_back(std::tuple<double, double, double>(scale[0]*coordinates[0]+translation[0],
//                                                                                                     scale[1]*coordinates[1]+translation[1],
//                                                                                                     scale[2]*coordinates[2]+translation[2]));
//              else {
//                std::cout << "Vertex has " << coordinates.size() << " coordinates" << std::endl;
//                vertices.push_back(std::tuple<double, double, double>(0, 0, 0));
//              }
            }

//            // CityObjects
//            for (auto object: doc["CityObjects"].get_object()) {
//              parsedFile.children.push_back(AzulObject());
//              std::string_view objectId = object.unescaped_key();
//              parsedFile.children.back().id = objectId;
//              parseCityJSONObject(object.value().get_object(), parsedFile.children.back(), vertices, &geometryTemplates);
//            }
            
          } else {
            std::cout << "Found a line that isn't a CityJSONFeature";
          }
          
        }
        
        statusMessage = "Loaded CityJSON " + cityJsonVersion + " file";
      } else {
        statusMessage = "CityJSON " + std::string(docVersion) + " is not supported";
      }
    } else {
      statusMessage = "JSON files other than CityJSON are not supported";
    }
    
  }
};

#endif /* JSONParsingHelper_hpp */
