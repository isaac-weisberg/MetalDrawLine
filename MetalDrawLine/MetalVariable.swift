import MetalKit

struct MetalArrayVariable<Element>: ~Copyable {
    let initialCount: Int
    var value: [Element] {
        didSet {
            dirty = true
            #if DEBUG
                assert(value.count == initialCount)
            #endif
        }
    }

    let buffer: MTLBuffer
    var dirty = true
    
    init?(
        value: [Element],
        device: MTLDevice,
    ) {
        self.value = value
        self.initialCount = value.count
        guard let buffer = device.makeBuffer(
            bytes: value,
            length: MemoryLayout<Element>.stride * value.count,
        ) else {
            return nil
        }
        
        self.buffer = buffer
    }
    
    mutating func flushIfNeeded() {
        if dirty {
            dirty = false
            flush()
        }
    }
    
    func flush() {
        memcpy(buffer.contents(), value, MemoryLayout<Element>.stride * value.count)
    }
    
    mutating func reverseFlush() {
        memcpy(&value, buffer.contents(), MemoryLayout<Element>.stride * value.count)
    }
}

struct MetalVariable<Element>: ~Copyable {
    var value: Element {
        didSet {
            dirty = true
        }
    }

    let buffer: MTLBuffer
    var dirty = true
    
    init?(
        value: Element,
        device: MTLDevice,
    ) {
        self.value = value
        guard let buffer = device.makeBuffer(
            bytes: &self.value,
            length: MemoryLayout<Element>.stride,
        ) else {
            return nil
        }
        
        self.buffer = buffer
    }
    
    mutating func flushIfNeeded() {
        if dirty {
            dirty = false
            flush()
        }
    }
    
    mutating func flush() {
        memcpy(buffer.contents(), &value, MemoryLayout<Element>.stride)
    }
}
