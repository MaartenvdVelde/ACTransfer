//
//  BatchRun.swift
//  PRIMs
//
//  Created by Niels Taatgen on 5/22/15.
//  Copyright (c) 2015 Niels Taatgen. All rights reserved.
//

import Foundation


class BatchRun {
    let batchScript: String
    let outputFileName: URL
    let outputTrace: Bool
    var model: Model
    unowned let mainModel: Model
    unowned let controller: MainViewController
    let directory: URL
    var progress: Double = 0.0
    var traceFileName: URL
    var fullTraceFileName: URL
    var fullTraceOutput: String = ""
    
    init(script: String, mainModel: Model, outputFile: URL, outputTrace: Bool, controller: MainViewController, directory: URL) {
        self.batchScript = script
        self.outputFileName = outputFile
        self.traceFileName = outputFile.deletingPathExtension().appendingPathExtension("tracedat")
        self.fullTraceFileName = outputFile.deletingPathExtension().appendingPathExtension("fulltrace")
        self.outputTrace = outputTrace
        if outputTrace {
            self.model = Model(batchModeFullTrace: true)
        } else {
            self.model = Model(batchMode: true)
        }
        self.controller = controller
        self.directory = directory
        self.mainModel = mainModel
    }
    

    
    func runScript() {
        mainModel.clearTrace()
        DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated).async { () -> Void in

        var scanner = Scanner(string: self.batchScript)
        let whiteSpaceAndNL = CharacterSet.whitespacesAndNewlines
        _ = scanner.scanUpToCharactersFromSet(whiteSpaceAndNL)
        let numberOfRepeats = scanner.scanInt()
        if numberOfRepeats == nil {
            self.mainModel.addToTraceField("Illegal number of repeats")
            return
        }
        var newfile = true
        
        self.addToFullTrace("Running PRIMs in batch mode (\(numberOfRepeats!) runs).")
        
        for i in 0..<numberOfRepeats! {
            self.mainModel.addToTraceField("Run #\(i + 1)")
            
            self.addToFullTrace("Run #\(i + 1)")
            
            DispatchQueue.main.async {
                self.controller.updateAllViews()
            }
            scanner = Scanner(string: self.batchScript)
            
            while let command = scanner.scanUpToCharactersFromSet(whiteSpaceAndNL as CharacterSet) {
                var stopByTime = false
                switch command {
                case "run-time":
                    stopByTime = true
                    fallthrough
                case "run":
                    let taskname = scanner.scanUpToCharactersFromSet(whiteSpaceAndNL as CharacterSet)
                    if taskname == nil {
                        self.mainModel.addToTraceField("Illegal task name in run")
                        return
                    }
                    let taskLabel = scanner.scanUpToCharactersFromSet(whiteSpaceAndNL as CharacterSet)
                    if taskLabel == nil {
                        self.mainModel.addToTraceField("Illegal task label in run")
                        return
                    }
                    let endCriterium = scanner.scanDouble()
                    if endCriterium == nil {
                        self.mainModel.addToTraceField("Illegal number of trials or end time in run")
                        return
                    }
                    
                    while !scanner.isAtEnd && (scanner.string as NSString).character(at: scanner.scanLocation) != 10 && (scanner.string as NSString).character(at: scanner.scanLocation) != 13 {
                        let batchParam = scanner.scanUpToCharactersFromSet(whiteSpaceAndNL as CharacterSet)
                        self.model.batchParameters.append(batchParam!)
                        self.mainModel.addToTraceField("Parameter: \(batchParam!)")
                    }
                
                    if stopByTime {
                        self.mainModel.addToTraceField("Running task \(taskname!) with label \(taskLabel!) for \(endCriterium!) seconds")
                        self.addToFullTrace("Running task \(taskname!) with label \(taskLabel!) for \(endCriterium!) seconds")
                    } else {
                        self.mainModel.addToTraceField("Running task \(taskname!) with label \(taskLabel!) for \(endCriterium!) trials")
                        self.addToFullTrace("Running task \(taskname!) with label \(taskLabel!) for \(endCriterium!) trials")
                    }
                    DispatchQueue.main.async {
                        self.controller.updateAllViews()
                    }
                    var tasknumber = self.model.findTask(taskname!)
                    if tasknumber == nil {
                        let taskPath = self.directory.appendingPathComponent(taskname! + ".prims")
                        print("Trying to load \(taskPath)")
                        if !self.model.loadModelWithString(taskPath) {
                            self.mainModel.addToTraceField("Task \(taskname!) is not loaded nor can it be found")
                            return
                        }
                        tasknumber = self.model.findTask(taskname!)
                    }
                    if tasknumber == nil {
                        self.mainModel.addToTraceField("Task \(taskname!) cannot be found")
                        return
                    }
                    self.model.loadOrReloadTask(tasknumber!)
                    var j = 0
                    let startTime = self.model.time
                    while (!stopByTime && j < Int(endCriterium!)) || (stopByTime && (self.model.time - startTime) < endCriterium!) {
                        j += 1
                        
                        self.mainModel.addToTraceField("Trial \(j)")
                        DispatchQueue.main.async {
                            self.controller.updateAllViews()
                        }
                        
                        self.model.run()
                        var output: String = ""
                        for line in self.model.outputData {
                            output.append("\(i) \(taskname!) \(taskLabel!) \(j) \(line.time) \(line.eventType) \(line.eventParameter1) \(line.eventParameter2) \(line.eventParameter3) ")
                            for item in line.inputParameters {
                                output.append("\(item) ")
                            }
                            output.append("\n")
                        }
                        // Print trace to file
                        var traceOutput = ""
                        if self.model.batchTrace {
                            for (time, type, event) in self.model.batchTraceData {
                                traceOutput.append("\(i) \(taskname!) \(taskLabel!) \(j) \(time) \(type) \(event) \n")
                            }
                            self.model.batchTraceData = []
                        }
                        
                        if self.model.batchModeFullTrace {
                            self.addToFullTrace(self.model.getTrace(4))
                        }
                        
                        if !newfile {
                            // Output File
                            if FileManager.default.fileExists(atPath: self.outputFileName.path) {
                                var err:NSError?
                                do {
                                    let fileHandle = try FileHandle(forWritingTo: self.outputFileName)
                                    fileHandle.seekToEndOfFile()
                                    let data = output.data(using: String.Encoding.utf8, allowLossyConversion: false)
                                    fileHandle.write(data!)
                                    fileHandle.closeFile()
                                } catch let error as NSError {
                                    err = error
                                    self.mainModel.addToTraceField("Can't open fileHandle \(err)")
                                }
                            }
                            // Trace File
                            if FileManager.default.fileExists(atPath: self.traceFileName.path) && (self.model.batchTrace) {
                                var err:NSError?
                                do {
                                    let fileHandle = try FileHandle(forWritingTo: self.traceFileName)
                                    fileHandle.seekToEndOfFile()
                                    let data = traceOutput.data(using: String.Encoding.utf8, allowLossyConversion: false)
                                    fileHandle.write(data!)
                                    fileHandle.closeFile()
                                } catch let error as NSError {
                                    err = error
                                    self.mainModel.addToTraceField("Can't open trace fileHandle \(err)")
                                }
                            }
                        } else {
                            newfile = false
                            var err:NSError?
                            // Output file
                            do {
                                try output.write(to: self.outputFileName, atomically: false, encoding: String.Encoding.utf8)
                            } catch let error as NSError {
                                err = error
                                self.mainModel.addToTraceField("Can't write datafile \(err)")
                            }
                            // Trace file
                            do {
                                try traceOutput.write(to: self.traceFileName, atomically: false, encoding: String.Encoding.utf8)
                            } catch let error as NSError {
                                err = error
                                self.mainModel.addToTraceField("Can't write tracefile \(err)")
                            }
                        }
                    }
                case "reset":
                    self.mainModel.addToTraceField("Resetting models")
                    self.addToFullTrace("Resetting models")
                    DispatchQueue.main.async {
                        self.controller.updateAllViews()
                    }
                    print("*** About to reset model ***")
                    self.model.dm = nil
                    self.model.procedural = nil
                    self.model.action = nil
                    self.model.operators = nil
                    self.model.action = nil
                    self.model.imaginal = nil
                    self.model.batchParameters = []
                    if self.outputTrace {
                        self.model = Model(batchModeFullTrace: true)
                    } else {
                        self.model = Model(batchMode: true)
                    }
                case "repeat":
                    _ = scanner.scanInt()
                case "done": break
//                    print("*** Model has finished running ****")
                case "load-image":
                    let filename = scanner.scanUpToCharactersFromSet(whiteSpaceAndNL as CharacterSet)
                    if filename == nil {
                        self.mainModel.addToTraceField("Illegal task name in run")
                        return
                    }
                    let taskPath = self.directory.appendingPathComponent(filename! + ".brain").path
                    self.mainModel.addToTraceField("Loading image file \(taskPath)")
                    guard let m = (NSKeyedUnarchiver.unarchiveObject(withFile: taskPath) as? Model) else { return }
                    self.model = m
                    self.model.dm.reintegrateChunks()
//                    self.model.batchMode = true
                    if self.outputTrace {
                        self.model.batchModeFullTrace = true
                    } else {
                        self.model.batchMode = true
                    }
                case "save-image":
                    let filename = scanner.scanUpToCharactersFromSet(whiteSpaceAndNL as CharacterSet)
                    if filename == nil {
                        self.mainModel.addToTraceField("Illegal task name in run")
                        return
                    }
                    let taskPath = self.directory.appendingPathComponent(filename! + ".brain").path
                    self.mainModel.addToTraceField("Saving image to file \(taskPath)")
                    NSKeyedArchiver.archiveRootObject(self.model, toFile: taskPath)
                default: break
                    
                }
            }
            self.mainModel.addToTraceField("Done")
            self.addToFullTrace("Done")
            DispatchQueue.main.async {
                self.controller.updateAllViews()
            }
            self.progress = 100 * (Double(i) + 1) / Double(numberOfRepeats!)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name(rawValue: "progress"),object: nil)
            }
            }
            
            if self.outputTrace {
                self.writeFullTraceToFile()
            }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name(rawValue: "progress"),object: nil)
            }
        }

        
    }
    
    func addToFullTrace(_ s: String) {
        self.fullTraceOutput.append("\(s)\n")
    }
    
    func writeFullTraceToFile() {
        if FileManager.default.fileExists(atPath: self.fullTraceFileName.path) {
            do {
                try FileManager.default.removeItem(atPath: self.fullTraceFileName.path)
            } catch let error as NSError {
                print("Can't overwrite existing full tracefile \(error)")
            }
        }
        
        do {
            try fullTraceOutput.write(to: self.fullTraceFileName, atomically: false, encoding: String.Encoding.utf8)
        } catch let error as NSError {
            print("Can't write full tracefile \(error)")
        }
    }
    
    
}
