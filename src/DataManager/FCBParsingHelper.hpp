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

#ifndef FCBParsingHelper_hpp
#define FCBParsingHelper_hpp

#include <array>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <tuple>
#include <unordered_map>
#include <vector>

#include "AppearanceHelpers.hpp"
#include "DataModel.hpp"

// Parses FlatCityBuf (.fcb) files: a binary CityJSON encoding built on
// FlatBuffers (https://www.cityjson.org/flatcitybuf/). The reader is
// self-contained: it hand-decodes the small subset of the FlatBuffers wire
// format the schemas use (tables, vtables, offsets, vectors, structs), so no
// FlatBuffers runtime is needed.
//
// File layout (see docs/specification.md in the FlatCityBuf repository):
//
//   [ 8-byte magic "fcb" 0x01 "fcb" 0x00 ]
//   [ u32 header_size ] [ Header FlatBuffer (size-prefixed root) ]
//   [ packed Hilbert R-tree ] [ attribute B+tree index ] [ features... ]
//
// Each feature is a size-prefixed FlatBuffer (CityFeature) holding the
// feature's own objects, quantised int32 vertices, and optionally an
// appearance palette. The R-tree and attribute index sections are skipped:
// azul loads whole files, so only their byte lengths (derived from the
// header) are needed to find the features section.
//
// Geometry follows the CityJSON dimensional hierarchy, flattened into count
// arrays: solids[i] shells per solid, shells[i] surfaces per shell,
// surfaces[i] rings per surface, strings[i] vertex indices per ring, and
// `boundaries` the flat run of vertex indices. The encoder writes one
// redundant count level above the geometry's own depth (a MultiSurface
// carries a one-entry `shells`, a Solid a one-entry `solids`); the walker
// below ignores it, exactly like the reference decoders.

class FCBParsingHelper {
public:
  std::string statusMessage;

  void parse(const char *filePath, AzulObject &parsedFile);

private:
  // ------------------------------------------------------------------ //
  // Minimal FlatBuffers reader. The wire format is stable by design and  //
  // little-endian; every access is bounds-checked against the file and   //
  // marks the reader invalid on violation so a corrupt file aborts        //
  // cleanly instead of crashing.                                          //
  // ------------------------------------------------------------------ //
  struct FcbReader {
    const uint8_t *data = nullptr;
    std::size_t size = 0;
    bool valid = true;

    bool inBounds(std::size_t pos, std::size_t n) {
      if (!valid) return false;
      if (pos > size || n > size - pos) {
        valid = false;
        return false;
      }
      return true;
    }

    template <typename T> bool read(std::size_t pos, T &out) {
      if (!inBounds(pos, sizeof(T))) return false;
      std::memcpy(&out, data + pos, sizeof(T));
      return true;
    }

    // Root table of a size-prefixed buffer whose payload starts at bufferStart.
    bool rootAt(std::size_t bufferStart, std::size_t &tablePos) {
      uint32_t rootOffset;
      if (!read(bufferStart, rootOffset)) return false;
      tablePos = bufferStart + rootOffset;
      return inBounds(tablePos, 1);
    }

    // Position of a scalar/struct field in a table; false when the field is
    // absent (vtable slot zero) or the table is corrupt.
    bool fieldPos(std::size_t tablePos, int fieldIndex, std::size_t &fieldPosOut) {
      // The vtable soffset is SIGNED: the writer usually places vtables before
      // their table, but deduplication can place one after it (negative
      // soffset), so vtablePos = tablePos - soffset in int64 arithmetic.
      int32_t soffset;
      if (!read(tablePos, soffset)) return false;
      int64_t vtablePos = static_cast<int64_t>(tablePos) - soffset;
      if (vtablePos < 0 || !inBounds(static_cast<std::size_t>(vtablePos), 1)) return false;
      uint16_t vtableSize, tableSize;
      if (!read(static_cast<std::size_t>(vtablePos), vtableSize) ||
          !read(static_cast<std::size_t>(vtablePos) + 2, tableSize)) return false;
      if (vtableSize < 4) {
        valid = false;
        return false;
      }
      std::size_t slotPos = static_cast<std::size_t>(vtablePos) + 4 + 2 * fieldIndex;
      if (slotPos + 2 > static_cast<std::size_t>(vtablePos) + vtableSize) return false;
      uint16_t fieldOffset;
      if (!read(slotPos, fieldOffset)) return false;
      if (fieldOffset == 0 || fieldOffset >= tableSize) return false;
      fieldPosOut = tablePos + fieldOffset;
      return inBounds(fieldPosOut, 1);
    }

    // Target of an offset field (table, string or vector reference).
    bool offsetTarget(std::size_t tablePos, int fieldIndex, std::size_t &target) {
      std::size_t fieldPosOut;
      if (!fieldPos(tablePos, fieldIndex, fieldPosOut)) return false;
      uint32_t offset;
      if (!read(fieldPosOut, offset)) return false;
      target = fieldPosOut + offset;
      return inBounds(target, 1);
    }

    template <typename T> bool scalar(std::size_t tablePos, int fieldIndex, T &out) {
      std::size_t fieldPosOut;
      if (!fieldPos(tablePos, fieldIndex, fieldPosOut)) return false;
      return read(fieldPosOut, out);
    }

    bool stringField(std::size_t tablePos, int fieldIndex, std::string &out) {
      std::size_t target;
      if (!offsetTarget(tablePos, fieldIndex, target)) return false;
      uint32_t length;
      if (!read(target, length)) return false;
      if (!inBounds(target + 4, length)) return false;
      out.assign(reinterpret_cast<const char *>(data + target + 4), length);
      return true;
    }

    // Vector of `elemSize`-byte back-to-back elements (scalars or structs).
    bool vectorAt(std::size_t tablePos, int fieldIndex, std::size_t elemSize,
                  std::size_t &count, std::size_t &dataPos) {
      std::size_t target;
      if (!offsetTarget(tablePos, fieldIndex, target)) return false;
      return vectorAtField(target, elemSize, count, dataPos);
    }

    // Same, for a vector whose field position is already known.
    bool vectorAtField(std::size_t fieldPos, std::size_t elemSize,
                       std::size_t &count, std::size_t &dataPos) {
      uint32_t length;
      if (!read(fieldPos, length)) return false;
      count = length;
      dataPos = fieldPos + 4;
      if (!inBounds(dataPos, count * elemSize)) return false;
      return true;
    }

    // i-th element of a vector of tables or strings: relative to its slot.
    bool tableElementAt(std::size_t dataPos, std::size_t index, std::size_t &elemPos) {
      std::size_t slotPos = dataPos + 4 * index;
      uint32_t offset;
      if (!read(slotPos, offset)) return false;
      elemPos = slotPos + offset;
      return inBounds(elemPos, 1);
    }

    bool u32Vector(std::size_t tablePos, int fieldIndex, std::vector<uint32_t> &out) {
      std::size_t count, dataPos;
      if (!vectorAt(tablePos, fieldIndex, 4, count, dataPos)) return false;
      out.clear();
      out.reserve(count);
      for (std::size_t i = 0; i < count; ++i) {
        uint32_t value;
        if (!read(dataPos + 4 * i, value)) return false;
        out.push_back(value);
      }
      return true;
    }

    bool doubleVector(std::size_t tablePos, int fieldIndex, std::vector<double> &out) {
      std::size_t count, dataPos;
      if (!vectorAt(tablePos, fieldIndex, 8, count, dataPos)) return false;
      out.clear();
      out.reserve(count);
      for (std::size_t i = 0; i < count; ++i) {
        double value;
        if (!read(dataPos + 8 * i, value)) return false;
        out.push_back(value);
      }
      return true;
    }

    bool tableVector(std::size_t tablePos, int fieldIndex, std::vector<std::size_t> &out) {
      std::size_t count, dataPos;
      if (!vectorAt(tablePos, fieldIndex, 4, count, dataPos)) return false;
      out.clear();
      out.reserve(count);
      for (std::size_t i = 0; i < count; ++i) {
        std::size_t elemPos;
        if (!tableElementAt(dataPos, i, elemPos)) return false;
        out.push_back(elemPos);
      }
      return true;
    }

    bool stringVector(std::size_t tablePos, int fieldIndex, std::vector<std::string> &out) {
      std::size_t count, dataPos;
      if (!vectorAt(tablePos, fieldIndex, 4, count, dataPos)) return false;
      out.clear();
      out.reserve(count);
      for (std::size_t i = 0; i < count; ++i) {
        std::size_t target;
        if (!tableElementAt(dataPos, i, target)) return false;
        uint32_t length;
        if (!read(target, length)) return false;
        if (!inBounds(target + 4, length)) return false;
        out.emplace_back(reinterpret_cast<const char *>(data + target + 4), length);
      }
      return true;
    }
  };

