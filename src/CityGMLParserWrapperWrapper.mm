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

- (void) initialiseIterator {
  parserWrapper->parser->currentObject = parserWrapper->parser->objects.begin();
}

- (void) advanceIterator {
  ++parserWrapper->parser->currentObject;
}

- (BOOL) iteratorEnded {
  if (parserWrapper->parser->currentObject == parserWrapper->parser->objects.end()) {
    return true;
  } return false;
}

- (unsigned int) type {
  return parserWrapper->parser->currentObject->type;
}

- (const char *) identifier: (unsigned long *)length {
  *length = parserWrapper->parser->currentObject->id.size();
  return parserWrapper->parser->currentObject->id.c_str();
}

- (const GLfloat *) trianglesBuffer: (unsigned long *)elements {
  if (parserWrapper->parser->currentObject == parserWrapper->parser->objects.end()) {
    *elements = 0;
    return nil;
  } *elements = parserWrapper->parser->currentObject->triangles.size();
  return parserWrapper->parser->currentObject->triangles.data();
}

- (const GLfloat *) triangles2Buffer: (unsigned long *)elements {
  if (parserWrapper->parser->currentObject == parserWrapper->parser->objects.end()) {
    *elements = 0;
    return nil;
  } *elements = parserWrapper->parser->currentObject->triangles2.size();
  return parserWrapper->parser->currentObject->triangles2.data();
}

- (const GLfloat *) edgesBuffer: (unsigned long *)elements {
  if (parserWrapper->parser->currentObject == parserWrapper->parser->objects.end()) {
    *elements = 0;
    return nil;
  } *elements = parserWrapper->parser->currentObject->edges.size();
  return parserWrapper->parser->currentObject->edges.data();
}

- (float *) minCoordinates {
  return parserWrapper->parser->minCoordinates;
}

- (float *) midCoordinates {
  return parserWrapper->parser->midCoordinates;
}

- (float *) maxCoordinates {
  return parserWrapper->parser->maxCoordinates;
}

- (float) maxRange {
  return parserWrapper->parser->maxRange;
}

- (void) dealloc {
  delete parserWrapper->parser;
  delete parserWrapper;
}

@end
