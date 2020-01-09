//
//  MBETextTypes.swift
//  LibtessSPMExample
//
//  Created by Vasiliy Shaydullin on 10.12.2019.
//  Copyright © 2019 Vasiliy Shaydullin. All rights reserved.
//

import Foundation
import CoreText
import LibtessSPM
import MetalKit

/// A linked list of glyphs, each jointly represented as a list of contours, a CGPath, and a set of vertices and indices
class Glyph {
    var path: CGPath?
    var contours: [PathContour] = []
    var vertices: [simd_float3] = []
    var indices: [Int] = []
}

class PathContour {
    var vertices: [simd_float3] = []
    var capacity : Int = 32
}

func PathContourAddVertex(contour: PathContour, v: simd_float3) {
    if contour.vertices.count >= contour.capacity - 1 {
        contour.capacity = Int(Double(contour.capacity) * 1.61) // Engineering approximation to the golden ratio
    }
    contour.vertices.append(v)
}

struct MeshVertex {
    var vector: simd_float3
    var normal: simd_float3
    var textCoord: simd_float2
}

typealias IndexType = UInt32
