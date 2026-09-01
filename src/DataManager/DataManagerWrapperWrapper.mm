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

#import "DataManagerWrapperWrapper.h"
#import "DataManager.hpp"
#if TARGET_OS_OSX
#import "azul-Swift.h"
#elif TARGET_OS_SIMULATOR
#import "azul_iOS_simulator-Swift.h"
#else
#import "azul_iOS-Swift.h"
#endif

struct DataManagerWrapper {
  DataManager *dataManager;
};

// Recomputes the derived visibility ('Y'/'N'/'P') of every ancestor of
// `target` after its own state was set directly, mirroring what the macOS
// checkbox toggle does. Returns true once `target` was found in this subtree.
static bool refreshAncestorsVisibility(AzulObject &node, AzulObject *target, DataManager *dataManager) {
  for (auto &child: node.children) {
    if (&child == target || refreshAncestorsVisibility(child, target, dataManager)) {
      dataManager->checkVisibility(node);
      return true;
    }
  }
  return false;
}

@interface AzulObjectIterator()
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

- (void) transformGeographicCoordinates {
  dataManagerWrapper->dataManager->transformGeographicCoordinates();
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
  if (dataManagerWrapper->dataManager->currentTriangleBuffer->triangles.empty()) {
    *bytes = 0;
    return nullptr;
  }
  *bytes = dataManagerWrapper->dataManager->currentTriangleBuffer->triangles.size()*sizeof(float);
  return &dataManagerWrapper->dataManager->currentTriangleBuffer->triangles.front();
}

- (const unsigned int *) currentTriangleBufferIndicesWithSize:(long *)bytes {
  if (dataManagerWrapper->dataManager->currentTriangleBuffer->indices.empty()) {
    *bytes = 0;
    return nullptr;
  }
  *bytes = dataManagerWrapper->dataManager->currentTriangleBuffer->indices.size()*sizeof(unsigned int);
  return dataManagerWrapper->dataManager->currentTriangleBuffer->indices.data();
}

- (const char *) currentTriangleBufferTypeWithLength:(long *)length {
  *length = dataManagerWrapper->dataManager->currentTriangleBuffer->type.size();
  return dataManagerWrapper->dataManager->currentTriangleBuffer->type.c_str();
}

- (const float *) currentTriangleBufferColour {
  return dataManagerWrapper->dataManager->currentTriangleBuffer->colour;
}

- (const char *) currentTriangleBufferTextureURIWithLength:(long *)length {
  *length = dataManagerWrapper->dataManager->currentTriangleBuffer->textureUri.size();
  return dataManagerWrapper->dataManager->currentTriangleBuffer->textureUri.c_str();
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
  if (dataManagerWrapper->dataManager->currentEdgeBuffer->edges.empty()) {
    *bytes = 0;
    return nullptr;
  }
  *bytes = dataManagerWrapper->dataManager->currentEdgeBuffer->edges.size()*sizeof(float);
  return &dataManagerWrapper->dataManager->currentEdgeBuffer->edges.front();
}

- (const float *) currentEdgeBufferColour {
  return dataManagerWrapper->dataManager->currentEdgeBuffer->colour;
}

- (void) advanceEdgeBufferIterator {
  ++dataManagerWrapper->dataManager->currentEdgeBuffer;
}

- (int) setBestHitFromObjectId:(int)objectId {
  return dataManagerWrapper->dataManager->setBestHitFromObjectId(objectId);
}

- (id) bestHitObjectIterator {
  if (dataManagerWrapper->dataManager->bestHitFile == dataManagerWrapper->dataManager->parsedFiles.end()) return nil;
  if (dataManagerWrapper->dataManager->bestHitObject == dataManagerWrapper->dataManager->bestHitFile->children.end()) return nil;
  AzulObjectIterator *item = [[AzulObjectIterator alloc] init];
  item.iterator = dataManagerWrapper->dataManager->bestHitObject;
  return item;
}

- (BOOL) edgeBufferIteratorEnded {
  return dataManagerWrapper->dataManager->currentEdgeBuffer == dataManagerWrapper->dataManager->edgeBuffers.end();
}

- (double *) minCoordinates {
  return dataManagerWrapper->dataManager->minCoordinates;
}

- (double *) midCoordinates {
  return dataManagerWrapper->dataManager->midCoordinates;
}

