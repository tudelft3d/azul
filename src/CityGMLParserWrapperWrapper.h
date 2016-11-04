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
- (void) clear;
- (void) initialiseIterator;
- (void) advanceIterator;
- (BOOL) iteratorEnded;
- (unsigned int) type;
- (const char *) identifier: (unsigned long *)length;
- (const GLfloat *) trianglesBuffer: (unsigned long *)elements;
- (const GLfloat *) triangles2Buffer: (unsigned long *)elements;
- (const GLfloat *) edgesBuffer: (unsigned long *)elements;
- (float *) minCoordinates;
- (float *) midCoordinates;
- (float *) maxCoordinates;
- (float) maxRange;
- (void) dealloc;

@end

#endif /* CityGMLParserWrapperWrapper_h */
