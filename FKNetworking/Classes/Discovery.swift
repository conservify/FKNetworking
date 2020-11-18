//
//  Discovery.swift
//  AFNetworking
//
//  Created by Jacob Lewallen on 10/30/19.
//

import Foundation
import Network
import SystemConfiguration

let UdpMulticastGroup = "224.1.2.3";
let UdpPort = 22143;
let DefaultLocalDomain = "local."

protocol SimpleUDP {
    func start();
    func stop();
}

@available(iOS 14.00, *)
class LatestSimpleUDP : SimpleUDP {
    private var networkingListener: NetworkingListener
    private var group: NWConnectionGroup?;
    var monitor: NWPathMonitor?

    init(networkingListener: NetworkingListener) {
        self.networkingListener = networkingListener
    }

    public func start() {
        NSLog("ServiceDiscovery::listening udp");
        
        monitor = NWPathMonitor()

        monitor?.pathUpdateHandler = { path in
            NSLog("ServiceDiscovery::path-updated: \(String(describing: path))")
            
            if let ifaces = self.monitor?.currentPath.availableInterfaces {
                for iface in ifaces {
                    NSLog("ServiceDiscovery::iface \(String(describing: iface))")
                }
            }
        }
        
        /*
        for interface in SCNetworkInterfaceCopyAll() as NSArray {
            if let name = SCNetworkInterfaceGetBSDName(interface as! SCNetworkInterface),
               let type = SCNetworkInterfaceGetInterfaceType(interface as! SCNetworkInterface) {
                
            }
        }
        */
        
        DispatchQueue.global(qos: .background).async {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(UdpMulticastGroup),
                                               port: NWEndpoint.Port(rawValue: UInt16(UdpPort))!)
            
            guard let multicast = try? NWMulticastGroup(for: [endpoint]) else {
                NSLog("ServiceDiscovery::error creating group (FATAL)")
                return
            }
            
            let group = NWConnectionGroup(with: multicast, using: .udp)
            group.setReceiveHandler(maximumMessageSize: 1024, rejectOversizedMessages: true) { (message, content, isComplete) in
                var address = ""
                switch(message.remoteEndpoint) {
                    case .hostPort(let host, _):
                        address = "\(host)"
                    default:
                        NSLog("ServiceDiscovery::unexpected remote on udp")
                        return
                }

                NSLog("ServiceDiscovery::received \(address)")

                guard let data = content?.base64EncodedString() else {
                    NSLog("ServiceDiscovery::no data")
                    return
                }

                DispatchQueue.main.async {
                    let message = UdpMessage(address: address, data: data)
                    self.networkingListener.onUdpMessage(message: message)
                }
            }

            group.stateUpdateHandler = { (newState) in
                NSLog("ServiceDiscovery::group entered state \(String(describing: newState))")
            }
            
            group.start(queue: .main)
            
            self.monitor?.start(queue: .main)

            self.group = group

            NSLog("ServiceDiscovery::udp running")
        }
    }

    public func stop() {
        NSLog("ServiceDiscovery::stopping")
        if monitor != nil {
            monitor?.cancel()
            monitor = nil
        }
        guard let g = self.group else { return }
        g.cancel()
        self.group = nil
        NSLog("ServiceDiscovery::stopped")
    }
}

@objc
open class DiscoveryStartOptions : NSObject {
    @objc public var serviceTypeSearch: String? = nil
    @objc public var serviceNameSelf: String? = nil
    @objc public var serviceTypeSelf: String? = nil
}

@objc
open class DiscoveryStopOptions : NSObject {
    @objc public var suspending: Bool = false
}

@objc
open class ServiceDiscovery : NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var networkingListener: NetworkingListener
    var browser: NetServiceBrowser
    var pending: NetService?
    var simple: SimpleUDP?
    var ourselves: NetService?
    var appDelegate: AppDelegate

    @objc
    init(networkingListener: NetworkingListener) {
        self.networkingListener = networkingListener
        self.browser = NetServiceBrowser()
        self.appDelegate = AppDelegate()
        UIApplication.shared.delegate = appDelegate
        super.init()
    }

    @objc
    public func start(options: DiscoveryStartOptions) {
        NSLog("ServiceDiscovery::starting");
        
        // Clear any pending resolve. Allows them to be freed, as well.
        pending = nil
        
        // If given a type to search for, start listening.
        if let name = options.serviceTypeSearch {
            NSLog("ServiceDiscovery::searching: %@", name);
            browser.delegate = self
            browser.stop()
            browser.searchForServices(ofType: name, inDomain: DefaultLocalDomain)
        }
        
        if let nameSelf = options.serviceNameSelf,
           let typeSelf = options.serviceTypeSelf {
            if ourselves == nil {
                NSLog("ServiceDiscovery::registering self: name=%@ type=%@", nameSelf, typeSelf)
                ourselves = NetService(domain: DefaultLocalDomain, type: typeSelf, name: nameSelf, port: Int32(UdpPort))
                ourselves!.delegate = self
                ourselves!.publish()
            }
            else {
                NSLog("ServiceDiscovery::already registered")
            }
        }
        else {
            NSLog("ServiceDiscovery::NOT registering self")
        }

        if #available(iOS 14.00, *) {
            if simple == nil {
                NSLog("ServiceDiscovery::starting udp")
                simple = LatestSimpleUDP(networkingListener: self.networkingListener)
                simple?.start()
            }
            else {
                NSLog("ServiceDiscovery::udp already running")
            }
        }
        else {
            NSLog("ServiceDiscovery:udp unavailable")
        }
        
        NSLog("ServiceDiscovery::started, waiting");
    }

    @objc
    public func stop(options: DiscoveryStopOptions) {
        NSLog("ServiceDiscovery::stopping")
        
        // We call this no matter what, now even if we never registered.
        browser.stop()
        
        if #available(iOS 14.00, *) {
            if !options.suspending && simple != nil {
                simple?.stop()
                simple = nil
            }
        }
        
        NSLog("ServiceDiscovery::stopped")
        networkingListener.onStopped()
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        NSLog("ServiceDiscovery::didNotPublish: %@", sender.name)
        NSLog("ServiceDiscovery::didNotPublish: %@", errorDict)
    }

    public func netServiceWillPublish(_ sender: NetService) {
        NSLog("ServiceDiscovery::netServiceWillPublish");
    }

    public func netServiceDidPublish(_ sender: NetService) {
        NSLog("ServiceDiscovery::netServiceDidPublish");
    }

    public func netServiceWillResolve(_ sender: NetService) {
        NSLog("ServiceDiscovery::netServiceWillResolve");
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        NSLog("ServiceDiscovery::netServiceDidResolveAddress %@ %@", sender.name, sender.hostName ?? "<none>");

        if let serviceIp = resolveIPv4(addresses: sender.addresses!) {
            NSLog("ServiceDiscovery::Found IPV4: %@", serviceIp)
            networkingListener.onFoundService(service: ServiceInfo(type: sender.type, name: sender.name, host: serviceIp, port: sender.port))
        }
        else {
            NSLog("ServiceDiscovery::No ipv4")
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