- (double *) maxCoordinates {
  return dataManagerWrapper->dataManager->maxCoordinates;
}

- (double) maxRange {
  return dataManagerWrapper->dataManager->maxRange;
}

- (void) dealloc {
  delete dataManagerWrapper->dataManager;
  delete dataManagerWrapper;
}

#if TARGET_OS_OSX
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
    [child setIterator:dataManagerWrapper->dataManager->fileChild(index)];
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
  
  TableCellView *result = [outlineView makeViewWithIdentifier:@"TableCellView" owner:self];
  if (result == nil) {
    result = [[TableCellView alloc] initWithFrame:NSZeroRect];
  }
  
  // Files
  if ([outlineView parentForItem:item] == nil) {
    NSString *filePath = [NSString stringWithUTF8String:[currentItem iterator]->id.c_str()];
    NSString *lastComponent = [filePath lastPathComponent];
    NSString *filename = [lastComponent stringByDeletingPathExtension];
    UTType *fileType;
    if ([lastComponent hasSuffix:@".city.json"]) {
      fileType = [UTType typeWithFilenameExtension:@"city.json"];
    } else {
      NSString *fileExtension = [lastComponent pathExtension];
      fileType = [UTType typeWithFilenameExtension:fileExtension];
    }
    NSImage *fileIcon = [[NSWorkspace sharedWorkspace] iconForContentType:fileType];
    [[result imageView] setImage:fileIcon];
    [[result textField] setStringValue:filename];
  }
  
  // Objects
  else {
    NSString *objectType = [NSString stringWithUTF8String:[currentItem iterator]->type.c_str()];
    if (objectType == nil) objectType = @"";
    NSMutableString *stringToPut = [NSMutableString stringWithString:objectType];
    if ([currentItem iterator]->id.size() > 0) {
    NSString *objectId = [NSString stringWithUTF8String:[currentItem iterator]->id.c_str()];
    if (objectId != nil) {
      [stringToPut appendString:@" ("];
      [stringToPut appendString:objectId];
      [stringToPut appendString:@")"];
    }
    } NSImage *objectIcon = [NSImage imageNamed:objectType];
    if (objectIcon != nil) [[result imageView] setImage:objectIcon];
    else [[result imageView] setImage:nil];
    [[result textField] setStringValue:stringToPut];
  }
  
  if ([currentItem iterator]->visible == 'Y') [[result checkBox] setState:NSControlStateValueOn];
  else if ([currentItem iterator]->visible == 'N') [[result checkBox] setState:NSControlStateValueOff];
  else [[result checkBox] setState:NSControlStateValueMixed];
//  std::cout << "Visibility: " << [currentItem iterator]->visible << std::endl;
  [[result checkBox] setAction:@selector(toggleVisibility:)];
  [[result checkBox] setTarget:self];
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
      self->dataManagerWrapper->dataManager->setSelection(*[currentItem iterator], true);
    }
  }];

  dataManagerWrapper->dataManager->updateSelectionStates();
  [controller updateSelectionStateBuffer];
  [[controller metalView] setNeedsDisplay:YES];
  [[controller metalView] animateSelectionPulse];
  
  [[controller attributesTableView] reloadData];
}

