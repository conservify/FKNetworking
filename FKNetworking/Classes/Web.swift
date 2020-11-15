 //
//  Web.swift
//  AFNetworking
//
//  Created by Jacob Lewallen on 10/30/19.
//

import Foundation

var tokens: UInt64 = 0

func newToken() -> String {
    tokens += 1
    return "cfynw-\(tokens)"
}

@objc
open class WebTransfer : NSObject {
    @objc public var id: String = newToken()
    @objc public var method: String? = nil
    @objc public var url: String? = nil
    @objc public var path: String? = nil
    @objc public var body: String? = nil
    @objc public var uploadCopy: Bool = false
    @objc public var base64DecodeRequestBody: Bool = false
    @objc public var base64EncodeResponseBody: Bool = false
    @objc public var contentType: String? = nil
    @objc public var headers: [String: String] = [String:String]()
    
    @objc public func header(key: String, value: String) -> WebTransfer {
        headers[key] = value
        return self
    }
    
    @objc public var methodOrDefault: String {
        return method ?? "GET"
    }
    
    @objc public var isGET: Bool {
        return methodOrDefault == "GET"
    }
}

@objc
open class Web : NSObject, URLSessionDelegate, URLSessionDownloadDelegate, URLSessionDataDelegate {
    var lastProgress: Date = Date.distantPast
    var minimumDelay: TimeInterval = 0.5
    var tokens: UInt64 = 0
    var taskToId: [URLSessionTask: String] = [URLSessionTask: String]();
    var idToTask: [String: URLSessionTask] = [String: URLSessionTask]();
    var transfers: [String: WebTransfer] = [String: WebTransfer]();
    var received: [String: Data] = [String: Data]();
    var temps: [String: TemporaryFile] = [String: TemporaryFile]();
    var sessionId = "conservify-bg";
    
    var uploadListener: WebTransferListener
    var downloadListener: WebTransferListener
    
    @objc
    public init(uploadListener: WebTransferListener, downloadListener: WebTransferListener) {
        self.uploadListener = uploadListener
        self.downloadListener = downloadListener
        super.init()
    }
    
    private func newToken() -> String {
        tokens += 1
        return "cfynw-\(tokens)"
    }
    
    public func basic(info: WebTransfer) -> String {
        let id = info.id
        
        guard let url = URL(string: info.url!) else {
            NSLog("[%@] invalid url", id)
            downloadListener.onError(taskId: id, message: "invalid url")
            return id
        }
        
        NSLog("[%@] http %@ %@", id, info.url!, info.methodOrDefault)
        
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.httpMethod = info.methodOrDefault
        
        for (key, value) in info.headers {
            req.addValue(value, forHTTPHeaderField: key)
        }

        if info.body != nil {
            if info.isGET {
                NSLog("[%@] WARNING: ignoring body for GET", id)
            }
            else {
                if info.base64DecodeRequestBody {
                    req.httpBody = Data(base64Encoded: info.body!)
                }
                else {
                    req.httpBody = info.body!.data(using: .utf8)
                }
            }
        }
        
        let sessionConfig = URLSessionConfiguration.default
        if #available(iOS 11.0, *) {
            sessionConfig.waitsForConnectivity = false
            // Remember that this applies to the entire duration of the request.
            sessionConfig.timeoutIntervalForResource = 10
        }
        sessionConfig.timeoutIntervalForRequest = 10

