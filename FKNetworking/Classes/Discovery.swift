import Foundation
import Network
import SystemConfiguration

@objc
open class ServiceDiscovery : NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var networkingListener: NetworkingListener
    var browser: NetServiceBrowser
    var pending: NetService?
    var udpGroup: SimpleListener?
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
            NSLog("ServiceDiscovery::searching %@", name);
            browser.delegate = self
            browser.stop()
            browser.searchForServices(ofType: name, inDomain: DefaultLocalDomain)
        }
        
        if let nameSelf = options.serviceNameSelf,
           let typeSelf = options.serviceTypeSelf {
            if ourselves == nil {
                NSLog("ServiceDiscovery::publishing self: name=%@ type=%@", nameSelf, typeSelf)
                ourselves = NetService(domain: DefaultLocalDomain, type: typeSelf, name: nameSelf, port: Int32(UdpPort))
                ourselves!.delegate = self
                ourselves!.publish()
            }
            else {
                NSLog("ServiceDiscovery::publishing already registered")
            }
        }
        else {
            NSLog("ServiceDiscovery::publishing disabled")
        }

        if #available(iOS 14.00, *) {
            if udpGroup == nil {
                NSLog("ServiceDiscovery::udp starting")
                udpGroup = MulticastUDP(networkingListener: self.networkingListener)
                udpGroup?.start()
            }
            else {
                NSLog("ServiceDiscovery::udp already running")
            }
        }
        else {
            NSLog("ServiceDiscovery:udp unavailable")
        }
        
        NSLog("ServiceDiscovery::started");
    }

    @objc
    public func stop(options: DiscoveryStopOptions) {
        NSLog("ServiceDiscovery::stopping")
        
        if options.mdns {
            // We call this no matter what, now even if we never registered.
            NSLog("ServiceDiscovery(stop)::searching stopping")
            browser.stop()
            
            // This is optional.
            if ourselves != nil {
                NSLog("ServiceDiscovery(stop)::publishing stop")
                ourselves?.stop()
                ourselves = nil
            }
            else {
                NSLog("ServiceDiscovery(stop)::publishing disabled")
            }
        }
        
        if options.dns {
            if #available(iOS 14.00, *) {
                if udpGroup != nil {
                    if !options.suspending {
                        NSLog("ServiceDiscovery(stop)::udp stopping")
                        udpGroup?.stop()
                        udpGroup = nil
                    }
                    else {
                        NSLog("ServiceDiscovery(stop)::udp staying running")
                    }
                }
            }
            else {
                NSLog("ServiceDiscovery(stop)::udp unavailable")
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
