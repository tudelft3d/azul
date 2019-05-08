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

#ifndef OBJParsingHelper_hpp
#define OBJParsingHelper_hpp

#include <boost/spirit/home/x3.hpp>
#include "DataModel.hpp"

class OBJParsingHelper {
public:
  void parse(const char *filePath, AzulObject &parsedFile) {
    
    std::ifstream inputStream(filePath);
    inputStream.seekg(0, std::ios::end);
    std::streamoff length = inputStream.tellg();
    inputStream.seekg(0, std::ios::beg);
    char *buffer = new char[length];
    inputStream.read(buffer, length);
    inputStream.close();
    
    parsedFile.type = "File";
    parsedFile.id = filePath;
    
    std::vector<AzulPoint> vertices;
    bool inObject = false, inGroup = false;
    std::vector<AzulObject>::reverse_iterator currentObject, currentGroup;
    
    const char *lineStart = buffer;
    while (*lineStart != '\0') {
      const char *lineEnd = lineStart;
      
      // Find end of line
      while (*lineEnd != '\n' && *lineEnd != '\r' && *lineEnd != '\0') ++lineEnd;
      
      // Find start of definition
      const char *definitionStart = lineStart;
      while (isspace(*definitionStart)) ++definitionStart;
      
      // Vertex
      if (strncmp(definitionStart, "v ", 2) == 0) {
        float coordinate;
        const char *coordinateStart = definitionStart;
        ++coordinateStart;
        vertices.push_back(AzulPoint());
        for (int i = 0; i < 3; ++i) {
          while (isspace(*coordinateStart) && coordinateStart != lineEnd) ++coordinateStart;
          const char *coordinateEnd = coordinateStart;
          while (!isspace(*coordinateEnd) && coordinateEnd != lineEnd) ++coordinateEnd;
          if (!boost::spirit::x3::parse(coordinateStart, coordinateEnd, boost::spirit::x3::float_, coordinate)) {
            std::cout << "Invalid coordinate" << std::endl;
            for (int j = 0; j < 3; ++j) vertices.back().coordinates[j] = 0.0;
            break;
          } vertices.back().coordinates[i] = coordinate;
          coordinateStart = coordinateEnd;
        }
//        std::cout << "Vertex[" << vertices.size() << "](" << vertices.back().coordinates[0] << ", " << vertices.back().coordinates[1] << ", " << vertices.back().coordinates[2] << ")" << std::endl;
      }
      
      // Face
      else if (strncmp(definitionStart, "f ", 2) == 0) {
        unsigned int vertexIndex;
        const char *vertexIndexStart = definitionStart;
        ++vertexIndexStart;
        AzulPolygon newPolygon;
        while (vertexIndexStart != lineEnd) {
          while (isspace(*vertexIndexStart) && vertexIndexStart != lineEnd) ++vertexIndexStart;
          const char *vertexIndexEnd = vertexIndexStart;
          while (!isspace(*vertexIndexEnd) && vertexIndexEnd != lineEnd) ++vertexIndexEnd;
          if (!boost::spirit::x3::parse(vertexIndexStart, vertexIndexEnd, boost::spirit::x3::uint_, vertexIndex)) {
            std::cout << "Invalid vertex index (unparseable)" << std::endl;
            break;
          } if (vertexIndex >= 1 && vertexIndex <= vertices.size()) newPolygon.exteriorRing.points.push_back(vertices[vertexIndex-1]);
          else {
            std::cout << "Invalid vertex index (non-existent index)" << std::endl;
            break;
          } vertexIndexStart = vertexIndexEnd;
        } if (newPolygon.exteriorRing.points.back().coordinates[0] != newPolygon.exteriorRing.points.front().coordinates[0] ||
              newPolygon.exteriorRing.points.back().coordinates[1] != newPolygon.exteriorRing.points.front().coordinates[1] ||
              newPolygon.exteriorRing.points.back().coordinates[2] != newPolygon.exteriorRing.points.front().coordinates[2]) newPolygon.exteriorRing.points.push_back(newPolygon.exteriorRing.points.front());
        if (newPolygon.exteriorRing.points.size() > 3) {
          if (inGroup) currentGroup->polygons.push_back(newPolygon);
          else if (inObject) currentObject->polygons.push_back(newPolygon);
          else parsedFile.polygons.push_back(newPolygon);
        }
      }
      
      // Object
      else if (strncmp(definitionStart, "o ", 2) == 0) {
        inObject = true;
        inGroup = false;
        parsedFile.children.push_back(AzulObject());
        currentObject = parsedFile.children.rbegin();
        const char *objectName = definitionStart;
        ++objectName;
        while (isspace(*objectName) && objectName != lineEnd) ++objectName;
        currentObject->type = "Object";
        currentObject->id = std::string(objectName, lineEnd-objectName);
//        std::cout << "Object " << currentObject->id << std::endl;
      }
      
      // Group
      else if (strncmp(definitionStart, "g ", 2) == 0) {
        inGroup = true;
        if (inObject) {
          currentObject->children.push_back(AzulObject());
          currentGroup = currentObject->children.rbegin();
        } else {
          parsedFile.children.push_back(AzulObject());
          currentGroup = parsedFile.children.rbegin();
        } const char *groupName = definitionStart;
        ++groupName;
        while (isspace(*groupName) && groupName != lineEnd) ++groupName;
        currentGroup->type = "Group";
        currentGroup->id = std::string(groupName, lineEnd-groupName);
//        std::cout << "Object " << currentObject->id << std::endl;
      }
      
      // Move start of line to next line
      lineStart = lineEnd;
      while (*lineStart == '\n' || *lineStart == '\r') ++lineStart;
    }
    
//    std::cout << vertices.size() << " vertices" << std::endl;
  }
};

#endif /* OBJParsingHelper_hpp */
