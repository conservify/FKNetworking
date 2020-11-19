import Foundation
import Network
import os

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
        self.wifi = WifiManager(networkingListener: networkingListener)
        NSLog("Networking::new")
        super.init()
    }
}
