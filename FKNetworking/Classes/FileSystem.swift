import Foundation
import SwiftProtobuf

@objc
open class FileSystem : NSObject {
    var tokens: UInt64 = 0
    var listener: FileSystemListener
    
    @objc
    public init(listener: FileSystemListener) {
        self.listener = listener
        super.init()
    }
    
    @objc
    public func open(path: String) -> PbFile {
        return PbFile.init(fs: self, path: path)
    }
    
    @objc
    public func copyFile(source: String, destiny: String) -> Bool {
        let sourceURL = NSURL.fileURL(withPath: source)
        let destinyURL = NSURL.fileURL(withPath: destiny)
        if !FileManager.default.secureCopyItem(at: sourceURL, to: destinyURL) {
            NSLog("error copying %@ -> %@", source, destiny)
            return false
        }
        return true
    }
    
    @objc
    public func newToken() -> String {
        tokens += 1
        return "cfyfs-\(tokens)"
    }
}
