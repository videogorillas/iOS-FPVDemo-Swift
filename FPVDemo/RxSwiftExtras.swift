//
// Created by Alex Zhukov on 8/21/17.
// Copyright (c) 2017 Alex Zhukov. All rights reserved.
//

import Foundation
import RxSwift

extension ObservableType {
    func toArrayUntil(predicate: @escaping (E) -> Bool) -> Observable<Array<E>> {
        return Observable.create { observer in
            var arr = Array<E>();
            let subscription = self.subscribe { e in
                switch e {
                case .next(let value):
                    let result = predicate(value)
                    arr.append(value)
                    if result {
                        let output: Array<E> = arr;
                        arr = Array<E>()
                        observer.on(.next(output))
                    }
                case .error(let error):
                    observer.on(.error(error))
                case .completed:
                    if arr.count > 0 {
                        let output: Array<E> = arr;
                        arr = Array<E>()
                        observer.on(.next(output))
                    }
                    observer.on(.completed)
                }
            }

            return subscription
        }
    }
}