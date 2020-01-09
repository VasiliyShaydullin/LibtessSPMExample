//
//  MBETextMesh.swift
//  LibtessSPMExample
//
//  Created by Vasiliy Shaydullin on 10.12.2019.
//  Copyright © 2019 Vasiliy Shaydullin. All rights reserved.
//

import Foundation
import CoreText
import MetalKit
import Darwin
import LibtessSPM

let USE_ADAPTIVE_SUBDIVISION = 1
let DEFAULT_QUAD_CURVE_SUBDIVISIONS = 5
let VERT_COMPONENT_COUNT = 2

class MBETestMesh {
    
    func meshWith(string: String, font: CTFont, extrusionDepth: CGFloat, vertexDescriptor: MDLVertexDescriptor, bufferAllocator: MTKMeshBufferAllocator) -> MTKMesh? {
        
        // Create an attributed string from the provided text; we make our own attributed string
        // to ensure that the entire mesh has a single style, which simplifies things greatly.
        let attributes = [NSAttributedString.Key.font : font]
        let attributedString = CFAttributedStringCreate(nil , string as CFString, attributes as CFDictionary)
        
        // Transform the attributed string to a linked list of glyphs, each with an associated path from the specified font
        let (glyphs, bounds) = glyphsFor(attributedString: attributedString!)
        
        // Flatten the paths associated with the glyphs so we can more easily tessellate them in the next step
        flattenPathsFor(glyphs: glyphs)
        
        // Tessellate the glyphs into contours and actual mesh geometry
        tessellatePathsFor(glyphs: glyphs)
        
        // Figure out how much space we need in our vertex and index buffers to accommodate the mesh
        let (vertexCount, indexCount) = calculateVertexCount(glyphs: glyphs)
        
        // Allocate the vertex and index buffers
        let vertexBuffer: MDLMeshBuffer = bufferAllocator.newBuffer(vertexCount * MemoryLayout<MeshVertex>.stride, type: MDLMeshBufferType.vertex)
        let indexBuffer: MDLMeshBuffer = bufferAllocator.newBuffer(indexCount * MemoryLayout<IndexType>.stride, type: MDLMeshBufferType.index)
        
        // Write text mesh geometry into the vertex and index buffers
        writeVerticesForGlyphs(glyphs: glyphs, bounds: bounds, extrusionDepth: extrusionDepth, vertexBuffer: vertexBuffer, offset: 0)
        writeIndicesForGlyphs(glyphs: glyphs, indexBuffer: indexBuffer, offset: 0, indexCount: indexCount)
        
        // Use ModelIO to create a mesh object, then return a MetalKit mesh we can render later
        let submesh: MDLSubmesh = MDLSubmesh(indexBuffer: indexBuffer,
                                             indexCount: indexCount,
                                             indexType: MDLIndexBitDepth.uInt32,
                                             geometryType: MDLGeometryType.triangles,
                                             material: nil)
        let submeshes = [submesh]
        let mdlMesh: MDLMesh = meshForVertexBuffer(vertexBuffer: vertexBuffer, vertexCount: vertexCount, submeshes: submeshes, vertexDescriptor: vertexDescriptor)
        
        do {
            let mesh = try MTKMesh(mesh: mdlMesh, device: bufferAllocator.device)
            return mesh
        } catch let err {
            print(err.localizedDescription)
        }
        return nil
    }
 
