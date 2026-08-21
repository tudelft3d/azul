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
#include <array>
#include <cstdint>
#include <filesystem>
#include <map>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>

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

  // A simdjson DOM element that may be absent. Default-constructed
  // simdjson::dom::element values have an invalid tape and must not be
  // inspected, so every optional element is carried in this wrapper.
  struct OptionalElement {
    bool present = false;
    simdjson::dom::element element;
    void set(const simdjson::dom::element &e) {
      present = true;
      element = e;
    }
    bool isArray() const {
      return present && element.is_array();
    }
    bool isNull() const {
      return present && element.is_null();
    }
    bool hasValue() const {
      return present && !element.is_null();
    }
    bool asIndex(unsigned long long &out) const {
      if (!present) return false;
      if (element.is_uint64()) {
        out = element.get_uint64();
        return true;
      }
      if (element.is_int64() && element.get_int64() >= 0) {
        out = static_cast<unsigned long long>(element.get_int64());
        return true;
      }
      return false;
    }
    simdjson::dom::array array() const {
      return element.get_array();
    }
    simdjson::dom::element raw() const {
      return element;
    }
  };

  static bool elementToIndex(const simdjson::dom::element &value, unsigned long long &out) {
    if (value.is_uint64()) {
      out = value.get_uint64();
      return true;
    }
    if (value.is_int64() && value.get_int64() >= 0) {
      out = static_cast<unsigned long long>(value.get_int64());
      return true;
    }
    return false;
  }

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

  void parseAppearanceObjectInto(simdjson::dom::element appearanceObject, AppearanceContext &targetContext) {
    targetContext.clear();
    if (!appearanceObject.is_object()) return;
    simdjson::dom::object appearanceObjectValue = appearanceObject.get_object();

    simdjson::dom::element materialsElement;
    if (appearanceObjectValue["materials"].get(materialsElement) == simdjson::SUCCESS && materialsElement.is_array()) {
      for (auto materialValue: materialsElement.get_array()) {
        ParsedMaterial parsedMaterial;
        simdjson::dom::element materialObject;
        if (materialValue.get(materialObject) != simdjson::SUCCESS || !materialObject.is_object()) {
          targetContext.materials.push_back(parsedMaterial);
          continue;
        }
        simdjson::dom::element diffuseElement;
        if (materialObject["diffuseColor"].get(diffuseElement) == simdjson::SUCCESS && diffuseElement.is_array()) {
          int component = 0;
          for (auto current: diffuseElement.get_array()) {
            if (component >= 3) break;
            parsedMaterial.diffuseColor[component] = static_cast<float>(current.get_double());
            ++component;
          }
          if (component == 3) parsedMaterial.hasDiffuseColor = true;
        }
        simdjson::dom::element transparencyElement;
        if (materialObject["transparency"].get(transparencyElement) == simdjson::SUCCESS && transparencyElement.is_number()) {
          parsedMaterial.transparency = static_cast<float>(transparencyElement.get_double());
          parsedMaterial.hasTransparency = true;
        }
        targetContext.materials.push_back(parsedMaterial);
      }
    }

    simdjson::dom::element texturesElement;
    if (appearanceObjectValue["textures"].get(texturesElement) == simdjson::SUCCESS && texturesElement.is_array()) {
      for (auto textureValue: texturesElement.get_array()) {
        std::string textureUri;
        simdjson::dom::element textureObject;
        if (textureValue.get(textureObject) == simdjson::SUCCESS && textureObject.is_object()) {
          simdjson::dom::element imageElement;
          if (textureObject["image"].get(imageElement) == simdjson::SUCCESS && imageElement.is_string()) {
            textureUri = resolveImageUri(std::string(imageElement.get_string().value()), currentFilePath);
          }
        }
        targetContext.textures.push_back(textureUri);
      }
    }

    simdjson::dom::element textureVerticesElement;
    if (appearanceObjectValue["vertices-texture"].get(textureVerticesElement) == simdjson::SUCCESS && textureVerticesElement.is_array()) {
      for (auto uvVertex: textureVerticesElement.get_array()) {
        simdjson::dom::array uvArray;
        if (uvVertex.get_array().get(uvArray)) continue;
        std::array<float, 2> uv = {0.0f, 0.0f};
        int component = 0;
        for (auto coordinate: uvArray) {
          if (component >= 2) break;
          uv[component] = static_cast<float>(coordinate.get_double());
          ++component;
        }
        if (component == 2) targetContext.textureVertices.push_back(uv);
      }
    }

    simdjson::dom::element defaultMaterialThemeElement;
    if (appearanceObjectValue["default-theme-material"].get(defaultMaterialThemeElement) == simdjson::SUCCESS && defaultMaterialThemeElement.is_string()) {
      targetContext.defaultThemeMaterial = std::string(defaultMaterialThemeElement.get_string().value());
    }
    simdjson::dom::element defaultTextureThemeElement;
    if (appearanceObjectValue["default-theme-texture"].get(defaultTextureThemeElement) == simdjson::SUCCESS && defaultTextureThemeElement.is_string()) {
      targetContext.defaultThemeTexture = std::string(defaultTextureThemeElement.get_string().value());
    }
  }

  void parseAppearanceObject(simdjson::dom::element appearanceObject) {
    parseAppearanceObjectInto(appearanceObject, appearanceContext);
  }

  AppearanceContext currentAppearanceContext() const {
    return appearanceContext;
  }

  void setAppearanceContext(const AppearanceContext &newContext) {
    appearanceContext = newContext;
  }

  void parseThemeAssignments(simdjson::dom::object themedObject, const std::string &preferredTheme, OptionalElement &values, std::string &theme) {
    bool hasFallback = false;
    OptionalElement fallbackValues;
    std::string fallbackTheme;

    for (auto themedValue: themedObject) {
      std::string currentTheme = std::string(themedValue.key);
      if (!themedValue.value.is_object()) continue;
      simdjson::dom::object assignmentObject = themedValue.value.get_object();

      bool hasValues = false;
      OptionalElement parsedValues;
      simdjson::dom::element valuesElement;
      if (assignmentObject["values"].get(valuesElement) == simdjson::SUCCESS && valuesElement.is_array()) {
        parsedValues.set(valuesElement);
        hasValues = true;
      } else {
        simdjson::dom::element singleValue;
        if (assignmentObject["value"].get(singleValue) == simdjson::SUCCESS && (singleValue.is_number() || singleValue.is_null())) {
          parsedValues.set(singleValue);
          hasValues = true;
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

  void parseGeometryAppearanceAssignments(simdjson::dom::object currentGeometry,
                                          OptionalElement &materialValues,
                                          std::string &materialTheme,
                                          OptionalElement &textureValues,
                                          std::string &textureTheme) {
    simdjson::dom::element materialObject;
    if (currentGeometry["material"].get(materialObject) == simdjson::SUCCESS && materialObject.is_object()) {
      parseThemeAssignments(materialObject.get_object(), appearanceContext.defaultThemeMaterial, materialValues, materialTheme);
    }

    simdjson::dom::element textureObject;
    if (currentGeometry["texture"].get(textureObject) == simdjson::SUCCESS && textureObject.is_object()) {
      parseThemeAssignments(textureObject.get_object(), appearanceContext.defaultThemeTexture, textureValues, textureTheme);
    }
  }

  void applyTextureCoordinatesToRing(simdjson::dom::array &ringAssignment, AzulRing &ring) {
    if (ringAssignment.size() < 2 || ring.points.empty()) return;
    std::vector<unsigned long long> textureVertexIndices;
    textureVertexIndices.reserve(ringAssignment.size()-1);
    for (std::size_t i = 1; i < ringAssignment.size(); ++i) {
      unsigned long long textureVertexIndex = 0;
      if (!elementToIndex(ringAssignment.at(i), textureVertexIndex) || textureVertexIndex >= appearanceContext.textureVertices.size()) {
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

  bool parseTextureRingAssignment(const simdjson::dom::element &ringAny,
                                  AzulRing *targetRing,
                                  bool collectTextureOnly,
                                  unsigned long long &textureIndexOut,
                                  bool &hasTextureOut) {
    if (!ringAny.is_array()) return false;
    simdjson::dom::array ringAssignment = ringAny.get_array();
    if (ringAssignment.size() == 0) return false;

    unsigned long long textureIndex = 0;
    if (!elementToIndex(ringAssignment.at(0), textureIndex)) return false;
    if (textureIndex >= appearanceContext.textures.size()) return false;
    hasTextureOut = true;
    textureIndexOut = textureIndex;
    if (!collectTextureOnly && targetRing != nullptr) applyTextureCoordinatesToRing(ringAssignment, *targetRing);
    return true;
  }

  int buildStyleForPolygon(AzulPolygon &polygon,
                           const OptionalElement &materialAssignment,
                           const std::string &materialTheme,
                           const OptionalElement &textureAssignment,
                           const std::string &textureTheme) {
    AzulAppearanceStyle style;
    bool hasStyle = false;

    unsigned long long materialIndex = 0;
    if (!materialTheme.empty() && materialAssignment.asIndex(materialIndex) && materialIndex < appearanceContext.materials.size()) {
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

    if (!textureTheme.empty() && textureAssignment.isArray()) {
      simdjson::dom::array textureAsArray = textureAssignment.array();
      if (textureAsArray.size() > 0) {
        simdjson::dom::element firstElement = textureAsArray.at(0);
        if (firstElement.is_array()) {
          std::size_t ringIndex = 0;
          for (auto ringAssignment: textureAsArray) {
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
          if (parseTextureRingAssignment(textureAssignment.raw(), &polygon.exteriorRing, false, localTextureIndex, localHasTexture) && localHasTexture) {
            hasTexture = true;
            textureIndex = localTextureIndex;
            appliedExteriorTexture = true;
          }
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

  void parseCityJSONObject(simdjson::dom::object jsonObject, AzulObject &object, size_t childIdx, std::vector<std::tuple<double, double, double>> &vertices, AzulObject *geometryTemplates) {

    // Type (mandatory)
    simdjson::dom::element typeElement;
    if (jsonObject["type"].get(typeElement) == simdjson::SUCCESS && typeElement.is_string()) {
      object.type = std::string(typeElement.get_string().value());
    } else {
      std::cout << "no type specified" << std::endl;
      return;
    }

    // Geometry (optional)
    simdjson::dom::element geometryElement;
    if (jsonObject["geometry"].get(geometryElement) == simdjson::SUCCESS && geometryElement.is_array()) {
      for (auto geometry: geometryElement.get_array()) {
        parseCityJSONObjectGeometry(geometry, object, vertices, geometryTemplates);
      }
    }

    // Attributes (optional)
    simdjson::dom::element attributesElement;
    if (jsonObject["attributes"].get(attributesElement) == simdjson::SUCCESS && attributesElement.is_object()) {
      for (auto attribute: attributesElement.get_object()) {
        std::string_view attributeName = attribute.key;
        simdjson::dom::element attrValue = attribute.value;
        if (attrValue.is_string()) {
          object.attributes.push_back(std::pair<std::string, std::string>(attributeName, attrValue.get_string().value()));
        } else if (attrValue.is_number()) {
          object.attributes.push_back(std::pair<std::string, std::string>(attributeName, std::to_string(attrValue.get_double())));
        } else if (attrValue.is_bool()) {
          if (attrValue.get_bool() == true) object.attributes.push_back(std::pair<std::string, std::string>(attributeName, "true"));
          else object.attributes.push_back(std::pair<std::string, std::string>(attributeName, "false"));
        } else if (attrValue.is_null()) {
          object.attributes.push_back(std::pair<std::string, std::string>(attributeName, "null"));
        } else {
          std::cout << attributeName << ": unknown attribute type" << std::endl;
        }
      }
    }

    // Parents (optional)
    simdjson::dom::element parentsElement;
    if (jsonObject["parents"].get(parentsElement) == simdjson::SUCCESS && parentsElement.is_array()) {
      for (auto parent: parentsElement.get_array()) {
        deferredParentRelationships.emplace_back(std::string(parent.get_string().value()), childIdx);
      }
    }
  }

  void parseCityJSONObjectGeometry(simdjson::dom::element currentGeometryElement, AzulObject &object, std::vector<std::tuple<double, double, double>> &vertices, AzulObject *geometryTemplates) {
    std::vector<std::map<std::string, std::string>> semanticSurfaces;
    std::string geometryType, geometryLod;
    std::vector<double> transformationMatrix;
    OptionalElement materialAssignments;
    OptionalElement textureAssignments;
    std::string materialTheme;
    std::string textureTheme;
    unsigned long long templateIndex;
    bool withSemantics = false;

    if (!currentGeometryElement.is_object()) return;
    simdjson::dom::object currentGeometry = currentGeometryElement.get_object();

    // Mandatory
    simdjson::dom::element typeElement;
    if (currentGeometry["type"].get(typeElement) == simdjson::SUCCESS && typeElement.is_string()) {
      geometryType = std::string(typeElement.get_string().value());
    } else {
      std::cout << "no geometry type specified" << std::endl;
      return;
    }

    simdjson::dom::element lodElement;
    if (currentGeometry["lod"].get(lodElement) == simdjson::SUCCESS) {
      if (lodElement.is_string()) {
        geometryLod = std::string(lodElement.get_string().value());
      } else if (lodElement.is_number()) {
        geometryLod = std::to_string(lodElement.get_double()); // invalid but common error
      } else {
        std::cout << "unknown lod type" << std::endl;
      }
    } else {
      if (geometryType != "GeometryInstance") std::cout << "no LoD specified" << std::endl;
      geometryLod = "unknown";
    }

    simdjson::dom::element boundariesElement;
    if (currentGeometry["boundaries"].get(boundariesElement) != simdjson::SUCCESS || !boundariesElement.is_array()) {
      return;
    }
    simdjson::dom::array boundaries = boundariesElement.get_array();

    // Optional
    simdjson::dom::element semanticsElement;
    OptionalElement semantics;
    if (currentGeometry["semantics"].get(semanticsElement) == simdjson::SUCCESS && semanticsElement.is_object()) {
      withSemantics = true;
      simdjson::dom::object semanticsObject = semanticsElement.get_object();
      simdjson::dom::element surfacesElement;
      if (semanticsObject["surfaces"].get(surfacesElement) == simdjson::SUCCESS && surfacesElement.is_array()) {
        for (simdjson::dom::element surface: surfacesElement.get_array()) {
          semanticSurfaces.push_back(std::map<std::string, std::string>());
          if (!surface.is_object()) continue;
          for (auto attribute: surface.get_object()) {
            simdjson::dom::element attrValue = attribute.value;
            if (attrValue.is_string()) {
              semanticSurfaces.back()[std::string(attribute.key)] = std::string(attrValue.get_string().value());
            } else if (attrValue.is_number()) {
              semanticSurfaces.back()[std::string(attribute.key)] = std::to_string(attrValue.get_double());
            } else if (attrValue.is_bool()) {
              if (attrValue.get_bool() == true) semanticSurfaces.back()[std::string(attribute.key)] = "true";
              else semanticSurfaces.back()[std::string(attribute.key)] = "false";
            } else if (attrValue.is_null()) {
              semanticSurfaces.back()[std::string(attribute.key)] = "null";
            } else {
              std::cout << "unknown attribute type" << std::endl;
            }
          }
        }
      }
      simdjson::dom::element semanticsValuesElement;
      if (semanticsObject["values"].get(semanticsValuesElement) == simdjson::SUCCESS) {
        semantics.set(semanticsValuesElement);
      }
    }
    parseGeometryAppearanceAssignments(currentGeometry, materialAssignments, materialTheme, textureAssignments, textureTheme);

    templateIndex = 0;
    simdjson::dom::element templateElement;
    if (currentGeometry["template"].get(templateElement) == simdjson::SUCCESS) {
      unsigned long long index;
      if (elementToIndex(templateElement, index)) templateIndex = index;
    }
    simdjson::dom::element transformationMatrixElement;
    if (currentGeometry["transformationMatrix"].get(transformationMatrixElement) == simdjson::SUCCESS && transformationMatrixElement.is_array()) {
      for (auto matrixElement: transformationMatrixElement.get_array()) transformationMatrix.push_back(matrixElement.get_double());
    }

    if (!geometryType.empty()) {
      if (geometryType == "MultiSurface" ||
          geometryType == "CompositeSurface") {
        object.children.push_back(AzulObject());
        object.children.back().type = "LoD";
        object.children.back().id = geometryLod;
        parseCityJSONGeometry(boundaries, semantics, materialAssignments, materialTheme, textureAssignments, textureTheme, withSemantics, semanticSurfaces, 2, object.children.back(), vertices);
      }

      else if (geometryType == "Solid") {
        object.children.push_back(AzulObject());
        object.children.back().type = "LoD";
        object.children.back().id = geometryLod;
        parseCityJSONGeometry(boundaries, semantics, materialAssignments, materialTheme, textureAssignments, textureTheme, withSemantics, semanticSurfaces, 3, object.children.back(), vertices);
      }

      else if (geometryType == "MultiSolid" ||
               geometryType == "CompositeSolid") {
        object.children.push_back(AzulObject());
        object.children.back().type = "LoD";
        object.children.back().id = geometryLod;
        parseCityJSONGeometry(boundaries, semantics, materialAssignments, materialTheme, textureAssignments, textureTheme, withSemantics, semanticSurfaces, 4, object.children.back(), vertices);
      }

      else if (geometryType == "GeometryInstance") {
        if (geometryTemplates != NULL && templateIndex < geometryTemplates->children.size() && transformationMatrix.size() == 16 && boundaries.size() >= 1) {
          unsigned long long anchorPoint = 0;
          if (!elementToIndex(boundaries.at(0), anchorPoint)) return;
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

  void parseCityJSONGeometry(simdjson::dom::array boundaries,
                             OptionalElement semantics,
                             OptionalElement materialAssignments,
                             const std::string &materialTheme,
                             OptionalElement textureAssignments,
                             const std::string &textureTheme,
                             bool withSemantics,
                             std::vector<std::map<std::string, std::string>> &semanticSurfaces,
                             int nesting,
                             AzulObject &object,
                             std::vector<std::tuple<double, double, double>> &vertices) {

    if (nesting > 1) {
      simdjson::dom::array::iterator boundaryIterator = boundaries.begin();
      simdjson::dom::array::iterator boundaryEnd = boundaries.end();

      bool hasSemanticsArray = semantics.isArray();
      bool hasMaterialsArray = materialAssignments.isArray();
      bool hasTexturesArray = textureAssignments.isArray();
      simdjson::dom::array semanticsArray = hasSemanticsArray ? semantics.array() : simdjson::dom::array();
      simdjson::dom::array materialsArray = hasMaterialsArray ? materialAssignments.array() : simdjson::dom::array();
      simdjson::dom::array texturesArray = hasTexturesArray ? textureAssignments.array() : simdjson::dom::array();
      simdjson::dom::array::iterator semanticsIterator = hasSemanticsArray ? semanticsArray.begin() : simdjson::dom::array::iterator();
      simdjson::dom::array::iterator semanticsEnd = hasSemanticsArray ? semanticsArray.end() : simdjson::dom::array::iterator();
      simdjson::dom::array::iterator materialsIterator = hasMaterialsArray ? materialsArray.begin() : simdjson::dom::array::iterator();
      simdjson::dom::array::iterator materialsEnd = hasMaterialsArray ? materialsArray.end() : simdjson::dom::array::iterator();
      simdjson::dom::array::iterator texturesIterator = hasTexturesArray ? texturesArray.begin() : simdjson::dom::array::iterator();
      simdjson::dom::array::iterator texturesEnd = hasTexturesArray ? texturesArray.end() : simdjson::dom::array::iterator();

      unsigned long long propagatedSemantics = 0;
      bool propagateSemantics = semantics.asIndex(propagatedSemantics);
      unsigned long long propagatedMaterials = 0;
      bool propagateMaterials = materialAssignments.asIndex(propagatedMaterials);
      unsigned long long propagatedTextures = 0;
      bool propagateTextures = textureAssignments.asIndex(propagatedTextures);

      for (; boundaryIterator != boundaryEnd; ++boundaryIterator) {
        if (!(*boundaryIterator).is_array()) {
          if (hasSemanticsArray && semanticsIterator != semanticsEnd) ++semanticsIterator;
          if (hasMaterialsArray && materialsIterator != materialsEnd) ++materialsIterator;
          if (hasTexturesArray && texturesIterator != texturesEnd) ++texturesIterator;
          continue;
        }
        simdjson::dom::array childBoundaries = (*boundaryIterator).get_array();

        OptionalElement childSemantics;
        if (hasSemanticsArray) {
          if (semanticsIterator != semanticsEnd) {
            childSemantics.set(*semanticsIterator);
            ++semanticsIterator;
          }
        } else if (propagateSemantics) {
          OptionalElement propagated;
          propagated.set(semantics.raw());
          childSemantics = propagated;
        }

        OptionalElement childMaterials;
        if (hasMaterialsArray) {
          if (materialsIterator != materialsEnd) {
            childMaterials.set(*materialsIterator);
            ++materialsIterator;
          }
        } else if (propagateMaterials) {
          OptionalElement propagated;
          propagated.set(materialAssignments.raw());
          childMaterials = propagated;
        }

        OptionalElement childTextures;
        if (hasTexturesArray) {
          if (texturesIterator != texturesEnd) {
            childTextures.set(*texturesIterator);
            ++texturesIterator;
          }
        } else if (propagateTextures) {
          OptionalElement propagated;
          propagated.set(textureAssignments.raw());
          childTextures = propagated;
        }

        bool childWithSemantics = withSemantics && childSemantics.hasValue();
        parseCityJSONGeometry(childBoundaries,
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
      if (withSemantics && semantics.asIndex(surfaceIndex) && surfaceIndex < semanticSurfaces.size()) {
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

  void parseCityJSONPolygon(simdjson::dom::array &jsonPolygon,
                            AzulPolygon &polygon,
                            std::vector<std::tuple<double, double, double>> &vertices,
                            const OptionalElement &materialAssignment,
                            const std::string &materialTheme,
                            const OptionalElement &textureAssignment,
                            const std::string &textureTheme) {
    bool outer = true;
    for (auto ringValue: jsonPolygon) {
      simdjson::dom::array jsonRing;
      if (ringValue.get_array().get(jsonRing)) {
        std::cout << "Ring is not an array" << std::endl;
        continue;
      }
      if (outer) {
        parseCityJSONRing(jsonRing, polygon.exteriorRing, vertices);
        outer = false;
      } else {
        polygon.interiorRings.push_back(AzulRing());
        parseCityJSONRing(jsonRing, polygon.interiorRings.back(), vertices);
      }
    }
    polygon.appearanceStyleId = buildStyleForPolygon(polygon, materialAssignment, materialTheme, textureAssignment, textureTheme);
  }

  void parseCityJSONRing(simdjson::dom::array &jsonRing, AzulRing &ring, std::vector<std::tuple<double, double, double>> &vertices) {
    for (auto jsonVertex: jsonRing) {
      unsigned long long vertexIndex;
      if (!elementToIndex(jsonVertex, vertexIndex)) {
        std::cout << "Vertex index is not an integer" << std::endl;
        continue;
      }
      if (vertexIndex < vertices.size()) {
        ring.points.push_back(AzulPoint());
        ring.points.back().coordinates[0] = std::get<0>(vertices[vertexIndex]);
        ring.points.back().coordinates[1] = std::get<1>(vertices[vertexIndex]);
        ring.points.back().coordinates[2] = std::get<2>(vertices[vertexIndex]);
      } else {
        std::cout << "Warning: vertex index " << vertexIndex << " is out of range (file has " << vertices.size() << " vertices)" << std::endl;
      }
    }
    if (!ring.points.empty() && ring.points.size() < 3) {
      std::cout << "Warning: ring has " << ring.points.size() << " points (at least 3 required), skipping it" << std::endl;
    } else if (!ring.points.empty()) {
      ring.points.push_back(ring.points.front());
    }
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

    simdjson::padded_string json;
    auto error = simdjson::padded_string::load(filePath).get(json);
    if (error) {
      std::cout << "Failed to load file: " << simdjson::error_message(error) << std::endl;
      return;
    }
    simdjson::dom::parser parser;
    simdjson::dom::element doc;
    error = parser.parse(json).get(doc);
    if (error) {
      std::cout << "Failed to parse JSON: " << simdjson::error_message(error) << std::endl;
      return;
    }
    parsedFile.type = "File";
    parsedFile.id = filePath;
    currentFilePath = filePath;
    deferredParentRelationships.clear();
    resetAppearanceForNewFile();

    if (knownCityJSON) {
      // Known CityJSON from .city.json extension — skip the content probe
      docType = "CityJSON";
      simdjson::dom::element versionElement;
      if (doc["version"].get(versionElement) == simdjson::SUCCESS && versionElement.is_string()) {
        docVersion = versionElement.get_string().value();
      }
    } else {
      // Probe file content to determine type
      if (!doc.is_object()) return;
      simdjson::dom::element typeElement;
      simdjson::dom::element versionElement;
      if (doc["type"].get(typeElement) == simdjson::SUCCESS && typeElement.is_string()) {
        docType = typeElement.get_string().value();
      }
      if (doc["version"].get(versionElement) == simdjson::SUCCESS && versionElement.is_string()) {
        docVersion = versionElement.get_string().value();
      }
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
        simdjson::dom::element appearanceElement;
        if (doc["appearance"].get(appearanceElement) == simdjson::SUCCESS) {
          parseAppearanceObject(appearanceElement);
        }

        // Transform object
        std::vector<double> scale;
        std::vector<double> translation;
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
        AzulObject geometryTemplates;
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
