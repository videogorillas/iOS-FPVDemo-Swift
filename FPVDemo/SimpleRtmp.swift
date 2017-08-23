//
// Created by Alex Zhukov on 8/23/17.
// Copyright (c) 2017 DJI. All rights reserved.
//

import Foundation
import RxSwift
import VideoToolbox
import AVFoundation
import HaishinKit

class SimpleRtmp {
    var rtmpConnection: RTMPConnection = RTMPConnection()
    let rtmpStream: RTMPStream;
    let scheduler = SerialDispatchQueueScheduler.init(qos: .default)
    var formatSet = false
    var sub: Disposable?;
    var avframes:Observable<AVFrame>?;
    var streamName:String?;

    init() {
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
            rtmpStream.publish(self.streamName)
        case RTMPStream.Code.publishStart.rawValue:
            let decoder = RxDecoder(ppsHex: RxDji.inspirePpsHex, spsHex: RxDji.inspireSpsHex)
            let encoder = RxEncoder()

            let decoded = decoder.decodeFrames(frames: avframes!)
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

    func publish(rtmpUri:String, streamName:String, avframes:Observable<AVFrame>) {
        self.avframes = avframes
        self.streamName = streamName
        rtmpConnection.addEventListener(HaishinKit.HEvent.RTMP_STATUS, selector: #selector(SimpleRtmp.rtmpStatusHandler(_:)), observer: self)
        rtmpConnection.connect(rtmpUri, arguments: nil)
    }

    func stop() {
        rtmpConnection.addEventListener(HaishinKit.HEvent.RTMP_STATUS, selector: #selector(SimpleRtmp.rtmpStatusHandler(_:)), observer: self)
        rtmpConnection.close()
        sub?.dispose()
    }
}