- (void) click {
  CGFloat mouseX = [[controller window] mouseLocationOutsideOfEventStream].x;
  CGFloat mouseY = [[controller window] mouseLocationOutsideOfEventStream].y;
  NSLog(@"click: mouse=(%f, %f)", mouseX, mouseY);

  int objectId = [[controller metalView] pickObjectAtX:mouseX y:mouseY];
  NSLog(@"click: objectId=%d", objectId);

  if (objectId >= 0 && dataManagerWrapper->dataManager->setBestHitFromObjectId(objectId) == 0) {
    int rowToSelect = [self findObjectRow];
    NSLog(@"click: rowToSelect=%d", rowToSelect);
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
  } else {
    NSLog(@"click: no hit, multipleSelection=%d", [[controller metalView] multipleSelection]);
    if (![[controller metalView] multipleSelection]) {
    [[controller objectsSourceList] deselectAll:self];
    for (auto &currentFile: dataManagerWrapper->dataManager->parsedFiles) dataManagerWrapper->dataManager->setSelection(currentFile, false);
    dataManagerWrapper->dataManager->updateSelectionStates();
    [controller updateSelectionStateBuffer];
    [[controller metalView] setNeedsDisplay:YES];
    }
  }
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
  simd_float4 centroidInObjectCoordinates = simd_make_float4((((centroidComputation.sum[0]/(double)centroidComputation.points)-dataManagerWrapper->dataManager->midCoordinates[0])/dataManagerWrapper->dataManager->maxRange),
                                                             (((centroidComputation.sum[1]/(double)centroidComputation.points)-dataManagerWrapper->dataManager->midCoordinates[1])/dataManagerWrapper->dataManager->maxRange),
                                                             (((centroidComputation.sum[2]/(double)centroidComputation.points)-dataManagerWrapper->dataManager->midCoordinates[2])/dataManagerWrapper->dataManager->maxRange),
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

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  if ([[controller objectsSourceList] numberOfSelectedRows] > 1) return 1;
  NSInteger objectsRow = [[controller objectsSourceList] selectedRow];
  if (objectsRow == -1) return 0;
  AzulObjectIterator *currentItem = [[controller objectsSourceList] itemAtRow:objectsRow];
  return [currentItem iterator]->attributes.size();
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  if ([[controller objectsSourceList] numberOfSelectedRows] > 1) {
    NSString *identifier = [[tableColumn identifier] isEqualToString:@"A"] ? @"AttributeNameCell" : @"AttributeValueCell";
    NSTableCellView *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
      result = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
      result.identifier = identifier;
      
      NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
      textField.bezeled = NO;
      textField.drawsBackground = NO;
      textField.editable = NO;
      textField.selectable = YES;
      textField.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
      textField.translatesAutoresizingMaskIntoConstraints = YES;
      textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
      [result addSubview:textField];
      result.textField = textField;
    }
    
    if ([[tableColumn identifier] isEqualToString:@"A"]) {
      result.textField.stringValue = @"Selection";
    } else {
      NSInteger count = [[controller objectsSourceList] numberOfSelectedRows];
      result.textField.stringValue = [NSString stringWithFormat:@"%ld items selected", count];
    }
    return result;
  }
  
  NSInteger objectsRow = [[controller objectsSourceList] selectedRow];
  if (objectsRow == -1) return nil;
  AzulObjectIterator *currentItem = [[controller objectsSourceList] itemAtRow:objectsRow];
  
  NSString *identifier = [[tableColumn identifier] isEqualToString:@"A"] ? @"AttributeNameCell" : @"AttributeValueCell";
  NSTableCellView *result = [tableView makeViewWithIdentifier:identifier owner:self];
  if (result == nil) {
    result = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    result.identifier = identifier;
    
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    textField.bezeled = NO;
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = YES;
    textField.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    textField.translatesAutoresizingMaskIntoConstraints = YES;
    textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [result addSubview:textField];
    result.textField = textField;
  }
  
  NSString *cellString;
  if ([[tableColumn identifier] isEqualToString:@"A"]) cellString = [NSString stringWithUTF8String:[currentItem iterator]->attributes[row].first.c_str()];
  else cellString = [NSString stringWithUTF8String:[currentItem iterator]->attributes[row].second.c_str()];
  result.textField.stringValue = cellString;
  return result;
}

- (void) toggleVisibility:(id)sender {
  if (![sender isKindOfClass:[NSButton class]]) {
    NSLog(@"Uh-oh (not an NSButton)!");
    return;
  } NSButton *checkBox = sender;
  TableCellView *toggledTableCellView = (TableCellView *)[checkBox superview];
  NSOutlineView *outlineView = [self.controller objectsSourceList];
  
  NSInteger toggledItemRow = [outlineView rowForView:toggledTableCellView];
  AzulObjectIterator *toggledItem = [outlineView itemAtRow:toggledItemRow];
  if ([checkBox state] == NSControlStateValueOff) self->dataManagerWrapper->dataManager->setVisible(*[toggledItem iterator], 'N');
  else self->dataManagerWrapper->dataManager->setVisible(*[toggledItem iterator], 'Y');
  [outlineView reloadItem:toggledItem reloadChildren:YES];
  
  AzulObjectIterator *currentItem = [outlineView parentForItem:toggledItem];
  while (currentItem != nil) {
    NSLog(@"Checking %@", currentItem);
    self->dataManagerWrapper->dataManager->checkVisibility(*[currentItem iterator]);
    [outlineView reloadItem:currentItem reloadChildren:NO];
    currentItem = [outlineView parentForItem:currentItem];
  }
  
  dataManagerWrapper->dataManager->updateVisibleStates();
  [controller updateVisibleStateBuffer];
  [controller updateSelectionStateBuffer];
  [[controller metalView] setNeedsDisplay:YES];
  
//  [[controller attributesTableView] reloadData];
}

