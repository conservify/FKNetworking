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
        let current = currentSSIDs()
        if current.count > 0 {
            for ssid in current {
                let network = WifiNetwork(ssid: ssid)
                networkingListener.onConnectedNetwork(network: network)
            }
        }
        else {
            networkingListener.onConnectedNetwork(network: nil)
        }
    }
    
    @objc
    public func scan() {
        let networks = WifiNetworks()
        networkingListener.onNetworksFound(networks: networks)
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
