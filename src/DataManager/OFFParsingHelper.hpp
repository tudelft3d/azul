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

#ifndef OFFParsingHelper_hpp
#define OFFParsingHelper_hpp

#include <boost/spirit/home/x3.hpp>
#include "DataModel.hpp"

class OFFParsingHelper {
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
    
    unsigned int parsingPhase = 0; // 0 - header, 1 - number of vertices/faces/edges, 2 - vertices, 3 - faces, 4 - colorspec (unsupported)
    
    const char *lineStart = buffer;
    unsigned long totalVertices = 0, totalFaces = 0;
    while (*lineStart != '\0') {
      const char *lineEnd = lineStart;
      
      // Find start and end of line
      while (*lineEnd != '\n' && *lineEnd != '\r' && *lineEnd != '\0') ++lineEnd;
      while (isspace(*lineStart) && lineStart != lineEnd) ++lineStart;
      
      // Comment
      if (*lineStart == '#') {
        
      }
      
      // Header
      else if (parsingPhase == 0) {
        if (strncmp(lineStart, "OFF", 3) == 0 ||
            strncmp(lineStart, "STOFF", 5) == 0 ||
            strncmp(lineStart, "COFF", 4) == 0 ||
            strncmp(lineStart, "NOFF", 4) == 0 ||
            strncmp(lineStart, "4OFF", 4) == 0 ||
            strncmp(lineStart, "nOFF", 4) == 0) {
          parsingPhase = 1;
        } else {
          std::cout << "Missing header" << std::endl;
          parsingPhase = 1;
          continue;
        }
      }
      
      // Number of vertices, faces and edges (ignored)
      else if (parsingPhase == 1) {
        const char *verticesNumberStart = lineStart;
        const char *verticesNumberEnd = verticesNumberStart;
        while (!isspace(*verticesNumberEnd) && verticesNumberEnd != lineEnd) ++verticesNumberEnd;
        if (!boost::spirit::x3::parse(verticesNumberStart, verticesNumberEnd, boost::spirit::x3::ulong_, totalVertices)) {
          std::cout << "Invalid number of vertices" << std::endl;
          return;
        } const char *facesNumberStart = verticesNumberEnd;
        while (isspace(*facesNumberStart) && facesNumberStart != lineEnd) ++facesNumberStart;
        const char *facesNumberEnd = facesNumberStart;
        while (!isspace(*facesNumberEnd) && facesNumberEnd != lineEnd) ++facesNumberEnd;
        if (!boost::spirit::x3::parse(facesNumberStart, facesNumberEnd, boost::spirit::x3::ulong_, totalFaces)) {
          std::cout << "Invalid number of faces" << std::endl;
          return;
        } // std::cout << totalVertices << " vertices and " << totalFaces << " faces." << std::endl;
        parsingPhase = 2;
      }
      
      // Vertices
      else if (parsingPhase == 2) {
        float coordinate;
        const char *coordinateStart = lineStart;
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
        } if (vertices.size() == totalVertices) parsingPhase = 3;
      }
      
      // Faces
      else if (parsingPhase == 3) {
        AzulPolygon newPolygon;
        const char *verticesInFaceStart = lineStart;
        while (isspace(*verticesInFaceStart) && verticesInFaceStart != lineEnd) ++verticesInFaceStart;
        const char *verticesInFaceEnd = verticesInFaceStart;
        while (!isspace(*verticesInFaceEnd) && verticesInFaceEnd != lineEnd) ++verticesInFaceEnd;
        unsigned long verticesInFace;
        if (!boost::spirit::x3::parse(verticesInFaceStart, verticesInFaceEnd, boost::spirit::x3::ulong_, verticesInFace)) {
          std::cout << "Invalid number of vertices in face" << std::endl;
          lineStart = lineEnd;
          while (*lineStart == '\n' || *lineStart == '\r') ++lineStart;
          continue;
        } const char *vertexIndexStart = verticesInFaceEnd;
        for (unsigned long currentVertexInFace = 0; currentVertexInFace < verticesInFace; ++currentVertexInFace) {
          while (isspace(*vertexIndexStart) && vertexIndexStart != lineEnd) ++vertexIndexStart;
          const char *vertexIndexEnd = vertexIndexStart;
          while (!isspace(*vertexIndexEnd) && vertexIndexEnd != lineEnd) ++vertexIndexEnd;
          unsigned long vertexIndex;
          if (!boost::spirit::x3::parse(vertexIndexStart, vertexIndexEnd, boost::spirit::x3::uint_, vertexIndex)) {
            std::cout << "Invalid vertex index (unparseable)" << std::endl;
            vertexIndexStart = vertexIndexEnd;
            continue;
          } if (vertexIndex < vertices.size()) newPolygon.exteriorRing.points.push_back(vertices[vertexIndex]);
          else {
            std::cout << "Invalid vertex index (non-existent index)" << std::endl;
            vertexIndexStart = vertexIndexEnd;
            continue;
          } vertexIndexStart = vertexIndexEnd;
        } if (newPolygon.exteriorRing.points.back().coordinates[0] != newPolygon.exteriorRing.points.front().coordinates[0] ||
              newPolygon.exteriorRing.points.back().coordinates[1] != newPolygon.exteriorRing.points.front().coordinates[1] ||
              newPolygon.exteriorRing.points.back().coordinates[2] != newPolygon.exteriorRing.points.front().coordinates[2]) newPolygon.exteriorRing.points.push_back(newPolygon.exteriorRing.points.front());
        if (newPolygon.exteriorRing.points.size() > 3) parsedFile.polygons.push_back(newPolygon);
        if (parsedFile.polygons.size() == totalFaces) parsingPhase = 4;
      }
      
      // Colorspec (unsupported for now)
      else {
        
      }
      
      // Move start of line to next line
      lineStart = lineEnd;
      while (*lineStart == '\n' || *lineStart == '\r') ++lineStart;
    }
    
//    std::cout << vertices.size() << " vertices" << std::endl;
  }
};

#endif /* OFFParsingHelper_hpp */