- (void) toggleVisibilityForSelection:(NSOutlineView *)outlineView {
  NSIndexSet *rows = [outlineView selectedRowIndexes];
  __block bool allVisible = true;
  [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *_Nonnull stop) {
    if (![[outlineView itemAtRow:idx] isKindOfClass:[AzulObjectIterator class]]) NSLog(@"Uh-oh!");
    else {
      AzulObjectIterator *currentItem = [outlineView itemAtRow:idx];
      if ([currentItem iterator]->visible != 'Y') allVisible = false;
    }
  }];
  if (allVisible) {
    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *_Nonnull stop) {
      if (![[outlineView itemAtRow:idx] isKindOfClass:[AzulObjectIterator class]]) NSLog(@"Uh-oh!");
      else {
        AzulObjectIterator *currentItem = [outlineView itemAtRow:idx];
        self->dataManagerWrapper->dataManager->setVisible(*[currentItem iterator], 'N');
        [outlineView reloadItem:currentItem reloadChildren:YES];
      }
    }];
  } else {
    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *_Nonnull stop) {
      if (![[outlineView itemAtRow:idx] isKindOfClass:[AzulObjectIterator class]]) NSLog(@"Uh-oh!");
      else {
        AzulObjectIterator *currentItem = [outlineView itemAtRow:idx];
        self->dataManagerWrapper->dataManager->setVisible(*[currentItem iterator], 'Y');
        [outlineView reloadItem:currentItem reloadChildren:YES];
      }
    }];
  }
  
  dataManagerWrapper->dataManager->updateVisibleStates();
  [controller updateVisibleStateBuffer];
  [controller updateSelectionStateBuffer];
  [[controller metalView] setNeedsDisplay:YES];
  
//  [[controller attributesTableView] reloadData];
}
#endif

- (void) setSearchString:(const char *)string {
  dataManagerWrapper->dataManager->clearSearch();
  dataManagerWrapper->dataManager->searchString = std::string(string);
  NSLog(@"Searching: %s", string);
}

- (void) setSortOrderWithKey:(const char *)key descending:(BOOL)descending {
  dataManagerWrapper->dataManager->setSortOrder(key, descending == YES);
}

- (void) setLodFilter:(const char *)lod {
  dataManagerWrapper->dataManager->setLodFilter(lod);
}

- (NSArray<NSString *> *) availableLods {
  std::vector<std::string> lods = dataManagerWrapper->dataManager->getAvailableLods();
  NSMutableArray *result = [NSMutableArray arrayWithCapacity:lods.size()];
  for (const auto &lod : lods) {
    [result addObject:[NSString stringWithUTF8String:lod.c_str()]];
  }
  return result;
}

- (void) setUseAppearances:(BOOL)enabled {
  dataManagerWrapper->dataManager->setUseAppearances(enabled == YES);
}

- (void) setAppearanceTheme:(const char *)theme {
  if (theme == nullptr) {
    dataManagerWrapper->dataManager->setAppearanceTheme("");
    return;
  }
  dataManagerWrapper->dataManager->setAppearanceTheme(std::string(theme));
}

- (NSArray<NSString *> *) availableAppearanceThemes {
  std::vector<std::string> themes = dataManagerWrapper->dataManager->availableAppearanceThemes();
  NSMutableArray *result = [NSMutableArray arrayWithCapacity:themes.size()];
  for (const auto &theme : themes) {
    [result addObject:[NSString stringWithUTF8String:theme.c_str()]];
  }
  return result;
}

- (void) updateSelectionStates {
  dataManagerWrapper->dataManager->updateSelectionStates();
}

- (void) updateVisibleStates {
  dataManagerWrapper->dataManager->updateVisibleStates();
}

- (const float *) visibleStateData {
  return dataManagerWrapper->dataManager->getVisibleStateData();
}

