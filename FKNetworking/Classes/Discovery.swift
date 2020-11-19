import Foundation
import Network
import SystemConfiguration

@objc
open class ServiceDiscovery : NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private var networkingListener: NetworkingListener
    private var browser: NetServiceBrowser
    private var appDelegate: AppDelegate
    private var pending: NetService?
    private var searching: Bool = false
    private var udpGroup: SimpleListener?
    private var ourselves: NetService?
    
    private var lock: NSLock
    private var startingLock: DispatchGroup?
    private var stoppingLock: DispatchGroup?

    @objc
    init(networkingListener: NetworkingListener) {
        self.networkingListener = networkingListener
        self.browser = NetServiceBrowser()
        self.appDelegate = AppDelegate()
        self.lock = NSLock()
        super.init()
        
        UIApplication.shared.delegate = appDelegate
    }

    @objc
    public func start(options: DiscoveryStartOptions) {
        NSLog("ServiceDiscovery::starting (acquire)");

        lock.lock()
        
        NSLog("ServiceDiscovery::starting");

        startingLock = DispatchGroup()
        
        // Clear any pending resolve. Allows them to be freed, as well.
        pending = nil
        
        // If given a type to search for, start listening.
        if let name = options.serviceTypeSearch {
            NSLog("ServiceDiscovery::searching %@", name);
            startingLock?.enter()
            browser.delegate = self
            browser.stop()
            browser.searchForServices(ofType: name, inDomain: DefaultLocalDomain)
            searching = true
        }
        
        if let nameSelf = options.serviceNameSelf,
           let typeSelf = options.serviceTypeSelf {
            if ourselves == nil {
                NSLog("ServiceDiscovery::publishing self: name=%@ type=%@", nameSelf, typeSelf)
                startingLock?.enter()
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
                udpGroup = MulticastUDP(networkingListener: self.networkingListener)
                udpGroup?.start(lock: startingLock!)
            }
            else {
                NSLog("ServiceDiscovery::udp already running")
            }
        }
        else {
            NSLog("ServiceDiscovery:udp unavailable")
        }
        
        startingLock?.notify(queue: .main) {
            NSLog("ServiceDiscovery::started")
            self.networkingListener.onStarted()
            self.lock.unlock()
        }
    }

    @objc
    public func stop(options: DiscoveryStopOptions) {
        NSLog("ServiceDiscovery::stopping (acquire)");

        lock.lock()
        
        NSLog("ServiceDiscovery::stopping")
        
        stoppingLock = DispatchGroup()
        
        if options.mdns {
            if (searching) {
                NSLog("ServiceDiscovery::searching stop")
                searching = false
                stoppingLock?.enter()
                browser.stop()
            }
            else {
                NSLog("ServiceDiscovery::searching already stopped")
            }
            
            // This is optional.
            if ourselves != nil {
                stoppingLock?.enter()
                NSLog("ServiceDiscovery::publishing stop")
                ourselves?.stop()
                ourselves = nil
            }
            else {
                NSLog("ServiceDiscovery::publishing already stopped")
            }
        }
        
        if options.dns {
            if #available(iOS 14.00, *) {
                if udpGroup != nil {
                    if !options.suspending {
                        udpGroup?.stop(lock: stoppingLock!)
                        udpGroup = nil
                    }
                    else {
                        NSLog("ServiceDiscovery::udp staying running")
                    }
                }
                else {
                    NSLog("ServiceDiscovery::udp already stopped")
                }
            }
            else {
                NSLog("ServiceDiscovery::udp unavailable")
            }
        }

        stoppingLock?.notify(queue: .main) {
            NSLog("ServiceDiscovery::stopped")
            self.networkingListener.onStopped()
            self.lock.unlock()
        }
    }

    public func netServiceWillPublish(_ sender: NetService) {
        NSLog("ServiceDiscovery::netServiceWillPublish");
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        NSLog("ServiceDiscovery::didNotPublish: %@", sender.name)
        NSLog("ServiceDiscovery::didNotPublish: %@", errorDict)
        startingLock?.leave() // TODO Indicate error?
    }

    public func netServiceDidPublish(_ sender: NetService) {
        NSLog("ServiceDiscovery::netServiceDidPublish");
        startingLock?.leave()
    }

    public func netServiceWillResolve(_ sender: NetService) {
        NSLog("ServiceDiscovery::netServiceWillResolve");
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        NSLog("ServiceDiscovery::netServiceDidResolveAddress %@ %@", sender.name, sender.hostName ?? "<none>");

        if let serviceIp = resolveIPv4(addresses: sender.addresses!) {
            NSLog("ServiceDiscovery::found IPV4: %@", serviceIp)
            networkingListener.onFoundService(service: ServiceInfo(type: sender.type, name: sender.name, host: serviceIp, port: sender.port))
        }
        else {
            NSLog("ServiceDiscovery::no ipv4")
        }
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        NSLog("ServiceDiscovery::didNotResolve");
    }

    public func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        NSLog("ServiceDiscovery::willSearch")
        self.startingLock?.leave()
    }

    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        NSLog("ServiceDiscovery::netServiceBrowserDidStopSearch");
        self.stoppingLock?.leave()
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        NSLog("ServiceDiscovery::didNotSearch");
        for (key, code) in errorDict {
            NSLog("ServiceDiscovery::didNotSearch(Errors): %@ = %@", key, code);
        }
        // TODO Consolidate failure with didNotPublish
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
