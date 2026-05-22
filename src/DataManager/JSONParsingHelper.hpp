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

#ifndef JSONParsingHelper_hpp
#define JSONParsingHelper_hpp

#include <algorithm>
#include <any>
#include <array>
#include <cstdint>
#include <filesystem>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <unordered_map>

#include "AppearanceHelpers.hpp"
#include "DataModel.hpp"
#include "simdjson.h"

class JSONParsingHelper {
protected:
  struct ParsedMaterial {
    bool hasDiffuseColor;
    float diffuseColor[3];
    bool hasTransparency;
    float transparency;
    ParsedMaterial() {
      hasDiffuseColor = false;
      hasTransparency = false;
      transparency = 0.0f;
      diffuseColor[0] = 0.0f;
      diffuseColor[1] = 0.0f;
      diffuseColor[2] = 0.0f;
    }
  };

  struct AppearanceContext {
    std::vector<ParsedMaterial> materials;
    std::vector<std::string> textures;
    std::vector<std::array<float, 2>> textureVertices;
    std::string defaultThemeTexture;
    std::string defaultThemeMaterial;
    void clear() {
      materials.clear();
      textures.clear();
      textureVertices.clear();
      defaultThemeTexture.clear();
      defaultThemeMaterial.clear();
    }
  };

  std::string_view docType;
  std::string_view docVersion;
  std::vector<std::pair<std::string, size_t>> deferredParentRelationships;
  AppearanceContext appearanceContext;
  std::vector<AzulAppearanceStyle> stylePool;
  std::unordered_map<std::string, int> styleIdByKey;
  std::set<std::string> parsedThemes;
  std::string currentFilePath;

  int addOrGetStyleId(const AzulAppearanceStyle &style) {
    std::string key = appearanceStyleKey(style);
    auto found = styleIdByKey.find(key);
    if (found != styleIdByKey.end()) return found->second;
    stylePool.push_back(style);
    int newId = static_cast<int>(stylePool.size()-1);
    styleIdByKey[key] = newId;
    return newId;
  }

  void resetAppearanceForNewFile() {
    appearanceContext.clear();
    stylePool.clear();
    styleIdByKey.clear();
    parsedThemes.clear();
  }

  void finalizeAppearanceForFile(AzulObject &parsedFile) {
    parsedFile.appearanceStyles = stylePool;
    parsedFile.appearanceThemes.assign(parsedThemes.begin(), parsedThemes.end());
  }

  bool anyToIndex(const std::any &value, unsigned long long &index) const {
    try {
      index = std::any_cast<unsigned long long>(value);
      return true;
    } catch (const std::bad_any_cast &) {
      return false;
    }
  }

  bool anyToVector(const std::any &value, std::vector<std::any> &vectorValue) const {
    try {
      vectorValue = std::any_cast<std::vector<std::any>>(value);
      return true;
    } catch (const std::bad_any_cast &) {
      return false;
    }
  }