- (int) visibleStateCount {
  return dataManagerWrapper->dataManager->getVisibleStateCount();
}

- (const float *) selectionStateData {
  return dataManagerWrapper->dataManager->getSelectionStateData();
}

- (int) selectionStateCount {
  return dataManagerWrapper->dataManager->getSelectionStateCount();
}

- (NSString *)statusMessage {
  NSString *statusMessage = [NSString stringWithUTF8String:self->dataManagerWrapper->dataManager->statusMessage.c_str()];
  return statusMessage;
}

- (void) setSelectedEdgesColourWithRed:(float)r green:(float)g blue:(float)b alpha:(float)a {
  dataManagerWrapper->dataManager->setSelectedEdgesColour(r, g, b, a);
}

- (void) getSelectedEdgesColourRed:(float *)r green:(float *)g blue:(float *)b alpha:(float *)a {
  dataManagerWrapper->dataManager->getSelectedEdgesColour(*r, *g, *b, *a);
}

- (NSInteger) colourTypeCount {
  return dataManagerWrapper->dataManager->getTypeCount();
}

- (NSString *) colourTypeNameAtIndex:(NSInteger)index {
  return [NSString stringWithUTF8String:dataManagerWrapper->dataManager->getTypeName(static_cast<int>(index)).c_str()];
}

- (void) getRed:(float *)r green:(float *)g blue:(float *)b alpha:(float *)a forColourTypeAtIndex:(NSInteger)index {
  dataManagerWrapper->dataManager->getTypeColour(static_cast<int>(index), *r, *g, *b, *a);
}

- (void) setColourWithRed:(float)r green:(float)g blue:(float)b alpha:(float)a forType:(const char *)type {
  dataManagerWrapper->dataManager->setTypeColour(std::string(type), r, g, b, a);
}

- (void) resetTypeColours {
  dataManagerWrapper->dataManager->resetTypeColours();
}

- (NSString *) objectIdForItem:(id)item {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return @"";
  AzulObjectIterator *currentItem = item;
  if ([currentItem iterator]->id.empty()) return @"";
  return [NSString stringWithUTF8String:[currentItem iterator]->id.c_str()];
}

// MARK: Item-based access to the object tree

- (char) visibleStateOfItem:(id)item {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return 'N';
  AzulObjectIterator *currentItem = item;
  return [currentItem iterator]->visible;
}

- (void) setVisibleState:(char)visible forItem:(id)item {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return;
  AzulObjectIterator *currentItem = item;
  dataManagerWrapper->dataManager->setVisible(*[currentItem iterator], visible);
  for (auto &file: dataManagerWrapper->dataManager->parsedFiles) {
    refreshAncestorsVisibility(file, &*[currentItem iterator], dataManagerWrapper->dataManager);
  }
  dataManagerWrapper->dataManager->updateVisibleStates();
  [self.controller updateVisibleStateBuffer];
  [self.controller updateSelectionStateBuffer];
}

- (NSInteger) numberOfAttributesOfItem:(id)item {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return 0;
  AzulObjectIterator *currentItem = item;
  return [currentItem iterator]->attributes.size();
}

- (NSString *) attributeKeyOfItem:(id)item atIndex:(NSInteger)index {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return @"";
  AzulObjectIterator *currentItem = item;
  if (index < 0 || index >= (NSInteger)[currentItem iterator]->attributes.size()) return @"";
  return [NSString stringWithUTF8String:[currentItem iterator]->attributes[index].first.c_str()];
}

- (NSString *) attributeValueOfItem:(id)item atIndex:(NSInteger)index {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return @"";
  AzulObjectIterator *currentItem = item;
  if (index < 0 || index >= (NSInteger)[currentItem iterator]->attributes.size()) return @"";
  return [NSString stringWithUTF8String:[currentItem iterator]->attributes[index].second.c_str()];
}

// MARK: Selection helpers

- (void) selectBestHitObject {
  for (auto &currentFile: dataManagerWrapper->dataManager->parsedFiles) {
    dataManagerWrapper->dataManager->setSelection(currentFile, false);
  }
  if (dataManagerWrapper->dataManager->bestHitFile != dataManagerWrapper->dataManager->parsedFiles.end() &&
      dataManagerWrapper->dataManager->bestHitObject != dataManagerWrapper->dataManager->bestHitFile->children.end()) {
    dataManagerWrapper->dataManager->setSelection(*dataManagerWrapper->dataManager->bestHitObject, true);
  }
  dataManagerWrapper->dataManager->updateSelectionStates();
}

