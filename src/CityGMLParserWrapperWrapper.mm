// azul
// Copyright © 2016 Ken Arroyo Ohori
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

#import "CityGMLParserWrapperWrapper.h"
#import "CityGMLParser.hpp"

struct CityGMLParserWrapper {
  CityGMLParser *parser;
  std::vector<GLfloat> boundingBox;
};

@implementation CityGMLParserWrapperWrapper

- (id) init {
  if (self = [super init]) {
    parserWrapper = new CityGMLParserWrapper();
    parserWrapper->parser = new CityGMLParser();
  } return self;
}

- (void) parse: (const char *)filePath {
  parserWrapper->parser->parse(filePath);
}

- (void) clear {
  parserWrapper->parser->clear();
}

- (void) initialiseObjectIterator {
  parserWrapper->parser->currentObject = parserWrapper->parser->objects.begin();
}

- (void) advanceObjectIterator {
  ++parserWrapper->parser->currentObject;
}

- (BOOL) objectIteratorEnded {
  if (parserWrapper->parser->currentObject == parserWrapper->parser->objects.end()) {
    return true;
  } return false;
}

- (void) initialiseTriangleBufferIterator {
  parserWrapper->parser->currentTrianglesBuffer = parserWrapper->parser->currentObject->trianglesByType.begin();
}

- (void) advanceTriangleBufferIterator {
  ++parserWrapper->parser->currentTrianglesBuffer;
}

- (BOOL) triangleBufferIteratorEnded {
  if (parserWrapper->parser->currentTrianglesBuffer == parserWrapper->parser->currentObject->trianglesByType.end()) {
    return true;
  } return false;
}

- (unsigned int) currentObjectType {
  return parserWrapper->parser->currentObject->type;
}

- (const char *) currentObjectIdentifierWithLength: (unsigned long *)length {
  *length = parserWrapper->parser->currentObject->id.size();
  return parserWrapper->parser->currentObject->id.c_str();
}

- (const float *) currentObjectEdgesBufferWithElements: (unsigned long *)elements {
  *elements = parserWrapper->parser->currentObject->edges.size();
  return parserWrapper->parser->currentObject->edges.data();
}

- (const float *) currentTrianglesBufferWithType: (int *)type andElements:(unsigned long *)elements {
  *type = parserWrapper->parser->currentTrianglesBuffer->first;
  *elements = parserWrapper->parser->currentTrianglesBuffer->second.size();
  return parserWrapper->parser->currentTrianglesBuffer->second.data();
}

- (float *) minCoordinates {
  return parserWrapper->parser->minCoordinates;
}

- (float *) maxCoordinates {
  return parserWrapper->parser->maxCoordinates;
}

- (void) dealloc {
  delete parserWrapper->parser;
  delete parserWrapper;
}

@end
