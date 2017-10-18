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

#pragma once

#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#import "BasicTypes.h"

#import "TableCellView.h"

@class Controller;

@interface AzulObjectIterator : NSObject
//-(instancetype)initWithDataManager:(DataManagerWrapperWrapper*)manager;
//-(const )
@end

@class DataManager;


@interface EdgeBufferIterator : NSObject
-(instancetype _Nonnull)initWithManager:(DataManager* _Nonnull)manager;
-(const struct EdgeBufferRef * _Nullable)next;
//@property(readonly, nonatomic) const EdgeBufferRef * _Nullable current;
@end

@interface TriangleBufferIterator : NSObject
-(instancetype _Nonnull)initWithManager:(DataManager* _Nonnull)manager;
-(const struct TriangleBufferRef * _Nullable)next;
//@property(readonly, nonatomic) const EdgeBufferRef * _Nullable current;
@end


@interface DataManager: NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource>

@property Controller *controller;

// Life cycle

- (void) clear;

// Tasks in order
- (void) parse:(const char *)filePath;
- (void) clearHelpers;
- (void) updateBoundsWithLastFile;
- (void) triangulateLastFile;
- (void) generateEdgesForLastFile;
- (void) clearPolygonsOfLastFile;
- (void) regenerateTriangleBuffersWithMaximumSize:(long)maxBufferSize;
- (void) regenerateEdgeBuffersWithMaximumSize:(long)maxBufferSize;

// Bounds
@property(nonatomic, readonly) vector_float3 minCoordinates;
@property(nonatomic, readonly) vector_float3 midCoordinates;
@property(nonatomic, readonly) vector_float3 maxCoordinates;
@property(nonatomic, readonly) float maxRange;

// Search
- (void) setSearchString:(const char *)string;

// Objects source list
- (NSInteger) outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item;
- (BOOL) outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item;
- (id) outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item;
- (NSView *) outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item;
- (void)outlineViewSelectionDidChange:(NSNotification *)notification;

// Attributes table view
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;

// Selection by clicking
- (void) click;
- (int) findObjectRow;
- (void) sourceListDoubleClick;

@end

