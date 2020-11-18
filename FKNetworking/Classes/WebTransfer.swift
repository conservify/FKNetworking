import Foundation

var tokens: UInt64 = 0

func newToken() -> String {
    tokens += 1
    return "cfynw-\(tokens)"
}

@objc
open class WebTransfer : NSObject {
    @objc public var id: String = newToken()
    @objc public var method: String? = nil
    @objc public var url: String? = nil
    @objc public var path: String? = nil
    @objc public var body: String? = nil
    @objc public var uploadCopy: Bool = false
    @objc public var base64DecodeRequestBody: Bool = false
    @objc public var base64EncodeResponseBody: Bool = false
    @objc public var contentType: String? = nil
    @objc public var headers: [String: String] = [String:String]()
    
    @objc public func header(key: String, value: String) -> WebTransfer {
        headers[key] = value
        return self
    }
    
    @objc public var methodOrDefault: String {
        return method ?? "GET"
    }
    
    @objc public var isGET: Bool {
        return methodOrDefault == "GET"
    }
}

