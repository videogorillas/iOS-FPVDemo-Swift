//
// Created by Alex Zhukov on 8/22/17.
// Copyright (c) 2017 Alex Zhukov. All rights reserved.
//

import Foundation
import RxSwift
import VideoToolbox
import AVFoundation
import HaishinKit
import Logboard

func readFile(path: String) throws -> [UInt8] {
    return try [UInt8](Data(contentsOf: URL(fileURLWithPath: path)))
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

func myError(err: OSStatus) -> NSError {
    return NSError(domain: NSOSStatusErrorDomain, code: Int(err))
}

func setupEncoder() throws {
    let avframes: Observable<AVFrame> = Observable.empty() //try RxDji.framesFrom(dir: inspireDir)
    let scheduler = SerialDispatchQueueScheduler.init(qos: .default)
    let delayedFrames = avframes.concatMap { frame -> Observable<AVFrame> in
        return Observable.just(frame).delay(0.033333, scheduler: scheduler)
    }

    let decoder = RxDecoder(ppsHex: RxDji.inspirePpsHex, spsHex: RxDji.inspireSpsHex)
    let encoder = RxEncoder()

    let decoded = decoder.decodeFrames(frames: delayedFrames)
    encoder.encodeH264(uncompressed: decoded).subscribe { event in
        switch event {
        case .next(let encoded):
            let _enc: CMSampleBuffer = encoded
            let format: CMFormatDescription? = CMSampleBufferGetFormatDescription(encoded)
            let pts: CMTime = CMSampleBufferGetPresentationTimeStamp(_enc)
            print("encoded \(pts.value)")
        case .error(let err):
            print(err)
        case .completed:
            print("done")
        }
    }
}

func inspireFrames(videoData:Observable<[UInt8]>) -> Observable<AVFrame> {
    var iframeBuf = fromHex(hex: RxDji.inspireIframe)
    iframeBuf.append(contentsOf: acc_unit_delimiter)
    let rawFrames: Observable<[UInt8]> = Observable.just(iframeBuf).concat(videoData)
    let nals = splitNals(bufSource: rawFrames)
    let annb = annexb2mp4(nals: nals)
    let frameNals = annb.toArrayUntil(predicate: { nal in
        return .ACC_UNIT_DELIM == readNal(nalu: nal[4])
    })

    let frames = frameNals.map { _nals -> [UInt8] in
        var fullFrame: [UInt8] = [];
        for nal in _nals {
            fullFrame.append(contentsOf: nal)
        }
        return fullFrame
    }

    let avframes = populatePts(frames: frames)

    return avframes
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
        let pts = now - startPts
        var timing: CMSampleTimingInfo = CMSampleTimingInfo(
                duration: CMTimeMake(d / 1000, 1000),
                presentationTimeStamp: CMTimeMake(pts / 1000, 1000),
                decodeTimeStamp: kCMTimeInvalid
        )
        prevPts = now
        return AVFrame(timing: timing, frame: f)
    }
    return avframes
}

func currentTimeUsec() -> Int64 {
    var t:timeval = timeval();

    guard 0 == gettimeofday(&t, nil) else {
        print("error gettimeofday")
        return 0
    }
    return Int64(t.tv_sec * 1000000 + t.tv_usec)
}

class Bla {
    let rtmpUri: String = "rtmpt://10.0.1.124:8042/live4"
    let streamName: String = "alex@videogorillas.com/stream_\(arc4random())"

    var rtmpConnection: RTMPConnection = RTMPConnection()
    let rtmpStream: RTMPStream;
    let scheduler = SerialDispatchQueueScheduler.init(qos: .default)
    var formatSet = false
    var sub: Disposable?;
    let avframes:Observable<AVFrame>;

    init(avframes:Observable<AVFrame>) {
        self.avframes = avframes;
        rtmpStream = RTMPStream(connection: rtmpConnection)
    }

    @objc func rtmpStatusHandler(_ notification: Notification) throws {
        print("rtmpStatusHandler \(notification)")

        let e: HaishinKit.HEvent = HaishinKit.HEvent.from(notification)

        guard
                let data: ASObject = e.data as? ASObject,
                let code: String = data["code"] as? String else {
            print("no code in event")
            return
        }
        print("rtmpStatusHandler code \(code)")

        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            rtmpStream.publish(streamName)
        case RTMPStream.Code.publishStart.rawValue:
            let decoder = RxDecoder(ppsHex: RxDji.inspirePpsHex, spsHex: RxDji.inspireSpsHex)
            let encoder = RxEncoder()

            let decoded = decoder.decodeFrames(frames: avframes)
            self.sub = encoder.encodeH264(uncompressed: decoded).observeOn(scheduler).subscribe { event in
                switch event {
                case .next(let encoded):
                    let _enc: CMSampleBuffer = encoded
                    let pts: CMTime = CMSampleBufferGetPresentationTimeStamp(_enc)
                    print("encoded \(pts.value)")

                    if !self.formatSet {
                        self.formatSet = true;
                        let format: CMFormatDescription? = CMSampleBufferGetFormatDescription(encoded)
                        self.rtmpStream.muxer.didSetFormatDescription(video: format)
                    }
                    self.rtmpStream.muxer.sampleOutput(video: _enc)
                case .error(let err):
                    print("error: \(err)")
                    self.stop()
                case .completed:
                    print("completed")
                    self.stop()
                }
            }
        default:
            break
        }
    }

    func connect() {
        rtmpConnection.addEventListener(HaishinKit.HEvent.RTMP_STATUS, selector: #selector(Bla.rtmpStatusHandler(_:)), observer: self)
        rtmpConnection.connect(rtmpUri, arguments: nil)
    }

    func stop() {
        rtmpConnection.addEventListener(HaishinKit.HEvent.RTMP_STATUS, selector: #selector(Bla.rtmpStatusHandler(_:)), observer: self)
        rtmpConnection.close()
        sub?.dispose()
    }
}