  // Field indices in the FlatBuffers schemas (vtable slots, declaration order).
  enum {
    // Header
    HEADER_TRANSFORM = 0, HEADER_APPEARANCE = 1, HEADER_COLUMNS = 2,
    HEADER_SEMANTIC_COLUMNS = 3, HEADER_FEATURES_COUNT = 4, HEADER_INDEX_NODE_SIZE = 5,
    HEADER_ATTRIBUTE_INDEX = 6, HEADER_REFERENCE_SYSTEM = 8, HEADER_IDENTIFIER = 9,
    HEADER_REFERENCE_DATE = 10, HEADER_TITLE = 11, HEADER_TEMPLATES = 12,
    HEADER_TEMPLATES_VERTICES = 13, HEADER_VERSION = 27,
    // Appearance
    APPEARANCE_MATERIALS = 0, APPEARANCE_TEXTURES = 1, APPEARANCE_VERTICES_TEXTURE = 2,
    APPEARANCE_DEFAULT_THEME_TEXTURE = 3, APPEARANCE_DEFAULT_THEME_MATERIAL = 4,
    // Material
    MATERIAL_NAME = 0, MATERIAL_DIFFUSE_COLOR = 2, MATERIAL_TRANSPARENCY = 6,
    // Texture
    TEXTURE_IMAGE = 1,
    // Column
    COLUMN_INDEX = 0, COLUMN_NAME = 1, COLUMN_TYPE = 2,
    // ReferenceSystem
    REFERENCE_SYSTEM_AUTHORITY = 0, REFERENCE_SYSTEM_CODE = 2, REFERENCE_SYSTEM_CODE_STRING = 3,
    // CityFeature
    FEATURE_OBJECTS = 1, FEATURE_VERTICES = 2, FEATURE_APPEARANCE = 3,
    // CityObject
    CITY_OBJECT_TYPE = 0, CITY_OBJECT_EXTENSION_TYPE = 1, CITY_OBJECT_ID = 2,
    CITY_OBJECT_GEOMETRY = 4, CITY_OBJECT_GEOMETRY_INSTANCES = 5, CITY_OBJECT_ATTRIBUTES = 6,
    CITY_OBJECT_COLUMNS = 7, CITY_OBJECT_PARENTS = 10,
    // Geometry
    GEOMETRY_TYPE = 0, GEOMETRY_LOD = 1, GEOMETRY_SOLIDS = 2, GEOMETRY_SHELLS = 3,
    GEOMETRY_SURFACES = 4, GEOMETRY_STRINGS = 5, GEOMETRY_BOUNDARIES = 6,
    GEOMETRY_SEMANTICS = 7, GEOMETRY_SEMANTICS_OBJECTS = 8, GEOMETRY_MATERIAL = 9,
    GEOMETRY_TEXTURE = 10,
    // SemanticObject
    SEMANTIC_OBJECT_TYPE = 0, SEMANTIC_OBJECT_ATTRIBUTES = 1, SEMANTIC_OBJECT_PARENT = 3,
    SEMANTIC_OBJECT_EXTENSION_TYPE = 4,
    // MaterialMapping
    MATERIAL_MAPPING_THEME = 0, MATERIAL_MAPPING_SOLIDS = 1, MATERIAL_MAPPING_SHELLS = 2,
    MATERIAL_MAPPING_VERTICES = 3, MATERIAL_MAPPING_VALUE = 4,
    // TextureMapping
    TEXTURE_MAPPING_THEME = 0, TEXTURE_MAPPING_SOLIDS = 1, TEXTURE_MAPPING_SHELLS = 2,
    TEXTURE_MAPPING_SURFACES = 3, TEXTURE_MAPPING_STRINGS = 4, TEXTURE_MAPPING_VERTICES = 5,
    // GeometryInstance
    GEOMETRY_INSTANCE_TRANSFORMATION = 0, GEOMETRY_INSTANCE_TEMPLATE = 1,
    GEOMETRY_INSTANCE_BOUNDARIES = 2,
  };

  // GeometryType enumerators (geometry.fbs).
  enum {
    GEOMETRY_TYPE_MULTIPOINT = 0, GEOMETRY_TYPE_MULTILINESTRING = 1,
    GEOMETRY_TYPE_MULTISURFACE = 2, GEOMETRY_TYPE_COMPOSITESURFACE = 3,
    GEOMETRY_TYPE_SOLID = 4, GEOMETRY_TYPE_MULTISOLID = 5,
    GEOMETRY_TYPE_COMPOSITESOLID = 6, GEOMETRY_TYPE_GEOMETRYINSTANCE = 7,
  };

  // ColumnType enumerators (header.fbs).
  enum {
    COLUMN_TYPE_BYTE = 0, COLUMN_TYPE_UBYTE = 1, COLUMN_TYPE_BOOL = 2,
    COLUMN_TYPE_SHORT = 3, COLUMN_TYPE_USHORT = 4, COLUMN_TYPE_INT = 5,
    COLUMN_TYPE_UINT = 6, COLUMN_TYPE_LONG = 7, COLUMN_TYPE_ULONG = 8,
    COLUMN_TYPE_FLOAT = 9, COLUMN_TYPE_DOUBLE = 10, COLUMN_TYPE_STRING = 11,
    COLUMN_TYPE_JSON = 12, COLUMN_TYPE_DATETIME = 13, COLUMN_TYPE_BINARY = 14,
  };

  static constexpr uint32_t NULL_INDEX = UINT32_MAX;

  // Enum name tables; names must match CityJSON exactly. A tag past the end
  // (extension object/surface without its extension_type string, or a newer
  // encoder's tag) gets the same placeholder the reference readers emit.
  static const char *cityObjectTypeName(uint8_t type);
  static const char *semanticSurfaceTypeName(uint8_t type);

  // Appearance palette of the current file (header or current feature).
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

  std::vector<ParsedMaterial> materials;
  std::vector<std::string> textures;
  std::vector<std::array<float, 2>> textureVertices;
  std::string defaultThemeTexture;
  std::string defaultThemeMaterial;

  // Header appearance, kept so a feature without its own palette falls back
  // to it (single-file CityJSON writers put the palette in the header).
  std::vector<ParsedMaterial> headerMaterials;
  std::vector<std::string> headerTextures;
  std::vector<std::array<float, 2>> headerTextureVertices;
  std::string headerDefaultThemeTexture;
  std::string headerDefaultThemeMaterial;

  std::vector<AzulAppearanceStyle> stylePool;
  std::unordered_map<std::string, int> styleIdByKey;
  std::set<std::string> parsedThemes;
  std::vector<std::pair<std::string, std::size_t>> deferredParentRelationships;
  std::string currentFilePath;

  double scale[3] = {1.0, 1.0, 1.0};
  double translate[3] = {0.0, 0.0, 0.0};

  // World-coordinate vertices of the current feature (or the templates).
  std::vector<std::tuple<double, double, double>> featureVertices;

  // LoD children of the header geometry templates, indexed by template index.
  std::vector<AzulObject> templateChildren;

  struct ColumnInfo {
    uint16_t index;
    std::string name;
    uint8_t type;
  };
  std::vector<ColumnInfo> columns;         // header attribute columns
  std::vector<ColumnInfo> semanticColumns; // header semantic surface columns

  struct MaterialMapping {
    std::string theme;
    bool hasValues;
    bool hasSharedValue;
    uint32_t sharedValue;
    std::vector<uint32_t> solids, shells, values;
  };
  struct TextureMapping {
    std::string theme;
    bool hasValues;
    std::vector<uint32_t> solids, shells, surfaces, strings, values;
  };
  struct FcbSurface {
    std::vector<std::vector<uint32_t>> rings;      // vertex indices, exterior first
    uint32_t semanticIndex = NULL_INDEX;           // into semantics_objects
    uint32_t materialIndex = NULL_INDEX;           // into the material palette
    std::vector<std::vector<uint32_t>> textureRings; // per ring: [texture index, UVs...]
  };

  void resetAppearanceForNewFile();
  void finalizeAppearanceForFile(AzulObject &parsedFile);
  int addOrGetStyleId(const AzulAppearanceStyle &style);
  void parseAppearanceInto(FcbReader &r, std::size_t appearancePos, std::vector<ParsedMaterial> &materials,
                           std::vector<std::string> &textures,
                           std::vector<std::array<float, 2>> &textureVertices,
                           std::string &defaultThemeTexture, std::string &defaultThemeMaterial);
  void parseAppearance(FcbReader &r, std::size_t appearancePos);
  bool parseColumns(FcbReader &r, std::size_t columnsPos, std::vector<ColumnInfo> &out);
  void decodeAttributes(FcbReader &r, std::size_t attributesPos,
                         const std::vector<ColumnInfo> &schema, AzulObject &object);
  bool parseMaterialMapping(FcbReader &r, std::size_t pos, MaterialMapping &out);
  bool parseTextureMapping(FcbReader &r, std::size_t pos, TextureMapping &out);
  template <typename Mapping>
  const Mapping *selectMapping(const std::vector<Mapping> &mappings, const std::string &defaultTheme);

