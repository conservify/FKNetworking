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
    @objc public var type: String = ""
    @objc public var name: String = ""
    @objc public var host: String = ""
    @objc public var port: Int = 0
    
    @objc
    public init(type: String, name: String, host: String, port: Int) {
        self.type = type
        self.name = name
        self.host = host
        self.port = port
    }
}

@objc
open class WifiNetwork : NSObject {
    @objc public var ssid: String = ""
    
    @objc
    public init(ssid: String) {
        self.ssid = ssid
    }
}

@objc
open class WifiNetworks : NSObject {
}

@objc
public protocol NetworkingListener {
    func onStarted()
    func onFoundService(service: ServiceInfo)
    func onLostService(service: ServiceInfo)
    func onConnectionInfo(connected: Bool)
    func onConnectedNetwork(network: WifiNetwork)
    func onNetworksFound(networks: WifiNetworks)
    func onNetworkScanError()
}

@objc
public protocol WebTransferListener {
    func onStarted(taskId: String, headers: [String:String])
    func onProgress(taskId: String, bytes: Int, total: Int)
    func onComplete(taskId: String, headers: [String:String], contentType: String, body: Any, statusCode: Int)
    func onError(taskId: String)
}

@objc
open class WebTransfer : NSObject {
    @objc var url: String? = nil
    @objc var path: String? = nil
    @objc var body: String? = nil
    @objc var contentType: String? = nil
    @objc var headers: [String: String] = [String:String]()
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
    
    var pending: NetService?
    
    @objc
    init(networkingListener: NetworkingListener) {
        self.networkingListener = networkingListener
        self.browser = NetServiceBrowser()
        super.init()
    }
    
    @objc
    public func start(serviceType: String) {
        NSLog("ServiceDiscovery::starting");
        NSLog(serviceType);
        pending = nil
        browser.delegate = self
        browser.stop()
        browser.searchForServices(ofType: serviceType, inDomain: "local.")
        networkingListener.onStarted()
    }
    
    public func netServiceWillResolve(_ sender: NetService) {
        NSLog("ServiceDiscovery::netServiceWillResolve");
    }
    
    public func netServiceDidResolveAddress(_ sender: NetService) {
        NSLog("ServiceDiscovery::netServiceDidResolveAddress %@ %@", sender.name, sender.hostName ?? "<none>");
        
        if let serviceIp = resolveIPv4(addresses: sender.addresses!) {
            NSLog("Found IPV4: %@", serviceIp)
            networkingListener.onFoundService(service: ServiceInfo(type: sender.type, name: sender.name, host: serviceIp, port: sender.port))
        }
        else {
            NSLog("No ipv4")
        }
    }
    
    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        NSLog("ServiceDiscovery::didNotResolve");
    }
    
    public func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        NSLog("ServiceDiscovery::willSearch")
    }
    
    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        NSLog("ServiceDiscovery::netServiceBrowserDidStopSearch");
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        NSLog("ServiceDiscovery::didNotSearch");
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFindDomain domainString: String, moreComing: Bool) {
        NSLog("ServiceDiscovery::didFindDomain");
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        NSLog("ServiceDiscovery::didFindService %@ %@", service.name, service.type);
        
        service.stop()
        service.delegate = self
        service.resolve(withTimeout: 5.0)

        // TODO Do we need a queue of these?
        pending = service
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemoveDomain domainString: String, moreComing: Bool) {
        NSLog("ServiceDiscovery::didRemoveDomain");
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        NSLog("ServiceDiscovery::didRemoveService %@", service.name);
        networkingListener.onLostService(service: ServiceInfo(type: service.type, name: service.name, host: "", port: 0))
    }
    
    func resolveIPv4(addresses: [Data]) -> String? {
        var resolved: String?
        
        for address in addresses {
            let data = address as NSData
            var storage = sockaddr_storage()
            data.getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
            
            if Int32(storage.ss_family) == AF_INET {
                let addr4 = withUnsafePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        $0.pointee
                    }
                }
    
                if let ip = String(cString: inet_ntoa(addr4.sin_addr), encoding: .ascii) {
                    resolved = ip
                    break
                }
            }
        }
        
        return resolved
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
}

@objc
public protocol DataListener {
   
}

@objc
open class FileSystem : NSObject {
    
}
