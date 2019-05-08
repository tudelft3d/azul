// azul
// Copyright © 2016-2019 Ken Arroyo Ohori
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

#import "DataManagerWrapperWrapper.h"
#import "DataManager.hpp"
#import "azul-Swift.h"

struct DataManagerWrapper {
  DataManager *dataManager;
};

@interface AzulObjectIterator: NSObject
@property std::vector<AzulObject>::iterator iterator;
@end

@implementation AzulObjectIterator
@synthesize iterator;

- (BOOL)isEqual:(id)other {
  if (other == self) return YES;
  if (![other isKindOfClass:[AzulObjectIterator class]]) {
    return NO;
  } return [(AzulObjectIterator *)other iterator] == iterator;
}

- (NSUInteger)hash {
  return (NSUInteger)&*iterator;
}

@end

@implementation DataManagerWrapperWrapper

@synthesize controller;

- (id) init {
  if (self = [super init]) {
    dataManagerWrapper = new DataManagerWrapper();
    dataManagerWrapper->dataManager = new DataManager();
  } return self;
}

- (void) parse:(const char *)filePath {
  dataManagerWrapper->dataManager->parse(filePath);
}

- (void) clearHelpers {
  dataManagerWrapper->dataManager->clearHelpers();
}

- (void) clear {
  dataManagerWrapper->dataManager->clear();
}

- (void) updateBoundsWithLastFile {
  dataManagerWrapper->dataManager->updateBoundsWithLastFile();
}

- (void) triangulateLastFile {
  dataManagerWrapper->dataManager->triangulateLastFile();
}

- (void) generateEdgesForLastFile {
  dataManagerWrapper->dataManager->generateEdgesForLastFile();
}

- (void) clearPolygonsOfLastFile {
  dataManagerWrapper->dataManager->clearPolygonsOfLastFile();
}

- (void) regenerateTriangleBuffersWithMaximumSize:(long)maxBufferSize {
  dataManagerWrapper->dataManager->regenerateTriangleBuffers(maxBufferSize);
}

- (void) regenerateEdgeBuffersWithMaximumSize:(long)maxBufferSize {
  dataManagerWrapper->dataManager->regenerateEdgeBuffers(maxBufferSize);
}

- (void) initialiseTriangleBufferIterator {
  dataManagerWrapper->dataManager->currentTriangleBuffer = dataManagerWrapper->dataManager->triangleBuffers.begin();
}

- (const float *) currentTriangleBufferWithSize:(long *)bytes {
  *bytes = dataManagerWrapper->dataManager->currentTriangleBuffer->triangles.size()*sizeof(float);
  return &dataManagerWrapper->dataManager->currentTriangleBuffer->triangles.front();
}

- (const char *) currentTriangleBufferTypeWithLength:(long *)length {
  *length = dataManagerWrapper->dataManager->currentTriangleBuffer->type.size();
  return dataManagerWrapper->dataManager->currentTriangleBuffer->type.c_str();
}

- (const float *) currentTriangleBufferColour {
  return dataManagerWrapper->dataManager->currentTriangleBuffer->colour;
}

- (void) advanceTriangleBufferIterator {
  ++dataManagerWrapper->dataManager->currentTriangleBuffer;
}

- (BOOL) triangleBufferIteratorEnded {
  return dataManagerWrapper->dataManager->currentTriangleBuffer == dataManagerWrapper->dataManager->triangleBuffers.end();
}

- (void) initialiseEdgeBufferIterator {
  dataManagerWrapper->dataManager->currentEdgeBuffer = dataManagerWrapper->dataManager->edgeBuffers.begin();
}

- (const float *) currentEdgeBufferWithSize:(long *)bytes {
  *bytes = dataManagerWrapper->dataManager->currentEdgeBuffer->edges.size()*sizeof(float);
  return &dataManagerWrapper->dataManager->currentEdgeBuffer->edges.front();
}

- (const float *) currentEdgeBufferColour {
  return dataManagerWrapper->dataManager->currentEdgeBuffer->colour;
}

- (void) advanceEdgeBufferIterator {
  ++dataManagerWrapper->dataManager->currentEdgeBuffer;
}

- (BOOL) edgeBufferIteratorEnded {
  return dataManagerWrapper->dataManager->currentEdgeBuffer == dataManagerWrapper->dataManager->edgeBuffers.end();
}

- (float *) minCoordinates {
  return dataManagerWrapper->dataManager->minCoordinates;
}

