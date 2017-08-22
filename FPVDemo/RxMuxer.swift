//
// Created by Alex Zhukov on 8/21/17.
// Copyright (c) 2017 Alex Zhukov. All rights reserved.
//

import Foundation
import RxSwift

let acc_unit_delimiter: [UInt8] = [00, 00, 00, 01, 0x09, 0x10];

enum NALUnitType: UInt8 {
    case NON_IDR_SLICE = 1 //, "NON_IDR_SLICE", "non IDR slice");
    case SLICE_PART_A = 2 //, "SLICE_PART_A", "slice part a");
    case SLICE_PART_B = 3//= new NALUnitType(3, "SLICE_PART_B", "slice part b");
    case SLICE_PART_C = 4//= new NALUnitType(4, "SLICE_PART_C", "slice part c");
    case IDR_SLICE = 5 //new NALUnitType(5, "IDR_SLICE", "idr slice");
    case SEI = 6 //new NALUnitType(6, "SEI", "sei");
    case SPS = 7//new NALUnitType(7, "SPS", "sequence parameter set");
    case PPS = 8//new NALUnitType(8, "PPS", "picture parameter set");
    case ACC_UNIT_DELIM = 9//new NALUnitType(9, "ACC_UNIT_DELIM", "access unit delimiter");
    case END_OF_SEQ = 10//new NALUnitType(10, "END_OF_SEQ", "end of sequence");
    case END_OF_STREAM = 11//new NALUnitType(11, "END_OF_STREAM", "end of stream");
    case FILLER_DATA = 12//new NALUnitType(12, "FILLER_DATA", "filler data");
    case SEQ_PAR_SET_EXT = 13//new NALUnitType(13, "SEQ_PAR_SET_EXT", "sequence parameter set extension");
    case AUX_SLICE = 19//new NALUnitType(19, "AUX_SLICE", "auxilary slice");
}

func readNal(nalu: UInt8) -> NALUnitType? {
//    let nal_ref_idc = (nalu >> 5) & 0x3;
    let nb = nalu & 0x1f;
    return NALUnitType(rawValue: nb)
}


func annexb2mp4(nals: Observable<[UInt8]>) -> Observable<[UInt8]> {
    return nals.map { nal -> [UInt8] in
        var mp4 = nal;
        let sz = nal.count - 4;
        mp4[0] = UInt8((sz >> 24) & 0xff)
        mp4[1] = UInt8((sz >> 16) & 0xff)
        mp4[2] = UInt8((sz >> 8) & 0xff)
        mp4[3] = UInt8(sz & 0xff)
        return mp4
    }
}

func fourccToString(fourcc: FourCharCode) -> String {
    let n = Int(fourcc)
    var s: String = String(Character(UnicodeScalar((n >> 24) & 255)!))
    s.append(Character(UnicodeScalar((n >> 16) & 255)!))
    s.append(Character(UnicodeScalar((n >> 8) & 255)!))
    s.append(Character(UnicodeScalar(n & 255)!))
    return s.trimmingCharacters(in: CharacterSet.whitespaces)
}


func splitNals(bufSource: Observable<[UInt8]>) -> Observable<[UInt8]> {
    return Observable.create { observer in
        var haystack: UInt32 = 0xffffffff;
        var pending: [UInt8] = [];
        let subscription = bufSource.subscribe { e in
            switch e {
            case .next(let src):
                for i in 0..<src.count {
                    let b = src[i];
                    haystack <<= 8;
                    haystack |= UInt32(b);
                    pending.append(b)
                    if (haystack == 1) {
                        haystack = 0xfffffff
                        if pending.count > 4 {
                            pending.removeLast(4)
                            observer.on(.next(pending))
                            pending = [0, 0, 0, 1];
                        }
                    }
                }
            case .error(let error):
                observer.on(.error(error))
            case .completed:
                if pending.count > 0 {
                    observer.on(.next(pending))
                }
                observer.on(.completed)
            }
        }
        return subscription
    }
}