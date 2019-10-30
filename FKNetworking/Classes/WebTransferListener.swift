//
//  WebTransferListener.swift
//  AFNetworking
//
//  Created by Jacob Lewallen on 10/30/19.
//

import Foundation

@objc
public protocol WebTransferListener {
    func onProgress(taskId: String, headers: [String: String], bytes: Int, total: Int)
    func onComplete(taskId: String, headers: [String: String], contentType: String!, body: Any!, statusCode: Int)
    func onError(taskId: String, message: String)
}
