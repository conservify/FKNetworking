import Foundation
import SwiftProtobuf

@objc
public protocol FileSystemListener {
    func onFileInfo(path: String, token: String, info: FileInfo)
    func onFileRecords(path: String, token: String, position: UInt64, size: UInt64, records: Any?)
    func onFileError(path: String, token: String, error: String)
}

