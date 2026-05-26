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

#ifndef AppearanceHelpers_hpp
#define AppearanceHelpers_hpp

#include <algorithm>
#include <filesystem>
#include <system_error>
#include <sstream>
#include <string>

#include "DataModel.hpp"

inline std::string appearanceStyleKey(const AzulAppearanceStyle &style) {
  std::ostringstream key;
  key << (style.hasTexture ? "T" : "N") << "|"
      << style.theme << "|"
      << style.textureUri << "|"
      << (style.hasMaterial ? "M" : "N") << "|"
      << static_cast<unsigned int>(llround(style.materialColour[0] * 255.0f)) << ","
      << static_cast<unsigned int>(llround(style.materialColour[1] * 255.0f)) << ","
      << static_cast<unsigned int>(llround(style.materialColour[2] * 255.0f)) << ","
      << static_cast<unsigned int>(llround(style.materialColour[3] * 255.0f));
  return key.str();
}

inline std::string resolveImageUri(std::string imageUri, const std::string &currentFilePath) {
  std::replace(imageUri.begin(), imageUri.end(), '\\', '/');
  if (imageUri.empty()) return "";
  if (imageUri.find("://") != std::string::npos) return imageUri;
  if (imageUri[0] == '/') return imageUri;
  if (imageUri.size() > 1 && imageUri[1] == ':') return imageUri;
  std::filesystem::path sourcePath(currentFilePath);
  std::filesystem::path resolved = (sourcePath.parent_path() / std::filesystem::path(imageUri)).lexically_normal();
  {
    std::error_code ec;
    if (std::filesystem::exists(resolved, ec)) return resolved.string();
  }

  // Accept both common folder names used in datasets: "appearance" and "appearances".
  std::string altImageUri = imageUri;
  std::size_t pluralPos = imageUri.find("appearances/");
  if (pluralPos != std::string::npos) {
    altImageUri.replace(pluralPos, std::string("appearances").size(), "appearance");
  } else {
    std::size_t singularPos = imageUri.find("appearance/");
    if (singularPos != std::string::npos) {
      altImageUri.replace(singularPos, std::string("appearance").size(), "appearances");
    } else {
      return resolved.string();
    }
  }
  resolved = (sourcePath.parent_path() / std::filesystem::path(altImageUri)).lexically_normal();
  {
    std::error_code ec;
    if (std::filesystem::exists(resolved, ec)) return resolved.string();
  }
  return resolved.string();
}

#endif /* AppearanceHelpers_hpp */
