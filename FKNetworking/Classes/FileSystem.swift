//
//  Data.swift
//  AFNetworking
//
//  Created by Jacob Lewallen on 10/30/19.
//

import Foundation
import SwiftProtobuf

@objc
open class ReadOptions : NSObject {
    @objc public var batchSize: UInt64 = 10;
}

@objc
open class FileInfo : NSObject {
    @objc public var file: String = "";
    @objc public var size: UInt64 = 0;
}

@objc
public protocol FileSystemListener {
    func onFileInfo(path: String, token: String, info: FileInfo)
    func onFileRecords(path: String, token: String, position: UInt64, size: UInt64, records: Any?)
    func onFileError(path: String, token: String, error: String)
}

@objc
open class PbFile : NSObject {
    var fs: FileSystem
    var path: String
    
    @objc
    public init(fs: FileSystem, path: String) {
        self.fs = fs
        self.path = path
        super.init()
    }
    
    @objc
    public func readInfo(token: String) -> Bool {
        let queue = DispatchQueue(label: "read-info")
        
        queue.async {
            let listener = self.fs.listener
            
            NSLog("[%@] starting", token)
            do {
                let fm = FileManager()
                let attr = try fm.attributesOfItem(atPath: self.path)
                let fileSize = attr[FileAttributeKey.size] as! UInt64
                let fileInfo = FileInfo()
                fileInfo.file = self.path
                fileInfo.size = fileSize
                listener.onFileInfo(path: self.path, token: token, info: fileInfo)
            }
            catch let error {
                NSLog("[%@] info failed: %@", token, error.localizedDescription)
                listener.onFileError(path: self.path, token: token, error: error.localizedDescription)
            }
        }
        
        return true
    }
    
    @objc
    public func readDelimited(token: String, options: ReadOptions) -> Bool {
        let queue = DispatchQueue(label: "read-delimited")
        
        queue.async {
            let listener = self.fs.listener
            var position: UInt64 = 0
            
            NSLog("[%@] starting", token)

            do {
                let fm = FileManager()
                let attr = try fm.attributesOfItem(atPath: self.path)
                let size = attr[FileAttributeKey.size] as! UInt64
                if let stream = InputStream(fileAtPath: self.path) {
                    var records: [Data] = []
                    
                    stream.open()
                    
                    while position < size {
                        let (length, lengthBytes) = try PbFile.decodeVarint(stream)
                        if length == 0 {
                            break
                        }
                        
                        position += UInt64(lengthBytes)
                        
                        var data = Data(count: Int(length))
                        var bytesRead: Int = 0
                        data.withUnsafeMutableBytes { (body: UnsafeMutableRawBufferPointer) in
                            if let baseAddress = body.baseAddress, body.count > 0 {
                                // This assumingMemoryBound is technically unsafe, but without SR-11078
                                // (https://bugs.swift.org/browse/SR-11087) we don't have another option.
                                // It should be "safe enough".
                                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                                bytesRead = stream.read(pointer, maxLength: Int(length))
                            }
                        }

                        if bytesRead != length {
                            if bytesRead == -1 {
                                if let streamError = stream.streamError {
                                throw streamError
                                }
                                throw BinaryDelimited.Error.unknownStreamError
                            }
                            throw BinaryDelimited.Error.truncated
                        }
                        
                        position += UInt64(bytesRead)
                        
                        records.append(data)
                        
                        if records.count == options.batchSize {
                            listener.onFileRecords(path: self.path, token: token, position: position, size: size, records: records)
                            records = []
                        }
                    }
                    
                    if records.count == options.batchSize {
                        listener.onFileRecords(path: self.path, token: token, position: position, size: size, records: records)
                        records = []
                    }

                    listener.onFileRecords(path: self.path, token: token, position: position, size: size, records: nil)
                    
                    stream.close()
                }
            }
            catch let error {
                NSLog("[%@] delimited failed: %@", token, error.localizedDescription)
                listener.onFileError(path: self.path, token: token, error: error.localizedDescription)
            }
        }
        
        return true
    }
    
    // From BinaryDelimited.swift
    internal static func decodeVarint(_ stream: InputStream) throws -> (UInt64, Int) {
        // Buffer to reuse within nextByte.
        var totalBytesRead = 0
        let readBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        #if swift(>=4.1)
            defer { readBuffer.deallocate() }
        #else
            defer { readBuffer.deallocate(capacity: 1) }
        #endif

        func nextByte() throws -> UInt8 {
            let bytesRead = stream.read(readBuffer, maxLength: 1)
            if bytesRead != 1 {
                if bytesRead == -1 {
                    if let streamError = stream.streamError {
                        throw streamError
                    }
                    throw BinaryDelimited.Error.unknownStreamError
                }
                throw BinaryDelimited.Error.truncated
            }
            totalBytesRead += 1
            return readBuffer[0]
        }

        var value: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let c = try nextByte()
            value |= UInt64(c & 0x7f) << shift
            if c & 0x80 == 0 {
                return (value, totalBytesRead)
            }
            shift += 7
            if shift > 63 {
                throw BinaryDecodingError.malformedProtobuf
            }
        }
    }
}

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
    public func newToken() -> String {
        tokens += 1
        return "cfyfs-\(tokens)"
    }
}

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
