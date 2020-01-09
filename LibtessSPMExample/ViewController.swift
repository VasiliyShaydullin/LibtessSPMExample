//
//  ViewController.swift
//  LibtessSPMExample
//
//  Created by Vasiliy Shaydullin on 26.12.2019.
//  Copyright © 2019 Vasiliy Shaydullin. All rights reserved.
//

import MetalKit

class ViewController: UIViewController {

    var renderer: Renderer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let mtkView = view as? MTKView else {
          fatalError("metal view not set up in storyboard")
        }
        self.renderer = Renderer(metalView: mtkView)
        
        let bufferAllocator = MTKMeshBufferAllocator(device: mtkView.device!)
        let font = CTFontCreateWithName("HoeflerText-Black" as CFString, 72, nil)
        guard let vertexDescriptor = renderer?.vertexDescriptor else { return }
        let textMesh = MBETestMesh().meshWith(string: "Hello, world!", font: font, extrusionDepth: 16.0, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
        
        self.renderer?.mesh = textMesh
        
    }
}