- (float *) midCoordinates {
  return dataManagerWrapper->dataManager->midCoordinates;
}

- (float *) maxCoordinates {
  return dataManagerWrapper->dataManager->maxCoordinates;
}

- (float) maxRange {
  return dataManagerWrapper->dataManager->maxRange;
}

- (void) dealloc {
  delete dataManagerWrapper->dataManager;
  delete dataManagerWrapper;
}

- (BOOL) outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
//  NSLog(@"isItemExpandable:%@", item);
  if (![item isKindOfClass:[AzulObjectIterator class]]) {
    NSLog(@"Uh-oh!");
    return NO;
  } AzulObjectIterator *currentItem = item;
  return dataManagerWrapper->dataManager->isExpandable(*[currentItem iterator]);
}

- (NSInteger) outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
//  NSLog(@"numberOfChildrenOfItem:%@", item);
  if (item == nil) return dataManagerWrapper->dataManager->parsedFiles.size();
  if (![item isKindOfClass:[AzulObjectIterator class]]) {
    NSLog(@"Uh-oh!");
    return 0;
  } AzulObjectIterator *currentItem = item;
  return dataManagerWrapper->dataManager->numberOfChildren(*[currentItem iterator]);
}

- (id) outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
//  NSLog(@"child:%ld ofItem:%@", (long)index, item);
  if (item == nil) {
    AzulObjectIterator *child = [[AzulObjectIterator alloc] init];
    [child setIterator:dataManagerWrapper->dataManager->parsedFiles.begin()+index];
    return child;
  } if (![item isKindOfClass:[AzulObjectIterator class]]) {
    NSLog(@"Uh-oh!");
    return 0;
  } AzulObjectIterator *currentItem = item;
  AzulObjectIterator *child = [[AzulObjectIterator alloc] init];
  [child setIterator:dataManagerWrapper->dataManager->child(*[currentItem iterator], index)];
  return child;
}

- (NSView *) outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
//  NSLog(@"viewForTableColumn:%@ item:%@", tableColumn, item);
  if (![item isKindOfClass:[AzulObjectIterator class]]) {
    NSLog(@"Uh-oh!");
    return nil;
  } AzulObjectIterator *currentItem = item;
  
  // Files
  if ([outlineView parentForItem:item] == nil) {
    NSString *filePath = [NSString stringWithUTF8String:[currentItem iterator]->id.c_str()];
    NSString *filename = [[filePath lastPathComponent] stringByDeletingPathExtension];
    NSString *fileExtension = [[filePath lastPathComponent] pathExtension];
    NSImage *fileIcon = [[NSWorkspace sharedWorkspace] iconForFileType:fileExtension];
    TableCellView *result = [[TableCellView alloc] init];
    [[result imageView] setImage:fileIcon];
    [[result textField] setStringValue:filename];
    return result;
  }
  
  // Objects
  NSString *objectType = [NSString stringWithUTF8String:[currentItem iterator]->type.c_str()];
  NSMutableString *stringToPut = [NSMutableString stringWithString:objectType];
  if ([currentItem iterator]->id.size() > 0) {
  NSString *objectId = [NSString stringWithUTF8String:[currentItem iterator]->id.c_str()];
    [stringToPut appendString:@" ("];
    [stringToPut appendString:objectId];
    [stringToPut appendString:@")"];
  } NSImage *objectIcon = [NSImage imageNamed:objectType];
  TableCellView *result = [[TableCellView alloc] init];
  if (objectIcon != nil) [[result imageView] setImage:objectIcon];
  [[result textField] setStringValue:stringToPut];
  return result;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
//  NSLog(@"outlineViewSelectionDidChange");
  
  for (auto &currentFile: dataManagerWrapper->dataManager->parsedFiles) dataManagerWrapper->dataManager->setSelection(currentFile, false);
  
  NSOutlineView *outlineView = [notification object];
  NSIndexSet *rows = [outlineView selectedRowIndexes];
  [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *_Nonnull stop) {
    if (![[outlineView itemAtRow:idx] isKindOfClass:[AzulObjectIterator class]]) NSLog(@"Uh-oh!");
    else {
      AzulObjectIterator *currentItem = [outlineView itemAtRow:idx];
      dataManagerWrapper->dataManager->setSelection(*[currentItem iterator], true);
    }
  }];

  dataManagerWrapper->dataManager->regenerateTriangleBuffers(16*1024*1024);
  [controller reloadTriangleBuffers];
  dataManagerWrapper->dataManager->regenerateEdgeBuffers(16*1024*1024);
  [controller reloadEdgeBuffers];
  [[controller metalView] setNeedsDisplay:YES];
  
  [[controller attributesTableView] reloadData];
}

