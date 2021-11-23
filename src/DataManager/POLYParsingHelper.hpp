// azul
// Copyright © 2016-2021 Ken Arroyo Ohori
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

#ifndef POLYParsingHelper_hpp
#define POLYParsingHelper_hpp

#include <boost/spirit/home/x3.hpp>
#include "DataModel.hpp"

class POLYParsingHelper {
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
    
    std::map<unsigned long, AzulPoint> vertices;
    
    unsigned int parsingPhase = 0; // 0 - vertices header, 1 - vertices, 2 - faces header, 3 - one face header, 4 - one face content, 5 - holes/attributes/etc (unsupported)
    
    const char *lineStart = buffer;
    unsigned long totalVertices = 0, totalFaces = 0, totalPolygonsInFace = 0, polygonsInFaceSoFar = 0, facesSoFar = 0;
    while (*lineStart != '\0') {
      const char *lineEnd = lineStart;
      
      // Find start and end of line
      while (*lineEnd != '\n' && *lineEnd != '\r' && *lineEnd != '\0') ++lineEnd;
      while (isspace(*lineStart) && lineStart != lineEnd) ++lineStart;
      
      // Comment
      if (*lineStart == '#') {
        
      }
      
      // Vertices header
      else if (parsingPhase == 0) {
        const char *verticesNumberStart = lineStart;
        const char *verticesNumberEnd = verticesNumberStart;
        while (!isspace(*verticesNumberEnd) && verticesNumberEnd != lineEnd) ++verticesNumberEnd;
        if (!boost::spirit::x3::parse(verticesNumberStart, verticesNumberEnd, boost::spirit::x3::ulong_, totalVertices)) {
          std::cout << "Invalid number of vertices" << std::endl;
          return;
        } const char *dimensionStart = verticesNumberEnd;
        while (isspace(*dimensionStart) && dimensionStart != lineEnd) ++dimensionStart;
        const char *dimensionEnd = dimensionStart;
        while (!isspace(*dimensionEnd) && dimensionEnd != lineEnd) ++dimensionEnd;
        unsigned long dimension;
        if (!boost::spirit::x3::parse(dimensionStart, dimensionEnd, boost::spirit::x3::ulong_, dimension)) {
          std::cout << "Invalid dimension (unparseable)" << std::endl;
          return;
        } if (dimension != 3) {
          std::cout << "Invalid dimension " << dimension << " (not a 3D file)" << std::endl;
          return;
        } if (totalVertices == 0) {
          std::cout << "No vertices in file. Separate .node file unsupported for now." << std::endl;
          return;
        } // std::cout << totalVertices << " vertices" << std::endl;
        parsingPhase = 1;
      }
      
      // Vertices
      else if (parsingPhase == 1) {
        const char *vertexNumberStart = lineStart;
        const char *vertexNumberEnd = vertexNumberStart;
        while (!isspace(*vertexNumberEnd) && vertexNumberEnd != lineEnd) ++vertexNumberEnd;
        unsigned long vertexNumber;
        if (!boost::spirit::x3::parse(vertexNumberStart, vertexNumberEnd, boost::spirit::x3::ulong_, vertexNumber)) {
          std::cout << "Invalid vertex number" << std::endl;
          return;
        } float coordinate;
        const char *coordinateStart = vertexNumberEnd;
        vertices[vertexNumber] = AzulPoint();
        for (int i = 0; i < 3; ++i) {
          while (isspace(*coordinateStart) && coordinateStart != lineEnd) ++coordinateStart;
          const char *coordinateEnd = coordinateStart;
          while (!isspace(*coordinateEnd) && coordinateEnd != lineEnd) ++coordinateEnd;
          if (!boost::spirit::x3::parse(coordinateStart, coordinateEnd, boost::spirit::x3::float_, coordinate)) {
            std::cout << "Invalid coordinate" << std::endl;
            for (int j = 0; j < 3; ++j) vertices[vertexNumber].coordinates[j] = 0.0;
            break;
          } vertices[vertexNumber].coordinates[i] = coordinate;
          coordinateStart = coordinateEnd;
        } if (vertices.size() == totalVertices) parsingPhase = 2;
      }
      
      // Faces header
      else if (parsingPhase == 2) {
        const char *facesNumberStart = lineStart;
        const char *facesNumberEnd = facesNumberStart;
        while (!isspace(*facesNumberEnd) && facesNumberEnd != lineEnd) ++facesNumberEnd;
        if (!boost::spirit::x3::parse(facesNumberStart, facesNumberEnd, boost::spirit::x3::ulong_, totalFaces)) {
          std::cout << "Invalid number of faces" << std::endl;
          return;
        } if (totalFaces == 0) return;
//        std::cout << totalFaces << " faces" << std::endl;
        parsingPhase = 3;
      }
      
      // One face header
      else if (parsingPhase == 3) {
        const char *polygonsNumberStart = lineStart;
        const char *polygonsNumberEnd = polygonsNumberStart;
        while (!isspace(*polygonsNumberEnd) && polygonsNumberEnd != lineEnd) ++polygonsNumberEnd;
        if (!boost::spirit::x3::parse(polygonsNumberStart, polygonsNumberEnd, boost::spirit::x3::ulong_, totalPolygonsInFace)) {
          std::cout << "Invalid number of polygons in face" << std::endl;
          return;
        } // std::cout << totalFaces << " polygons in face" << std::endl;
        ++facesSoFar;
        polygonsInFaceSoFar = 0;
        parsingPhase = 4;
      }
      
      // One face content
      else if (parsingPhase == 4) {
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
        ++polygonsInFaceSoFar;
        if (polygonsInFaceSoFar == totalPolygonsInFace) {
          if (facesSoFar == totalFaces) parsingPhase = 5;
          else parsingPhase = 3;
        }
      }
      
      // Holes, attributes, etc. (unsupported for now)
      else {
        
      }
      
      // Move start of line to next line
      lineStart = lineEnd;
      while (*lineStart == '\n' || *lineStart == '\r') ++lineStart;
    }
    
//    std::cout << vertices.size() << " vertices" << std::endl;
  }
};

#endif /* POLYParsingHelper_hpp */