    func glyphsFor(attributedString: CFAttributedString) -> ([Glyph], CGRect?) {
        var glyphArray = [Glyph]()
        var imageBounds: CGRect? = CGRect()
        
        // Create a typesetter and use it to lay out a single line of text
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        let line = CTTypesetterCreateLine(typesetter, CFRangeMake(0, 0))
        let runs: NSArray = CTLineGetGlyphRuns(line)
        
        // For each of the runs, of which there should only be one...
        for runIdx in 0..<runs.count {
            let run: CTRun  = runs[runIdx] as! CTRun
            let glyphCount = CTRunGetGlyphCount(run)
            
            // Retrieve the list of glyph positions so we know how to transform the paths we get from the font
            let glyphPositions = UnsafeMutablePointer<CGPoint>.allocate(capacity: glyphCount)
            CTRunGetPositions(run, CFRangeMake(0, 0), glyphPositions)
            
            // Retrieve the bounds of the text, so we can crudely center it
            var bounds = CTRunGetImageBounds(run, nil, CFRangeMake(0, 0))
            bounds.origin.x -= bounds.size.width / 2
            
            let glyphs = UnsafeMutablePointer<CGGlyph>.allocate(capacity: glyphCount)
            CTRunGetGlyphs(run, CFRangeMake(0, 0), glyphs)
            
            // Fetch the font from the current run. We could have taken this as a parameter, but this is more future-proof.
            let runAttributes: NSDictionary = CTRunGetAttributes(run)
            let font: CTFont = runAttributes[kCTFontAttributeName] as! CTFont
            
            // For each glyph in the run...
            for glyphIdx in 0..<glyphCount {
                // Compute a transform that will position the glyph correctly relative to the others, accounting for centering
                let glyphPosition = glyphPositions[glyphIdx]
                var glyphTransform = CGAffineTransform(translationX: glyphPosition.x - bounds.size.width / 2, y: glyphPosition.y)
                
                // Retrieve the actual path for this glyph from the font
                let path = CTFontCreatePathForGlyph(font, glyphs[glyphIdx], &glyphTransform)
                
                if path == nil {
                    continue // non-printing and whitespace characters have no associated path
                }
                
                let glyph = Glyph()
                glyph.path = path
                glyphArray.append(glyph)
                
            }
            
            if imageBounds != nil {
                imageBounds = bounds
            }
            
        }
        
        return (glyphArray, imageBounds)
    }
    
    func flattenPathsFor(glyphs: [Glyph]) {
        // For each glyph, replace its non-flattened path with a flattened path
        for glyph in glyphs { 
            let flattenedPath = namenewFlattenedPathFor(path: glyph.path ?? CGPath(rect: CGRect(), transform: nil), flatness: 0.1)
            glyph.path = flattenedPath
            
        }
    }
    
    func namenewFlattenedPathFor(path: CGPath, flatness: CGFloat) -> CGPath {
        let flattenedPath = CGMutablePath()
        // Iterate the elements in the path, converting curve segments into sequences of small line segments
        path.applyWithBlock { (element) in
            switch element.pointee.type {
            case .moveToPoint:
                let point = element.pointee.points[0]
                flattenedPath.move(to: point)
            case .addLineToPoint:
                let point = element.pointee.points[0]
                flattenedPath.addLine(to: point)
            case .addQuadCurveToPoint:
                if USE_ADAPTIVE_SUBDIVISION == 1 {
                    let MAX_SUBDIVS = 20
                    let a = flattenedPath.currentPoint // "from" point
                    let b = element.pointee.points[1]  // "to" point
                    let c = element.pointee.points[0]  // control point
                    let tolSq = flatness * flatness    // maximum tolerable squared error
                    var t: CGFloat = 0.0;     // Parameter of the curve up to which we've subdivided
                    var candT: CGFloat = 0.5  // "Candidate" parameter of the curve we're currently evaluating
                    var p = a        // Point along curve at parameter t
                    while t < 1.0 {
                        var subdivs = 1
                        var err = CGFloat.greatestFiniteMagnitude // Squared distance from midpoint of candidate segment to midpoint of true curve segment
                        var candP = p
                        candT = fmin(1.0, t + 0.5)
                        while err > tolSq {
                            candP = MBETestMesh.evalQuadCurve(a: a, b: b, c: c, t: candT)
                            let midT = (t + candT) / 2
                            let midCurve = MBETestMesh.evalQuadCurve(a: a, b: b, c: c, t: midT)
                            let midSeg = MBETestMesh.lerpPoints(a: p, b: candP, t: 0.5)
                            err = pow(midSeg.x - midCurve.x, 2) + pow(midSeg.y - midCurve.y, 2)
                            if err > tolSq {
                                candT = t + 0.5 * (candT - t)
                                subdivs += 1
                                if subdivs > MAX_SUBDIVS {
                                    break
                                }
                            }
                        }
                        t = candT
                        p = candP
                        flattenedPath.addLine(to: p)
                    }
                } else {
                    let a = flattenedPath.currentPoint
                    let b = element.pointee.points[1]
                    let c = element.pointee.points[0]
                    for i in 0..<DEFAULT_QUAD_CURVE_SUBDIVISIONS {
                        let t = CGFloat(i) / CGFloat(DEFAULT_QUAD_CURVE_SUBDIVISIONS - 1)
                        let r = MBETestMesh.evalQuadCurve(a: a, b: b, c: c, t: t);
                        flattenedPath.addLine(to: r)
                    }
                }
            case .addCurveToPoint:
                print("Can't currently flatten font outlines containing cubic curve segments")
            case .closeSubpath:
                flattenedPath.closeSubpath()
            @unknown default:
                break
            }
        }
        return flattenedPath
    }
    
