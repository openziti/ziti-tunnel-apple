//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation

class NetifDriver : NSObject {
    weak var ptp:PacketTunnelProvider?
    
    var driver:UnsafeMutablePointer<netif_driver_t>!
    var packetCallback:packet_cb?
    var netif:UnsafeMutableRawPointer?
    
    var readQueue:[Data] = []
    var queueLock = NSLock()
    var asyncHandle:uv_async_t?
    
    init(ptp:PacketTunnelProvider) {
        self.ptp = ptp
        driver = UnsafeMutablePointer<netif_driver_t>.allocate(capacity: 1)
        driver.initialize(to: netif_driver_t())
        super.init()
    }
    
    func open() -> UnsafeMutablePointer<netif_driver_t> {
        let driver = UnsafeMutablePointer<netif_driver_t>.allocate(capacity: 1)
        driver.initialize(to: netif_driver_t())
        
        driver.pointee.handle = OpaquePointer(self.toVoidPtr())
        driver.pointee.setup = NetifDriver.setup_cb
        driver.pointee.uv_poll_init = nil // keep this nil (tunneler sdk will use setup if it exists, poll only if it doesn't)
        driver.pointee.read = NetifDriver.read_cb // empty with log message.  should never be called
        driver.pointee.write = NetifDriver.write_cb
        driver.pointee.close = NetifDriver.close_cb
        
        return driver
    }
    
    func close() {
        driver.deinitialize(count: 1)
        driver.deallocate()
    }
    
    func queuePacket(_ data:Data) {
        queueLock.lock()
        readQueue.append(data)
        queueLock.unlock()
        
        if asyncHandle != nil {
            uv_async_send(&(asyncHandle!))
        }
    }
    
    static let setup_cb:setup_packet_cb = { handle, loop, cb, netif in
        guard let mySelf = NetifDriver.unretained(UnsafeMutableRawPointer(handle)) else {
            NSLog("NetifDriver setup_cb WTF invalid handle")
            return -1
        }
        
        mySelf.asyncHandle = uv_async_t()
        uv_async_init(loop, &(mySelf.asyncHandle!), NetifDriver.async_cb)
        mySelf.asyncHandle?.data = mySelf.toVoidPtr()
        
        mySelf.packetCallback = cb // Prob need to be called on the given loop...
        mySelf.netif = netif // ?
        
        return Int32(0)
    }
    
    static let async_cb:uv_async_cb = { ctx in
        guard let mySelf = NetifDriver.unretained(ctx?.pointee.data) else {
            NSLog("NetifDriver async_cb WTF invalid ctx")
            return
        }
        
        mySelf.queueLock.lock()
        let q = mySelf.readQueue
        mySelf.readQueue = []
        mySelf.queueLock.unlock()
        
        q.forEach { data in
            let len = data.count
            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
            ptr.initialize(from: [UInt8](data), count: len)
            defer {
                ptr.deinitialize(count: len)
                ptr.deallocate()
            }
            ptr.withMemoryRebound(to: Int8.self, capacity: len) {
                mySelf.packetCallback?($0, len, mySelf.netif)
            }
        }
    }
    
    static let read_cb:netif_read_cb = { handle, buf, len in
        NSLog("NetifDriver Unexpected read callback for non-poll driver")
        return Int(0)
    }
    
    static let write_cb:netif_write_cb = { handle, buf, len in
        guard let mySelf = NetifDriver.unretained(UnsafeMutableRawPointer(handle)) else {
            NSLog("NetifDriver write_cb WTF invalid handle")
            return -1
        }
        guard let ptp = mySelf.ptp else {
            NSLog("NetifDriver write_cb WTF invalid ptp")
            return -1
        }
        
        let data = Data(bytes: buf!, count: len)
        ptp.writePacket(data)
        
        return len
    }
    
    static let close_cb:netif_close_cb = { handle in
        guard let mySelf = NetifDriver.unretained(UnsafeMutableRawPointer(handle)) else {
            NSLog("NetifDriver write_cb WTF invalid handle")
            return -1
        }
        mySelf.close()
        return Int32(0)
    }
    
    
    func toVoidPtr() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }

    static func unretained(_ ctx:UnsafeMutableRawPointer?) -> NetifDriver? {
        guard ctx != nil else { return nil }
        return Unmanaged<NetifDriver>.fromOpaque(UnsafeMutableRawPointer(ctx!)).takeUnretainedValue()
    }
}
