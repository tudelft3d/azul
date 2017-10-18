//
//  Extensions.swift
//  azul
//
//  Created by Adam Nemecek on 10/15/17.
//  Copyright © 2017 Ken Arroyo Ohori. All rights reserved.
//

import MetalKit
import Cocoa

extension float2 {
    init(cgPoint : CGPoint) {
        self.init(x: Float(cgPoint.x), y: Float(cgPoint.y))
    }

    init(cgSize : CGSize) {
        self.init(x: Float(cgSize.width), y: Float(cgSize.height))
    }
}

extension NSPoint {
    static func -(lhs: NSPoint, rhs: NSPoint) -> NSPoint {
        return .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

protocol CachingIterator : IteratorProtocol {
    var current : Element? { get }
}

extension EdgeBufferIterator : IteratorProtocol { }
extension TriangleBufferIterator : IteratorProtocol { }


extension MTLDevice {
    func makeBuffer(ref: UnsafePointer<TriangleBufferRef>) -> MTLBuffer {
        let len = Int(ref.pointee.count) * MemoryLayout<Float>.size
        return makeBuffer(bytes: ref.pointee.content, length: len, options: [])!
    }
}

extension MTLDevice {
    func makeBuffer(ref: UnsafePointer<EdgeBufferRef>) -> MTLBuffer {
        let len = Int(ref.pointee.count) * MemoryLayout<Float>.size
        return makeBuffer(bytes: ref.pointee.content, length: len, options: [])!
    }
}

//extension MTKView {
//    func location(for event : NSEvent) -> float2 {
//        let point = convert(event.locationInWindow, to: nil)
//        let m = window!.mouseLocationOutsideOfEventStream
//        assert(point == m)
//
//        return .init(cgPoint: point)
//    }
//
//    func mouseLocation() -> float2 {
//        let point = window!.mouseLocationOutsideOfEventStream
//
//    }
//}

extension MTKView {
    @objc public var currentMouseLocation : float2 {
        let bounds = self.bounds
        let frame = self.convert(bounds, to: nil) // is this the same as .frame?

        let mouse = float2(cgPoint: window!.mouseLocationOutsideOfEventStream)
        let origin = float2(cgPoint: frame.origin)
        let point = mouse - origin
        return float2(-1,-1) + 2 * (point / float2(cgSize: bounds.size))
    }
}

extension Sequence where Iterator.Element == URL {
    func first(for types : Set<String>) -> URL? {
        return first { types.contains($0.pathExtension) }
    }
}

extension NSDraggingInfo {
    func urls() -> [URL]? {
        return draggingPasteboard().readObjects(forClasses: [NSURL.self], options: [:]) as? [URL]
    }
}

