// azul
// Copyright © 2016-2026 Ken Arroyo Ohori
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
  std::vector<double> scale;
  std::vector<double> translation;
  AzulObject geometryTemplates;
  AppearanceContext rootAppearanceContext;
public:
  void parse(const char *filePath, AzulObject &parsedFile) {
    try {

      simdjson::padded_string json;
      auto error = simdjson::padded_string::load(filePath).get(json);
      if (error) {
        std::cout << "Failed to load file: " << simdjson::error_message(error) << std::endl;
        return;
      }
      simdjson::dom::parser parser;
      simdjson::dom::document_stream docs;
      error = parser.parse_many(json, json.size()).get(docs);
      if (error) {
        std::cout << "parse_many failed: " << simdjson::error_message(error) << std::endl;
        return;
      }
      parsedFile.type = "File";
      parsedFile.id = filePath;
      currentFilePath = filePath;
      deferredParentRelationships.clear();
      resetAppearanceForNewFile();
      rootAppearanceContext.clear();
      scale.clear();
      translation.clear();
      geometryTemplates = AzulObject();

      for (auto doc: docs) {

        // Check what we have
        if (!doc.is_object()) return;
        simdjson::dom::element typeElement;
        simdjson::dom::element versionElement;
        if (doc["type"].get(typeElement) == simdjson::SUCCESS && typeElement.is_string()) {
          docType = typeElement.get_string().value();
        }
        if (doc["version"].get(versionElement) == simdjson::SUCCESS && versionElement.is_string()) {
          docVersion = versionElement.get_string().value();
        }

        if (docType == "CityJSON") {
          std::cout << docType << " " << docVersion << " detected" << std::endl;
          if (docVersion == "1.0" ||
              docVersion == "1.1" ||
              docVersion == "2.0") {

            // Metadata
            simdjson::dom::element metadataElement;
            if (doc["metadata"].get(metadataElement) == simdjson::SUCCESS && metadataElement.is_object()) {
              for (auto element: metadataElement.get_object()) {
                std::string_view attributeName = element.key;
                simdjson::dom::element attributeValueElement = element.value;
                if (attributeValueElement.is_string()) {
                  std::string_view attributeValue = attributeValueElement.get_string().value();
                  parsedFile.attributes.push_back(std::pair<std::string, std::string>(attributeName, attributeValue));
                } else {
                  std::cout << attributeName << " is a complex attribute. Skipped." << std::endl;
                }
              }
            }

            // Appearance object
            simdjson::dom::element appearanceElement;
            if (doc["appearance"].get(appearanceElement) == simdjson::SUCCESS) {
              parseAppearanceObject(appearanceElement);
              rootAppearanceContext = currentAppearanceContext();
            } else {
              rootAppearanceContext.clear();
            }

            // Transform object
            simdjson::dom::element transformElement;
            if (doc["transform"].get(transformElement) == simdjson::SUCCESS && transformElement.is_object()) {
              simdjson::dom::object transformObject = transformElement.get_object();
              simdjson::dom::element scaleElement;
              if (transformObject["scale"].get(scaleElement) == simdjson::SUCCESS && scaleElement.is_array()) {
                for (auto axis: scaleElement.get_array()) {
                  scale.push_back(axis.get_double());
                }
              }
              simdjson::dom::element translateElement;
              if (transformObject["translate"].get(translateElement) == simdjson::SUCCESS && translateElement.is_array()) {
                for (auto axis: translateElement.get_array()) {
                  translation.push_back(axis.get_double());
                }
              }
              if (scale.size() != 3) {
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
            std::vector<std::tuple<double, double, double>> geometryTemplatesVertices;
            simdjson::dom::element templatesElement;
            if (doc["geometry-templates"].get(templatesElement) == simdjson::SUCCESS && templatesElement.is_object()) {
              simdjson::dom::object templatesObject = templatesElement.get_object();

              // Template vertices
              simdjson::dom::element templateVerticesElement;
              if (templatesObject["vertices-templates"].get(templateVerticesElement) == simdjson::SUCCESS && templateVerticesElement.is_array()) {
                for (auto vertex: templateVerticesElement.get_array()) {
                  simdjson::dom::array vertexArray;
                  if (!vertex.is_array()) continue;
                  vertexArray = vertex.get_array();
                  double coordinates[3] = {0.0, 0.0, 0.0};
                  if (vertexArray.size() >= 3) {
                    coordinates[0] = vertexArray.at(0).get_double();
                    coordinates[1] = vertexArray.at(1).get_double();
                    coordinates[2] = vertexArray.at(2).get_double();
                  } else {
                    std::cout << "Template vertex has " << vertexArray.size() << " coordinates" << std::endl;
                  }
                  geometryTemplatesVertices.emplace_back(coordinates[0], coordinates[1], coordinates[2]);
                }
              }

              // Templates
              simdjson::dom::element templatesArrayElement;
              if (templatesObject["templates"].get(templatesArrayElement) == simdjson::SUCCESS && templatesArrayElement.is_array()) {
                for (auto t: templatesArrayElement.get_array()) {
                  parseCityJSONObjectGeometry(t, geometryTemplates, geometryTemplatesVertices, NULL);
                }
              }
            }

            // Vertices
            std::vector<std::tuple<double, double, double>> vertices;
            simdjson::dom::element verticesElement;
            if (doc["vertices"].get(verticesElement) == simdjson::SUCCESS && verticesElement.is_array()) {
              simdjson::dom::array verticesArray = verticesElement.get_array();
              vertices.reserve(verticesArray.size());
              for (auto vertex: verticesArray) {
                if (!vertex.is_array()) continue;
                simdjson::dom::array vertexArray = vertex.get_array();
                double coordinates[3] = {0.0, 0.0, 0.0};
                if (vertexArray.size() >= 3) {
                  coordinates[0] = vertexArray.at(0).get_double();
                  coordinates[1] = vertexArray.at(1).get_double();
                  coordinates[2] = vertexArray.at(2).get_double();
                } else {
                  std::cout << "Vertex has " << vertexArray.size() << " coordinates" << std::endl;
                }
                vertices.emplace_back(scale[0]*coordinates[0]+translation[0],
                                      scale[1]*coordinates[1]+translation[1],
                                      scale[2]*coordinates[2]+translation[2]);
              }
            }

            // CityObjects
            simdjson::dom::element cityObjectsElement;
            if (doc["CityObjects"].get(cityObjectsElement) == simdjson::SUCCESS && cityObjectsElement.is_object()) {
              simdjson::dom::object cityObjects = cityObjectsElement.get_object();
              parsedFile.children.reserve(cityObjects.size());
              for (auto object: cityObjects) {
                std::string_view objectId = object.key;
                parsedFile.children.push_back(AzulObject());
                parsedFile.children.back().id = objectId;
                parseCityJSONObject(object.value.get_object(), parsedFile.children.back(), parsedFile.children.size() - 1, vertices, &geometryTemplates);
              }
            }

            statusMessage = "Loaded CityJSON " + std::string(docVersion) + " file";
          } else {
            statusMessage = "CityJSON " + std::string(docVersion) + " is not supported";
          }
        }

        else if (docType == "CityJSONFeature") {
          AppearanceContext featureAppearanceContext = rootAppearanceContext;
          simdjson::dom::element featureAppearanceElement;
          if (doc["appearance"].get(featureAppearanceElement) == simdjson::SUCCESS) {
            parseAppearanceObjectInto(featureAppearanceElement, featureAppearanceContext);
          }
          setAppearanceContext(featureAppearanceContext);

          // Vertices
          std::vector<std::tuple<double, double, double>> vertices;
          simdjson::dom::element verticesElement;
          if (doc["vertices"].get(verticesElement) == simdjson::SUCCESS && verticesElement.is_array()) {
            simdjson::dom::array verticesArray = verticesElement.get_array();
            vertices.reserve(verticesArray.size());
            for (auto vertex: verticesArray) {
              if (!vertex.is_array()) continue;
              simdjson::dom::array vertexArray = vertex.get_array();
              double coordinates[3] = {0.0, 0.0, 0.0};
              if (vertexArray.size() >= 3) {
                coordinates[0] = vertexArray.at(0).get_double();
                coordinates[1] = vertexArray.at(1).get_double();
                coordinates[2] = vertexArray.at(2).get_double();
              } else {
                std::cout << "Vertex has " << vertexArray.size() << " coordinates" << std::endl;
              }
              vertices.emplace_back(scale[0]*coordinates[0]+translation[0],
                                    scale[1]*coordinates[1]+translation[1],
                                    scale[2]*coordinates[2]+translation[2]);
            }
          }

          // CityObjects
          simdjson::dom::element cityObjectsElement;
          if (doc["CityObjects"].get(cityObjectsElement) == simdjson::SUCCESS && cityObjectsElement.is_object()) {
            simdjson::dom::object cityObjects = cityObjectsElement.get_object();
            for (auto object: cityObjects) {
              std::string_view objectId = object.key;
              parsedFile.children.push_back(AzulObject());
              parsedFile.children.back().id = objectId;
              parseCityJSONObject(object.value.get_object(), parsedFile.children.back(), parsedFile.children.size() - 1, vertices, &geometryTemplates);
            }
          }

        }

        else {
          std::cout << "Found a line that isn't a CityJSONFeature";
        }

      }
      buildHierarchy(parsedFile);
      finalizeAppearanceForFile(parsedFile);

    } catch (simdjson::simdjson_error &e) {
      std::cout << "simdjson error: " << e.what() << std::endl;
      parsedFile.type = "File";
      parsedFile.id = filePath;
    }
  }
};

#endif /* JSONLinesParsingHelper_hpp */
