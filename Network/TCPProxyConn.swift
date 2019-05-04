//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import NetworkExtension
import Foundation

class TCPProxyConn : NSObject, ZitiClientProtocol {
    let key:String
    let ip:String
    let port:UInt16
    
    var thread:Thread?
    let writeCond = NSCondition()
    var inputStream: InputStream?
    var outputStream: OutputStream?
    let maxReadLen:Int = Int(UInt16.max / 15960) * 15960 // TODO: should be configurable based on windowSize/Scale, mult of mss
    
    var onDataAvailable: DataAvailableCallback? = nil
    
    init(_ key:String, _ ip:String, _ port:UInt16) {
        self.key = key
        self.ip = ip
        self.port = port
        NSLog("init TCPProxyConn \(key), \(ip):\(port)")
    }
    
    deinit {
        NSLog("deinit TCPProxyConn \(key), \(ip):\(port)")
        close()
    }
    
    func connect(_ onDataAvailable: @escaping DataAvailableCallback) -> Bool {
        self.onDataAvailable = onDataAvailable
        Stream.getStreamsToHost(withName: ip, port: Int(port), inputStream: &inputStream, outputStream: &outputStream)
        guard inputStream != nil && outputStream != nil else {
            NSLog("TCPProxyConn Unable to connect to \(ip):\(port)")
            return false
        }
        inputStream!.delegate = self
        outputStream!.delegate = self
        self.thread = Thread(target: self, selector: #selector(TCPProxyConn.doRunLoop), object: nil)
        thread?.name = key
        thread?.start()
        
        return true
    }
    
    func write(payload:Data) -> Int {
        guard let outputStream = outputStream  else { return -1 }
        writeCond.lock()
        let okFlags = Stream.Status.open.rawValue | Stream.Status.writing.rawValue
        while outputStream.streamStatus.rawValue & okFlags == 0 {
            //NSLog("*** outstream stat: \(outputStream.streamStatus.rawValue) on \(Thread.current)")
            if !writeCond.wait(until: Date(timeIntervalSinceNow: 5.0)) { 
                NSLog("*** TCProxy conn timed out waiting for output stream to open, thread \(Thread.current)")
                writeCond.unlock()
                return -1
            }
            //NSLog("*** loop outstream stat: \(outputStream.streamStatus.rawValue) on \(Thread.current)")
        }
        
        //NSLog("TCPProxyConn attempting to write \(payload.count) bytes on thread \(Thread.current)")
        let n = outputStream.write([UInt8](payload[payload.startIndex..<payload.endIndex]), maxLength: payload.count)
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
        inputStream!.schedule(in: .current, forMode: RunLoop.Mode.common)
        outputStream!.schedule(in: .current, forMode: RunLoop.Mode.common)
        
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
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: maxReadLen)
        //while stream.hasBytesAvailable {
            let nBytes = stream.read(buf, maxLength: maxReadLen)
            if nBytes > 0 {
                let data = Data(bytesNoCopy: buf, count: nBytes, deallocator: .none)
                onDataAvailable?(data, nBytes)
            } else {
                // 0 == eob, -1 == error. stream.streamError? contains more info...
                onDataAvailable?(nil, nBytes)
            }
       // }
        buf.deallocate()
    }
}