  void parseAppearanceObjectInto(simdjson::ondemand::object appearanceObject, AppearanceContext &targetContext) {
    targetContext.clear();

    simdjson::ondemand::array materialsArray;
    if (!appearanceObject["materials"].get_array().get(materialsArray)) {
      for (auto materialValue: materialsArray) {
        ParsedMaterial parsedMaterial;
        simdjson::ondemand::object materialObject;
        if (materialValue.get_object().get(materialObject)) {
          targetContext.materials.push_back(parsedMaterial);
          continue;
        }
        simdjson::ondemand::array diffuseArray;
        if (!materialObject["diffuseColor"].get_array().get(diffuseArray)) {
          int component = 0;
          for (auto current: diffuseArray) {
            if (component >= 3) break;
            parsedMaterial.diffuseColor[component] = static_cast<float>(current.get_double().value());
            ++component;
          }
          if (component == 3) parsedMaterial.hasDiffuseColor = true;
        }
        simdjson::ondemand::value transparencyValue;
        if (!materialObject["transparency"].get(transparencyValue) &&
            transparencyValue.type() == simdjson::ondemand::json_type::number) {
          parsedMaterial.transparency = static_cast<float>(transparencyValue.get_double().value());
          parsedMaterial.hasTransparency = true;
        }
        targetContext.materials.push_back(parsedMaterial);
      }
    }

    simdjson::ondemand::array texturesArray;
    if (!appearanceObject["textures"].get_array().get(texturesArray)) {
      for (auto textureValue: texturesArray) {
        std::string textureUri;
        simdjson::ondemand::object textureObject;
        if (!textureValue.get_object().get(textureObject)) {
          simdjson::ondemand::value imageValue;
          if (!textureObject["image"].get(imageValue) &&
              imageValue.type() == simdjson::ondemand::json_type::string) {
            textureUri = resolveImageUri(std::string(imageValue.get_string().value()), currentFilePath);
          }
        }
        targetContext.textures.push_back(textureUri);
      }
    }

    simdjson::ondemand::array textureVerticesArray;
    if (!appearanceObject["vertices-texture"].get_array().get(textureVerticesArray)) {
      for (auto uvVertex: textureVerticesArray) {
        simdjson::ondemand::array uvArray;
        if (uvVertex.get_array().get(uvArray)) continue;
        std::array<float, 2> uv = {0.0f, 0.0f};
        int component = 0;
        for (auto coordinate: uvArray) {
          if (component >= 2) break;
          uv[component] = static_cast<float>(coordinate.get_double().value());
          ++component;
        }
        if (component == 2) targetContext.textureVertices.push_back(uv);
      }
    }

    simdjson::ondemand::value defaultMaterialThemeValue;
    if (!appearanceObject["default-theme-material"].get(defaultMaterialThemeValue) &&
        defaultMaterialThemeValue.type() == simdjson::ondemand::json_type::string) {
      targetContext.defaultThemeMaterial = std::string(defaultMaterialThemeValue.get_string().value());
    }
    simdjson::ondemand::value defaultTextureThemeValue;
    if (!appearanceObject["default-theme-texture"].get(defaultTextureThemeValue) &&
        defaultTextureThemeValue.type() == simdjson::ondemand::json_type::string) {
      targetContext.defaultThemeTexture = std::string(defaultTextureThemeValue.get_string().value());
    }
  }

  void parseAppearanceObject(simdjson::ondemand::object appearanceObject) {
    parseAppearanceObjectInto(appearanceObject, appearanceContext);
  }

  AppearanceContext currentAppearanceContext() const {
    return appearanceContext;
  }

  void setAppearanceContext(const AppearanceContext &newContext) {
    appearanceContext = newContext;
  }

  void parseThemeAssignments(simdjson::ondemand::object themedObject, const std::string &preferredTheme, std::any &values, std::string &theme) {
    bool hasFallback = false;
    std::any fallbackValues;
    std::string fallbackTheme;

    for (auto themedValue: themedObject) {
      std::string currentTheme = std::string(themedValue.unescaped_key().value());
      simdjson::ondemand::object assignmentObject;
      if (themedValue.value().get_object().get(assignmentObject)) continue;

      bool hasValues = false;
      std::any parsedValues;
      simdjson::ondemand::array nestedValuesArray;
      if (!assignmentObject["values"].get_array().get(nestedValuesArray)) {
        std::vector<std::any> nestedValues;
        parseNestedArray(nestedValuesArray, nestedValues);
        parsedValues = nestedValues;
        hasValues = true;
      } else {
        simdjson::ondemand::value singleValue;
        if (!assignmentObject["value"].get(singleValue)) {
          if (singleValue.type() == simdjson::ondemand::json_type::number) {
            parsedValues = static_cast<unsigned long long>(singleValue.get_uint64().value());
            hasValues = true;
          } else if (singleValue.type() == simdjson::ondemand::json_type::null) {
            parsedValues.reset();
            hasValues = true;
          }
        }
      }
      if (!hasValues) continue;

      if (!hasFallback) {
        fallbackTheme = currentTheme;
        fallbackValues = parsedValues;
        hasFallback = true;
      }
      if (!preferredTheme.empty() && currentTheme == preferredTheme) {
        theme = currentTheme;
        values = parsedValues;
        return;
      }
    }

    if (hasFallback) {
      theme = fallbackTheme;
      values = fallbackValues;
    }
  }

