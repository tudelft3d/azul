// azul
// Copyright © 2016-2026 Ken Arroyo Ohori
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

#ifndef DataManagerWrapperWrapper_h
#define DataManagerWrapperWrapper_h

#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#else
#import <UIKit/UIKit.h>
#endif
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#if TARGET_OS_OSX
#import "TableCellView.h"
#endif

struct DataManagerWrapper;

#if TARGET_OS_OSX
@class Controller;
#else
@class MainViewController;
#endif

// Exposed to Swift for iOS tree navigation
@interface AzulObjectIterator: NSObject
@property (nonatomic) int depth;
@end

#if TARGET_OS_OSX
@interface DataManagerWrapperWrapper: NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate> {
#else
@interface DataManagerWrapperWrapper: NSObject {
#endif
  struct DataManagerWrapper *dataManagerWrapper;
}

#if TARGET_OS_OSX
@property Controller *controller;
#else
@property (weak) MainViewController *controller;
#endif

// Life cycle
- (id) init;
- (void) clear;
- (void) dealloc;

// Tasks in order
- (void) parse:(const char *)filePath;
- (void) clearHelpers;
- (void) transformGeographicCoordinates;
- (void) updateBoundsWithLastFile;
- (void) triangulateLastFile;
- (void) generateEdgesForLastFile;
- (void) clearPolygonsOfLastFile;
- (void) regenerateTriangleBuffersWithMaximumSize:(long)maxBufferSize;
- (void) regenerateEdgeBuffersWithMaximumSize:(long)maxBufferSize;

// Triangle buffers
- (void) initialiseTriangleBufferIterator;
- (const float *) currentTriangleBufferWithSize:(long *)bytes;
- (const unsigned int *) currentTriangleBufferIndicesWithSize:(long *)bytes;
- (const char *) currentTriangleBufferTypeWithLength:(long *)length;
- (const float *) currentTriangleBufferColour;
- (const char *) currentTriangleBufferTextureURIWithLength:(long *)length;
- (void) advanceTriangleBufferIterator;
- (BOOL) triangleBufferIteratorEnded;

// Edge buffers
- (void) initialiseEdgeBufferIterator;
- (const float *) currentEdgeBufferWithSize:(long *)bytes;
- (const float *) currentEdgeBufferColour;
- (void) advanceEdgeBufferIterator;
- (BOOL) edgeBufferIteratorEnded;

// Bounds
- (double *) minCoordinates;
- (double *) midCoordinates;
- (double *) maxCoordinates;
- (double) maxRange;

// Search
- (void) setSearchString:(const char *)string;

// Sorting (key: "" = document order, "id", "type")
- (void) setSortOrderWithKey:(const char *)key descending:(BOOL)descending NS_SWIFT_NAME(setSortOrder(key:descending:));

// LOD filtering
- (void) setLodFilter:(const char *)lod;
- (NSArray<NSString *> *) availableLods;

// Appearance filtering
- (void) setUseAppearances:(BOOL)enabled;
- (void) setAppearanceTheme:(const char *)theme;
- (NSArray<NSString *> *) availableAppearanceThemes;

// Status message
- (NSString *)statusMessage;

// Objects source list
#if TARGET_OS_OSX
- (NSInteger) outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item;
- (BOOL) outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item;
- (id) outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item;
- (NSView *) outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item;
- (void)outlineViewSelectionDidChange:(NSNotification *)notification;

// Attributes table view
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
#endif

// Selection by clicking
#if TARGET_OS_OSX
- (void) click;
- (int) findObjectRow;
- (void) sourceListDoubleClick;

// Toggling visibility
- (void) toggleVisibility:(id)sender;
- (void) toggleVisibilityForSelection:(NSOutlineView *)outlineView;
#endif

// Picking
- (int) setBestHitFromObjectId:(int)objectId;
- (id) bestHitObjectIterator;

// Item-based access to the object tree (used by tests and iOS)
- (char) visibleStateOfItem:(id)item;
- (void) setVisibleState:(char)visible forItem:(id)item;
- (NSInteger) numberOfAttributesOfItem:(id)item;
- (NSString *) attributeKeyOfItem:(id)item atIndex:(NSInteger)index;
- (NSString *) attributeValueOfItem:(id)item atIndex:(NSInteger)index;

// Selection helpers
- (void) selectBestHitObject;
- (void) clearSelection;

// Selection state (GPU-based)
- (void) updateSelectionStates;
- (const float *) selectionStateData;
- (int) selectionStateCount;

// Object IDs from items
- (NSString *) objectIdForItem:(id)item;

// Visibility state (GPU-based)
- (void) updateVisibleStates;
- (const float *) visibleStateData;
- (int) visibleStateCount;

// iOS tree navigation
#if !TARGET_OS_OSX
- (NSInteger) numberOfParsedFiles;
- (id) iteratorForFileAtIndex:(NSInteger)index;
- (BOOL) isItemExpandable:(id)item;
- (NSInteger) numberOfChildrenOfItem:(id)item;
- (id) childOfItem:(id)item atIndex:(NSInteger)index;
- (NSString *) typeOfItem:(id)item;
- (NSString *) identifierOfItem:(id)item;
- (void) selectItem:(id)item;
- (const double *) centroidOfItem:(id)item;
- (int) centroidPointCountOfItem:(id)item;
#endif

// Selection colours
- (void) setSelectedEdgesColourWithRed:(float)r green:(float)g blue:(float)b alpha:(float)a;
- (void) getSelectedEdgesColourRed:(float *)r green:(float *)g blue:(float *)b alpha:(float *)a;

// Type colours
- (NSInteger) colourTypeCount;
- (NSString *) colourTypeNameAtIndex:(NSInteger)index;
- (void) getRed:(float *)r green:(float *)g blue:(float *)b alpha:(float *)a forColourTypeAtIndex:(NSInteger)index;
- (void) setColourWithRed:(float)r green:(float)g blue:(float)b alpha:(float)a forType:(const char *)type;
- (void) resetTypeColours;

@end

#endif /* DataManagerWrapperWrapper_h */
