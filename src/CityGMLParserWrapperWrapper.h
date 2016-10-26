//
//  CityGMLParserWrapperWrapper.h
//  Azul
//
//  Copyright © 2016 Ken Arroyo Ohori. All rights reserved.
//

#ifndef CityGMLParserWrapperWrapper_h
#define CityGMLParserWrapperWrapper_h

#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>

struct CityGMLParserWrapper;

@interface CityGMLParserWrapperWrapper: NSObject {
  struct CityGMLParserWrapper *parserWrapper;
}

- (id) init;
- (void) parse: (const char *)filePath;
- (void) initialiseIterator;
- (void) advanceIterator;
- (BOOL) hasIteratorEnded;
- (unsigned int) getType;
- (const GLfloat *) getTrianglesBuffer: (unsigned long *)elements;
- (const GLfloat *) getTriangles2Buffer: (unsigned long *)elements;
- (const GLfloat *) getEdgesBuffer: (unsigned long *)elements;
- (void) dealloc;

@end

#endif /* CityGMLParserWrapperWrapper_h */
