import Foundation

public final class TemporaryFile {
    public let url: URL
    
    public init(beside besides: String, extension ext: String) {
        let besidesUrl = URL(fileURLWithPath: besides)
        let directory = besidesUrl.deletingLastPathComponent()
        
        url = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }
    
    func remove() {
        NSLog("deleting temporary")
        DispatchQueue.global(qos: .utility).async { [url = self.url] in
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    deinit {
        /*
         remove()
         */
    }
}
