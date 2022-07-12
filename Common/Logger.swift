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
    
    // Allow these to be set before initializing the shared logger
    static var ROTATE_DAILY = true
    static var FILE_SIZE_THRESHOLD = 5_000_000 // "minsize" bytes
    static var MAX_NUM_LOGS = 3
    
    static let PROCESS_LOGS_INTERVAL = TimeInterval(60*15) // secs
    
    private let tag:String
    private var timer:Timer? = nil
    private var lastRotateTime:Date?
    let zitiLog:ZitiLog
    
    var calendar = Calendar(identifier: .gregorian)
    
    private init(_ tag:String) {
        self.tag = tag
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
            setupCurrLog(currLog)
            if let attrs = try? fm.attributesOfItem(atPath: currLog.path) as NSDictionary {
                if let createDate = attrs.fileCreationDate() {
                    zLog.info("Setting lastRotateTime to log creation date: \(createDate)")
                    lastRotateTime = createDate
                }
            }
        }
        
        if lastRotateTime == nil {
            lastRotateTime = Date()
        }
        zLog.info("lastRotateTime: \(lastRotateTime as Any)")
    }
    
    private func setupCurrLog(_ currLog:URL) {
        let fm = FileManager.default
                
        // create empty log file if not present
        if !fm.isWritableFile(atPath: currLog.path) {
            do {
                try "".write(toFile: currLog.path, atomically: true, encoding: .utf8)
            } catch {
                zLog.error("Unable to create log file \(currLog.path)")
                return
            }
        }
        
        // redirect stdout and stderr to the file
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
    }
    
    // note that if this method errors we just continue. zLog sill logs to stderr, which is picked up by the OS logging system
    func rotateLogs(_ force:Bool=false) {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.APP_GROUP_ID)  else {
            zLog.error("Invalid app group URL")
            return
        }
        guard let currLog = currLog else {
            zLog.error("Invalid log URL")
            return
        }
        
        // always make sure we have a currLog to write
        setupCurrLog(currLog)
        
        // rotate logs (potentially))
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: currLog.path) as NSDictionary {
            let sz = attrs.fileSize()
            
            var dailyRotateNeeded = false
            if Logger.ROTATE_DAILY, let lrt = lastRotateTime {
                if !Calendar.current.isDate(lrt, inSameDayAs:Date()) {
                    dailyRotateNeeded = true
                }
            }
            
            if force || dailyRotateNeeded || (sz >= Logger.FILE_SIZE_THRESHOLD) {
                if Logger.MAX_NUM_LOGS > 2 {
                    for i in (1...(Logger.MAX_NUM_LOGS-2)).reversed() {
                        let from = currLog.appendingPathExtension("\(i)")
                        let to = currLog.appendingPathExtension("\(i+1)")
                        
                        do {
                            try? fm.removeItem(at: to)
                            if fm.fileExists(atPath: from.path) {
                                zLog.info("Rotating log: \(from.path) to \(to.path)")
                                try fm.moveItem(at: from, to: to)
                            }
                        } catch {
                            zLog.error("Error rotating \(from.path) to \(to.path): \(error.localizedDescription)")
                        }
                    }
                }
                
                // roll out the current log
                if Logger.MAX_NUM_LOGS > 1 {
                    let to = currLog.appendingPathExtension("1")
                    do {
                        zLog.info("Rotating logs: \(currLog.path) to \(to.path)")
                        try? fm.removeItem(at: to)
                        try fm.moveItem(at: currLog, to: to)
                        setupCurrLog(currLog)
                        
                        // Start each log by logging app version
                        zLog.info(Version.verboseStr)
                    } catch {
                        zLog.error("Error rotating \(currLog.path) to \(to.path): \(error.localizedDescription)")
                    }
                }
                
                // update lastRotateTime
                lastRotateTime = Date()
            }
        }
        
        // remove any logs > MAX_NUM_LOGS
        let logDir = appGroupURL.appendingPathComponent("logs", isDirectory:true)
        guard let list = try? fm.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil, options: []) else {
            zLog.warn("Unable to search log dir for log files to clear")
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
    }
    
    static func updateRotateSettings(_ daily:Bool, _ count:Int, _ sizeMB:Int) {
        DispatchQueue.main.async {
            zLog.info("Updating log rotate config to daily:\(daily), count:\(count), sizeMB:\(sizeMB)")
            
            Logger.ROTATE_DAILY = daily
            Logger.MAX_NUM_LOGS = count + 1
            Logger.FILE_SIZE_THRESHOLD = sizeMB * 1024 * 1024
            
            Logger.shared?.timer?.invalidate()
            Logger.shared?.rotateLogs(false)
            Logger.shared?.timer = Timer.scheduledTimer(withTimeInterval: Logger.PROCESS_LOGS_INTERVAL, repeats: true) { _ in
                Logger.shared?.rotateLogs(false)
            }
        }
    }
    
    static func initShared(_ tag:String) {
        Logger.shared = Logger(tag)
        Logger.shared?.initLogDir()
        
        zLog.info("Setting log level to \(ZitiLog.LogLevel.INFO)")
        ZitiLog.setLogLevel(.INFO)
        
        if let tz = TimeZone(identifier: "UTC") {
            Logger.shared?.calendar.timeZone = tz
        } else {
            zLog.warn("Unable to set timezone to UTC")
        }
    }
}

extension Bundle {
    var displayName: String? {
            return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}
