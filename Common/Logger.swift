//
//  Logger.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 4/27/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class Logger {
    static var shared:Logger?
    
    private let tag:String
    private var timer:Timer? = nil
    
    private init(_ tag:String) {
        self.tag = tag
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func cleanup(_ appGroupUrl:URL) {
        // delete \(tag)*.logs more than 48 hours old
    }
    
    private func updateLogger() -> Bool {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ZitiIdentityStore.APP_GROUP_ID)  else {
                NSLog("WTF Invalid app group URL")
                return false
        }
        
        // cleanup...
        cleanup(appGroupURL)
            
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        
        let url = appGroupURL.appendingPathComponent("\(tag)_\(dateStr).log", isDirectory:false)
        
        // create empty logfile if not present
        if !FileManager.default.isWritableFile(atPath: url.path) {
            do {
                try "".write(toFile: url.path, atomically: true, encoding: .utf8)
            } catch {
                NSLog("Unable to create log file \(url.path)")
                return false
            }
        }
        
        guard let lfh = FileHandle(forUpdatingAtPath: url.path) else {
            NSLog("Unable to get file handle for updating \(url.path)")
            return false
        }
        
        lfh.seekToEndOfFile()
        let stdErrDes = dup2(lfh.fileDescriptor, FileHandle.standardError.fileDescriptor)
        let stdOutDes = dup2(lfh.fileDescriptor, FileHandle.standardOutput.fileDescriptor)
        
        if (stdErrDes != FileHandle.standardError.fileDescriptor) || (stdOutDes != FileHandle.standardOutput.fileDescriptor) {
            NSLog("Unable to capture stdout and stderr to file \(url.path)")
            return false
        }
        setbuf(__stdoutp, nil) // set stdout to flush
        
        NSLog("Logging to \(url.path)")
        return true
    }
    
    static func initShared(_ tag:String) {
        Logger.shared = Logger(tag)
        if Logger.shared?.updateLogger() == false {
            // Do what?  invalidate Logger? revisit when add #file #function #line stuff
        }

        // fire timer periodically for clean-up and rolling
        // (do this on main queue since need to guarentee its done in a run loop)
        DispatchQueue.main.async {
            let timeInterval = TimeInterval(60*60) // hourly (could be a lot smarter about this...)
            Logger.shared?.timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { _ in
                _ = Logger.shared?.updateLogger()
            }
        }
    }
}
