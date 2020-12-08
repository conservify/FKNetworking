import Foundation

@objc
open class Web : NSObject, URLSessionDelegate, URLSessionDownloadDelegate, URLSessionDataDelegate {
    var lastProgress: Date = Date.distantPast
    var minimumDelay: TimeInterval = 0.25
    var tokens: UInt64 = 0
    var taskToId: [URLSessionTask: String] = [URLSessionTask: String]();
    var idToTask: [String: URLSessionTask] = [String: URLSessionTask]();
    var transfers: [String: WebTransfer] = [String: WebTransfer]();
    var received: [String: Data] = [String: Data]();
    var temps: [String: TemporaryFile] = [String: TemporaryFile]();
    
    var sessionId = "conservify-bg";
    var sessionConfigStandard: URLSessionConfiguration;
    var sessionConfigLocal: URLSessionConfiguration;
    var urlSessionStandard: URLSession?;
    var urlSessionLocal: URLSession?;
    
    var uploadListener: WebTransferListener
    var downloadListener: WebTransferListener
    
    @objc
    public init(uploadListener: WebTransferListener, downloadListener: WebTransferListener) {
        self.uploadListener = uploadListener
        self.downloadListener = downloadListener
        
        // This session configuration is used for non-device communciations.
        sessionConfigStandard = URLSessionConfiguration.background(withIdentifier: sessionId)
        sessionConfigStandard.isDiscretionary = false
        sessionConfigStandard.sessionSendsLaunchEvents = true
        if #available(iOS 11.0, *) {
            sessionConfigStandard.waitsForConnectivity = false
            // This applies to the entire transfer. Not what you want.
            // sessionConfig.timeoutIntervalForResource = 10
        }
        sessionConfigStandard.timeoutIntervalForRequest = 10
        
        // When asked, we can use this session for talking to devices on our local networks.
        sessionConfigLocal = URLSessionConfiguration.background(withIdentifier: sessionId)
        sessionConfigLocal.isDiscretionary = false
        sessionConfigLocal.sessionSendsLaunchEvents = true
        if #available(iOS 11.0, *) {
            sessionConfigLocal.waitsForConnectivity = false
            // This applies to the entire transfer. Not what you want.
            // sessionConfig.timeoutIntervalForResource = 10
        }
        sessionConfigLocal.timeoutIntervalForRequest = 10
        sessionConfigLocal.allowsCellularAccess = false

        super.init()
        
        urlSessionStandard = URLSession(configuration: sessionConfigStandard, delegate: self, delegateQueue: nil)
        urlSessionLocal = URLSession(configuration: sessionConfigLocal, delegate: self, delegateQueue: nil)
    }
    
    @objc
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
        
        var session = urlSessionStandard!
        if info.favorLocal {
            session = urlSessionLocal!
        }
        
        let task = session.dataTask(with: req)
        
        received[id] = Data()
        transfers[id] = info
        taskToId[task] = id
        idToTask[id] = task
        
        task.resume()
        
        return id
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
        
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData/*, timeoutInterval: 10*/)
        req.httpMethod = info.methodOrDefault
        
        for (key, value) in info.headers {
            req.addValue(value, forHTTPHeaderField: key)
        }
        
        var session = urlSessionStandard!
        if info.favorLocal {
            session = urlSessionLocal!
        }
        
        let task = session.downloadTask(with: req)
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
        
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = info.methodOrDefault
        
        for (key, value) in info.headers {
            req.addValue(value, forHTTPHeaderField: key)
        }
        
        var session = urlSessionStandard!
        if info.favorLocal {
            session = urlSessionLocal!
        }
        
        let task = session.uploadTask(with: req, fromFile: sourceURL)
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
            
            guard let receivedBody = received[taskId] else {
                NSLog("Web::download no received body")
                return
            }
            
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
            let headers = httpResponse.headersAsStrings()
            
            var body: String?
            if taskInfo.base64EncodeResponseBody {
                body = String(data: receivedBody.base64EncodedData(), encoding: .utf8)
                NSLog("Web::encoded body(base64): %@", body!)
            }
            else {
                body = String(data: receivedBody, encoding: .utf8)
                NSLog("Web::string body(text): %@", body!)
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
    
    // Invoked as we're sending data, for both file uploads and POSTing data to servers.
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64,
                           totalBytesExpectedToSend: Int64) {
        NSLog("Web::upload progress: wrote=%d total=%d lp=%f", totalBytesSent, totalBytesExpectedToSend, lastProgress.timeIntervalSinceNow)
        
        guard let taskId = taskToId[task] else {
            NSLog("Web::upload progress for unknown task?")
            return
        }
        
        let headers = [String: String]()
        
        if -lastProgress.timeIntervalSinceNow > minimumDelay || totalBytesSent == totalBytesExpectedToSend {
            OperationQueue.main.addOperation {
                self.uploadListener.onProgress(taskId: taskId, headers: headers,
                                               bytes: Int(totalBytesSent),
                                               total: Int(totalBytesExpectedToSend))
            }
            lastProgress = Date()
        }
    }

    // Invoked during download to update us about progress about a DownloadTask.
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        NSLog("Web::download progress: wrote=%d total=%d lp=%f", totalBytesWritten, totalBytesExpectedToWrite, lastProgress.timeIntervalSinceNow)
        
        guard let taskId = taskToId[downloadTask] else {
            NSLog("Web::download progress for unknown task?")
            return
        }
        
        let headers = [String: String]()
        
        if -lastProgress.timeIntervalSinceNow > minimumDelay || totalBytesWritten == totalBytesExpectedToWrite {
            OperationQueue.main.addOperation {
                self.downloadListener.onProgress(taskId: taskId, headers: headers,
                                                 bytes: Int(totalBytesWritten),
                                                 total: Int(totalBytesExpectedToWrite))
            }
            lastProgress = Date()
        }
    }
    
    // Invoked as we're receiving data for a DataTask.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let taskId = taskToId[dataTask] else {
            NSLog("Web::transfer done for unknown task")
            return
        }
        
        NSLog("[%@] transfer received data (%d)", taskId, data.count)
        
        guard var receiving = received[taskId] else {
            NSLog("Web::transfer done, no waiting data")
            return
        }
        
        let bytesBefore = receiving.count
        
        receiving.append(data)
        
        received[taskId] = receiving
        
        if #available(iOS 11.0, *) {
            let headers = [String: String]()
            let expectedBytes = dataTask.countOfBytesExpectedToReceive
            if -lastProgress.timeIntervalSinceNow > minimumDelay || receiving.count == expectedBytes || bytesBefore == 0 {
                OperationQueue.main.addOperation {
                    self.downloadListener.onProgress(taskId: taskId, headers: headers,
                                                     bytes: Int(receiving.count),
                                                     total: Int(expectedBytes))
                }
                lastProgress = Date()
            }
        }
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
    
    private func newToken() -> String {
        tokens += 1
        return "cfynw-\(tokens)"
    }
    
    private func getListenerFor(task: URLSessionTask) -> WebTransferListener {
        if task is URLSessionDownloadTask {
            return downloadListener
        }
        return uploadListener
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
