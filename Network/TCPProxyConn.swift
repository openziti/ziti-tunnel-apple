//
//  TCPProxyConn
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/23/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import NetworkExtension
import Foundation

class TCPProxyConn : NSObject, ZitiClientProtocol {
    var thread:Thread?
    let writeCond = NSCondition() // TODO: change this to a queue...
    var inputStream: InputStream?
    var outputStream: OutputStream?
    let mss:Int
    
    typealias DataAvailableCallback = ((Data?, Int) -> Void)
    var onDataAvailable: DataAvailableCallback? = nil
    
    required init(mss:Int) {
        self.mss = mss
        super.init()
        self.thread = Thread(target: self, selector: #selector(TCPProxyConn.doRunLoop), object: nil)
        NSLog("init TCPProxyConn")
    }
    
    deinit {
        NSLog("deinit TCPProxyConn")
        close()
    }
    
    func start(_ onDataAvailable: @escaping DataAvailableCallback) -> Bool {
        self.onDataAvailable = onDataAvailable
        Stream.getStreamsToHost(withName: "127.0.0.1", port: 7777, inputStream: &inputStream, outputStream: &outputStream)
        guard inputStream != nil && outputStream != nil else {
            NSLog("Unable to create socket")
            return false
        }
        inputStream!.delegate = self
        outputStream!.delegate = self
        
        thread?.name = "TCPProxyConn" // TODO
        thread?.start()
        
        return true
    }
    
    //var writeQueue:[Data] = []
    func write(payload:Data) -> Int {
        
        // TODO: change this to queue data until connected
        writeCond.lock()
        while outputStream?.streamStatus ?? .notOpen != .open {
            if !writeCond.wait(until: Date(timeIntervalSinceNow: 1.0)) {
                NSLog("TCProxy conn timed out waiting for output stream to open")
                writeCond.unlock()
                return -1
            }
        }
        writeCond.unlock()
        //NSLog("TCPProxyConn attempting to write \(payload.count) bytes on thread \(Thread.current)")
        let n = payload.withUnsafeBytes { outputStream?.write($0, maxLength: payload.count) }
        let nBytes = n != nil ? n! : -1
        //NSLog("TCPProxyConn wrote \(nBytes) bytes")
        
        return nBytes
    }
    
    func close() {
        if inputStream?.streamStatus ?? .closed != .closed { inputStream?.close() }
        if outputStream?.streamStatus ?? .closed != .closed { outputStream?.close() }
        if thread?.isCancelled ?? true == false { thread?.cancel() }
    }
    
    @objc private func doRunLoop() {
        inputStream!.schedule(in: .current, forMode: .commonModes)
        outputStream!.schedule(in: .current, forMode: .commonModes)
        
        inputStream!.open()
        outputStream!.open()
        
        NSLog("Starting runloop for \(Thread.current)")
        while !Thread.current.isCancelled {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: TimeInterval(0.5)))
        }
        NSLog("Ending runloop for \(Thread.current)")
    }
}

extension TCPProxyConn : StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if let inStream = aStream as? InputStream  {
            if eventCode == .hasBytesAvailable { doRead(inStream) }
        } else if aStream is OutputStream {
            if eventCode == .openCompleted { writeCond.signal() }
        }
    }
    
    private func doRead(_ stream:InputStream) {
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: mss)
        let nBytes = stream.read(buf, maxLength: mss)
        if nBytes > 0 {
            let data = Data(bytesNoCopy: buf, count: nBytes, deallocator: .custom {buf,_ in buf.deallocate()})
            onDataAvailable?(data, nBytes)
        } else {
            // 0 == eob, -1 == error. stream.streamError? contains more info...
            onDataAvailable?(nil, nBytes)
        }
    }
}
