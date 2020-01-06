//
//  WifiManager.swift
//  AFNetworking
//
//  Created by Jacob Lewallen on 10/30/19.
//

import Foundation
import SystemConfiguration.CaptiveNetwork

@objc
open class WifiManager : NSObject {
    var networkingListener: NetworkingListener
    
    @objc
    public init(networkingListener: NetworkingListener) {
        self.networkingListener = networkingListener
        super.init()
    }
    
    @objc
    public func findConnectedNetwork() {
        let status = NetworkingStatus()
        let current = currentSSIDs()
        if current.count > 0 {
            for ssid in current {
                let network = WifiNetwork(ssid: ssid)
                status.connectedWifi = network
                networkingListener.onNetworkStatus(status: status)
            }
        }
        else {
            networkingListener.onNetworkStatus(status: status)
        }
    }
    
    @objc
    public func scan() {
        let status = NetworkingStatus()
        status.wifiNeworks = WifiNetworks()
        networkingListener.onNetworkStatus(status: status)
    }
    
    func currentSSIDs() -> [String] {
        guard let interfaceNames = CNCopySupportedInterfaces() as? [String] else {
            return []
        }
        
        return interfaceNames.compactMap { name in
            guard let info = CNCopyCurrentNetworkInfo(name as CFString) as? [String:AnyObject] else {
                return nil
            }
            guard let ssid = info[kCNNetworkInfoKeySSID as String] as? String else {
                return nil
            }
            return ssid
        }
    }
}