  void walkSurfaces(FcbReader &r, uint8_t geometryType,
                    const std::vector<uint32_t> &solids, const std::vector<uint32_t> &shells,
                    const std::vector<uint32_t> &surfaces, const std::vector<uint32_t> &strings,
                    const std::vector<uint32_t> &boundaries,
                    const std::vector<uint32_t> &semanticsValues,
                    const MaterialMapping *material, const TextureMapping *texture,
                    std::vector<FcbSurface> &out);
  void parseGeometry(FcbReader &r, std::size_t geometryPos, AzulObject &object,
                     const std::vector<std::tuple<double, double, double>> &vertices);
  void parseCityObject(FcbReader &r, std::size_t objectPos, AzulObject &object,
                       std::size_t childIndex);
  void parseGeometryInstance(FcbReader &r, std::size_t instancePos, AzulObject &object,
                             const std::vector<std::tuple<double, double, double>> &vertices);
  void transformPolygons(AzulObject &object, const double matrix[16],
                         double anchorX, double anchorY, double anchorZ);
  void addPolygonForSurface(FcbReader &r, const FcbSurface &surface, AzulObject &lodObject,
                            const std::vector<std::size_t> &semanticsObjects,
                            const MaterialMapping *material, const TextureMapping *texture,
                            const std::vector<std::tuple<double, double, double>> &vertices);
  int buildStyleForSurface(AzulPolygon &polygon, const FcbSurface &surface,
                           const MaterialMapping *material, const TextureMapping *texture);
  void buildHierarchy(AzulObject &parsedFile);
};

// --------------------------------------------------------------------- //
// Enum names                                                             //
// --------------------------------------------------------------------- //
inline const char *FCBParsingHelper::cityObjectTypeName(uint8_t type) {
  static const char *const names[] = {
      "Bridge", "BridgePart", "BridgeInstallation", "BridgeConstructiveElement",
      "BridgeRoom", "BridgeFurniture", "Building", "BuildingPart",
      "BuildingInstallation", "BuildingConstructiveElement", "BuildingFurniture",
      "BuildingStorey", "BuildingRoom", "BuildingUnit", "CityFurniture",
      "CityObjectGroup", "GenericCityObject", "LandUse", "OtherConstruction",
      "PlantCover", "SolitaryVegetationObject", "TINRelief", "Road", "Railway",
      "Waterway", "TransportSquare", "Tunnel", "TunnelPart", "TunnelInstallation",
      "TunnelConstructiveElement", "TunnelHollowSpace", "TunnelFurniture", "WaterBody"};
  if (type >= sizeof(names) / sizeof(names[0])) return "+UnknownCityObject";
  return names[type];
}

inline const char *FCBParsingHelper::semanticSurfaceTypeName(uint8_t type) {
  static const char *const names[] = {
      "RoofSurface", "GroundSurface", "WallSurface", "ClosureSurface",
      "OuterCeilingSurface", "OuterFloorSurface", "Window", "Door",
      "InteriorWallSurface", "CeilingSurface", "FloorSurface", "WaterSurface",
      "WaterGroundSurface", "WaterClosureSurface", "TrafficArea",
      "AuxiliaryTrafficArea", "TransportationMarking", "TransportationHole"};
  if (type >= sizeof(names) / sizeof(names[0])) return "+GenericSurface";
  return names[type];
}

// --------------------------------------------------------------------- //
// Appearance helpers (mirror JSONParsingHelper's style pooling)          //
// --------------------------------------------------------------------- //
inline void FCBParsingHelper::resetAppearanceForNewFile() {
  materials.clear();
  textures.clear();
  textureVertices.clear();
  defaultThemeTexture.clear();
  defaultThemeMaterial.clear();
  headerMaterials.clear();
  headerTextures.clear();
  headerTextureVertices.clear();
  headerDefaultThemeTexture.clear();
  headerDefaultThemeMaterial.clear();
  stylePool.clear();
  styleIdByKey.clear();
  parsedThemes.clear();
}

inline void FCBParsingHelper::finalizeAppearanceForFile(AzulObject &parsedFile) {
  parsedFile.appearanceStyles = stylePool;
  parsedFile.appearanceThemes.assign(parsedThemes.begin(), parsedThemes.end());
}

inline int FCBParsingHelper::addOrGetStyleId(const AzulAppearanceStyle &style) {
  std::string key = appearanceStyleKey(style);
  auto found = styleIdByKey.find(key);
  if (found != styleIdByKey.end()) return found->second;
  stylePool.push_back(style);
  int newId = static_cast<int>(stylePool.size() - 1);
  styleIdByKey[key] = newId;
  return newId;
}

inline void FCBParsingHelper::parseAppearanceInto(FcbReader &r, std::size_t appearancePos,
                                                  std::vector<ParsedMaterial> &materials,
                                                  std::vector<std::string> &textures,
                                                  std::vector<std::array<float, 2>> &textureVertices,
                                                  std::string &defaultThemeTexture,
                                                  std::string &defaultThemeMaterial) {
  materials.clear();
  textures.clear();
  textureVertices.clear();
  defaultThemeTexture.clear();
  defaultThemeMaterial.clear();

  std::vector<std::size_t> materialPositions;
  if (r.tableVector(appearancePos, APPEARANCE_MATERIALS, materialPositions)) {
    for (std::size_t pos: materialPositions) {
      ParsedMaterial parsedMaterial;
      std::vector<double> diffuseColor;
      if (r.doubleVector(pos, MATERIAL_DIFFUSE_COLOR, diffuseColor) && diffuseColor.size() == 3) {
        parsedMaterial.diffuseColor[0] = static_cast<float>(diffuseColor[0]);
        parsedMaterial.diffuseColor[1] = static_cast<float>(diffuseColor[1]);
        parsedMaterial.diffuseColor[2] = static_cast<float>(diffuseColor[2]);
        parsedMaterial.hasDiffuseColor = true;
      }
      double transparency;
      if (r.scalar(pos, MATERIAL_TRANSPARENCY, transparency)) {
        parsedMaterial.transparency = static_cast<float>(transparency);
        parsedMaterial.hasTransparency = true;
      }
      materials.push_back(parsedMaterial);
    }
  }

  std::vector<std::size_t> texturePositions;
  if (r.tableVector(appearancePos, APPEARANCE_TEXTURES, texturePositions)) {
    for (std::size_t pos: texturePositions) {
      std::string image;
      if (r.stringField(pos, TEXTURE_IMAGE, image) && !image.empty()) {
        textures.push_back(resolveImageUri(image, currentFilePath));
      } else {
        textures.emplace_back();
      }
    }
  }

  std::size_t textureVertexCount, textureVertexPos;
  if (r.vectorAt(appearancePos, APPEARANCE_VERTICES_TEXTURE, 16, textureVertexCount, textureVertexPos)) {
    for (std::size_t i = 0; i < textureVertexCount; ++i) {
      double u, v;
      if (!r.read(textureVertexPos + 16 * i, u) || !r.read(textureVertexPos + 16 * i + 8, v)) return;
      textureVertices.push_back({static_cast<float>(u), static_cast<float>(v)});
    }
  }

  r.stringField(appearancePos, APPEARANCE_DEFAULT_THEME_TEXTURE, defaultThemeTexture);
  r.stringField(appearancePos, APPEARANCE_DEFAULT_THEME_MATERIAL, defaultThemeMaterial);
}

inline void FCBParsingHelper::parseAppearance(FcbReader &r, std::size_t appearancePos) {
  parseAppearanceInto(r, appearancePos, materials, textures, textureVertices,
                      defaultThemeTexture, defaultThemeMaterial);
}

inline bool FCBParsingHelper::parseColumns(FcbReader &r, std::size_t columnsPos,
                                           std::vector<ColumnInfo> &out) {
  // columnsPos is the position of the vector's offset field.
  uint32_t offset;
  if (!r.read(columnsPos, offset)) return false;
  std::size_t vectorPos = columnsPos + offset;
  std::size_t count, dataPos;
  if (!r.vectorAtField(vectorPos, 4, count, dataPos)) return false;
  out.clear();
  out.reserve(count);
  for (std::size_t i = 0; i < count; ++i) {
    std::size_t columnPos;
    if (!r.tableElementAt(dataPos, i, columnPos)) return false;
    ColumnInfo column;
    // The writer omits scalar fields equal to their schema default, so an
    // absent index is 0 and an absent type is Byte.
    column.index = 0;
    r.scalar(columnPos, COLUMN_INDEX, column.index);
    if (!r.stringField(columnPos, COLUMN_NAME, column.name)) return false;
    column.type = 0;
    r.scalar(columnPos, COLUMN_TYPE, column.type);
    out.push_back(column);
  }
  return true;
}

