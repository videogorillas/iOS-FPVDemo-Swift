//
// Created by Alex Zhukov on 8/21/17.
// Copyright (c) 2017 Alex Zhukov. All rights reserved.
//

import Foundation
import RxSwift
import VideoToolbox
import AVFoundation

class RxEncoder {
    var session: VTCompressionSession?;
    var obs: AnyObserver<CMSampleBuffer>?;

    private func setup(observer: AnyObserver<CMSampleBuffer>) {
        self.obs = observer;

#if os(iOS)
        let defaultAttributes: [NSString: AnyObject] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as AnyObject,
            kCVPixelBufferOpenGLESCompatibilityKey: kCFBooleanTrue,
        ]
#else
        let defaultAttributes: [NSString: AnyObject] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as AnyObject,
            kCVPixelBufferOpenGLCompatibilityKey: kCFBooleanTrue,
        ]
#endif

        let width: Int32 = 854
        let height: Int32 = 480

        var attributes: [NSString: AnyObject] = defaultAttributes
        attributes[kCVPixelBufferWidthKey] = NSNumber(value: width)
        attributes[kCVPixelBufferHeightKey] = NSNumber(value: height)
        let isBaseline = true;
        let bitrate = 512 * 1024
        let maxKeyFrameIntervalDuration = 2.0;
        let profileLevel = kVTProfileLevel_H264_Baseline_3_1
        let expectedFPS = 30

        let scalingMode = "Trim"

        var properties: [NSString: NSObject] = [
            kVTCompressionPropertyKey_RealTime: kCFBooleanTrue,
            kVTCompressionPropertyKey_ProfileLevel: profileLevel as NSObject,
            kVTCompressionPropertyKey_AverageBitRate: Int(bitrate) as NSObject,
            kVTCompressionPropertyKey_ExpectedFrameRate: NSNumber(value: expectedFPS),
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: NSNumber(value: maxKeyFrameIntervalDuration),
            kVTCompressionPropertyKey_AllowFrameReordering: !isBaseline as NSObject,
            kVTCompressionPropertyKey_PixelTransferProperties: [
                "ScalingMode": scalingMode
            ] as NSObject
        ]
        let enabledHardwareEncoder = true

#if os(OSX)
        if (enabledHardwareEncoder) {
            properties[kVTVideoEncoderSpecification_EncoderID] = "com.apple.videotoolbox.videoencoder.h264.gva" as NSObject
            properties["EnableHardwareAcceleratedVideoEncoder"] = kCFBooleanTrue
            properties["RequireHardwareAcceleratedVideoEncoder"] = kCFBooleanTrue
        }
#endif

//    if (dataRateLimits != H264Encoder.defaultDataRateLimits) {
//        properties[kVTCompressionPropertyKey_DataRateLimits] = dataRateLimits as NSObject
//    }
//    if (!isBaseline) {
//        properties[kVTCompressionPropertyKey_H264EntropyMode] = kVTH264EntropyMode_CABAC
//    }

        let callback: VTCompressionOutputCallback = { (
                outputCallbackRefCon: UnsafeMutableRawPointer?,
                sourceFrameRefCon: UnsafeMutableRawPointer?,
                status: OSStatus,
                infoFlags: VTEncodeInfoFlags,
                sampleBuffer: CMSampleBuffer?) in
            let _state = Unmanaged<RxEncoder>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()

            guard let sampleBuffer: CMSampleBuffer = sampleBuffer, status == noErr else {
                print("error encode \(status)")
                _state.obs!.on(.error(myError(err: status)))
                return
            }
            _state.obs!.on(.next(sampleBuffer))
        }

        var _session: VTCompressionSession? = nil
        let err = VTCompressionSessionCreate(kCFAllocatorDefault, width, height, kCMVideoCodecType_H264, nil, attributes as CFDictionary?, nil, callback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self), &_session)

        if err != noErr {
            print("VTCompressionSessionCreate error \(err)")
            observer.on(.error(myError(err: err)))
            return
        }
        let status = VTSessionSetProperties(_session!, properties as CFDictionary)
        if status != noErr {
            print("VTSessionSetProperties error \(err)")
            observer.on(.error(myError(err: status)))
            return
        }
        self.session = _session

    }

    func encodeH264(uncompressed: Observable<DecodedFrame>) -> Observable<CMSampleBuffer> {
        return Observable.create { observer in
            self.setup(observer: observer);
            return uncompressed.subscribe { e in
                switch e {
                case .next(var decoded):
                    var flags: VTEncodeInfoFlags = VTEncodeInfoFlags()
                    let imageBuffer: CVImageBuffer = decoded.imageBuffer
                    VTCompressionSessionEncodeFrame(
                            self.session!,
                            imageBuffer,
                            decoded.presentationTimeStamp,
                            decoded.duration,
                            nil,
                            nil,
                            &flags
                    )
                case .error(let error):
                    print("error")
                    observer.on(.error(error))
                case .completed:
                    print("completed")
                }
            }
        }

    }
}