    static func evalQuadCurve(a : CGPoint, b : CGPoint, c : CGPoint, t: CGFloat) -> CGPoint {
        let q0 =  CGPoint(x: lerp(a: a.x, b: c.x, t: t), y: lerp(a: a.y, b: c.y, t: t))
        let q1 = CGPoint(x: lerp(a: c.x, b: b.x, t: t), y: lerp(a: c.y, b: b.y, t: t))
        let r = CGPoint(x: lerp(a: q0.x, b: q1.x, t: t), y: lerp(a: q0.y, b: q1.y, t: t))
        return r
    }
    
    static func lerp(a: CGFloat, b: CGFloat, t: CGFloat) -> CGFloat {
        return a + t * (b - a)
    }
    
    static func lerpPoints(a : CGPoint, b : CGPoint, t : CGFloat) -> CGPoint {
        return CGPoint(x: lerp(a: a.x, b: b.x, t: t), y: lerp(a: a.y, b: b.y, t: t))
    }
    
    func tessellatePathsFor(glyphs: [Glyph]) {
        // Create a new libtess tessellator, requesting constrained Delaunay triangulation
        var tess = LibtessSPM()
        tess?.setOption(optin: .constrainedDelanayTriangulation, value: 1)
        
        let polygonIndexCount = 3 // triangles only
        
        for glyph in glyphs {
            // Accumulate the contours of the flattened path into the tessellator so it can compute the CDT
            let contours = tessellate(path: glyph.path ?? CGPath(rect: CGRect(), transform: nil), tessellator: tess)
            
            // Do the actual tessellation work
            let result = tess?.tesselate(windingRule: .odd, elementType: .polygons, polySize: polygonIndexCount, vertexSize: .size2)
            guard let (verticesTess, indicesTess) = result else {
                print("result = nil")
                continue
            }
            
            
            // Retrieve the tessellated mesh from the tessellator and copy the contour list and geometry to the current glyph
            glyph.contours = contours
            glyph.vertices = verticesTess
            glyph.indices = indicesTess
            
        }
        
        tess = nil
    }
    // MARK: ----
    func tessellate(path: CGPath, tessellator: LibtessSPM?) -> [PathContour] {
        var contour = PathContour()
        var contours = [PathContour]()
        // Iterate the line segments in the flattened path, accumulating each subpath as a contour,
        // then pass closed contours to the tessellator
        path.applyWithBlock { (element) in
            switch element.pointee.type {
            case .moveToPoint:
                let point = element.pointee.points[0]
                if (contour.vertices.count != 0) {
                    print("Open subpaths are not supported; all contours must be closed")
                }
                PathContourAddVertex(contour: contour, v: simd_float3(Float(point.x), Float(point.y), 0))
                
            case .addLineToPoint:
                let point = element.pointee.points[0]
                PathContourAddVertex(contour: contour, v: simd_float3(Float(point.x), Float(point.y), 0))
                
            case .addQuadCurveToPoint:
                print("Tessellator does not expect curve segments; flatten path first")
                
            case .addCurveToPoint:
                break
                
            case .closeSubpath:
                let vertices = contour.vertices
                let vertexCount = contour.vertices.count
                tessellator?.addContour(size: 2, vertices: vertices, stride: MemoryLayout<Vector>.stride, count: vertexCount)
                contours.append(contour)
                contour = PathContour()
            @unknown default:
                break
            }
        }
        return contours
    }
    
