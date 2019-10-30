//
//  WebTransferListener.swift
//  AFNetworking
//
//  Created by Jacob Lewallen on 10/30/19.
//

import Foundation

@objc
public protocol WebTransferListener {
    func onStarted(taskId: String, headers: [String: String])
    func onProgress(taskId: String, bytes: Int, total: Int)
    func onComplete(taskId: String, headers: [String: String], contentType: String!, body: Any!, statusCode: Int)
    func onError(taskId: String)
}
