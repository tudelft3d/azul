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

#import "PerformanceHelper.h"
#import "PerformanceHelperImpl.hpp"

@interface PerformanceHelper() {
    struct PerformanceHelperImpl *performanceHelper;
}
@end

@implementation PerformanceHelper

- (instancetype) init {
  if (self = [super init]) {
    performanceHelper = new PerformanceHelperImpl();
  } return self;
}

- (void) startTimer {
  performanceHelper->startTimer();
}

- (void) printTimeSpent {
  performanceHelper->printTimer();
}

- (void) printMemoryUsage {
  performanceHelper->printMemoryUsage();
}

- (void) dealloc {
    delete performanceHelper;
}

@end