    func calculateVertexCount(glyphs: [Glyph]) -> (Int, Int) {
        var vertexBufferCount = 0
        var indexBufferCount = 0
        
        for glyph in glyphs {
            // Space for front- and back-facing tessellated faces
            vertexBufferCount += 2 * (glyph.vertices.count)
            indexBufferCount += 2 * (glyph.indices.count)
            
            let contours = glyph.contours
            // Space for stitching faces
            for contour in contours {
                vertexBufferCount += 2 * (contour.vertices.count)
                indexBufferCount += 6 * ((contour.vertices.count) + 1)
            }
        }
        return (vertexBufferCount, indexBufferCount)
    }
    
    func writeVerticesForGlyphs(glyphs: [Glyph], bounds: CGRect?, extrusionDepth: CGFloat, vertexBuffer: MDLMeshBuffer, offset: Int) {
        let map: MDLMeshBufferMap = vertexBuffer.map()
        // For each glyph, write two copies of the tessellated mesh into the vertex buffer,
        // one after the other. The first copy is for front-facing faces, and the second
        // copy is for rear-facing faces
        var vertices: [MeshVertex] = []
        for glyph in glyphs {
            
            for i in 0..<glyph.vertices.count {
                //j += 1
                let x = glyph.vertices[i].x
                let y = glyph.vertices[i].y
                let s = MBETestMesh.remap((bounds ?? CGRect()).minX, (bounds ?? CGRect()).maxX, 0, 1, CGFloat(x))
                let t = MBETestMesh.remap((bounds ?? CGRect()).minY, (bounds ?? CGRect()).maxY, 1, 0, CGFloat(y))
                
                vertices.append(MeshVertex(vector: simd_float3(Float(x), Float(y), 0),
                                           normal: simd_float3(0, 0, 0),
                                           textCoord: simd_float2(Float(s), Float(t))))
                
            }
            
            for j in 0..<glyph.vertices.count {
                let x = glyph.vertices[j].x
                let y = glyph.vertices[j].y
                let s = MBETestMesh.remap((bounds ?? CGRect()).minX, (bounds ?? CGRect()).maxX, 0, 1, CGFloat(x))
                let t = MBETestMesh.remap((bounds ?? CGRect()).minY, (bounds ?? CGRect()).maxY, 1, 0, CGFloat(y))
                
                vertices.append(MeshVertex(vector: simd_float3(Float(x), Float(y), Float(-extrusionDepth)),
                                           normal: simd_float3(0, 0, 0),
                                           textCoord: simd_float2(Float(s), Float(t))))
            }
        }
        
        // Now, write two copies of the contour vertices into the vertex buffer. The first
        // set correspond to the front-facing faces, and the second copy correspond to the
        // rear-facing faces
        for glyph in glyphs {
            let contours = glyph.contours
            for contour in contours {
                for i in 0..<contour.vertices.count {
                    
                    let x = contour.vertices[i].x
                    let y = contour.vertices[i].y
                    
                    let s = MBETestMesh.remap((bounds ?? CGRect()).minX, (bounds ?? CGRect()).maxX, 0, 1, CGFloat(x))
                    let t = MBETestMesh.remap((bounds ?? CGRect()).minY, (bounds ?? CGRect()).maxY, 1, 0, CGFloat(y))
                    
                    vertices.append(MeshVertex(vector: simd_float3(Float(x), Float(y), 0),
                                               normal: simd_float3(0, 0, 0),
                                               textCoord: simd_float2(Float(s), Float(t))))
                    
                }
                
                for j in 0..<contour.vertices.count {
                    let x = contour.vertices[j].x
                    let y = contour.vertices[j].y
                    
                    let s = MBETestMesh.remap((bounds ?? CGRect()).minX, (bounds ?? CGRect()).maxX, 0, 1, CGFloat(x))
                    let t = MBETestMesh.remap((bounds ?? CGRect()).minY, (bounds ?? CGRect()).maxY, 1, 0, CGFloat(y))
                    
                    vertices.append(MeshVertex(vector: simd_float3(Float(x), Float(y), Float(-extrusionDepth)),
                                               normal: simd_float3(0, 0, 0),
                                               textCoord: simd_float2(Float(s), Float(t))))
                }
            }
        }
        map.bytes.assumingMemoryBound(to: MeshVertex.self).assign(from: vertices, count: vertices.count)
    }
    