inline void FCBParsingHelper::decodeAttributes(FcbReader &r, std::size_t attributesPos,
                                               const std::vector<ColumnInfo> &schema,
                                               AzulObject &object) {
  // Attributes are a run of (u16 column index, typed value) pairs; a value's
  // type and length come from the column schema, and null is only expressible
  // by omitting the pair. attributesPos is the position of the vector's
  // offset field.
  if (schema.empty()) {
    std::cout << "FCB: attribute blob without a column schema" << std::endl;
    return;
  }
  std::unordered_map<uint16_t, const ColumnInfo *> byIndex;
  byIndex.reserve(schema.size());
  for (const ColumnInfo &column: schema) byIndex[column.index] = &column;

  uint32_t vectorOffset;
  if (!r.read(attributesPos, vectorOffset)) return;
  std::size_t vectorPos = attributesPos + vectorOffset;
  uint32_t blobLength;
  if (!r.read(vectorPos, blobLength)) return;
  std::size_t blobPos = vectorPos + 4;
  if (!r.inBounds(blobPos, blobLength)) return;

  std::size_t at = 0;
  while (at < blobLength) {
    uint16_t columnIndex;
    if (!r.read(blobPos + at, columnIndex)) return;
    at += 2;
    auto found = byIndex.find(columnIndex);
    if (found == byIndex.end()) {
      std::cout << "FCB: attribute references unknown column index " << columnIndex << std::endl;
      return;
    }
    const ColumnInfo &column = *found->second;
    std::string value;
    switch (column.type) {
      case COLUMN_TYPE_BYTE:
      case COLUMN_TYPE_UBYTE: {
        uint8_t v;
        if (!r.read(blobPos + at, v)) return;
        at += 1;
        value = std::to_string(v);
        break;
      }
      case COLUMN_TYPE_BOOL: {
        uint8_t v;
        if (!r.read(blobPos + at, v)) return;
        at += 1;
        value = v != 0 ? "true" : "false";
        break;
      }
      case COLUMN_TYPE_SHORT: {
        int16_t v;
        if (!r.read(blobPos + at, v)) return;
        at += 2;
        value = std::to_string(v);
        break;
      }
      case COLUMN_TYPE_USHORT: {
        uint16_t v;
        if (!r.read(blobPos + at, v)) return;
        at += 2;
        value = std::to_string(v);
        break;
      }
      case COLUMN_TYPE_INT: {
        int32_t v;
        if (!r.read(blobPos + at, v)) return;
        at += 4;
        value = std::to_string(v);
        break;
      }
      case COLUMN_TYPE_UINT: {
        uint32_t v;
        if (!r.read(blobPos + at, v)) return;
        at += 4;
        value = std::to_string(v);
        break;
      }
      case COLUMN_TYPE_LONG: {
        int64_t v;
        if (!r.read(blobPos + at, v)) return;
        at += 8;
        value = std::to_string(v);
        break;
      }
      case COLUMN_TYPE_ULONG: {
        uint64_t v;
        if (!r.read(blobPos + at, v)) return;
        at += 8;
        value = std::to_string(v);
        break;
      }
      case COLUMN_TYPE_FLOAT: {
        uint32_t bits;
        if (!r.read(blobPos + at, bits)) return;
        at += 4;
        float f;
        std::memcpy(&f, &bits, sizeof(f));
        value = std::to_string(static_cast<double>(f));
        break;
      }
      case COLUMN_TYPE_DOUBLE: {
        double d;
        if (!r.read(blobPos + at, d)) return;
        at += 8;
        value = std::to_string(d);
        break;
      }
      case COLUMN_TYPE_STRING:
      case COLUMN_TYPE_DATETIME: {
        uint32_t length;
        if (!r.read(blobPos + at, length)) return;
        at += 4;
        if (!r.inBounds(blobPos + at, length)) return;
        value.assign(reinterpret_cast<const char *>(r.data + blobPos + at), length);
        at += length;
        break;
      }
      case COLUMN_TYPE_JSON:
      case COLUMN_TYPE_BINARY: {
        // Complex values have no string form in azul's attribute model; the
        // JSON parser skips them too.
        uint32_t length;
        if (!r.read(blobPos + at, length)) return;
        at += 4;
        if (!r.inBounds(blobPos + at, length)) return;
        at += length;
        std::cout << "FCB: complex attribute " << column.name << " skipped" << std::endl;
        continue;
      }
      default:
        std::cout << "FCB: unknown attribute type " << static_cast<int>(column.type) << std::endl;
        return;
    }
    object.attributes.push_back(std::pair<std::string, std::string>(column.name, value));
  }
}

inline bool FCBParsingHelper::parseMaterialMapping(FcbReader &r, std::size_t pos,
                                                   MaterialMapping &out) {
  out.hasValues = false;
  r.stringField(pos, MATERIAL_MAPPING_THEME, out.theme);
  out.hasSharedValue = false;
  out.sharedValue = NULL_INDEX;
  uint32_t sharedValue;
  if (r.scalar(pos, MATERIAL_MAPPING_VALUE, sharedValue)) {
    out.hasSharedValue = true;
    out.sharedValue = sharedValue;
    out.hasValues = true;
  }
  if (r.u32Vector(pos, MATERIAL_MAPPING_VERTICES, out.values)) out.hasValues = true;
  r.u32Vector(pos, MATERIAL_MAPPING_SOLIDS, out.solids);
  r.u32Vector(pos, MATERIAL_MAPPING_SHELLS, out.shells);
  return r.valid;
}

inline bool FCBParsingHelper::parseTextureMapping(FcbReader &r, std::size_t pos,
                                                  TextureMapping &out) {
  out.hasValues = false;
  r.stringField(pos, TEXTURE_MAPPING_THEME, out.theme);
  if (r.u32Vector(pos, TEXTURE_MAPPING_VERTICES, out.values)) out.hasValues = true;
  r.u32Vector(pos, TEXTURE_MAPPING_SOLIDS, out.solids);
  r.u32Vector(pos, TEXTURE_MAPPING_SHELLS, out.shells);
  r.u32Vector(pos, TEXTURE_MAPPING_SURFACES, out.surfaces);
  r.u32Vector(pos, TEXTURE_MAPPING_STRINGS, out.strings);
  return r.valid;
}

// A geometry may carry several theme mappings; pick the default theme when
// present, otherwise the first mapping that carries values, mirroring how the
// JSON parser picks a theme out of a theme-keyed object (themes without
// values are skipped there). Mapping order in FCB is the writer's sorted
// theme order, which is why the values check matters.
template <typename Mapping>
const Mapping *FCBParsingHelper::selectMapping(const std::vector<Mapping> &mappings,
                                               const std::string &defaultTheme) {
  if (mappings.empty()) return nullptr;
  const Mapping *fallback = nullptr;
  for (const Mapping &mapping: mappings) {
    if (!mapping.hasValues) continue;
    if (fallback == nullptr) fallback = &mapping;
    if (mapping.theme == defaultTheme) return &mapping;
  }
  return fallback;
}

