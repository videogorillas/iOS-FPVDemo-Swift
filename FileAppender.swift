//
// Created by lenka on 8/23/17.
// Copyright (c) 2017 DJI. All rights reserved.
//

import Foundation
import Logboard

class FileAppender: LogboardAppender {
    var out:OutputStream?

    init() {
        let file = "ololosha.log" //this is the file. we will write to and read from it

        let fileURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent(file)

        if let outputStream = OutputStream(url: fileURL, append: true) {
            outputStream.open()
            self.out = outputStream
        } else {
            print("Unable to open file")
        }
    }

    public func append(_ logboard:Logboard, level: Logboard.Level, message:String, file:StaticString, function:StaticString, line:Int) {
        let str = "[\(level)] [\(logboard.identifier)] [\(line)] \(function) > \(message)"
        print(str)
        self.out?.write(str+"\n")
    }
    public func append(_ logboard:Logboard, level: Logboard.Level, format:String, arguments:CVarArg, file:StaticString, function:StaticString, line:Int) {
        let str = "[\(level)] [\(logboard.identifier)] [\(line)] \(function) > \(String(format: format, arguments))"
        print(str)
        self.out?.write(str+"\n")
    }

}
