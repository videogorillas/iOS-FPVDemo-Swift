//
// Created by Alex Zhukov on 8/22/17.
// Copyright (c) 2017 Alex Zhukov. All rights reserved.
//

import Foundation
import RxSwift
import VideoToolbox
import AVFoundation
import Logboard

class AVFrame {
    var timing: CMSampleTimingInfo;
    let frame: [UInt8];

    init(timing: CMSampleTimingInfo, frame: [UInt8]) {
        self.timing = timing;
        self.frame = frame;

    }
}

struct DecodedFrame: CustomStringConvertible {
    let presentationTimeStamp: CMTime;
    let duration: CMTime;
    let imageBuffer: CVBuffer;

    public var description: String {
        return "\(presentationTimeStamp.value)/\(duration.value)"
    }
}

func populatePts(frames: Observable<[UInt8]>) -> Observable<AVFrame> {
    var startPts: Int64 = 0;
    var prevPts: Int64 = 0;

    let avframes = frames.map { f -> AVFrame in
        let now = currentTimeUsec()
        if prevPts == 0 {
            prevPts = now
            startPts = now
        }
        let d = now - prevPts
        let pts = prevPts - startPts
        let timing: CMSampleTimingInfo = CMSampleTimingInfo(
                duration: CMTimeMake(d / 1000, 1000),
                presentationTimeStamp: CMTimeMake(pts / 1000, 1000),
                decodeTimeStamp: kCMTimeInvalid
        )
        prevPts = now
        return AVFrame(timing: timing, frame: f)
    }
    return avframes
}

func fromHex(hex: String) -> [UInt8] {
    let hexa = Array(hex.characters)
    return stride(from: 0, to: hex.characters.count, by: 2).flatMap {
        UInt8(String(hexa[$0..<$0.advanced(by: 2)]), radix: 16)
    }
}

func toHex(array: [UInt8]) -> String {
    return array.map {
        String(format: "%02hhx", $0)
    }.joined()
}


func myError(err: OSStatus) -> NSError {
    return NSError(domain: NSOSStatusErrorDomain, code: Int(err))
}

fileprivate let log = Logboard.with("ololosha")

func currentTimeUsec() -> Int64 {
    var t:timeval = timeval();

    guard 0 == gettimeofday(&t, nil) else {
        log.error("error gettimeofday")
        return 0
    }
    return Int64(t.tv_sec) * 1000000 + Int64(t.tv_usec)
}

