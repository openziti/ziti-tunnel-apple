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

class Logger {
    static var shared:Logger?
    static let TUN_TAG = "TUN"
    static let APP_TAG = "APP"
    
    private let tag:String
    private var timer:Timer? = nil
    
    private init(_ tag:String) {
        self.tag = tag
    }
    
    deinit {
        timer?.invalidate()
    }
    
    var currLog:URL? {
        return currLog(forTag: tag)
    }
    
    func currLog(forTag tag:String) -> URL? {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ZitiIdentityStore.APP_GROUP_ID)  else {
                return nil
        }
        
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        return appGroupURL.appendingPathComponent("\(tag)_\(dateStr).log", isDirectory:false)
    }
    
    // Delete \(tag)*.logs more than 48 hours old
    private func cleanup() {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ZitiIdentityStore.APP_GROUP_ID)  else {
                NSLog("currLogfile: Invalid app group URL")
                return
        }
        
        let fm = FileManager.default
        guard let list = try? fm.contentsOfDirectory(at: appGroupURL, includingPropertiesForKeys: nil, options: []) else {
            NSLog("Logger.cleanup Unable to search log directory to log files to clear")
            return
        }
        
        let now = Date()
        list.forEach { url in
            if url.lastPathComponent.starts(with: tag) && url.pathExtension == "log" {
                if let attrs = try? fm.attributesOfItem(atPath: url.path), let iat = attrs[.creationDate] as? Date {
                    let daysOld = ((now.timeIntervalSince(iat) / 60) / 60) / 24
                    if daysOld > 2.0 {
                        NSLog("Removing \(url.lastPathComponent) (is over \(Int(daysOld)) days old)")
                        do { try fm.removeItem(at: url) }
                        catch { NSLog("Unable to remove \(url.lastPathComponent). Error:\(error.localizedDescription)") }
                    }
                } else {
                    NSLog("Logger.cleanup Unable to get file attributes pf \(url.lastPathComponent)")
                }
            }
        }
    }
    
    private func updateLogger() -> Bool {
        guard let url = currLog else {
            NSLog("updateLogger: Invalid log URL")
            return false
        }
        
        // cleanup all log files...
        defer {
            cleanup()
        }
        
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
            NSLog("Unable to created shared Logger")
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
