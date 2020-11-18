import Foundation
import SwiftProtobuf

@objc
open class SampleData : NSObject {
    @objc
    public func write() -> String? {
        do {
            let directory = NSTemporaryDirectory()
            let fileName = NSUUID().uuidString
            let path: String = directory + "/" + fileName

            if let stream = OutputStream(toFileAtPath: path, append: false) {
                stream.open()
                
                defer { stream.close() }
            
                for index in 1...100 {
                    var record = FkData_DataRecord()
                    record.identity.name = "Fake Station"
                    record.status.uptime = UInt32(index)
                    try BinaryDelimited.serialize(message: record, to: stream)
                }
                                    
                return path
            }
        }
        catch let error {
            NSLog("write sample data failed: %@", error.localizedDescription)
        }
        
        return nil;
    }
}

