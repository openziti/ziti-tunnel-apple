//
// Copyright 2019-2020 NetFoundry, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import CZiti

// call Logger.initShared() first...
var zLog:ZitiLog {
    assert(Logger.shared != nil, "zLog used before Logger initialized")
    return Logger.shared!.zitiLog
}

class Logger {
    static var shared:Logger?
    static let TUN_TAG = "appex"
    static let APP_TAG = "app"
    
    static let FILE_SIZE_THRESHOLD = 5_000_000 // "minsize" bytes
    static let MAX_NUM_LOGS = 3
    static let PROCESS_LOGS_INTERVAL = TimeInterval(60*15) // secs
    
    private let rotateDaily:Bool
    private var lastRotateTime:Date?
    
    private let tag:String
    private var timer:Timer? = nil
    let zitiLog:ZitiLog
    
    private init(_ tag:String, _ rotateDaily:Bool=true) {
        self.tag = tag
        self.rotateDaily = rotateDaily
        self.zitiLog = ZitiLog(Bundle.main.displayName ?? tag)
    }
    
    deinit {
        timer?.invalidate()
    }
    
    var currLog:URL? {
        return currLog(forTag: tag)
    }
    
    func currLog(forTag tag:String) -> URL? {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.APP_GROUP_ID)  else {
                return nil
        }
        return appGroupURL.appendingPathComponent("logs/\(tag).log", isDirectory:false)
    }
    
    private func initLogDir() {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.APP_GROUP_ID)  else {
            zLog.error("currLogfile: Invalid app group URL")
            return
        }
        
        // create log directory if doesn't already exist
        let fm = FileManager.default
        let logDir = appGroupURL.appendingPathComponent("logs", isDirectory:true)
        do {
           try fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        } catch {
            zLog.error("Error creating log dir \(error.localizedDescription)")
            return
        }
        
        // remove any logs > NLOGS
        guard let list = try? fm.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil, options: []) else {
            zLog.warn("Logger.cleanup Unable to search log dir for log files to clear")
            return
        }
        list.forEach { url in
            let fn = url.lastPathComponent
            if fn.starts(with: tag) {
                let comps = fn.components(separatedBy: ".")
                if comps.count >= 3, let indxStr = comps.last, let indx = Int(indxStr) {
                    if indx >= Logger.MAX_NUM_LOGS {
                        do {
                            try fm.removeItem(at: url)
                        } catch {
                            zLog.error("Unable to remove \(url.lastPathComponent). Error:\(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        
        // remove "old style" logs from previous version that were stored in app group directory
        guard let list = try? fm.contentsOfDirectory(at: appGroupURL, includingPropertiesForKeys: nil, options: []) else {
            zLog.warn("Logger.cleanup Unable to search app directory for old-style log files to clear")
            return
        }
        list.forEach { url in
            if url.lastPathComponent.starts(with: "TUN_") ||  url.lastPathComponent.starts(with: "APP_") && url.pathExtension == "log" {
                do {
                    zLog.warn("Removing old style log file \(url.path).  Logs are now stored in dedicated logs directory")
                    try fm.removeItem(at: url)
                } catch {
                    zLog.error("Unable to remove \(url.lastPathComponent). Error:\(error.localizedDescription)")
                }
            }
        }
        
        // Set lastRotateTime
        if let currLog = currLog {
            let prev = currLog.appendingPathExtension("1")
            if let attrs = try? fm.attributesOfItem(atPath: prev.path) as NSDictionary {
                if let modDate = attrs.fileModificationDate() {
                    lastRotateTime = modDate
                }
            }
        }
    }
    
    // note that if this method errors we just continue,a s zLog sill log to stderr, which is picked up by the OS logging system
    func rotateLogs(_ force:Bool=false) {
        guard let currLog = currLog else {
            zLog.error("Invalid log URL")
            return
        }
        
        let fm = FileManager.default
                
        // create empty logfile if not present (do here rather than e.g., in init() to handle case of log directory
        // being deleted while running)
        if !fm.isWritableFile(atPath: currLog.path) {
            do {
                try "".write(toFile: currLog.path, atomically: true, encoding: .utf8)
            } catch {
                zLog.error("Unable to create log file \(currLog.path)")
                return
            }
        }
        
        // set redirects to go to to current log file
        // do this here (rather than e.g., in init()) to handle the case where somebody deletes the log
        // file. This allows logging to restart the next time this method is called)
        guard let lfh = FileHandle(forUpdatingAtPath: currLog.path) else {
            zLog.error("Unable to get file handle for updating \(currLog.path)")
            return
        }
        
        lfh.seekToEndOfFile()
        let stdErrDes = dup2(lfh.fileDescriptor, FileHandle.standardError.fileDescriptor)
        let stdOutDes = dup2(lfh.fileDescriptor, FileHandle.standardOutput.fileDescriptor)
        
        if (stdErrDes != FileHandle.standardError.fileDescriptor) || (stdOutDes != FileHandle.standardOutput.fileDescriptor) {
            zLog.error("Unable to capture stdout and stderr to file \(currLog.path)")
        }
        setbuf(__stdoutp, nil) // set stdout to flush
        
        // rotate logs (potentially))
        if let attrs = try? fm.attributesOfItem(atPath: currLog.path) as NSDictionary {
            let sz = attrs.fileSize()
            
            var dailyRotateNeeded = false
            if rotateDaily, let lrt = lastRotateTime {
                if !Calendar.current.isDate(lrt, inSameDayAs:Date()) {
                    dailyRotateNeeded = true
                }
            }
            
            if force || dailyRotateNeeded || (sz >= Logger.FILE_SIZE_THRESHOLD) {
                for i in (1...(Logger.MAX_NUM_LOGS-2)).reversed() {
                    let from = currLog.appendingPathExtension("\(i)")
                    let to = currLog.appendingPathExtension("\(i+1)")
                    
                    do {
                        try? fm.removeItem(at: to)
                        try fm.moveItem(at: from, to: to)
                    } catch {
                        zLog.error("Error rotating \(from.path) to \(to.path): \(error.localizedDescription)")
                    }
                }
                
                // roll out the current log
                let to = currLog.appendingPathExtension("1")
                do {
                    try? fm.removeItem(at: to)
                    
                    // copy instead of mv since we want to manipulate file handle to move to start of the file
                    // to preserve any running `tail -f` on current log
                    try fm.copyItem(at: currLog, to: to)
                    try lfh.truncate(atOffset: 0)
                    try lfh.seek(toOffset: 0)
                    
                    // Start each log by logging app version
                    zLog.info(Version.verboseStr)
                } catch {
                    zLog.error("Error rotating \(currLog.path) to \(to.path): \(error.localizedDescription)")
                }
                
                // update lastRotateTime
                lastRotateTime = Date()
            }
        }
    }
    
    static func initShared(_ tag:String) {
        Logger.shared = Logger(tag)
        Logger.shared?.initLogDir()
        
        zLog.info("Setting log level to \(ZitiLog.LogLevel.INFO)")
        ZitiLog.setLogLevel(.INFO)
        
        // Process once at startup to make sure we have log dir, roll logs from previos runs if necessary
        Logger.shared?.rotateLogs(false)
        
        // fire timer periodically for clean-up and rolling
        DispatchQueue.main.async {
            Logger.shared?.timer = Timer.scheduledTimer(withTimeInterval: Logger.PROCESS_LOGS_INTERVAL, repeats: true) { _ in
                Logger.shared?.rotateLogs(false)
            }
        }
    }
}

extension Bundle {
    var displayName: String? {
            return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}
