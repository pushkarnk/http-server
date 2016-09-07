import Foundation
import Dispatch
import Glibc

struct HTTPUtils {
    static let CRLF = "\r\n"
    static let VERSION = "HTTP/1.1"
    static let SPACE = " "
    static let CRLF2 = CRLF + CRLF
    static let EMPTY = ""
}

class TCPSocket {
  
    private var listenSocket: Int32!
    private var socketAddress = UnsafeMutablePointer<sockaddr_in>.allocate(capacity: 1) 
    private var connectionSocket: Int32!
    
    private func isNotNegative(r: CInt) -> Bool {
        return r != -1
    }

    private func isZero(r: CInt) -> Bool {
        return r == 0
    }

    private func attempt(_ name: String, file: String = #file, line: UInt = #line, valid: (CInt) -> Bool,  _ b: @autoclosure () -> CInt) throws -> CInt {
        let r = b()
        guard valid(r) else { throw ServerError(operation: name, errno: r, file: file, line: line) }
        return r
    }

    init(port: UInt16) throws {
        listenSocket = try attempt("socket", valid: isNotNegative, socket(AF_INET, Int32(SOCK_STREAM.rawValue), Int32(IPPROTO_TCP))) 
        var on: Int = 1
        _ = try attempt("setsockopt", valid: isZero, setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int>.size)))
        let sa = sockaddr_in(sin_family: sa_family_t(AF_INET), sin_port: htons(port), sin_addr: in_addr(s_addr: INADDR_ANY), sin_zero: (0,0,0,0,0,0,0,0))
        socketAddress.initialize(to: sa)
        try socketAddress.withMemoryRebound(to: sockaddr.self, capacity: MemoryLayout<sockaddr>.size, { 
            let addr = UnsafePointer<sockaddr>($0)
            _ = try attempt("bind", valid: isZero, bind(listenSocket, addr, socklen_t(MemoryLayout<sockaddr>.size)))
        })
    }

    func acceptConnection() throws {
        _ = try attempt("listen", valid: isZero, listen(listenSocket, SOMAXCONN))
        try socketAddress.withMemoryRebound(to: sockaddr.self, capacity: MemoryLayout<sockaddr>.size, {
            let addr = UnsafeMutablePointer<sockaddr>($0)
            var sockLen = socklen_t(MemoryLayout<sockaddr>.size) 
            connectionSocket = try attempt("accept", valid: isNotNegative, accept(listenSocket, addr, &sockLen))
        })
    }
 
    func readData() throws -> String {
        var buffer = [UInt8](repeating: 0, count: 4096)
        _ = try attempt("read", valid: isNotNegative, CInt(read(connectionSocket, &buffer, 4096)))
        return String(cString: &buffer)
    }
   
    func writeData(data: String) throws {
        var bytes = Array(data.utf8)
        _  = try attempt("write", valid: isNotNegative, CInt(write(connectionSocket, &bytes, data.utf8.count))) 
    }

    func shutdown() {
        close(connectionSocket)
        close(listenSocket)
    }
}

class HTTPServer {

    let socket: TCPSocket 
    
    init(port: UInt16) throws {
        socket = try TCPSocket(port: port)
    }

    public class func create(port: UInt16) throws -> HTTPServer {
        return try HTTPServer(port: port)
    }

    public func listen() throws {
        try socket.acceptConnection()
    }

    public func stop() {
        socket.shutdown()
    }
   
    public func request() throws -> HTTPRequest {
       return HTTPRequest(request: try socket.readData()) 
    }

    public func respond(with response: HTTPResponse) throws {
        try socket.writeData(data: response.description)
    } 
}

struct HTTPRequest {
    enum Method : String {
        case GET
        case POST
        case PUT
    }
    let method: Method
    let uri: String 
    let body: String
    let headers: [String]

    public init(request: String) {
        let lines = request.components(separatedBy: HTTPUtils.CRLF2)[0].components(separatedBy: HTTPUtils.CRLF)
        headers = Array(lines[0...lines.count-2])
        method = Method(rawValue: headers[0].components(separatedBy: " ")[0])!
        uri = headers[0].components(separatedBy: " ")[1]
        body = lines.last!
    }

}

struct HTTPResponse {
    enum Response : Int {
        case OK = 200
    }
    private let responseCode: Response
    private let headers: String
    private let body: String

    public init(response: Response, headers: String = HTTPUtils.EMPTY, body: String) {
        self.responseCode = response
        self.headers = headers
        self.body = body
    }
   
    public var description: String {
        let statusLine = HTTPUtils.VERSION + HTTPUtils.SPACE + "\(responseCode.rawValue)" + HTTPUtils.SPACE + "\(responseCode)"
        return statusLine + (headers != HTTPUtils.EMPTY ? HTTPUtils.CRLF + headers : HTTPUtils.EMPTY) + HTTPUtils.CRLF2 + body
    }
}

public class TestURLSessionServer {
    var capitals: [String:String] = ["Nepal":"Kathmandu", "Peru":"Lima", "Italy":"Rome", "USA":"Washington, D.C", "hello.txt":"This is sample content"]

    let httpServer: HTTPServer
    
    public init (port: UInt16) throws {
        httpServer = try HTTPServer.create(port: port)
    }
    public func start(started: DispatchSemaphore) throws {
        started.signal()
        try httpServer.listen()
    }
   
    public func readAndRespond() throws {
        try httpServer.respond(with: process(request: httpServer.request()))
    } 

    func process(request: HTTPRequest) -> HTTPResponse {
        if request.method == .GET {
            return getResponse(uri: request.uri)
        } else {
            fatalError("Unsupported method!")
        }
    }

    func getResponse(uri: String) -> HTTPResponse {
        if uri == "/hello.txt" {
            let text = capitals[String(uri.characters.dropFirst())]!
            return HTTPResponse(response: .OK, headers: "Content-Length: \(text.characters.count)", body: text)
        }
        return HTTPResponse(response: .OK, body: capitals[String(uri.characters.dropFirst())]!) 
    }

    func stop() {
        httpServer.stop()
    }
}

struct ServerError : Error {
    let operation: String
    let errno: CInt
    let file: String
    let line: UInt
    var _code: Int { return Int(errno) }
    var _domain: String { return NSPOSIXErrorDomain }
}


extension ServerError : CustomStringConvertible {
    var description: String {
        let s = String(validatingUTF8: strerror(errno)) ?? ""
        return "\(operation) failed: \(s) (\(_code))"
    }
}