  void parseGeometryAppearanceAssignments(simdjson::ondemand::object currentGeometry,
                                          std::any &materialValues,
                                          std::string &materialTheme,
                                          std::any &textureValues,
                                          std::string &textureTheme) {
    simdjson::ondemand::object materialObject;
    if (!currentGeometry["material"].get_object().get(materialObject)) {
      parseThemeAssignments(materialObject, appearanceContext.defaultThemeMaterial, materialValues, materialTheme);
    }

    simdjson::ondemand::object textureObject;
    if (!currentGeometry["texture"].get_object().get(textureObject)) {
      parseThemeAssignments(textureObject, appearanceContext.defaultThemeTexture, textureValues, textureTheme);
    }
  }

  void applyTextureCoordinatesToRing(const std::vector<std::any> &ringAssignment, AzulRing &ring) {
    if (ringAssignment.size() < 2 || ring.points.empty()) return;
    std::vector<unsigned long long> textureVertexIndices;
    textureVertexIndices.reserve(ringAssignment.size()-1);
    for (std::size_t i = 1; i < ringAssignment.size(); ++i) {
      unsigned long long textureVertexIndex = 0;
      if (!anyToIndex(ringAssignment[i], textureVertexIndex) || textureVertexIndex >= appearanceContext.textureVertices.size()) {
        return;
      }
      textureVertexIndices.push_back(textureVertexIndex);
    }

    std::size_t ringPointCount = ring.points.size();
    bool closedRing = false;
    if (ringPointCount >= 2 &&
        ring.points.front().coordinates[0] == ring.points.back().coordinates[0] &&
        ring.points.front().coordinates[1] == ring.points.back().coordinates[1] &&
        ring.points.front().coordinates[2] == ring.points.back().coordinates[2]) {
      closedRing = true;
    }
    std::size_t expectedPointCount = closedRing && ringPointCount > 0 ? ringPointCount-1 : ringPointCount;

    if (textureVertexIndices.size() != expectedPointCount && textureVertexIndices.size() != ringPointCount) return;

    ring.textureCoordinates.clear();
    if (textureVertexIndices.size() == expectedPointCount) {
      for (std::size_t i = 0; i < expectedPointCount; ++i) {
        ring.textureCoordinates.push_back(appearanceContext.textureVertices[textureVertexIndices[i]]);
      }
      if (closedRing && !ring.textureCoordinates.empty()) ring.textureCoordinates.push_back(ring.textureCoordinates.front());
    } else {
      for (auto textureVertexIndex: textureVertexIndices) {
        ring.textureCoordinates.push_back(appearanceContext.textureVertices[textureVertexIndex]);
      }
    }
    ring.hasTextureCoordinates = !ring.textureCoordinates.empty();
  }

  bool parseTextureRingAssignment(const std::any &ringAny,
                                  AzulRing *targetRing,
                                  bool collectTextureOnly,
                                  unsigned long long &textureIndexOut,
                                  bool &hasTextureOut) {
    std::vector<std::any> ringAssignment;
    if (!anyToVector(ringAny, ringAssignment) || ringAssignment.empty()) return false;

    unsigned long long textureIndex = 0;
    if (!anyToIndex(ringAssignment.front(), textureIndex)) return false;
    if (textureIndex >= appearanceContext.textures.size()) return false;
    hasTextureOut = true;
    textureIndexOut = textureIndex;
    if (!collectTextureOnly && targetRing != nullptr) applyTextureCoordinatesToRing(ringAssignment, *targetRing);
    return true;
  }

