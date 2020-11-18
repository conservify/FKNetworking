import Foundation
import SwiftProtobuf

@objc
open class ReadOptions : NSObject {
    @objc public var batchSize: UInt64 = 10;
    @objc public var base64EncodeData: Bool = true;
}


