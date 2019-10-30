//
//  Web.swift
//  AFNetworking
//
//  Created by Jacob Lewallen on 10/30/19.
//

import Foundation

@objc
open class WebTransfer : NSObject {
    @objc public var url: String? = nil
    @objc public var path: String? = nil
    @objc public var body: String? = nil
    @objc public var contentType: String? = nil
    @objc public var headers: [String: String] = [String:String]()
    
    @objc public func header(key: String, value: String) -> WebTransfer {
        headers[key] = value
        return self
    }
}

@objc
open class Web : NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    var downloads: [URLSessionDownloadTask: String] = [URLSessionDownloadTask: String]();
    var tasks: [String: WebTransfer] = [String: WebTransfer]();
    
    var uploadListener: WebTransferListener
    var downloadListener: WebTransferListener
    
    @objc
    public init(uploadListener: WebTransferListener, downloadListener: WebTransferListener) {
        self.uploadListener = uploadListener
        self.downloadListener = downloadListener
        super.init()
    }
    
    func basic(info: WebTransfer) -> String {
        let id = UUID().uuidString
        
        let url = URL(string: info.url!)!
        
        NSLog("[%@] http %@", id, info.url!)
        
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            NSLog("[%@] completed", id)

            if error != nil {
                NSLog("error: %@", error!.localizedDescription)
                self.downloadListener.onStarted(taskId: id, headers: [String: String]())
                self.downloadListener.onError(taskId: id)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                guard let data = data else { return }
                
                let body = String(data: data, encoding: .utf8)
                
                NSLog("body: %@", body!)
                
                let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
                let headers = httpResponse.headersAsStrings()
                
                self.downloadListener.onStarted(taskId: id, headers: headers)
                self.downloadListener.onComplete(taskId: id, headers: headers, contentType: contentType, body: body!, statusCode: httpResponse.statusCode)
            }
            else {
                NSLog("[%@] unexpected response %@", id, response.debugDescription)
            }
        }
        
        task.resume()
        
        return id
    }
    
    @objc
    public func json(info: WebTransfer) -> String {
        return basic(info: info)
    }
    
    @objc
    public func binary(info: WebTransfer) -> String {
        return basic(info: info)
    }
    
    @objc
    public func download(info: WebTransfer) -> String {
        let id = UUID().uuidString
        
        NSLog("[%@] downloading %@", id, info.url!)
        
        let url = URL(string: info.url!)!
        
        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        
        let task = urlSession.downloadTask(with: url)
        
        tasks[id] = info
        downloads[task] = id
        
        task.resume()
        
        return id
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error == nil {
            NSLog("download done with no error")
            return
        }
        
        NSLog("download error: %@", error!.localizedDescription)
        
        if let downloadTask = task as? URLSessionDownloadTask {
            let taskId = downloads[downloadTask]!
            
            downloadListener.onError(taskId: taskId)
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        NSLog("download progress: %d %d", totalBytesWritten, totalBytesExpectedToWrite)
        
        let taskId = downloads[downloadTask]!
        
        downloadListener.onProgress(taskId: taskId, bytes: Int(totalBytesWritten), total: Int(totalBytesExpectedToWrite))
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        NSLog("download of %@ complete", location.absoluteString)
        
        let taskId = downloads[downloadTask]!
        let taskInfo = tasks[taskId]!
        
        NSLog("[%@] download completed: %@", taskId, taskInfo.path!)
        
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            do {
                try FileManager.default.removeItem(atPath: taskInfo.path!)
            }
            catch let error {
                NSLog("[%@] download completed: remove failed: %@", taskId, error.localizedDescription)
            }
            
            do {
                let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
                let headers = httpResponse.headersAsStrings()
                
                let destinyURL = NSURL.fileURL(withPath: taskInfo.path!)
                
                NSLog("[%@] download completed: moving to %@", taskId, destinyURL.absoluteString)
                
                try FileManager.default.moveItem(at: location, to: destinyURL)
                
                NSLog("[%@] download completed: moved", taskId)
                
                downloadListener.onComplete(taskId: taskId, headers: headers, contentType: contentType, body: nil, statusCode: httpResponse.statusCode)
            }
            catch let error {
                NSLog("[%@] download completed: ERROR %@", taskId, error.localizedDescription)
                
                downloadListener.onError(taskId: taskId)
            }
        }
    }
    
    @objc
    public func upload(info: WebTransfer) -> String {
        let id = UUID().uuidString
        
        return id
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