// --------------------------------------------------------------------- //
// Surface walker: reconstructs surfaces (polygons) from the flattened     //
// count arrays, with their semantic/material indices and per-ring         //
// texture leaves, at the depth the geometry type implies. The redundant   //
// count level the encoder writes above a type's own depth is ignored.     //
// --------------------------------------------------------------------- //
inline void FCBParsingHelper::walkSurfaces(FcbReader &r, uint8_t geometryType,
                                           const std::vector<uint32_t> &solids,
                                           const std::vector<uint32_t> &shells,
                                           const std::vector<uint32_t> &surfaces,
                                           const std::vector<uint32_t> &strings,
                                           const std::vector<uint32_t> &boundaries,
                                           const std::vector<uint32_t> &semanticsValues,
                                           const MaterialMapping *material,
                                           const TextureMapping *texture,
                                           std::vector<FcbSurface> &out) {
  out.clear();

  std::size_t surfaceCursor = 0; // surfaces[]: rings per surface
  std::size_t shellCursor = 0;   // shells[]: surfaces per shell
  std::size_t stringCursor = 0;  // strings[]: vertex indices per ring
  std::size_t boundaryCursor = 0;
  std::size_t semanticCursor = 0;
  std::size_t materialShellCursor = 0;
  std::size_t materialValueCursor = 0;
  std::size_t textureSurfaceCursor = 0;
  std::size_t textureShellCursor = 0;
  std::size_t textureStringCursor = 0;
  std::size_t textureValueCursor = 0;

  auto takeRing = [&](std::vector<uint32_t> &ring) {
    uint32_t ringSize = (stringCursor < strings.size()) ? strings[stringCursor] : 0;
    ++stringCursor;
    if (boundaryCursor > boundaries.size() || boundaries.size() - boundaryCursor < ringSize) {
      r.valid = false;
      return;
    }
    ring.assign(boundaries.begin() + boundaryCursor, boundaries.begin() + boundaryCursor + ringSize);
    boundaryCursor += ringSize;
  };
  auto takeSurface = [&](FcbSurface &surface) {
    uint32_t ringCount = (surfaceCursor < surfaces.size()) ? surfaces[surfaceCursor] : 0;
    ++surfaceCursor;
    for (uint32_t k = 0; k < ringCount; ++k) {
      surface.rings.push_back(std::vector<uint32_t>());
      takeRing(surface.rings.back());
      if (!r.valid) return;
    }
  };
  auto takeSemanticIndex = [&]() -> uint32_t {
    uint32_t index = NULL_INDEX;
    if (semanticCursor < semanticsValues.size()) index = semanticsValues[semanticCursor];
    ++semanticCursor;
    return index;
  };
  auto takeMaterialIndex = [&]() -> uint32_t {
    if (materialValueCursor >= material->values.size()) return NULL_INDEX;
    return material->values[materialValueCursor++];
  };
  auto materialIndexForSurface = [&](bool nullShell) -> uint32_t {
    if (material == nullptr || nullShell) return NULL_INDEX;
    // A shared value colours every surface of the geometry.
    if (material->hasSharedValue) return material->sharedValue;
    return takeMaterialIndex();
  };
  auto takeTextureRing = [&](std::vector<uint32_t> &leaf) {
    uint32_t leafSize = (textureStringCursor < texture->strings.size()) ? texture->strings[textureStringCursor] : 0;
    ++textureStringCursor;
    std::size_t end = std::min(textureValueCursor + leafSize, texture->values.size());
    leaf.assign(texture->values.begin() + textureValueCursor, texture->values.begin() + end);
    textureValueCursor = end;
  };

  if (geometryType == GEOMETRY_TYPE_MULTISURFACE ||
      geometryType == GEOMETRY_TYPE_COMPOSITESURFACE) {
    // One surface per `surfaces` entry; `shells` is the redundant level.
    for (std::size_t i = 0; i < surfaces.size(); ++i) {
      FcbSurface surface;
      takeSurface(surface);
      surface.semanticIndex = takeSemanticIndex();
      surface.materialIndex = materialIndexForSurface(false);
      uint32_t textureRingCount = 0;
      if (texture != nullptr && textureSurfaceCursor < texture->surfaces.size()) {
        textureRingCount = texture->surfaces[textureSurfaceCursor];
      }
      ++textureSurfaceCursor;
      for (uint32_t k = 0; k < textureRingCount; ++k) {
        surface.textureRings.push_back(std::vector<uint32_t>());
        takeTextureRing(surface.textureRings.back());
      }
      out.push_back(surface);
      if (!r.valid) return;
    }
  } else if (geometryType == GEOMETRY_TYPE_SOLID) {
    // One shell per `shells` entry; `solids` is the redundant level.
    for (std::size_t i = 0; i < shells.size(); ++i) {
      uint32_t surfaceCount = shells[i];
      // A NULL shell count means none of its surfaces has a material.
      uint32_t materialCount = 0;
      bool nullMaterialShell = false;
      if (material != nullptr && materialShellCursor < material->shells.size()) {
        materialCount = material->shells[materialShellCursor];
      }
      ++materialShellCursor;
      nullMaterialShell = materialCount == NULL_INDEX;
      uint32_t textureShellCount = 0;
      if (texture != nullptr && i < texture->shells.size()) textureShellCount = texture->shells[i];
      for (uint32_t k = 0; k < surfaceCount; ++k) {
        FcbSurface surface;
        takeSurface(surface);
        surface.semanticIndex = takeSemanticIndex();
        surface.materialIndex = materialIndexForSurface(nullMaterialShell);
        uint32_t textureRingCount = 0;
        if (k < textureShellCount && texture != nullptr &&
            textureSurfaceCursor < texture->surfaces.size()) {
          textureRingCount = texture->surfaces[textureSurfaceCursor];
        }
        ++textureSurfaceCursor;
        for (uint32_t ring = 0; ring < textureRingCount; ++ring) {
          surface.textureRings.push_back(std::vector<uint32_t>());
          takeTextureRing(surface.textureRings.back());
        }
        out.push_back(surface);
        if (!r.valid) return;
      }
    }
  } else if (geometryType == GEOMETRY_TYPE_MULTISOLID ||
             geometryType == GEOMETRY_TYPE_COMPOSITESOLID) {
    // `solids[i]` shells in the i-th solid; nothing above it.
    for (std::size_t i = 0; i < solids.size(); ++i) {
      uint32_t solidShellCount = solids[i];
      uint32_t materialSolidCount = 0;
      bool nullMaterialSolid = false;
      if (material != nullptr && i < material->solids.size()) materialSolidCount = material->solids[i];
      nullMaterialSolid = materialSolidCount == NULL_INDEX;
      uint32_t textureSolidCount = 0;
      if (texture != nullptr && i < texture->solids.size()) textureSolidCount = texture->solids[i];
      for (uint32_t j = 0; j < solidShellCount; ++j) {
        uint32_t surfaceCount = (shellCursor < shells.size()) ? shells[shellCursor] : 0;
        ++shellCursor;
        // Material per shell; a NULL count is a whole null shell.
        uint32_t materialCount = 0;
        bool nullMaterialShell = false;
        if (material != nullptr && !nullMaterialSolid && materialShellCursor < material->shells.size()) {
          materialCount = material->shells[materialShellCursor];
        }
        ++materialShellCursor;
        nullMaterialShell = materialCount == NULL_INDEX;
        uint32_t textureShellCount = 0;
        if (texture != nullptr && j < textureSolidCount &&
            textureShellCursor < texture->shells.size()) {
          textureShellCount = texture->shells[textureShellCursor];
        }
        ++textureShellCursor;
        for (uint32_t k = 0; k < surfaceCount; ++k) {
          FcbSurface surface;
          takeSurface(surface);
          surface.semanticIndex = takeSemanticIndex();
          surface.materialIndex = materialIndexForSurface(nullMaterialSolid || nullMaterialShell);
          uint32_t textureRingCount = 0;
          if (k < textureShellCount && texture != nullptr &&
              textureSurfaceCursor < texture->surfaces.size()) {
            textureRingCount = texture->surfaces[textureSurfaceCursor];
          }
          ++textureSurfaceCursor;
          for (uint32_t ring = 0; ring < textureRingCount; ++ring) {
            surface.textureRings.push_back(std::vector<uint32_t>());
            takeTextureRing(surface.textureRings.back());
          }
          out.push_back(surface);
          if (!r.valid) return;
        }
      }
    }
  }
}

// --------------------------------------------------------------------- //
// Geometry                                                               //
// --------------------------------------------------------------------- //
inline void FCBParsingHelper::parseGeometry(FcbReader &r, std::size_t geometryPos,
                                            AzulObject &object,
                                            const std::vector<std::tuple<double, double, double>> &vertices) {
  uint8_t geometryType;
  if (!r.scalar(geometryPos, GEOMETRY_TYPE, geometryType)) return;

  std::string lod;
  r.stringField(geometryPos, GEOMETRY_LOD, lod);

  if (geometryType != GEOMETRY_TYPE_MULTISURFACE &&
      geometryType != GEOMETRY_TYPE_COMPOSITESURFACE &&
      geometryType != GEOMETRY_TYPE_SOLID &&
      geometryType != GEOMETRY_TYPE_MULTISOLID &&
      geometryType != GEOMETRY_TYPE_COMPOSITESOLID) {
    // MultiPoint and MultiLineString are not rendered by azul; a
    // GeometryInstance appears in geometry_instances instead.
    return;
  }

  std::vector<uint32_t> solids, shells, surfaces, strings, boundaries;
  r.u32Vector(geometryPos, GEOMETRY_SOLIDS, solids);
  r.u32Vector(geometryPos, GEOMETRY_SHELLS, shells);
  r.u32Vector(geometryPos, GEOMETRY_SURFACES, surfaces);
  r.u32Vector(geometryPos, GEOMETRY_STRINGS, strings);
  r.u32Vector(geometryPos, GEOMETRY_BOUNDARIES, boundaries);
  if (!r.valid) return;

  std::vector<uint32_t> semanticsValues;
  r.u32Vector(geometryPos, GEOMETRY_SEMANTICS, semanticsValues);
  std::vector<std::size_t> semanticsObjects;
  r.tableVector(geometryPos, GEOMETRY_SEMANTICS_OBJECTS, semanticsObjects);

  std::vector<std::size_t> materialPositions;
  std::vector<MaterialMapping> materialMappings;
  if (r.tableVector(geometryPos, GEOMETRY_MATERIAL, materialPositions)) {
    for (std::size_t pos: materialPositions) {
      MaterialMapping mapping;
      if (parseMaterialMapping(r, pos, mapping)) materialMappings.push_back(mapping);
    }
  }
  std::vector<std::size_t> texturePositions;
  std::vector<TextureMapping> textureMappings;
  if (r.tableVector(geometryPos, GEOMETRY_TEXTURE, texturePositions)) {
    for (std::size_t pos: texturePositions) {
      TextureMapping mapping;
      if (parseTextureMapping(r, pos, mapping)) textureMappings.push_back(mapping);
    }
  }
  if (!r.valid) return;

  object.children.push_back(AzulObject());
  object.children.back().type = "LoD";
  object.children.back().id = lod.empty() ? "unknown" : lod;
  AzulObject &lodObject = object.children.back();

  const MaterialMapping *material = selectMapping(materialMappings, defaultThemeMaterial);
  const TextureMapping *texture = selectMapping(textureMappings, defaultThemeTexture);

  std::vector<FcbSurface> surfacesOut;
  walkSurfaces(r, geometryType, solids, shells, surfaces, strings, boundaries,
               semanticsValues, material, texture, surfacesOut);
  if (!r.valid) return;

  for (const FcbSurface &surface: surfacesOut) {
    addPolygonForSurface(r, surface, lodObject, semanticsObjects, material, texture, vertices);
    if (!r.valid) return;
  }
}