- (void) click {
  CGRect viewFrameInWindowCoordinates = [[controller metalView] convertRect:[[controller metalView] bounds] toView:nil];

  // Compute the current mouse position
  float currentX = -1.0 + 2.0*([[controller window] mouseLocationOutsideOfEventStream].x-viewFrameInWindowCoordinates.origin.x) / [[controller metalView] bounds].size.width;
  float currentY = -1.0 + 2.0*([[controller window] mouseLocationOutsideOfEventStream].y-viewFrameInWindowCoordinates.origin.y) / [[controller metalView] bounds].size.height;

  float bestHit = dataManagerWrapper->dataManager->click(currentX, currentY, [[controller metalView] modelMatrix], [[controller metalView] viewMatrix], [[controller metalView] projectionMatrix]);

  // (De)select closest hit
  if (bestHit > -1.0) {
    int rowToSelect = [self findObjectRow];
    if (rowToSelect == -1) return;
    if ([[controller metalView] multipleSelection]) {
      if ([[[controller objectsSourceList] selectedRowIndexes] containsIndex:rowToSelect]) [[controller objectsSourceList] deselectRow:rowToSelect];
      else {
        NSIndexSet *rowToSelectIndexes = [NSIndexSet indexSetWithIndex:rowToSelect];
        [[controller objectsSourceList] selectRowIndexes:rowToSelectIndexes byExtendingSelection:true];
      }
    } else {
      NSIndexSet *rowToSelectIndexes = [NSIndexSet indexSetWithIndex:rowToSelect];
      [[controller objectsSourceList] selectRowIndexes:rowToSelectIndexes byExtendingSelection:false];
    } [[controller objectsSourceList] scrollRowToVisible:rowToSelect];
  } else if (![[controller metalView] multipleSelection]) [[controller objectsSourceList] deselectAll:self];
}

- (int) findObjectRow {

  // Reach correct file, expand file if necessary
  int row = 0;
  while (row < [[controller objectsSourceList] numberOfRows]) {
    if (![[[controller objectsSourceList] itemAtRow:row] isKindOfClass:[AzulObjectIterator class]]) NSLog(@"Uh-oh!");
    else {
      AzulObjectIterator *currentItem = [[controller objectsSourceList] itemAtRow:row];
      if ([currentItem iterator] == dataManagerWrapper->dataManager->bestHitFile) {
        if (dataManagerWrapper->dataManager->bestHitFile->children.empty()) {
          return row;
        } else {
          [[controller objectsSourceList] expandItem:[[controller objectsSourceList] itemAtRow:row]];
          ++row;
          break;
        }
      }
    } ++row;
  }

  // Find object
  while (row < [[controller objectsSourceList] numberOfRows] &&
         [[controller objectsSourceList] parentForItem:[[controller objectsSourceList] itemAtRow:row]] != nil) {
    if (![[[controller objectsSourceList] itemAtRow:row] isKindOfClass:[AzulObjectIterator class]]) NSLog(@"Uh-oh!");
    else {
      AzulObjectIterator *currentItem = [[controller objectsSourceList] itemAtRow:row];
      if ([currentItem iterator] == dataManagerWrapper->dataManager->bestHitObject) {
        return row;
      }
    } ++row;
  }

  // Not found
  std::cout << "Hit not found" << std::endl;
  return -1;
}

