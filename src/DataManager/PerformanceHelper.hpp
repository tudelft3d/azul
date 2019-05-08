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

#ifndef PerformanceHelper_hpp
#define PerformanceHelper_hpp

#include <mach/mach.h>
#include <iostream>
#include <string>

class PerformanceHelper {
  clock_t startTime;
  
public:
  void startTimer() {
    startTime = clock();
  }
  
  void printTimer() {
    clock_t stopTime = clock();
    double seconds = (stopTime-startTime)/(double)CLOCKS_PER_SEC;
    std::string time = "Time: ";
    time +=  std::to_string(seconds) + " seconds";
    std::cout << time << std::endl;
  }
  
  void printMemoryUsage() {
    struct task_basic_info t_info;
    mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT;
    std::string usage;
    if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count) == KERN_SUCCESS) {
      
      usage += "Resident memory: ";
      if (t_info.resident_size > 1024*1024*1024) {
        usage += std::to_string(t_info.resident_size/(1024.0*1024.0*1024.0)) + " GB";
      } else if (t_info.resident_size > 1024*1024) {
        usage += std::to_string(t_info.resident_size/(1024.0*1024.0)) + " MB";
      } else if (t_info.resident_size > 1024) {
        usage += std::to_string(t_info.resident_size/1024.0) + " KB";
      } else {
        usage += std::to_string(t_info.resident_size) + " bytes";
      }
      
      usage += " virtual: ";
      if (t_info.virtual_size > 1024*1024*1024) {
        usage += std::to_string(t_info.virtual_size/(1024.0*1024.0*1024.0)) + " GB";
      } else if (t_info.virtual_size > 1024*1024) {
        usage += std::to_string(t_info.virtual_size/(1024.0*1024.0)) + " MB";
      } else if (t_info.virtual_size > 1024) {
        usage += std::to_string(t_info.virtual_size/1024.0) + " KB";
      } else {
        usage += std::to_string(t_info.virtual_size) + " bytes";
      }
      
    } std::cout << usage << std::endl;
  }
};

#endif /* PerformanceHelper_hpp */