        let task = URLSession(configuration: sessionConfig).dataTask(with: req) { (data, response, error) in
            NSLog("[%@] completed", id)

            if error != nil {
                NSLog("Web::error: %@", error!.localizedDescription)
                self.downloadListener.onError(taskId: id, message: error!.localizedDescription)
            }
            else {
                if let httpResponse = response as? HTTPURLResponse {
                    guard let data = data else { return }

                    NSLog("Web::data: %@", data.debugDescription)
                    
                    var body: String?
                    if info.base64EncodeResponseBody {
                        body = String(data: data.base64EncodedData(), encoding: .utf8)
                        NSLog("Web::encoded body: %@", body!)
                    }
                    else {
                        body = String(data: data, encoding: .utf8)
                        NSLog("Web::string body: %@", body!)
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
    
    private func cleanup(id: String) {
        if let task = idToTask[id] {
            transfers[id] = nil
            idToTask[id] = nil
            taskToId[task] = nil
            received[id] = nil
        }
        if let temp = temps[id] {
            temp.remove()
            temps[id] = nil
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
        
        guard let url = URL(string: info.url!) else {
            NSLog("[%@] invalid url", id)
            downloadListener.onError(taskId: id, message: "invalid url")
            return id
        }

        let sessionConfig = URLSessionConfiguration.background(withIdentifier: sessionId)
        sessionConfig.isDiscretionary = false
        sessionConfig.sessionSendsLaunchEvents = true
        if #available(iOS 11.0, *) {
            sessionConfig.waitsForConnectivity = false
            // This applies to the entire transfer. Not what you want.
            // sessionConfig.timeoutIntervalForResource = 10
        }
        sessionConfig.timeoutIntervalForRequest = 10

        let urlSession = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData/*, timeoutInterval: 10*/)
        req.httpMethod = info.methodOrDefault
        
        for (key, value) in info.headers {
            req.addValue(value, forHTTPHeaderField: key)
        }
        
        let task = urlSession.downloadTask(with: req)
        // task.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        // task.countOfBytesClientExpectsToSend = 200
        // task.countOfBytesClientExpectsToReceive = 500 * 1024

        received[id] = Data()
        transfers[id] = info
        taskToId[task] = id
        idToTask[id] = task
        
        task.resume()
        
        return id
    }
    
    private func getListenerFor(task: URLSessionTask) -> WebTransferListener {
        if task is URLSessionDownloadTask {
            return downloadListener
        }
        return uploadListener
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskId = taskToId[task] else {
            NSLog("Web::download done for unknown task")
            return
        }
        
        NSLog("[%@] transfer completed", taskId)

        let listener = getListenerFor(task: task)
        let taskInfo = transfers[taskId]!
        
        if error == nil {
            guard let httpResponse = task.response as? HTTPURLResponse else {
                NSLog("Web::download done w/o HTTPURLResponse?")
                return
            }
            
            let response = received[taskId]!
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
            let headers = httpResponse.headersAsStrings()
            
            var body: String?
            if taskInfo.base64EncodeResponseBody {
                body = String(data: response.base64EncodedData(), encoding: .utf8)
                NSLog("Web::encoded body: %@", body!)
            }
            else {
                body = String(data: response, encoding: .utf8)
                NSLog("Web::string body: %@", body!)
            }
            
            OperationQueue.main.addOperation {
                listener.onComplete(taskId: taskId,
                                    headers: headers,
                                    contentType: contentType,
                                    body: body,
                                    statusCode: httpResponse.statusCode)
            }
        }
        else {
            NSLog("Web::download error: %@", error!.localizedDescription)
            
            OperationQueue.main.addOperation {
                listener.onError(taskId: taskId, message: error!.localizedDescription)
            }
        }

        cleanup(id: taskId)
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        NSLog("Web::download progress: %d %d", totalBytesWritten, totalBytesExpectedToWrite)
        
        guard let taskId = taskToId[downloadTask] else {
            NSLog("Web::download progress for unknown task?")
            return
        }
        
        let headers = [String: String]()
        
        if lastProgress.timeIntervalSinceNow > minimumDelay || totalBytesWritten == totalBytesExpectedToWrite {
            OperationQueue.main.addOperation {
                self.downloadListener.onProgress(taskId: taskId, headers: headers,
                                             bytes: Int(totalBytesWritten),
                                             total: Int(totalBytesExpectedToWrite))
            }
            lastProgress = Date()
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskId = taskToId[downloadTask] else {
            NSLog("Web::download done for unknown task")
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
        
            OperationQueue.main.addOperation {
                self.downloadListener.onError(taskId: taskId, message: error.localizedDescription)
            }
        }
    }
    
    @objc
    public func upload(info: WebTransfer) -> String {
        let id = info.id
                
        NSLog("[%@] uploading %@", id, info.url!)
        
        guard let url = URL(string: info.url!) else {
            NSLog("[%@] invalid url", id)
            uploadListener.onError(taskId: id, message: "invalid url")
            return id
        }
        
        var sourceURL = NSURL.fileURL(withPath: info.path!)
        let temporary = TemporaryFile(beside: info.path!, extension: "uploading")
        if info.uploadCopy {
            NSLog("[%@] copying %@ to %@", id, sourceURL.absoluteString, temporary.url.absoluteString)
            if !FileManager.default.secureCopyItem(at: sourceURL, to: temporary.url) {
                NSLog("[%@] error copying", id)
                uploadListener.onError(taskId: id, message: "copy error")
                return id
            }
            temps[id] = temporary
            sourceURL = temporary.url
            NSLog("[%@] copied", id)
        }
        else {
            NSLog("[%@] file ready %@", id, info.path!)
        }
        
        let sessionConfig = URLSessionConfiguration.background(withIdentifier: sessionId)
        sessionConfig.isDiscretionary = false
        sessionConfig.sessionSendsLaunchEvents = true
        if #available(iOS 11.0, *) {
            sessionConfig.waitsForConnectivity = false
            // This applies to the entire transfer. Not what you want.
            // sessionConfig.timeoutIntervalForResource = 10
        }
        sessionConfig.timeoutIntervalForRequest = 10

        let urlSession = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData/*, timeoutInterval: 10*/)
        req.httpMethod = info.methodOrDefault
        
        for (key, value) in info.headers {
            req.addValue(value, forHTTPHeaderField: key)
        }
        
        let task = urlSession.uploadTask(with: req, fromFile: sourceURL)
        // task.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        // task.countOfBytesClientExpectsToSend = 200
        // task.countOfBytesClientExpectsToReceive = 500 * 1024
        
        received[id] = Data()
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
        NSLog("Web::upload progress: %d %d", totalBytesSent, totalBytesExpectedToSend)
        
        guard let taskId = taskToId[task] else {
            NSLog("Web::upload progress for unknown task?")
            return
        }

        let headers = [String: String]()
        
        if lastProgress.timeIntervalSinceNow > minimumDelay || totalBytesSent == totalBytesExpectedToSend {
            OperationQueue.main.addOperation {
                self.uploadListener.onProgress(taskId: taskId, headers: headers,
                                               bytes: Int(totalBytesSent),
                                               total: Int(totalBytesExpectedToSend))
            }
            lastProgress = Date()
        }
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let taskId = taskToId[dataTask] else {
            NSLog("Web::transfer done for unknown task")
            return
        }
        
        // let taskInfo = transfers[taskId]!
        
        NSLog("[%@] transfer received data (%d)", taskId, data.count)
        
        received[taskId]!.append(data)
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        NSLog("Web::urlSessionDidFinishEvents")
        DispatchQueue.main.async {
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
            let backgroundCompletionHandler = appDelegate.backgroundCompletionHandler else {
                NSLog("Web::urlSessionDidFinishEvents: no handler")
                return
            }
            NSLog("Web::urlSessionDidFinishEvents: calling handler")
            backgroundCompletionHandler()
        }
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

extension FileManager {
    open func secureCopyItem(at srcURL: URL, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
        } catch (let error) {
            NSLog("error copying \(srcURL) to \(dstURL): \(error)")
            return false
        }
        return true
    }
}

public final class TemporaryFile {
    public let url: URL

    public init(beside besides: String, extension ext: String) {
        let besidesUrl = URL(fileURLWithPath: besides)
        let directory = besidesUrl.deletingLastPathComponent()

        url = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }
    
    open func remove() {
        NSLog("deleting temporary")
        DispatchQueue.global(qos: .utility).async { [url = self.url] in
            try? FileManager.default.removeItem(at: url)
        }
    }

    deinit {
        /*
        remove()
        */
    }
}
