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
    
    func connect(_ onDataAvailable: @escaping DataAvailableCallback) -> Bool {
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
        // target global serial queue, Interactiv
        guard let outputStream = outputStream  else { return -1 }
        writeCond.lock()
        let okFlags = Stream.Status.open.rawValue | Stream.Status.writing.rawValue
        while outputStream.streamStatus.rawValue & okFlags == 0 {
            NSLog("*** outstream stat: \(outputStream.streamStatus.rawValue) on \(Thread.current)")
            if !writeCond.wait(until: Date(timeIntervalSinceNow: 3.0)) { // TODO: ridic timeout...
                NSLog("*** TCProxy conn timed out waiting for output stream to open, thread \(Thread.current)")
                writeCond.unlock()
                return -1
            }
            NSLog("*** loop outstream stat: \(outputStream.streamStatus.rawValue) on \(Thread.current)")
        }
        
        //NSLog("TCPProxyConn attempting to write \(payload.count) bytes on thread \(Thread.current)")
        let n = payload.withUnsafeBytes { outputStream.write($0, maxLength: payload.count) }
        if outputStream.streamStatus == .writing { // should never happen since inside of a lock, but sometimes it does
            NSLog("** done writing \(n) of \(payload.count), \(outputStream.streamStatus.rawValue) on \(Thread.current)")
        }
        writeCond.unlock()
        
        //NSLog("TCPProxyConn wrote \(nBytes) bytes")
        return n
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
        
        NSLog("*** Starting runloop for \(Thread.current)")
        while !Thread.current.isCancelled {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: TimeInterval(0.5)))
        }
        NSLog("*** Ending runloop for \(Thread.current)")
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
        var i = 0
        while stream.hasBytesAvailable {
            let nBytes = stream.read(buf, maxLength: mss)
            NSLog("\(i)<<< Read \(nBytes) of possible \(mss)")
            if nBytes > 0 {
                let data = Data(bytesNoCopy: buf, count: nBytes, deallocator: .none)
                onDataAvailable?(data, nBytes)
            } else {
                // 0 == eob, -1 == error. stream.streamError? contains more info...
                onDataAvailable?(nil, nBytes)
            }
            i = i + 1
        }
        buf.deallocate()
    }
}