inline void FCBParsingHelper::addPolygonForSurface(FcbReader &r, const FcbSurface &surface,
                                                   AzulObject &lodObject,
                                                   const std::vector<std::size_t> &semanticsObjects,
                                                   const MaterialMapping *material,
                                                   const TextureMapping *texture,
                                                   const std::vector<std::tuple<double, double, double>> &vertices) {
  AzulObject *targetObject = &lodObject;

  // A surface with a valid semantic index becomes a child object carrying
  // the semantic surface's type and attributes, as in the JSON parser.
  if (surface.semanticIndex != NULL_INDEX && surface.semanticIndex < semanticsObjects.size()) {
    std::size_t semanticObjectPos = semanticsObjects[surface.semanticIndex];
    lodObject.children.push_back(AzulObject());
    targetObject = &lodObject.children.back();
    std::string extensionType;
    if (r.stringField(semanticObjectPos, SEMANTIC_OBJECT_EXTENSION_TYPE, extensionType) && !extensionType.empty()) {
      targetObject->type = extensionType;
    } else {
      uint8_t semanticType = 0; // absent means the default (RoofSurface)
      r.scalar(semanticObjectPos, SEMANTIC_OBJECT_TYPE, semanticType);
      targetObject->type = semanticSurfaceTypeName(semanticType);
    }
    std::size_t attributesPos;
    if (r.fieldPos(semanticObjectPos, SEMANTIC_OBJECT_ATTRIBUTES, attributesPos)) {
      decodeAttributes(r, attributesPos, semanticColumns, *targetObject);
    }
    // The parent index links a surface back to its group (e.g. a Door to its
    // WallSurface); the JSON parser keeps it as a plain attribute too.
    uint32_t parentIndex;
    if (r.scalar(semanticObjectPos, SEMANTIC_OBJECT_PARENT, parentIndex) &&
        parentIndex != NULL_INDEX) {
      targetObject->attributes.push_back(
          std::pair<std::string, std::string>("parent", std::to_string(parentIndex)));
    }
  }

  targetObject->polygons.push_back(AzulPolygon());
  AzulPolygon &polygon = targetObject->polygons.back();

  for (std::size_t i = 0; i < surface.rings.size(); ++i) {
    AzulRing ring;
    for (uint32_t vertexIndex: surface.rings[i]) {
      if (vertexIndex < vertices.size()) {
        ring.points.push_back(AzulPoint());
        ring.points.back().coordinates[0] = std::get<0>(vertices[vertexIndex]);
        ring.points.back().coordinates[1] = std::get<1>(vertices[vertexIndex]);
        ring.points.back().coordinates[2] = std::get<2>(vertices[vertexIndex]);
      }
    }

    // Close the ring (first point repeated at the end), as the JSON parser
    // does, so the texture coordinate handling below can match it exactly.
    if (!ring.points.empty()) ring.points.push_back(ring.points.front());

    // Texture coordinates: the ring's leaf is [texture index, UV indices...],
    // one UV per ring vertex before closing. Mirrors the JSON parser's
    // applyTextureCoordinatesToRing, closed-ring handling included.
    if (i < surface.textureRings.size() && surface.textureRings[i].size() >= 2) {
      const std::vector<uint32_t> &leaf = surface.textureRings[i];
      std::size_t ringPointCount = ring.points.size();
      bool closedRing = false;
      if (ringPointCount >= 2 &&
          ring.points.front().coordinates[0] == ring.points.back().coordinates[0] &&
          ring.points.front().coordinates[1] == ring.points.back().coordinates[1] &&
          ring.points.front().coordinates[2] == ring.points.back().coordinates[2]) {
        closedRing = true;
      }
      std::size_t expectedPointCount = closedRing && ringPointCount > 0 ? ringPointCount - 1 : ringPointCount;
      std::size_t uvCount = leaf.size() - 1;
      if ((uvCount == expectedPointCount || uvCount == ringPointCount) &&
          leaf[0] != NULL_INDEX && leaf[0] < textures.size()) {
        bool validUVs = true;
        for (std::size_t j = 1; j < leaf.size(); ++j) {
          if (leaf[j] >= textureVertices.size()) {
            validUVs = false;
            break;
          }
        }
        if (validUVs) {
          ring.textureCoordinates.clear();
          for (std::size_t j = 1; j < leaf.size(); ++j) {
            ring.textureCoordinates.push_back(textureVertices[leaf[j]]);
          }
          if (uvCount == expectedPointCount && closedRing && !ring.textureCoordinates.empty()) {
            ring.textureCoordinates.push_back(ring.textureCoordinates.front());
          }
          ring.hasTextureCoordinates = true;
        }
      }
    }
    if (i == 0) polygon.exteriorRing = ring;
    else polygon.interiorRings.push_back(ring);
  }

  polygon.appearanceStyleId = buildStyleForSurface(polygon, surface, material, texture);
}

inline int FCBParsingHelper::buildStyleForSurface(AzulPolygon &polygon, const FcbSurface &surface,
                                                  const MaterialMapping *material,
                                                  const TextureMapping *texture) {
  AzulAppearanceStyle style;
  bool hasStyle = false;

  // Material colour: diffuse color with alpha from transparency.
  if (material != nullptr && !material->theme.empty() &&
      surface.materialIndex != NULL_INDEX && surface.materialIndex < materials.size()) {
    const ParsedMaterial &parsedMaterial = materials[surface.materialIndex];
    style.hasMaterial = true;
    style.materialColour[0] = parsedMaterial.hasDiffuseColor ? parsedMaterial.diffuseColor[0] : 0.75f;
    style.materialColour[1] = parsedMaterial.hasDiffuseColor ? parsedMaterial.diffuseColor[1] : 0.75f;
    style.materialColour[2] = parsedMaterial.hasDiffuseColor ? parsedMaterial.diffuseColor[2] : 0.75f;
    float transparency = parsedMaterial.hasTransparency ? parsedMaterial.transparency : 0.0f;
    if (transparency < 0.0f) transparency = 0.0f;
    if (transparency > 1.0f) transparency = 1.0f;
    style.materialColour[3] = 1.0f - transparency;
    hasStyle = true;
  }

  // Texture: one image per polygon; the last ring with a texture wins, and
  // rings without a texture drop their coordinates, as in the JSON parser.
  bool hasTexture = false;
  std::string textureUri;
  bool appliedExteriorTexture = false;
  if (texture != nullptr && !texture->theme.empty()) {
    std::size_t ringIndex = 0;
    for (const std::vector<uint32_t> &leaf: surface.textureRings) {
      if (leaf.size() >= 1 && leaf[0] != NULL_INDEX && leaf[0] < textures.size()) {
        hasTexture = true;
        textureUri = textures[leaf[0]];
        if (ringIndex == 0) appliedExteriorTexture = true;
      }
      ++ringIndex;
    }
  }
  if (!appliedExteriorTexture) polygon.exteriorRing.hasTextureCoordinates = false;
  for (AzulRing &ring: polygon.interiorRings) {
    if (!ring.hasTextureCoordinates) ring.textureCoordinates.clear();
  }
  if (hasTexture) {
    style.hasTexture = true;
    style.textureUri = textureUri;
    hasStyle = true;
  }

  if (!hasStyle) return -1;
  if (style.hasTexture && texture != nullptr && !texture->theme.empty()) style.theme = texture->theme;
  else if (style.hasMaterial && material != nullptr && !material->theme.empty()) style.theme = material->theme;
  if (!style.theme.empty()) parsedThemes.insert(style.theme);
  return addOrGetStyleId(style);
}

