//
//  Web.swift
//  AFNetworking
//
//  Created by Jacob Lewallen on 10/30/19.
//

import Foundation

@objc
open class WebTransfer : NSObject {
    @objc public var id: String = UUID().uuidString
    @objc public var url: String? = nil
    @objc public var path: String? = nil
    @objc public var body: String? = nil
    @objc public var base64DecodeRequestBody: Bool = false
    @objc public var base64EncodeResponseBody: Bool = false
    @objc public var contentType: String? = nil
    @objc public var headers: [String: String] = [String:String]()
    
    @objc public func header(key: String, value: String) -> WebTransfer {
        headers[key] = value
        return self
    }
}

@objc
open class Web : NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    var taskToId: [URLSessionTask: String] = [URLSessionTask: String]();
    var idToTask: [String: URLSessionTask] = [String: URLSessionTask]();
    var transfers: [String: WebTransfer] = [String: WebTransfer]();
    
    var uploadListener: WebTransferListener
    var downloadListener: WebTransferListener
    
    @objc
    public init(uploadListener: WebTransferListener, downloadListener: WebTransferListener) {
        self.uploadListener = uploadListener
        self.downloadListener = downloadListener
        super.init()
    }
    
    func basic(info: WebTransfer) -> String {
        let id = info.id
        
        let url = URL(string: info.url!)!
        
        NSLog("[%@] http %@", id, info.url!)
        
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        
        for (key, value) in info.headers {
            req.addValue(value, forHTTPHeaderField: key)
        }

        if info.body != nil {
            if info.base64DecodeRequestBody {
                req.httpBody = Data(base64Encoded: info.body!)
            }
            else {
                req.httpBody = info.body!.data(using: .utf8)
            }
        }
        
        let task = URLSession.shared.dataTask(with: req) { (data, response, error) in
            NSLog("[%@] completed", id)

            if error != nil {
                NSLog("error: %@", error!.localizedDescription)
                self.downloadListener.onError(taskId: id, message: error!.localizedDescription)
            }
            else {
                if let httpResponse = response as? HTTPURLResponse {
                    guard let data = data else { return }

                    NSLog("data: %@", data.debugDescription)
                    
                    var body: String?
                    if info.base64EncodeResponseBody {
                        body = String(data: data.base64EncodedData(), encoding: .utf8)
                        NSLog("encoded body: %@", body!)
                    }
                    else {
                        body = String(data: data, encoding: .utf8)
                        NSLog("string body: %@", body!)
                    }
                    
                    let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
                    let headers = httpResponse.headersAsStrings()
                    
                    self.downloadListener.onComplete(taskId: id, headers: headers,
                                                     contentType: contentType, body: body,
                                                     statusCode: httpResponse.statusCode)
                }
                else {
                    NSLog("[%@] unexpected response %@", id, response.debugDescription)
                }
            }
            
            self.cleanup(id: id)
        }
        
        transfers[id] = info
        taskToId[task] = id
        idToTask[id] = task
        
        task.resume()

        return id
    }
    
    func cleanup(id: String) {
        if let task = idToTask[id] {
            transfers[id] = nil
            idToTask[id] = nil
            taskToId[task] = nil
        }
    }
    
    @objc
    public func simple(info: WebTransfer) -> String {
        return basic(info: info)
    }
    
    @objc
    public func download(info: WebTransfer) -> String {
        let id = info.id

        NSLog("[%@] downloading %@", id, info.url!)
        
        let url = URL(string: info.url!)!
        
        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        for (key, value) in info.headers {
            req.addValue(value, forHTTPHeaderField: key)
        }
        
        let task = urlSession.downloadTask(with: req)
        
        transfers[id] = info
        taskToId[task] = id
        idToTask[id] = task
        
        task.resume()
        
        return id
    }
    
    func getListenerFor(task: URLSessionTask) -> WebTransferListener {
        if task is URLSessionDownloadTask {
            return downloadListener
        }
        return uploadListener
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskId = taskToId[task] else {
            NSLog("download done for unknown task")
            return
        }
        
        let listener = getListenerFor(task: task)
        
        if error == nil {
            guard let httpResponse = task.response as? HTTPURLResponse else {
                NSLog("download done w/o HTTPURLResponse?")
                return
            }
            
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
            let headers = httpResponse.headersAsStrings()
            
            listener.onComplete(taskId: taskId,
                                headers: headers,
                                contentType: contentType,
                                body: nil,
                                statusCode: httpResponse.statusCode)
        }
        else {
            NSLog("download error: %@", error!.localizedDescription)
            
            listener.onError(taskId: taskId, message: error!.localizedDescription)
        }

        cleanup(id: taskId)
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        NSLog("download progress: %d %d", totalBytesWritten, totalBytesExpectedToWrite)
        
        guard let taskId = taskToId[downloadTask] else {
            NSLog("download progress for unknown task?")
            return
        }
        
        let headers = [String: String]()
        
        downloadListener.onProgress(taskId: taskId, headers: headers,
                                    bytes: Int(totalBytesWritten),
                                    total: Int(totalBytesExpectedToWrite))
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskId = taskToId[downloadTask] else {
            NSLog("download done for unknown task")
            return
        }
        
        let taskInfo = transfers[taskId]!

        NSLog("[%@] download completed: %@", taskId, taskInfo.path!)
        
        do {
            try FileManager.default.removeItem(atPath: taskInfo.path!)
        }
        catch let error {
            NSLog("[%@] remove failed: %@", taskId, error.localizedDescription)
        }
        
        do {
            let destinyURL = NSURL.fileURL(withPath: taskInfo.path!)
            
            NSLog("[%@] download completed: moving to %@", taskId, destinyURL.absoluteString)
            
            try FileManager.default.moveItem(at: location, to: destinyURL)
            
            NSLog("[%@] download completed: moved", taskId)
        }
        catch let error {
            NSLog("[%@] error %@", taskId, error.localizedDescription)
            
            downloadListener.onError(taskId: taskId, message: error.localizedDescription)
        }
    }
    
    @objc
    public func upload(info: WebTransfer) -> String {
        let id = info.id
        
        NSLog("[%@] uploading %@", id, info.url!)
        
        let url = URL(string: info.url!)!
        
        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        
        let sourceURL = NSURL.fileURL(withPath: info.path!)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)

        req.httpMethod = "POST"
        
        for (key, value) in info.headers {
            req.addValue(value, forHTTPHeaderField: key)
        }
        
        let task = urlSession.uploadTask(with: req, fromFile: sourceURL)
        
        transfers[id] = info
        taskToId[task] = id
        idToTask[id] = task
        
        task.resume()
        
        return id
    }
    
    public func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        NSLog("upload progress: %d %d", totalBytesSent, totalBytesExpectedToSend)
        
        guard let taskId = taskToId[task] else {
            NSLog("upload progress for unknown task?")
            return
        }

        let headers = [String: String]()
        
        uploadListener.onProgress(taskId: taskId, headers: headers,
                                  bytes: Int(totalBytesSent),
                                  total: Int(totalBytesExpectedToSend))
    }
}

extension HTTPURLResponse {
    func headersAsStrings() -> [String: String] {
        var headers = [String:String]()
        
        for (storedKey, storedValue) in self.allHeaderFields {
            if let stringKey = storedKey as? String, let stringValue = storedValue as? String {
                headers[stringKey] = stringValue
            }
        }
        
        return headers
    }
}
