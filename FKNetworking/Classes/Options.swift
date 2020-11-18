import Foundation

let UdpMulticastGroup = "224.1.2.3";
let UdpPort = 22143;
let DefaultLocalDomain = "local."

@objc
open class DiscoveryStartOptions : NSObject {
    @objc public var serviceTypeSearch: String? = nil
    @objc public var serviceNameSelf: String? = nil
    @objc public var serviceTypeSelf: String? = nil
}

@objc
open class DiscoveryStopOptions : NSObject {
    @objc public var suspending: Bool = false
    @objc public var mdns: Bool = true
    @objc public var dns: Bool = true
}


