import Foundation
import Network

protocol SimpleListener {
    func start(lock: DispatchGroup);
    func stop(lock: DispatchGroup);
}

class NoopSimpleListener : SimpleListener {
    public func start(lock: DispatchGroup) {
    }
    
    public func stop(lock: DispatchGroup) {
    }
}
