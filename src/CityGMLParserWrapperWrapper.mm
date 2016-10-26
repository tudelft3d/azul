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

- (BOOL) hasIteratorEnded {
  if (parserWrapper->parser->currentObject == parserWrapper->parser->objects.end()) {
    return true;
  } return false;
}

- (unsigned int) getType {
  return parserWrapper->parser->currentObject->type;
}

- (const GLfloat *) getTrianglesBuffer: (unsigned long *)elements {
  if (parserWrapper->parser->currentObject == parserWrapper->parser->objects.end()) {
    *elements = 0;
    return nil;
  } *elements = parserWrapper->parser->currentObject->triangles.size();
  return parserWrapper->parser->currentObject->triangles.data();
}

- (const GLfloat *) getTriangles2Buffer: (unsigned long *)elements {
  if (parserWrapper->parser->currentObject == parserWrapper->parser->objects.end()) {
    *elements = 0;
    return nil;
  } *elements = parserWrapper->parser->currentObject->triangles2.size();
  return parserWrapper->parser->currentObject->triangles2.data();
}

- (const GLfloat *) getEdgesBuffer: (unsigned long *)elements {
  if (parserWrapper->parser->currentObject == parserWrapper->parser->objects.end()) {
    *elements = 0;
    return nil;
  } *elements = parserWrapper->parser->currentObject->edges.size();
  return parserWrapper->parser->currentObject->edges.data();
}

- (void) dealloc {
  delete parserWrapper->parser;
  delete parserWrapper;
}

@end