// --------------------------------------------------------------------- //
// City objects and features                                              //
// --------------------------------------------------------------------- //
inline void FCBParsingHelper::parseCityObject(FcbReader &r, std::size_t objectPos,
                                              AzulObject &object, std::size_t childIndex) {
  // Type: the extension string when present, otherwise the enumerator name
  // (absent means the default, Bridge).
  std::string extensionType;
  if (r.stringField(objectPos, CITY_OBJECT_EXTENSION_TYPE, extensionType) && !extensionType.empty()) {
    object.type = extensionType;
  } else {
    uint8_t type = 0;
    r.scalar(objectPos, CITY_OBJECT_TYPE, type);
    object.type = cityObjectTypeName(type);
  }
  r.stringField(objectPos, CITY_OBJECT_ID, object.id);

  // Attributes, decoded against the object's own column schema when it
  // declares one, otherwise the header's.
  std::size_t attributesPos;
  if (r.fieldPos(objectPos, CITY_OBJECT_ATTRIBUTES, attributesPos)) {
    std::size_t ownColumnsPos;
    if (r.fieldPos(objectPos, CITY_OBJECT_COLUMNS, ownColumnsPos)) {
      std::vector<ColumnInfo> ownColumns;
      if (parseColumns(r, ownColumnsPos, ownColumns)) decodeAttributes(r, attributesPos, ownColumns, object);
    } else {
      decodeAttributes(r, attributesPos, columns, object);
    }
  }

  std::vector<std::string> parents;
  if (r.stringVector(objectPos, CITY_OBJECT_PARENTS, parents)) {
    for (const std::string &parent: parents) {
      deferredParentRelationships.emplace_back(parent, childIndex);
    }
  }

  std::vector<std::size_t> geometry;
  if (r.tableVector(objectPos, CITY_OBJECT_GEOMETRY, geometry)) {
    for (std::size_t geometryPos: geometry) {
      parseGeometry(r, geometryPos, object, featureVertices);
      if (!r.valid) return;
    }
  }

  std::vector<std::size_t> instances;
  if (r.tableVector(objectPos, CITY_OBJECT_GEOMETRY_INSTANCES, instances)) {
    for (std::size_t instancePos: instances) {
      parseGeometryInstance(r, instancePos, object, featureVertices);
      if (!r.valid) return;
    }
  }
}

inline void FCBParsingHelper::parseGeometryInstance(FcbReader &r, std::size_t instancePos,
                                                    AzulObject &object,
                                                    const std::vector<std::tuple<double, double, double>> &vertices) {
  std::size_t transformPos;
  if (!r.fieldPos(instancePos, GEOMETRY_INSTANCE_TRANSFORMATION, transformPos)) return;
  double matrix[16];
  for (int i = 0; i < 16; ++i) {
    if (!r.read(transformPos + 8 * i, matrix[i])) return;
  }
  uint32_t templateIndex = 0;
  // Absent means the default (0), which the writer omits.
  r.scalar(instancePos, GEOMETRY_INSTANCE_TEMPLATE, templateIndex);
  std::vector<uint32_t> boundaries;
  if (!r.u32Vector(instancePos, GEOMETRY_INSTANCE_BOUNDARIES, boundaries)) return;
  if (boundaries.empty() || templateIndex >= templateChildren.size()) return;
  uint32_t anchorIndex = boundaries[0];
  if (anchorIndex >= vertices.size()) return;

  object.children.push_back(AzulObject(templateChildren[templateIndex]));
  AzulObject &child = object.children.back();
  // FlatCityBuf drops the instance's LoD (the schema has no field for it);
  // the template's LoD is the best available reconstruction.
  if (child.id.empty()) child.id = "unknown";

  transformPolygons(child, matrix, std::get<0>(vertices[anchorIndex]),
                    std::get<1>(vertices[anchorIndex]), std::get<2>(vertices[anchorIndex]));
}

inline void FCBParsingHelper::transformPolygons(AzulObject &object, const double matrix[16],
                                                double anchorX, double anchorY, double anchorZ) {
  auto transformPoint = [&](AzulPoint &point) {
    // Note: uses the original coordinates for every axis, unlike the JSON
    // parser's inline-mutating version of this expansion.
    double px = point.coordinates[0];
    double py = point.coordinates[1];
    double pz = point.coordinates[2];
    double homogeneousCoordinate = matrix[12] * px + matrix[13] * py + matrix[14] * pz + matrix[15];
    point.coordinates[0] = (matrix[0] * px + matrix[1] * py + matrix[2] * pz + matrix[3]) /
                               homogeneousCoordinate +
                           anchorX;
    point.coordinates[1] = (matrix[4] * px + matrix[5] * py + matrix[6] * pz + matrix[7]) /
                               homogeneousCoordinate +
                           anchorY;
    point.coordinates[2] = (matrix[8] * px + matrix[9] * py + matrix[10] * pz + matrix[11]) /
                               homogeneousCoordinate +
                           anchorZ;
  };
  for (AzulPolygon &polygon: object.polygons) {
    for (AzulPoint &point: polygon.exteriorRing.points) transformPoint(point);
    for (AzulRing &ring: polygon.interiorRings) {
      for (AzulPoint &point: ring.points) transformPoint(point);
    }
  }
  for (AzulObject &child: object.children) transformPolygons(child, matrix, anchorX, anchorY, anchorZ);
}

// --------------------------------------------------------------------- //
// Hierarchy (same deferred-parent approach as the JSON parser)           //
// --------------------------------------------------------------------- //
inline void FCBParsingHelper::buildHierarchy(AzulObject &parsedFile) {
  if (deferredParentRelationships.empty()) return;

  std::unordered_map<std::string, std::size_t> idToIndex;
  idToIndex.reserve(parsedFile.children.size());
  for (std::size_t i = 0; i < parsedFile.children.size(); ++i) {
    idToIndex[parsedFile.children[i].id] = i;
  }

  std::vector<std::vector<std::size_t>> parentToChildrenIndices(parsedFile.children.size());
  std::vector<uint8_t> isChild(parsedFile.children.size(), false);
  for (const auto &[parentId, childIdx]: deferredParentRelationships) {
    auto parentIt = idToIndex.find(parentId);
    if (parentIt == idToIndex.end()) continue;
    parentToChildrenIndices[parentIt->second].push_back(childIdx);
    isChild[childIdx] = true;
  }

  std::vector<std::size_t> rootIndices;
  for (std::size_t i = 0; i < parsedFile.children.size(); ++i) {
    if (!isChild[i]) rootIndices.push_back(i);
  }

  std::vector<AzulObject> hierarchicalChildren;
  std::vector<uint8_t> moved(parsedFile.children.size(), false);
  hierarchicalChildren.reserve(rootIndices.size());

  std::vector<std::pair<std::vector<AzulObject> *, std::size_t>> stack;
  stack.reserve(parsedFile.children.size());

  for (std::size_t rootIdx: rootIndices) {
    moved[rootIdx] = true;
    hierarchicalChildren.push_back(std::move(parsedFile.children[rootIdx]));
    AzulObject &root = hierarchicalChildren.back();
    root.children.reserve(parentToChildrenIndices[rootIdx].size());
    stack.emplace_back(&root.children, rootIdx);
  }

  while (!stack.empty()) {
    auto [slot, parentIdx] = stack.back();
    stack.pop_back();
    for (std::size_t childIdx: parentToChildrenIndices[parentIdx]) {
      if (moved[childIdx]) continue;
      moved[childIdx] = true;
      slot->push_back(std::move(parsedFile.children[childIdx]));
      AzulObject &child = slot->back();
      child.children.reserve(parentToChildrenIndices[childIdx].size());
      stack.emplace_back(&child.children, childIdx);
    }
  }

  parsedFile.children = std::move(hierarchicalChildren);
}

