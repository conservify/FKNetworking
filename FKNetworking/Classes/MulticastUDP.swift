import Foundation
import Network
import SystemConfiguration

@available(iOS 14.00, *)
class MulticastUDP : SimpleListener {
    private var networkingListener: NetworkingListener
    private var group: NWConnectionGroup?;
    private var monitor: NWPathMonitor?
    private var pending: DispatchGroup?
    
    init(networkingListener: NetworkingListener) {
        self.networkingListener = networkingListener
    }
    
    public func start(lock: DispatchGroup) {
        NSLog("ServiceDiscovery::monitor starting")
        
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { path in
            NSLog("ServiceDiscovery::path-updated: \(String(describing: path))")
            
            if let ifaces = self.monitor?.currentPath.availableInterfaces {
                for iface in ifaces {
                    NSLog("ServiceDiscovery::iface \(String(describing: iface))")
                }
            }
        }
        
        self.monitor?.start(queue: .main)
        
        NSLog("ServiceDiscovery::udp group starting");
        
        lock.enter()
        
        pending = lock
        
        DispatchQueue.global(qos: .background).async {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(UdpMulticastGroup),
                                               port: NWEndpoint.Port(rawValue: UInt16(UdpPort))!)
            
            guard let multicast = try? NWMulticastGroup(for: [endpoint]) else {
                NSLog("ServiceDiscovery::udp group error creating (FATAL)")
                lock.leave()
                return
            }
            
            let group = NWConnectionGroup(with: multicast, using: .udp)
            
            group.stateUpdateHandler = self.stateChange
            
            group.setReceiveHandler(maximumMessageSize: 1024, rejectOversizedMessages: true) { (message, content, isComplete) in
                var address = ""
                switch(message.remoteEndpoint) {
                case .hostPort(let host, _):
                    address = "\(host)"
                default:
                    NSLog("ServiceDiscovery::udp msg unexpected remote")
                    return
                }
                
                NSLog("ServiceDiscovery::udp msg received \(address)")
                
                guard let data = content?.base64EncodedString() else {
                    NSLog("ServiceDiscovery::udp msg empty")
                    return
                }
                
                DispatchQueue.main.async {
                    let message = UdpMessage(address: address, data: data)
                    self.networkingListener.onUdpMessage(message: message)
                }
            }
            
            self.group = group
            
            group.start(queue: .main)
            
            NSLog("ServiceDiscovery::udp group started")
        }
    }
    
    public func stop(lock: DispatchGroup) {
        if let m = self.monitor {
            NSLog("ServiceDiscovery::monitor stopping")
            m.cancel()
            monitor = nil
        }
        else {
            NSLog("ServiceDiscovery::monitor already stopped")
        }
        
        if let g = self.group {
            NSLog("ServiceDiscovery::udp group stopping")
            
            lock.enter()
            
            pending = lock
            
            g.cancel()
            self.group = nil
        }
        else {
            NSLog("ServiceDiscovery::udp group was stopped")
        }
    }
    
    private func stateChange(newState: NWConnectionGroup.State) {
        NSLog("ServiceDiscovery::udp group entered state \(String(describing: newState))")
        
        switch newState {
        case .cancelled:
            if let l = pending {
                l.leave()
            }
        case .failed:
            if let l = pending {
                l.leave()
            }
        case .ready:
            if let l = pending {
                l.leave()
            }
        default:
            break
        }
    }
}


