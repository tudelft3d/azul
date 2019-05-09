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

#ifndef DataManager_hpp
#define DataManager_hpp

#include <fstream>
#include <boost/algorithm/string/predicate.hpp>
#include <simd/simd.h>

#include <CGAL/Exact_predicates_inexact_constructions_kernel.h>
#include <CGAL/Constrained_Delaunay_triangulation_2.h>
#include <CGAL/Triangulation_vertex_base_with_info_2.h>
#include <CGAL/Triangulation_face_base_with_info_2.h>
#include <CGAL/linear_least_squares_fitting_3.h>
#include "Enhanced_constrained_triangulation_2.h"

#include "GMLParsingHelper.hpp"
#include "JSONParsingHelper.hpp"
#include "OBJParsingHelper.hpp"
#include "POLYParsingHelper.hpp"
#include "OFFParsingHelper.hpp"

typedef CGAL::Exact_predicates_inexact_constructions_kernel Kernel;
typedef CGAL::Exact_predicates_tag Tag;
typedef CGAL::Triangulation_vertex_base_with_info_2<Kernel::Point_3, Kernel> VertexBase;
typedef CGAL::Constrained_triangulation_face_base_2<Kernel> FaceBase;
typedef CGAL::Triangulation_face_base_with_info_2<std::pair<bool, bool>, Kernel, FaceBase> FaceBaseWithInfo;
typedef CGAL::Triangulation_data_structure_2<VertexBase, FaceBaseWithInfo> TriangulationDataStructure;
typedef CGAL::Constrained_Delaunay_triangulation_2<Kernel, TriangulationDataStructure, Tag> ConstrainedDelaunayTriangulation;
typedef Enhanced_constrained_triangulation_2<ConstrainedDelaunayTriangulation> Triangulation;

class DataManager {
private:
  void triangulateAzulObjectAndItsChildren(AzulObject &object);
  void generateEdgesForAzulObjectAndItsChildren(AzulObject &object);
  void updateBoundsWithAzulObjectAndItsChildren(const AzulObject &object);
  void clearPolygonsOfAzulObjectAndItsChildren(AzulObject &object);
  void putAzulObjectAndItsChildrenIntoTriangleBuffers(const AzulObject &object, const std::string &typeWithColour, const long maxBufferSize);
  void putAzulObjectAndItsChildrenIntoEdgeBuffers(const AzulObject &object, const long maxBufferSize);
  void printAzulObject(const AzulObject &object, unsigned int tabs);
  void setMatchesSearch(AzulObject &object, char matches);
  bool matchesSearch(AzulObject &object);
  
public:
  // Helpers
  GMLParsingHelper gmlParsingHelper;
  JSONParsingHelper jsonParsingHelper;
  OBJParsingHelper objParsingHelper;
  POLYParsingHelper polyParsingHelper;
  OFFParsingHelper offParsingHelper;
  
  // Managed contents
  std::vector<AzulObject> parsedFiles;
  std::list<TriangleBuffer> triangleBuffers;
  std::list<EdgeBuffer> edgeBuffers;
  
  std::map<std::string, std::list<TriangleBuffer>::iterator> lastTriangleBufferOfType;
  std::map<bool, std::list<TriangleBuffer>::iterator> lastTriangleBufferBySelection;
  std::map<bool, std::list<EdgeBuffer>::iterator> lastEdgeBufferBySelection;
  
  // Iterators for access from Swift
  std::list<TriangleBuffer>::const_iterator currentTriangleBuffer;
  std::list<EdgeBuffer>::const_iterator currentEdgeBuffer;
  std::vector<AzulObject>::iterator bestHitFile, bestHitObject;

  // Colours
  std::tuple<float, float, float, float> black, selectedTrianglesColour, selectedEdgesColour;
  std::map<std::string, std::tuple<float, float, float, float>> colourForType;
  
  // Search
  std::string searchString;
  
  // Bounds
  float minCoordinates[3];
  float midCoordinates[3];
  float maxCoordinates[3];
  float maxRange;
  
  // Life cycle
  DataManager();
  void clear();
  
  // Tasks in order
  void parse(const char *filePath);
  void clearHelpers();
  void updateBoundsWithLastFile();
  void triangulateLastFile();
  void generateEdgesForLastFile();
  void clearPolygonsOfLastFile();
  void regenerateTriangleBuffers(long maxBufferSize);
  void regenerateEdgeBuffers(long maxBufferSize);
  
  // Selection
  void setSelection(AzulObject &object, bool selected);
  float click(const float currentX, const float currentY, const simd_float4x4 &modelMatrix, const simd_float4x4 &viewMatrix, const simd_float4x4 &projectionMatrix);
  float hit(const AzulObject &object, const simd_float3 &rayOrigin, const simd_float3 &rayDirection, const simd_float4x4 &objectToCamera);
  
  // Search
  void clearSearch();
  bool isExpandable(AzulObject &object);
  int numberOfChildren(AzulObject &object);
  std::vector<AzulObject>::iterator child(AzulObject &object, long index);
  
  // Math
  simd_float3x3 matrix_upper_left_3x3(const simd_float4x4 &matrix);
  simd_float4x4 matrix4x4_translation(const simd_float3 &shift);
  void addAzulObjectAndItsChildrenToCentroidComputation(const AzulObject &object, CentroidComputation &centroidComputation);
  
  // Debug
  void printParsedFiles();
};

#endif /* DataManager_hpp */
