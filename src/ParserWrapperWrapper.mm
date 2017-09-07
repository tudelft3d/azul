// azul
// Copyright © 2016-2017 Ken Arroyo Ohori
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

#import "ParserWrapperWrapper.h"
#import "Parser.hpp"

struct ParserWrapper {
  Parser *parser;
  std::vector<GLfloat> boundingBox;
};

@implementation ParserWrapperWrapper

- (id) init {
  if (self = [super init]) {
    parserWrapper = new ParserWrapper();
    parserWrapper->parser = new Parser();
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

- (void) initialiseAttributeIterator {
  parserWrapper->parser->currentAttribute = parserWrapper->parser->currentObject->attributes.begin();
}

- (void) advanceAttributeIterator {
  ++parserWrapper->parser->currentAttribute;
}

- (BOOL) attributeIteratorEnded {
  if (parserWrapper->parser->currentAttribute == parserWrapper->parser->currentObject->attributes.end()) {
    return true;
  } return false;
}

- (const char *) currentObjectTypeWithLength: (unsigned long *)length {
  *length = parserWrapper->parser->currentObject->type.size();
  return parserWrapper->parser->currentObject->type.c_str();
}

- (const char *) currentObjectIdentifierWithLength: (unsigned long *)length {
  *length = parserWrapper->parser->currentObject->id.size();
  return parserWrapper->parser->currentObject->id.c_str();
}

- (const float *) currentObjectEdgesBufferWithElements: (unsigned long *)elements {
  *elements = parserWrapper->parser->currentObject->edges.size();
  return parserWrapper->parser->currentObject->edges.data();
}

- (const char *) currentTrianglesBufferTypeWithLength: (unsigned long *)length {
  *length = parserWrapper->parser->currentTrianglesBuffer->first.size();
  return parserWrapper->parser->currentTrianglesBuffer->first.c_str();
}

- (const float *) currentTrianglesBufferWithElements: (unsigned long *)elements {
  *elements = parserWrapper->parser->currentTrianglesBuffer->second.size();
  return parserWrapper->parser->currentTrianglesBuffer->second.data();
}

- (const char *) currentAttributeNameWithLength: (unsigned long *)length {
  *length = parserWrapper->parser->currentAttribute->first.size();
  return parserWrapper->parser->currentAttribute->first.c_str();
}

- (const char *) currentAttributeValueWithLength: (unsigned long *)length {
  *length = parserWrapper->parser->currentAttribute->second.size();
  return parserWrapper->parser->currentAttribute->second.c_str();
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