    // Maps a value t in a range [a, b] to the range [c, d]
    static func remap(_ a : CGFloat, _ b : CGFloat, _ c : CGFloat, _ d : CGFloat, _ t : CGFloat) -> CGFloat {
        let p = (t - a) / (b - a);
        return c + p * (d - c);
    }
    
    func writeIndicesForGlyphs(glyphs: [Glyph], indexBuffer: MDLMeshBuffer, offset: Int, indexCount: Int) {
        let indexMap: MDLMeshBufferMap = indexBuffer.map()
        // Write indices for front-facing and back-facing faces
        var baseVertex: UInt32 = 0
        var indices: [IndexType] = []
        for glyph in glyphs {
            let glyphIndices = glyph.indices
            for i in stride(from: 0, to: glyph.indices.count, by: 3) {
               
                indices.append(UInt32(glyphIndices[i + 2]) + baseVertex)
                indices.append(UInt32(glyphIndices[i + 1]) + baseVertex)
                indices.append(UInt32(glyphIndices[i + 0]) + baseVertex)
            }
            
            for i in stride(from: 0, to: glyph.indices.count, by: 3) {
                indices.append(UInt32(glyphIndices[i + 0]) + baseVertex + UInt32(glyph.vertices.count))
                indices.append(UInt32(glyphIndices[i + 1]) + baseVertex + UInt32(glyph.vertices.count))
                indices.append(UInt32(glyphIndices[i + 2]) + baseVertex + UInt32(glyph.vertices.count))
            }
            baseVertex += UInt32(glyph.vertices.count * 2)
        }
        
         //Write indices for stitching faces
        for glyph in glyphs {
            let contours = glyph.contours
            for contour in contours {
                for i in 0..<contour.vertices.count {
                    let i0 = i
                    let i1 = (i + 1) % contour.vertices.count
                    let i2 = i + contour.vertices.count
                    let i3 = (i + 1) % contour.vertices.count + contour.vertices.count
                    
                    indices.append(UInt32(i0) + baseVertex)
                    indices.append(UInt32(i1) + baseVertex)
                    indices.append(UInt32(i2) + baseVertex)
                    indices.append(UInt32(i1) + baseVertex)
                    indices.append(UInt32(i3) + baseVertex)
                    indices.append(UInt32(i2) + baseVertex)
                    
                }
                
                baseVertex += UInt32(contour.vertices.count * 2)
            }
        }
        indexMap.bytes.assumingMemoryBound(to: IndexType.self).assign(from: indices, count: indices.count)
    }

    func meshForVertexBuffer(vertexBuffer: MDLMeshBuffer, vertexCount: Int, submeshes: [MDLSubmesh], vertexDescriptor: MDLVertexDescriptor) -> MDLMesh {
        let mdlMesh: MDLMesh = MDLMesh(vertexBuffer: vertexBuffer, vertexCount: vertexCount, descriptor: vertexDescriptor, submeshes: submeshes)
        
        mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: sqrt(2)/2)
        
        return mdlMesh
    }
}


