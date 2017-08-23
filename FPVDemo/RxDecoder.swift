//
// Created by Alex Zhukov on 8/21/17.
// Copyright (c) 2017 Alex Zhukov. All rights reserved.
//

import Foundation
import RxSwift
import VideoToolbox
import AVFoundation

class RxDecoder {
    var obs: AnyObserver<DecodedFrame>?;
    var completed: Bool = false;
    var pending: Int32 = 0;
    var _formatDescription: CMFormatDescription? = nil;
    var _session: VTDecompressionSession? = nil;
    let parameterSetPointers: [UnsafePointer<UInt8>];
    let ppsBuf:[UInt8]
    let spsBuf:[UInt8]

    init(ppsHex: String, spsHex: String) {
        self.ppsBuf = fromHex(hex: ppsHex)
        self.spsBuf = fromHex(hex: spsHex)

        let a: UnsafePointer<UInt8> = UnsafePointer(ppsBuf);
        let b: UnsafePointer<UInt8> = UnsafePointer(spsBuf);
        self.parameterSetPointers = [a, b]
    }

    func decodeFrames(frames: Observable<AVFrame>) -> Observable<DecodedFrame> {
        return Observable.create { observer in
            self.obs = observer;
            let parameterSetSizes: [Int] = [self.ppsBuf.count, self.spsBuf.count]

            let attributes: [NSString: AnyObject] = [
                kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_32BGRA),
                kCVPixelBufferIOSurfacePropertiesKey: [:] as AnyObject,
                kCVPixelBufferOpenGLCompatibilityKey: NSNumber(booleanLiteral: true),
            ]

            var record = VTDecompressionOutputCallbackRecord()
            record.decompressionOutputCallback = { (
                    decompressionOutputRefCon: UnsafeMutableRawPointer?,
                    sourceFrameRefCon: UnsafeMutableRawPointer?,
                    status: OSStatus,
                    infoFlags: VTDecodeInfoFlags,
                    imageBuffer: CVBuffer?,
                    presentationTimeStamp: CMTime,
                    duration: CMTime) in

                if decompressionOutputRefCon == nil {
                    print("done")
                    return
                }


                let _state = Unmanaged<RxDecoder>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()

                if status == noErr {
                    print("decoded \(presentationTimeStamp.value)")
                    let decoded = DecodedFrame(presentationTimeStamp: presentationTimeStamp, duration: duration, imageBuffer: imageBuffer!)
                    _state.obs!.on(.next(decoded));
                    if _state.pending == 0 && _state.completed {
                        _state.obs!.on(.completed)
                    }
                } else {
                    let _err = myError(err: status)
                    print("decode error f:\(presentationTimeStamp.value) e: \(_err)")
                    _state.obs!.on(.error(_err))
                }
                let _pending = OSAtomicDecrement32(&_state.pending)
                if _pending > 0 {
                    print("pending: \(_pending)")
                }
            };
            record.decompressionOutputRefCon = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)

            let err = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, self.parameterSetPointers, parameterSetSizes, 4, &self._formatDescription);
            if err != noErr {
                observer.on(.error(myError(err: err)))
            }

            let createErr = VTDecompressionSessionCreate(
                    kCFAllocatorDefault,
                    self._formatDescription!,
                    nil,
                    attributes as CFDictionary?,
                    &record,
                    &self._session)
            if createErr != noErr {
                observer.on(.error(myError(err: createErr)))
                return Disposables.create()
            }

            return frames.subscribe { e in
                switch e {
                case .next(let frame):
                    OSAtomicIncrement32(&self.pending)
                    let _expectedCount = frame.frame.count
                    frame.frame.withUnsafeBufferPointer { bytes in
                        var blockBuffer: CMBlockBuffer?
                        let sz = _expectedCount
                        let blockErr = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, UnsafeMutableRawPointer(mutating: bytes.baseAddress), sz, kCFAllocatorNull, nil, 0, sz, 0, &blockBuffer)
                        guard blockErr == noErr else {
                            observer.on(.error(myError(err: blockErr)))
                            return
                        }
                        var sampleBuffer: CMSampleBuffer?
                        var sampleSizes: [Int] = [sz]
                        let sbufErr = CMSampleBufferCreate(
                                kCFAllocatorDefault, blockBuffer!, true, nil, nil, self._formatDescription, 1, 1, &frame.timing, 1, &sampleSizes, &sampleBuffer)
                        guard sbufErr == noErr else {
                            observer.on(.error(myError(err: sbufErr)))
                            return
                        }

                        var flagsOut = VTDecodeInfoFlags()
                        let decodeFlags: VTDecodeFrameFlags = VTDecodeFrameFlags(rawValue:
                        VTDecodeFrameFlags._EnableAsynchronousDecompression.rawValue | VTDecodeFrameFlags._EnableTemporalProcessing.rawValue
                        )
                        let decodeErr = VTDecompressionSessionDecodeFrame(self._session!, sampleBuffer!, decodeFlags, nil, &flagsOut)
                        if decodeErr != noErr {
                            observer.on(.error(myError(err: decodeErr)))
                        }
                        return
                    }

                case .error(let error):
                    print("error")
                    observer.on(.error(error))
                case .completed:
                    print("completed")
                    self.completed = true;
                    if self.pending == 0 {
                        observer.on(.completed)
                    } else {
                        print("pending frames \(self.pending)")
                    }
                }
            }
        }
    }
}