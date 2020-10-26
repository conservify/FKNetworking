//
//  Discovery.swift
//  AFNetworking
//
//  Created by Jacob Lewallen on 10/30/19.
//

import Foundation
import Network

protocol SimpleUDP {
    func start();
    func stop();
}

@available(iOS 14.00, *)
class LatestSimpleUDP : SimpleUDP {
    private var networkingListener: NetworkingListener
    private var group: NWConnectionGroup?;
    
    init(networkingListener: NetworkingListener) {
        self.networkingListener = networkingListener
    }
    
    public func start() {
        NSLog("ServiceDiscovery::iOS 14, listening udp");

        DispatchQueue.global(qos: .background).async {
            guard let multicast = try? NWMulticastGroup(for: [ .hostPort(host: "224.1.2.3", port: 22143) ]) else {
                NSLog("ServiceDiscovery: error creating group")
                return
            }

            let group = NWConnectionGroup(with: multicast, using: .udp)
            group.setReceiveHandler(maximumMessageSize: 16384, rejectOversizedMessages: true) { (message, content, isComplete) in
                var address = ""
                switch(message.remoteEndpoint) {
                    case .hostPort(let host, _):
                        address = "\(host)"
                    default:
                        NSLog("ServiceDiscovery: unexpected remote on udp")
                        return
                }

                NSLog("ServiceDiscovery: received \(address)")

                guard let data = content?.base64EncodedString() else {
                    NSLog("ServiceDiscovery: no data")
                    return
                }

                DispatchQueue.main.async {
                    let message = UdpMessage(address: address, data: data)
                    self.networkingListener.onUdpMessage(message: message)
                }
            }

            group.stateUpdateHandler = { (newState) in
                NSLog("ServiceDiscovery: group entered state \(String(describing: newState))")
            }

            group.start(queue: .main)
            
            self.group = group
            
            NSLog("ServiceDiscovery: simple udp running")
        }
    }
    
    public func stop() {
        guard let g = self.group else { return }
        g.cancel()
        self.group = nil
    }
}

@objc
open class ServiceDiscovery : NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var networkingListener: NetworkingListener
    var browser: NetServiceBrowser
    var pending: NetService?
    var simple: SimpleUDP?
    var ourselves: NetService?
    
    @objc
    init(networkingListener: NetworkingListener) {
        self.networkingListener = networkingListener
        self.browser = NetServiceBrowser()
        super.init()
    }
    
    @objc
    public func start(serviceTypeSearch: String, serviceNameSelf: String?, serviceTypeSelf: String?) {
        NSLog("ServiceDiscovery::starting");
        NSLog(serviceTypeSearch);
        pending = nil
        browser.delegate = self
        browser.stop()
        browser.searchForServices(ofType: serviceTypeSearch, inDomain: "local.")
        
        if ourselves == nil && serviceNameSelf != nil && serviceTypeSelf != nil {
            ourselves = NetService(domain: "local", type: serviceTypeSelf!, name: serviceNameSelf!, port: 80)
            ourselves!.delegate = self
            ourselves!.publish()
        }
        
        if #available(iOS 14.00, *) {
            if simple == nil {
                simple = LatestSimpleUDP(networkingListener: self.networkingListener)
                simple!.start()
            }
        }
    }
    
    @objc
    public func stop() {
        browser.stop()
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
        
        networkingListener.onStarted()
    }
    
    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        NSLog("ServiceDiscovery::netServiceBrowserDidStopSearch");
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        NSLog("ServiceDiscovery::didNotSearch");
        for (key, code) in errorDict {
            NSLog("ServiceDiscovery::didNotSearch(Errors): %@ = %@", key, code);
        }
        networkingListener.onDiscoveryFailed()
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
