//
//  Networking.swift
//  FKNetworking
//
//  Created by Jacob Lewallen on 10/25/19.
//

import Foundation
import Network
import os

@objc
open class ServiceInfo : NSObject {
    public var type: String = ""
    public var name: String = ""
    public var host: String = ""
    public var port: Int = 0
}

@objc
open class WifiNetwork : NSObject {
    public var ssid: String = ""
}

@objc
open class WifiNetworks : NSObject {
}

@objc
public protocol NetworkingListener {
    func onStarted()
    //func onFoundService(service: ServiceInfo)
    //func onLostService(service: ServiceInfo)
    //func onConnectionInfo(connected: Bool)
    //func onConnectedNetwork(network: WifiNetwork)
    //func onNetworksFound(networks: WifiNetworks)
    //func onNetworkScanError()
}

@objc
public protocol WebTransferListener {
    func onStarted(task: String, headers: [String:String])
    func onProgress(task: String, bytes: Int, total: Int)
    func onComplete(task: String, headers: [String:String], contentType: String, body: Any, statusCode: Int)
}

@objc
open class WebTransfer : NSObject {
    var url: String? = nil
    var path: String? = nil
    var body: String? = nil
    var contentType: String? = nil
    var headers: [String: String] = [String:String]()
}

@objc
open class Web : NSObject {
    var uploadListener: WebTransferListener
    var downloadListener: WebTransferListener
    
    @objc
    public init(uploadListener: WebTransferListener, downloadListener: WebTransferListener) {
        self.uploadListener = uploadListener
        self.downloadListener = downloadListener
        super.init()
    }
    
    @objc
    public func test() {
        NSLog("Web::test")
    }

    @objc
    public func json(info: WebTransfer) -> String {
        return ""
    }
    
    @objc
    public func binary(info: WebTransfer) -> String {
        return ""
    }

    @objc
    public func download(info: WebTransfer) -> String {
        return ""
    }

    @objc
    public func upload(info: WebTransfer) -> String {
        return ""
    }
}

@objc
open class ServiceDiscovery : NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var networkingListener: NetworkingListener
    var browser: NetServiceBrowser
    
    @objc
    init(networkingListener: NetworkingListener) {
        self.networkingListener = networkingListener
        self.browser = NetServiceBrowser()
        super.init()
    }
    
    @objc
    public func start(serviceType: String) {
        NSLog("ServiceDiscovery::start");
        browser.delegate = self
        browser.searchForServices(ofType: serviceType, inDomain: "")
    }
    
    func netServiceBrowser(aNetServiceBrowser: NetServiceBrowser!, didFindService aNetService: NetService!, moreComing: Bool) {
    }
    
    func netServiceBrowser(aNetServiceBrowser: NetServiceBrowser!, didRemoveService aNetService: NetService!, moreComing: Bool) {
    }
    
    func netServiceDidResolveAddress(netservice: NetService!) {
    }
    
    func netService(netservice: NetService!, didNotResolve errorDict: [NSObject : AnyObject]!) {
    }
}

@objc
open class WifiManager : NSObject {
    override init() {
        super.init()
    }
}

@objc
open class Networking : NSObject {
    @objc open var networkingListener: NetworkingListener
    @objc open var serviceDiscovery: ServiceDiscovery
    @objc open var web: Web
    @objc open var wifi: WifiManager
    
    @objc
    public init(networkingListener: NetworkingListener, uploadListener: WebTransferListener, downloadListener: WebTransferListener) {
        self.networkingListener = networkingListener
        self.serviceDiscovery = ServiceDiscovery(networkingListener: networkingListener)
        self.web = Web(uploadListener: uploadListener, downloadListener: downloadListener)
        self.wifi = WifiManager()
        NSLog("Networking::new")
        super.init()
    }
    
    @objc
    public func test() {
        NSLog("Networking::test")
    }
    
    @objc
    public func getWeb() -> Web {
        return web
    }
    
    @objc
    public func getServiceDiscovery() -> ServiceDiscovery {
        return serviceDiscovery
    }
    
    @objc
    public func getWifiManager() -> WifiManager {
        return wifi
    }
    
    @objc
    public func start(serviceType: String) {
        NSLog("Networking::start");
        serviceDiscovery.start(serviceType: serviceType)
        networkingListener.onStarted()
    }
}

@objc
public protocol DataListener {
   
}

@objc
open class FileSystem : NSObject {
    
}