- (void) clearSelection {
  for (auto &currentFile: dataManagerWrapper->dataManager->parsedFiles) {
    dataManagerWrapper->dataManager->setSelection(currentFile, false);
  }
  dataManagerWrapper->dataManager->updateSelectionStates();
}

#if !TARGET_OS_OSX
// MARK: iOS tree navigation

- (NSInteger) numberOfParsedFiles {
  return dataManagerWrapper->dataManager->parsedFiles.size();
}

- (id) iteratorForFileAtIndex:(NSInteger)index {
  AzulObjectIterator *item = [[AzulObjectIterator alloc] init];
  item.iterator = dataManagerWrapper->dataManager->fileChild(index);
  item.depth = 0;
  return item;
}

- (BOOL) isItemExpandable:(id)item {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return NO;
  AzulObjectIterator *currentItem = item;
  return dataManagerWrapper->dataManager->isExpandable(*[currentItem iterator]);
}

- (NSInteger) numberOfChildrenOfItem:(id)item {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return 0;
  AzulObjectIterator *currentItem = item;
  return dataManagerWrapper->dataManager->numberOfChildren(*[currentItem iterator]);
}

- (id) childOfItem:(id)item atIndex:(NSInteger)index {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return nil;
  AzulObjectIterator *currentItem = item;
  AzulObjectIterator *child = [[AzulObjectIterator alloc] init];
  child.iterator = dataManagerWrapper->dataManager->child(*[currentItem iterator], index);
  child.depth = [currentItem depth] + 1;
  return child;
}

- (NSString *) typeOfItem:(id)item {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return @"";
  AzulObjectIterator *currentItem = item;
  if ([currentItem iterator]->type.empty()) return @"";
  return [NSString stringWithUTF8String:[currentItem iterator]->type.c_str()];
}

- (NSString *) identifierOfItem:(id)item {
  return [self objectIdForItem:item];
}

- (void) selectItem:(id)item {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return;
  AzulObjectIterator *currentItem = item;
  for (auto &currentFile: dataManagerWrapper->dataManager->parsedFiles) {
    dataManagerWrapper->dataManager->setSelection(currentFile, false);
  }
  dataManagerWrapper->dataManager->setSelection(*[currentItem iterator], true);
  dataManagerWrapper->dataManager->updateSelectionStates();
}

- (const double *) centroidOfItem:(id)item {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return nullptr;
  AzulObjectIterator *currentItem = item;
  dataManagerWrapper->dataManager->centroid[0] = 0;
  dataManagerWrapper->dataManager->centroid[1] = 0;
  dataManagerWrapper->dataManager->centroid[2] = 0;
  CentroidComputation centroidComputation;
  centroidComputation.sum[0] = 0;
  centroidComputation.sum[1] = 0;
  centroidComputation.sum[2] = 0;
  centroidComputation.points = 0;
  dataManagerWrapper->dataManager->addAzulObjectAndItsChildrenToCentroidComputation(*[currentItem iterator], centroidComputation);
  if (centroidComputation.points > 0) {
    dataManagerWrapper->dataManager->centroid[0] = centroidComputation.sum[0] / static_cast<double>(centroidComputation.points);
    dataManagerWrapper->dataManager->centroid[1] = centroidComputation.sum[1] / static_cast<double>(centroidComputation.points);
    dataManagerWrapper->dataManager->centroid[2] = centroidComputation.sum[2] / static_cast<double>(centroidComputation.points);
  }
  return dataManagerWrapper->dataManager->centroid;
}

- (int) centroidPointCountOfItem:(id)item {
  if (![item isKindOfClass:[AzulObjectIterator class]]) return 0;
  AzulObjectIterator *currentItem = item;
  CentroidComputation centroidComputation;
  centroidComputation.sum[0] = 0;
  centroidComputation.sum[1] = 0;
  centroidComputation.sum[2] = 0;
  centroidComputation.points = 0;
  dataManagerWrapper->dataManager->addAzulObjectAndItsChildrenToCentroidComputation(*[currentItem iterator], centroidComputation);
  return static_cast<int>(centroidComputation.points);
}
#endif

@end
