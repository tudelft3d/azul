//
//  CityGMLParserWrapperWrapper.m
//  Azul
//
//  Copyright © 2016 Ken Arroyo Ohori. All rights reserved.
//

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
