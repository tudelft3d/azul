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

#import "TableCellView.h"

@implementation TableCellView

- (TableCellView *)initWithFrame:(NSRect)frameRect {
//  NSLog(@"[TableCellView initWithFrame]");
  if (self = [super initWithFrame:frameRect]) {
    
    image = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 3, 16, 16)];
    [image setImageScaling:NSImageScaleProportionallyUpOrDown];
    [image setImageAlignment:NSImageAlignCenter];
    
    text = [[NSTextField alloc] initWithFrame:NSMakeRect(21, 3, 30000, 14)];
    [text setDrawsBackground:false];
    [text setBordered:false];
    [text setEditable:false];
    [text setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    
    [self setAutoresizingMask:NSViewWidthSizable];
    [self setImageView:image];
    [self setTextField:text];
    [self addSubview:[self imageView]];
    [self addSubview:[self textField]];
    
  } return self;
}

@end