- (void) sourceListDoubleClick {
  if (![[[controller objectsSourceList] itemAtRow:[[controller objectsSourceList] clickedRow]] isKindOfClass:[AzulObjectIterator class]]) {
    NSLog(@"Uh-oh!");
    return;
  } AzulObjectIterator *currentItem = [[controller objectsSourceList] itemAtRow:[[controller objectsSourceList] clickedRow]];
  
  // Compute centroid
  CentroidComputation centroidComputation;
  for (int coordinate = 0; coordinate < 3; ++coordinate) centroidComputation.sum[coordinate] = 0;
  centroidComputation.points = 0;
  dataManagerWrapper->dataManager->addAzulObjectAndItsChildrenToCentroidComputation(*[currentItem iterator], centroidComputation);
  simd_float4 centroidInObjectCoordinates = simd_make_float4((((centroidComputation.sum[0]/(float)centroidComputation.points)-dataManagerWrapper->dataManager->midCoordinates[0])/dataManagerWrapper->dataManager->maxRange),
                                                             (((centroidComputation.sum[1]/(float)centroidComputation.points)-dataManagerWrapper->dataManager->midCoordinates[1])/dataManagerWrapper->dataManager->maxRange),
                                                             (((centroidComputation.sum[2]/(float)centroidComputation.points)-dataManagerWrapper->dataManager->midCoordinates[2])/dataManagerWrapper->dataManager->maxRange),
                                                             1.0);
//  NSLog(@"Centroid: %f, %f, %f", centroidInObjectCoordinates[0], centroidInObjectCoordinates[1], centroidInObjectCoordinates[2]);
  
  // Use the centroid to compute the shift in the view space
  simd_float4x4 objectToCamera = matrix_multiply([[controller metalView] viewMatrix], [[controller metalView]modelMatrix]);
  simd_float4 centroidInCameraCoordinates = matrix_multiply(objectToCamera, centroidInObjectCoordinates);
  
  // Compute shift in object space
  simd_float3 shiftInCameraCoordinates = simd_make_float3(-centroidInCameraCoordinates.x, -centroidInCameraCoordinates.y, 0.0);
  simd_float3x3 cameraToObject = matrix_invert(dataManagerWrapper->dataManager->matrix_upper_left_3x3(objectToCamera));
  simd_float3 shiftInObjectCoordinates = matrix_multiply(cameraToObject, shiftInCameraCoordinates);
  [[controller metalView] setModelTranslationToCentreOfRotationMatrix:matrix_multiply([[controller metalView] modelTranslationToCentreOfRotationMatrix], dataManagerWrapper->dataManager->matrix4x4_translation(shiftInObjectCoordinates))];
  [[controller metalView] setModelMatrix:matrix_multiply(matrix_multiply([[controller metalView] modelShiftBackMatrix], [[controller metalView] modelRotationMatrix]), [[controller metalView] modelTranslationToCentreOfRotationMatrix])];
  
  // Correct shift so that the point of rotation remains at the same depth as the data
  cameraToObject = matrix_invert(dataManagerWrapper->dataManager->matrix_upper_left_3x3(matrix_multiply([[controller metalView] viewMatrix], [[controller metalView] modelMatrix])));
  float depthOffset = 1.0+[[controller metalView] depthAtCentre];
  simd_float3 depthOffsetInCameraCoordinates = simd_make_float3(0.0, 0.0, -depthOffset);
  simd_float3 depthOffsetInObjectCoordinates = matrix_multiply(cameraToObject, depthOffsetInCameraCoordinates);
  [[controller metalView] setModelTranslationToCentreOfRotationMatrix:matrix_multiply([[controller metalView] modelTranslationToCentreOfRotationMatrix], dataManagerWrapper->dataManager->matrix4x4_translation(depthOffsetInObjectCoordinates))];
  [[controller metalView] setModelMatrix:matrix_multiply(matrix_multiply([[controller metalView] modelShiftBackMatrix], [[controller metalView] modelRotationMatrix]), [[controller metalView] modelTranslationToCentreOfRotationMatrix])];
}

- (void) setSearchString:(const char *)string {
  dataManagerWrapper->dataManager->clearSearch();
  dataManagerWrapper->dataManager->searchString = std::string(string);
  NSLog(@"Searching: %s", string);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  NSInteger objectsRow = [[controller objectsSourceList] selectedRow];
  if (objectsRow == -1) return 0;
  AzulObjectIterator *currentItem = [[controller objectsSourceList] itemAtRow:objectsRow];
  return [currentItem iterator]->attributes.size();
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSInteger objectsRow = [[controller objectsSourceList] selectedRow];
  if (objectsRow == -1) return 0;
  AzulObjectIterator *currentItem = [[controller objectsSourceList] itemAtRow:objectsRow];
  NSString *cellString;
  if ([[tableColumn identifier] isEqualToString:@"A"]) cellString = [NSString stringWithUTF8String:[currentItem iterator]->attributes[row].first.c_str()];
  else cellString = [NSString stringWithUTF8String:[currentItem iterator]->attributes[row].second.c_str()];
  NSCell *cell = [[NSCell alloc] initTextCell:cellString];
  return cell;
}

@end