// --------------------------------------------------------------------- //
// Entry point                                                            //
// --------------------------------------------------------------------- //
inline void FCBParsingHelper::parse(const char *filePath, AzulObject &parsedFile) {
  std::ifstream file(filePath, std::ios::binary | std::ios::ate);
  if (!file) {
    std::cout << "Failed to open file: " << filePath << std::endl;
    statusMessage = "Failed to open FlatCityBuf file";
    return;
  }
  std::streamsize fileSize = file.tellg();
  if (fileSize < 12) {
    statusMessage = "Not a FlatCityBuf file";
    return;
  }
  std::vector<uint8_t> bytes(static_cast<std::size_t>(fileSize));
  file.seekg(0);
  file.read(reinterpret_cast<char *>(bytes.data()), fileSize);

  FcbReader r{bytes.data(), bytes.size()};

  // Magic bytes; byte 3 is the version and must be <= 1.
  if (std::memcmp(bytes.data(), "fcb", 3) != 0 || std::memcmp(bytes.data() + 4, "fcb", 3) != 0 ||
      bytes[3] > 1) {
    statusMessage = "Not a FlatCityBuf file";
    return;
  }

  parsedFile.type = "File";
  parsedFile.id = filePath;
  currentFilePath = filePath;
  resetAppearanceForNewFile();
  deferredParentRelationships.clear();
  columns.clear();
  semanticColumns.clear();
  templateChildren.clear();
  featureVertices.clear();
  for (int i = 0; i < 3; ++i) {
    scale[i] = 1.0;
    translate[i] = 0.0;
  }

  auto fail = [&](const char *reason) {
    std::cout << "FCB parse error: " << reason << std::endl;
    parsedFile.children.clear();
    parsedFile.attributes.clear();
    statusMessage = "Failed to parse FlatCityBuf file";
  };

  uint32_t headerSize;
  if (!r.read(8, headerSize) || headerSize < 8 || headerSize > 536870912) {
    fail("bad header size");
    return;
  }

  // The header is a size-prefixed FlatBuffer starting right after the
  // 4-byte size prefix (i.e. at file offset 12).
  std::size_t headerRoot;
  if (!r.rootAt(12, headerRoot)) {
    fail("bad header");
    return;
  }

  // Transform (struct: scale then translate, three doubles each).
  std::size_t transformPos;
  if (r.fieldPos(headerRoot, HEADER_TRANSFORM, transformPos)) {
    for (int i = 0; i < 3; ++i) r.read(transformPos + 8 * i, scale[i]);
    for (int i = 0; i < 3; ++i) r.read(transformPos + 24 + 8 * i, translate[i]);
  }

  std::size_t columnsPos;
  if (r.fieldPos(headerRoot, HEADER_COLUMNS, columnsPos)) parseColumns(r, columnsPos, columns);
  std::size_t semanticColumnsPos;
  if (r.fieldPos(headerRoot, HEADER_SEMANTIC_COLUMNS, semanticColumnsPos)) parseColumns(r, semanticColumnsPos, semanticColumns);
  if (!r.valid) {
    fail("bad header columns");
    return;
  }

  uint64_t featuresCount = 0;
  r.scalar(headerRoot, HEADER_FEATURES_COUNT, featuresCount);
  uint16_t indexNodeSize = 16; // default when the field is absent
  r.scalar(headerRoot, HEADER_INDEX_NODE_SIZE, indexNodeSize);

  // Byte lengths of the skipped index sections.
  uint64_t rtreeSize = 0;
  if (indexNodeSize != 0 && featuresCount != 0) {
    // Packed R-tree: ceil-divide the node count until one root remains.
    uint64_t nodeSize = indexNodeSize < 2 ? 2 : indexNodeSize;
    uint64_t n = featuresCount;
    uint64_t numNodes = n;
    for (;;) {
      n = (n + nodeSize - 1) / nodeSize;
      numNodes += n;
      if (n == 1) break;
    }
    rtreeSize = numNodes * 40;
  }
  uint64_t attrIndexSize = 0;
  std::size_t attrIndexCount, attrIndexPos;
  if (r.vectorAt(headerRoot, HEADER_ATTRIBUTE_INDEX, 16, attrIndexCount, attrIndexPos)) {
    for (std::size_t i = 0; i < attrIndexCount; ++i) {
      uint32_t length;
      if (!r.read(attrIndexPos + 16 * i + 4, length)) break;
      attrIndexSize += length;
    }
  }
  uint64_t featureBegin = 12 + headerSize + rtreeSize + attrIndexSize;
  if (featureBegin > bytes.size()) {
    fail("sections extend past end of file");
    return;
  }

  // Appearance palette (used by the geometry templates below).
  std::size_t appearancePos;
  if (r.offsetTarget(headerRoot, HEADER_APPEARANCE, appearancePos)) {
    parseAppearance(r, appearancePos);
    headerMaterials = materials;
    headerTextures = textures;
    headerTextureVertices = textureVertices;
    headerDefaultThemeTexture = defaultThemeTexture;
    headerDefaultThemeMaterial = defaultThemeMaterial;
  }

  // Reference system: "EPSG" + code by default, or the code_string.
  std::size_t referenceSystemPos;
  if (r.offsetTarget(headerRoot, HEADER_REFERENCE_SYSTEM, referenceSystemPos)) {
    std::string authority = "EPSG";
    std::string authorityValue;
    if (r.stringField(referenceSystemPos, REFERENCE_SYSTEM_AUTHORITY, authorityValue) && !authorityValue.empty()) {
      authority = authorityValue;
    }
    int32_t code = 0;
    r.scalar(referenceSystemPos, REFERENCE_SYSTEM_CODE, code);
    std::string codeString;
    std::string crsIdentifier;
    if (r.stringField(referenceSystemPos, REFERENCE_SYSTEM_CODE_STRING, codeString) && !codeString.empty()) {
      crsIdentifier = "https://www.opengis.net/def/crs/" + authority + "/0/" + codeString;
    } else if (code != 0) {
      crsIdentifier = "https://www.opengis.net/def/crs/" + authority + "/0/" + std::to_string(code);
    }
    parsedFile.crsIdentifier = crsIdentifier;
    if (!crsIdentifier.empty()) {
      parsedFile.attributes.push_back(std::pair<std::string, std::string>("referenceSystem", crsIdentifier));
    }
  }

  std::string version;
  r.stringField(headerRoot, HEADER_VERSION, version);
  std::string metadataValue;
  if (r.stringField(headerRoot, HEADER_IDENTIFIER, metadataValue) && !metadataValue.empty()) {
    parsedFile.attributes.push_back(std::pair<std::string, std::string>("identifier", metadataValue));
  }
  if (r.stringField(headerRoot, HEADER_REFERENCE_DATE, metadataValue) && !metadataValue.empty()) {
    parsedFile.attributes.push_back(std::pair<std::string, std::string>("referenceDate", metadataValue));
  }
  if (r.stringField(headerRoot, HEADER_TITLE, metadataValue) && !metadataValue.empty()) {
    parsedFile.attributes.push_back(std::pair<std::string, std::string>("title", metadataValue));
  }

  // Geometry templates: header-owned shapes whose vertices are absolute
  // doubles (no transform). Each becomes a LoD child of a placeholder
  // object; instances copy the child for the template index.
  std::size_t templateCount, templatePos;
  if (r.vectorAt(headerRoot, HEADER_TEMPLATES, 4, templateCount, templatePos)) {
    std::size_t templateVertexCount, templateVertexPos;
    std::vector<std::tuple<double, double, double>> templateVertices;
    if (r.vectorAt(headerRoot, HEADER_TEMPLATES_VERTICES, 24, templateVertexCount, templateVertexPos)) {
      for (std::size_t i = 0; i < templateVertexCount; ++i) {
        double x, y, z;
        if (!r.read(templateVertexPos + 24 * i, x) ||
            !r.read(templateVertexPos + 24 * i + 8, y) ||
            !r.read(templateVertexPos + 24 * i + 16, z)) break;
        templateVertices.emplace_back(x, y, z);
      }
    }
    for (std::size_t i = 0; i < templateCount; ++i) {
      std::size_t geometryPos;
      if (!r.tableElementAt(templatePos, i, geometryPos)) break;
      AzulObject holder;
      parseGeometry(r, geometryPos, holder, templateVertices);
      if (holder.children.empty()) {
        templateChildren.push_back(AzulObject());
      } else {
        templateChildren.push_back(std::move(holder.children.front()));
      }
    }
  }
  if (!r.valid) {
    fail("bad geometry templates");
    return;
  }

  // Features: sequential walk of size-prefixed CityFeature buffers.
  std::size_t pos = static_cast<std::size_t>(featureBegin);
  uint64_t featuresParsed = 0;
  while (pos + 4 <= bytes.size() && (featuresCount == 0 || featuresParsed < featuresCount)) {
    uint32_t featureSize;
    if (!r.read(pos, featureSize) || featureSize == 0 || pos + 4 + featureSize > bytes.size()) {
      fail("bad feature size");
      return;
    }
    std::size_t featureRoot;
    if (!r.rootAt(pos + 4, featureRoot)) {
      fail("bad feature");
      return;
    }

    // The feature's own appearance palette replaces the header's for its
    // objects; without one, the header palette is used.
    std::size_t featureAppearancePos;
    if (r.offsetTarget(featureRoot, FEATURE_APPEARANCE, featureAppearancePos)) {
      parseAppearance(r, featureAppearancePos);
    } else {
      materials = headerMaterials;
      textures = headerTextures;
      textureVertices = headerTextureVertices;
      defaultThemeTexture = headerDefaultThemeTexture;
      defaultThemeMaterial = headerDefaultThemeMaterial;
    }

    // Vertices: quantised int32 structs, dequantised with the header transform.
    featureVertices.clear();
    std::size_t vertexCount, vertexPos;
    if (r.vectorAt(featureRoot, FEATURE_VERTICES, 12, vertexCount, vertexPos)) {
      featureVertices.reserve(vertexCount);
      for (std::size_t i = 0; i < vertexCount; ++i) {
        int32_t vx, vy, vz;
        if (!r.read(vertexPos + 12 * i, vx) ||
            !r.read(vertexPos + 12 * i + 4, vy) ||
            !r.read(vertexPos + 12 * i + 8, vz)) break;
        featureVertices.emplace_back(scale[0] * vx + translate[0],
                                     scale[1] * vy + translate[1],
                                     scale[2] * vz + translate[2]);
      }
    }

    // Objects.
    std::size_t objectCount, objectPos;
    if (r.vectorAt(featureRoot, FEATURE_OBJECTS, 4, objectCount, objectPos)) {
      for (std::size_t i = 0; i < objectCount; ++i) {
        std::size_t cityObjectPos;
        if (!r.tableElementAt(objectPos, i, cityObjectPos)) break;
        parsedFile.children.push_back(AzulObject());
        parseCityObject(r, cityObjectPos, parsedFile.children.back(), parsedFile.children.size() - 1);
      }
    }

    pos += 4 + featureSize;
    ++featuresParsed;
    if (!r.valid) {
      fail("corrupt feature data");
      return;
    }
  }

  buildHierarchy(parsedFile);
  finalizeAppearanceForFile(parsedFile);
  statusMessage = "Loaded FlatCityBuf file";
}

#endif /* FCBParsingHelper_hpp */
