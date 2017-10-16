//
//  SharedTypes.h
//  azul
//
//  Created by Adam Nemecek on 10/15/17.
//  Copyright © 2017 Ken Arroyo Ohori. All rights reserved.
//

#pragma once

#include <simd/simd.h>

#ifdef __cplusplus
#   define Metal
#endif

//#ifdef Metal
    typedef vector_int2 int2;
    typedef vector_float4 float4;
    typedef vector_float3 float3;
    typedef matrix_float4x4 float4x4;
    typedef matrix_float3x3 float3x3;
//#endif

//// metal
//#ifdef Metal
//typedef bool boolean;
//
////    #define Attr(no) [[attribute(no]]
//#else
///// swift
////    #define Attr(no)
////    typedef vector_int2 int2;
//typedef _Bool boolean;
//#endif



struct Constants {
    float4x4 modelMatrix;
    float4x4 modelViewProjectionMatrix;
    float3x3 modelMatrixInverseTransposed;
    float4x4 viewMatrixInverse;
    float4 colour;
};

struct VertexWithNormal {
  float3 position;
  float3 normal;
};

