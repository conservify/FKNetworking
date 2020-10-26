//
//  NetworkingListener.swift
//  AFNetworking
//
//  Created by Jacob Lewallen on 10/30/19.
//

import Foundation

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
open class UdpMessage : NSObject {
    @objc public var address: String = ""
    @objc public var data: String = ""
    
    @objc
    public init(address: String, data: String) {
        self.address = address
        self.data = data
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
open class NetworkingStatus : NSObject {
    @objc public var connected: Bool = false;
    @objc public var connectedWifi: WifiNetwork? = nil;
    @objc public var wifiNeworks: WifiNetworks? = nil;
    @objc public var scanError: Bool = false;
}

@objc
public protocol NetworkingListener {
    func onStarted()
    
    func onDiscoveryFailed()
    func onFoundService(service: ServiceInfo)
    func onLostService(service: ServiceInfo)
    
    func onNetworkStatus(status: NetworkingStatus)
    func onUdpMessage(message: UdpMessage)
}
