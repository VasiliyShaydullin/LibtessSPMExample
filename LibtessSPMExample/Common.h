//
//  Common.h
//  LibtessSPMExample
//
//  Created by Vasiliy Shaydullin on 18.12.2019.
//  Copyright © 2019 Vasiliy Shaydullin. All rights reserved.
//

#ifndef Common_h
#define Common_h

#import <simd/simd.h>
typedef struct {
    matrix_float4x4 projectionMatrix;
    simd_float4x4 modelViewMatrix;
} Uniforms;

typedef enum {
  Position = 0,
  Normal = 1,
  UV = 2,
} Attributes;

typedef enum {
  BufferIndexVertices = 0,
  BufferIndexUniforms = 11,
} BufferIndices;

#endif /* Common_h */
