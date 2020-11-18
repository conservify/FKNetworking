import Foundation
import Network
import SystemConfiguration

@available(iOS 14.00, *)
class MulticastUDP : SimpleListener {
    private var networkingListener: NetworkingListener
    private var group: NWConnectionGroup?;
    private var monitor: NWPathMonitor?

    init(networkingListener: NetworkingListener) {
        self.networkingListener = networkingListener
    }

    public func start() {
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

        NSLog("ServiceDiscovery::udp starting");
        
        DispatchQueue.global(qos: .background).async {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(UdpMulticastGroup),
                                               port: NWEndpoint.Port(rawValue: UInt16(UdpPort))!)
            
            guard let multicast = try? NWMulticastGroup(for: [endpoint]) else {
                NSLog("ServiceDiscovery::udp error creating group (FATAL)")
                return
            }
            
            let group = NWConnectionGroup(with: multicast, using: .udp)
            group.setReceiveHandler(maximumMessageSize: 1024, rejectOversizedMessages: true) { (message, content, isComplete) in
                var address = ""
                switch(message.remoteEndpoint) {
                    case .hostPort(let host, _):
                        address = "\(host)"
                    default:
                        NSLog("ServiceDiscovery::udp unexpected remote")
                        return
                }

                NSLog("ServiceDiscovery::udp received \(address)")

                guard let data = content?.base64EncodedString() else {
                    NSLog("ServiceDiscovery::udp empty")
                    return
                }

                DispatchQueue.main.async {
                    let message = UdpMessage(address: address, data: data)
                    self.networkingListener.onUdpMessage(message: message)
                }
            }

            group.stateUpdateHandler = { (newState) in
                NSLog("ServiceDiscovery::udp group entered state \(String(describing: newState))")
            }
            
            self.group = group

            group.start(queue: .main)

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


