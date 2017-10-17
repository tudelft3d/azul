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


typedef struct {
    float coordinates[3];
} AzulPoint;

typedef struct {
    float components[3];
} AzulVector;

typedef struct {
    AzulPoint points[3];
    AzulVector normals[3];
} AzulTriangle;

typedef struct {
    AzulPoint points[2];
} AzulEdge;