  int buildStyleForPolygon(AzulPolygon &polygon,
                           const std::any &materialAssignment,
                           const std::string &materialTheme,
                           const std::any &textureAssignment,
                           const std::string &textureTheme) {
    AzulAppearanceStyle style;
    bool hasStyle = false;

    unsigned long long materialIndex = 0;
    if (!materialTheme.empty() && anyToIndex(materialAssignment, materialIndex) && materialIndex < appearanceContext.materials.size()) {
      const ParsedMaterial &parsedMaterial = appearanceContext.materials[materialIndex];
      style.hasMaterial = true;
      style.materialColour[0] = parsedMaterial.hasDiffuseColor ? parsedMaterial.diffuseColor[0] : 0.75f;
      style.materialColour[1] = parsedMaterial.hasDiffuseColor ? parsedMaterial.diffuseColor[1] : 0.75f;
      style.materialColour[2] = parsedMaterial.hasDiffuseColor ? parsedMaterial.diffuseColor[2] : 0.75f;
      float transparency = parsedMaterial.hasTransparency ? parsedMaterial.transparency : 0.0f;
      if (transparency < 0.0f) transparency = 0.0f;
      if (transparency > 1.0f) transparency = 1.0f;
      style.materialColour[3] = 1.0f-transparency;
      hasStyle = true;
    }

    unsigned long long textureIndex = 0;
    bool hasTexture = false;
    bool appliedExteriorTexture = false;

    std::vector<std::any> textureAsVector;
    if (!textureTheme.empty() && anyToVector(textureAssignment, textureAsVector) && !textureAsVector.empty()) {
      std::vector<std::any> firstAsVector;
      if (anyToVector(textureAsVector.front(), firstAsVector)) {
        std::size_t ringIndex = 0;
        for (auto const &ringAssignment: textureAsVector) {
          AzulRing *targetRing = nullptr;
          if (ringIndex == 0) targetRing = &polygon.exteriorRing;
          else if (ringIndex-1 < polygon.interiorRings.size()) targetRing = &polygon.interiorRings[ringIndex-1];
          bool localHasTexture = false;
          unsigned long long localTextureIndex = 0;
          bool assignmentApplied = parseTextureRingAssignment(ringAssignment, targetRing, false, localTextureIndex, localHasTexture);
          if (assignmentApplied && localHasTexture) {
            hasTexture = true;
            textureIndex = localTextureIndex;
            if (ringIndex == 0) appliedExteriorTexture = true;
          }
          ++ringIndex;
        }
      } else {
        bool localHasTexture = false;
        unsigned long long localTextureIndex = 0;
        if (parseTextureRingAssignment(textureAssignment, &polygon.exteriorRing, false, localTextureIndex, localHasTexture) && localHasTexture) {
          hasTexture = true;
          textureIndex = localTextureIndex;
          appliedExteriorTexture = true;
        }
      }
    }

    if (hasTexture && textureIndex < appearanceContext.textures.size()) {
      style.hasTexture = true;
      style.textureUri = appearanceContext.textures[textureIndex];
      hasStyle = true;
    }

    if (!appliedExteriorTexture) polygon.exteriorRing.hasTextureCoordinates = false;
    for (auto &ring: polygon.interiorRings) {
      if (!ring.hasTextureCoordinates) ring.textureCoordinates.clear();
    }

    if (!hasStyle) return -1;
    if (style.hasTexture && !textureTheme.empty()) style.theme = textureTheme;
    else if (style.hasMaterial && !materialTheme.empty()) style.theme = materialTheme;
    if (!style.theme.empty()) parsedThemes.insert(style.theme);
    return addOrGetStyleId(style);
  }
  
