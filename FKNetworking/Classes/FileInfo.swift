import Foundation
import SwiftProtobuf

@objc
open class FileInfo : NSObject {
    @objc public var file: String = "";
    @objc public var size: UInt64 = 0;
}
