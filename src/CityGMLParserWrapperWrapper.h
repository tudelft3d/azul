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