  void parseCityJSONObject(simdjson::ondemand::object jsonObject, AzulObject &object, size_t childIdx, std::vector<std::tuple<double, double, double>> &vertices, AzulObject *geometryTemplates) {

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
    {
      simdjson::ondemand::object attributesObject;
      if (!jsonObject["attributes"].get(attributesObject)) {
        for (auto attribute: attributesObject) {
          simdjson::ondemand::value attrValue = attribute.value();
          switch (attrValue.type()) {
            case simdjson::ondemand::json_type::string:
              object.attributes.push_back(std::pair<std::string, std::string>(attribute.unescaped_key().value(), attrValue.get_string().value()));
              break;
            case simdjson::ondemand::json_type::number:
              object.attributes.push_back(std::pair<std::string, std::string>(attribute.unescaped_key().value(), std::to_string(attrValue.get_double())));
              break;
            case simdjson::ondemand::json_type::boolean:
              if (attrValue.get_bool() == true) object.attributes.push_back(std::pair<std::string, std::string>(attribute.unescaped_key().value(), "true"));
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
      }
    }
//    std::cout << "\tattributes:" << std::endl;
//    for (const auto &attribute: object.attributes) {
//      std::cout << "\t\t" << attribute.first << ": " << attribute.second << std::endl;
//    }
    
    // Parents (optional)
    {
      simdjson::ondemand::array parents;
      if (!jsonObject["parents"].get(parents)) {
        for (auto parent: parents) {
          deferredParentRelationships.emplace_back(std::string(parent.get_string().value()), childIdx);
        }
      }
    }

    // TODO: geographicalExtent
  }

  void parseCityJSONObjectGeometry(simdjson::ondemand::object currentGeometry, AzulObject &object, std::vector<std::tuple<double, double, double>> &vertices, AzulObject *geometryTemplates) {
    std::vector<std::map<std::string_view, std::string_view>> semanticSurfaces;
    std::string geometryType, geometryLod;
    std::vector<double> transformationMatrix;
    std::any materialAssignments;
    std::any textureAssignments;
    std::string materialTheme;
    std::string textureTheme;
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
          simdjson::ondemand::value attrValue = attribute.value();
          switch (attrValue.type()) {
            case simdjson::ondemand::json_type::string:
              semanticSurfaces.back()[attribute.unescaped_key().value()] = attrValue.get_string().value();
              break;
            case simdjson::ondemand::json_type::number:
              semanticSurfaces.back()[attribute.unescaped_key().value()] = std::to_string(attrValue.get_double());
              break;
            case simdjson::ondemand::json_type::boolean:
              if (attrValue.get_bool() == true) semanticSurfaces.back()[attribute.unescaped_key().value()] = "true";
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
    parseGeometryAppearanceAssignments(currentGeometry, materialAssignments, materialTheme, textureAssignments, textureTheme);

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
        parseCityJSONGeometry(boundaries, semanticsAsAny, materialAssignments, materialTheme, textureAssignments, textureTheme, withSemantics, semanticSurfaces, 2, object.children.back(), vertices);
      }

      else if (geometryType == "Solid") {
        object.children.push_back(AzulObject());
        object.children.back().type = "LoD";
        object.children.back().id = geometryLod;
        parseCityJSONGeometry(boundaries, semanticsAsAny, materialAssignments, materialTheme, textureAssignments, textureTheme, withSemantics, semanticSurfaces, 3, object.children.back(), vertices);
      }

      else if (geometryType == "MultiSolid" ||
               geometryType == "CompositeSolid") {
        object.children.push_back(AzulObject());
        object.children.back().type = "LoD";
        object.children.back().id = geometryLod;
        parseCityJSONGeometry(boundaries, semanticsAsAny, materialAssignments, materialTheme, textureAssignments, textureTheme, withSemantics, semanticSurfaces, 4, object.children.back(), vertices);
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

  void parseCityJSONGeometry(std::vector<std::any> &boundaries,
                             std::any &semantics,
                             std::any &materialAssignments,
                             const std::string &materialTheme,
                             std::any &textureAssignments,
                             const std::string &textureTheme,
                             bool withSemantics,
                             std::vector<std::map<std::string_view, std::string_view>> &semanticSurfaces,
                             int nesting,
                             AzulObject &object,
                             std::vector<std::tuple<double, double, double>> &vertices) {

//    std::cout << "nesting: " << nesting << std::endl;
//    std::cout << "boundaries: "; dump(boundaries); std::cout << std::endl;
//    std::cout << "semantics: "; dump(semantics); std::cout << std::endl;

    if (nesting > 1) {
      std::vector<std::any> semanticsAsVector;
      std::vector<std::any> materialsAsVector;
      std::vector<std::any> texturesAsVector;
      bool hasSemanticsVector = anyToVector(semantics, semanticsAsVector);
      bool hasMaterialsVector = anyToVector(materialAssignments, materialsAsVector);
      bool hasTexturesVector = anyToVector(textureAssignments, texturesAsVector);

      for (std::size_t boundaryIndex = 0; boundaryIndex < boundaries.size(); ++boundaryIndex) {
        std::vector<std::any> boundaryAsVector;
        if (!anyToVector(boundaries[boundaryIndex], boundaryAsVector)) continue;

        std::any childSemantics;
        std::any childMaterials;
        std::any childTextures;
        if (hasSemanticsVector) {
          if (boundaryIndex < semanticsAsVector.size()) childSemantics = semanticsAsVector[boundaryIndex];
        } else if (semantics.has_value()) {
          childSemantics = semantics;
        }
        if (hasMaterialsVector) {
          if (boundaryIndex < materialsAsVector.size()) childMaterials = materialsAsVector[boundaryIndex];
        } else if (materialAssignments.has_value()) {
          childMaterials = materialAssignments;
        }
        if (hasTexturesVector) {
          if (boundaryIndex < texturesAsVector.size()) childTextures = texturesAsVector[boundaryIndex];
        } else if (textureAssignments.has_value()) {
          childTextures = textureAssignments;
        }

        bool childWithSemantics = withSemantics && childSemantics.has_value();
        parseCityJSONGeometry(boundaryAsVector,
                              childSemantics,
                              childMaterials,
                              materialTheme,
                              childTextures,
                              textureTheme,
                              childWithSemantics,
                              semanticSurfaces,
                              nesting-1,
                              object,
                              vertices);
      }
    } else if (nesting == 1) {
      AzulObject *targetObject = &object;
      unsigned long long surfaceIndex = 0;
      if (withSemantics && anyToIndex(semantics, surfaceIndex) && surfaceIndex < semanticSurfaces.size()) {
        object.children.push_back(AzulObject());
        targetObject = &object.children.back();
        for (auto attribute: semanticSurfaces[surfaceIndex]) {
          if (attribute.first == "type") targetObject->type = attribute.second;
          else targetObject->attributes.push_back(std::pair<std::string, std::string>(attribute.first, attribute.second));
        }
      }
      targetObject->polygons.push_back(AzulPolygon());
      parseCityJSONPolygon(boundaries,
                           targetObject->polygons.back(),
                           vertices,
                           materialAssignments,
                           materialTheme,
                           textureAssignments,
                           textureTheme);
    }
  }

  void parseCityJSONPolygon(std::vector<std::any> &jsonPolygon,
                            AzulPolygon &polygon,
                            std::vector<std::tuple<double, double, double>> &vertices,
                            const std::any &materialAssignment,
                            const std::string &materialTheme,
                            const std::any &textureAssignment,
                            const std::string &textureTheme) {
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
    polygon.appearanceStyleId = buildStyleForPolygon(polygon, materialAssignment, materialTheme, textureAssignment, textureTheme);
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
    }
    if (!ring.points.empty()) ring.points.push_back(ring.points.front());
  }

  void buildHierarchy(AzulObject &parsedFile) {
    if (deferredParentRelationships.empty()) return;

    std::unordered_map<std::string, size_t> idToIndex;
    idToIndex.reserve(parsedFile.children.size());
    for (size_t i = 0; i < parsedFile.children.size(); ++i) {
      idToIndex[parsedFile.children[i].id] = i;
    }

    std::vector<std::vector<size_t>> parentToChildrenIndices(parsedFile.children.size());
    std::vector<uint8_t> isChild(parsedFile.children.size(), false);
    for (auto &[parentId, childIdx] : deferredParentRelationships) {
      auto parentIt = idToIndex.find(parentId);
      if (parentIt == idToIndex.end()) continue;
      parentToChildrenIndices[parentIt->second].push_back(childIdx);
      isChild[childIdx] = true;
    }

    std::vector<size_t> rootIndices;
    for (size_t i = 0; i < parsedFile.children.size(); ++i) {
      if (!isChild[i]) rootIndices.push_back(i);
    }

    std::vector<AzulObject> hierarchicalChildren;
    std::vector<uint8_t> moved(parsedFile.children.size(), false);
    hierarchicalChildren.reserve(rootIndices.size());

    std::vector<std::pair<std::vector<AzulObject>*, size_t>> stack;
    stack.reserve(parsedFile.children.size());

    for (size_t rootIdx : rootIndices) {
      moved[rootIdx] = true;
      hierarchicalChildren.push_back(std::move(parsedFile.children[rootIdx]));
      auto &root = hierarchicalChildren.back();
      root.children.reserve(parentToChildrenIndices[rootIdx].size());
      stack.emplace_back(&root.children, rootIdx);
    }

    while (!stack.empty()) {
      auto [slot, parentIdx] = stack.back();
      stack.pop_back();
      for (size_t childIdx : parentToChildrenIndices[parentIdx]) {
        if (moved[childIdx]) continue;
        moved[childIdx] = true;
        slot->push_back(std::move(parsedFile.children[childIdx]));
        auto &childChildren = slot->back().children;
        childChildren.reserve(parentToChildrenIndices[childIdx].size());
        stack.emplace_back(&childChildren, childIdx);
      }
    }

    parsedFile.children = std::move(hierarchicalChildren);
  }

public:
  std::string statusMessage;
  
  void parse(const char *filePath, AzulObject &parsedFile, bool knownCityJSON = false) {
    try {

    simdjson::ondemand::parser parser;
    simdjson::padded_string json;
    simdjson::ondemand::document doc;
    auto error = simdjson::padded_string::load(filePath).get(json);
    if (error) {
      std::cout << "Failed to load file: " << simdjson::error_message(error) << std::endl;
      return;
    } error = parser.iterate(json).get(doc);
    if (error) {
      std::cout << "Failed to parse JSON: " << simdjson::error_message(error) << std::endl;
      return;
    } parsedFile.type = "File";
    parsedFile.id = filePath;
    currentFilePath = filePath;
    deferredParentRelationships.clear();
    resetAppearanceForNewFile();

    if (knownCityJSON) {
      // Known CityJSON from .city.json extension — skip the content probe
      docType = "CityJSON";
      std::string_view version;
      if (!doc["version"].get_string().get(version)) {
        docVersion = version;
      }
    } else {
      // Probe file content to determine type
      if (doc.type() != simdjson::ondemand::json_type::object) return;
      for (auto element: doc.get_object()) {
        if (element.key().value().is_equal("type")) {
          docType = element.value().get_string();
        } else if (element.key().value().is_equal("version")) {
          docVersion = element.value().get_string();
        }
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
              if (attributeName == "referenceSystem") {
                parsedFile.crsIdentifier = attributeValue;
                std::cout << "CRS: " << parsedFile.crsIdentifier << std::endl;
              }
              parsedFile.attributes.push_back(std::pair<std::string, std::string>(attributeName, attributeValue));
            } else {
              std::cout << attributeName << " is a complex attribute. Skipped." << std::endl;
            }
          }
        }

        // Appearance object
        error = doc["appearance"].get(object);
        if (!error) {
          parseAppearanceObject(object);
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
          parseCityJSONObject(object.value().get_object(), parsedFile.children.back(), parsedFile.children.size() - 1, vertices, &geometryTemplates);
        }
        buildHierarchy(parsedFile);
        finalizeAppearanceForFile(parsedFile);

        statusMessage = "Loaded CityJSON " + std::string(docVersion) + " file";
      } else {
        statusMessage = "CityJSON " + std::string(docVersion) + " is not supported";
      }
    } else {
      statusMessage = "JSON files other than CityJSON are not supported";
    }

    } catch (simdjson::simdjson_error &e) {
      std::cout << "simdjson error: " << e.what() << std::endl;
      parsedFile.type = "File";
      parsedFile.id = filePath;
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
    deferredParentRelationships.clear();
    appearanceContext.clear();
    stylePool.clear();
    styleIdByKey.clear();
    parsedThemes.clear();
    currentFilePath.clear();
  }
};

#endif /* JSONParsingHelper_hpp */
