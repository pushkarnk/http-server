import Foundation
import Glibc

struct HTTPUtils {
    static let CRLF = "\r\n"
    static let VERSION = "HTTP/1.1"
    static let SPACE = " "
    static let CRLF2 = CRLF + CRLF
}

class TCPSocket {
  
    private let listenSocket: Int32
    private var socketAddress = UnsafeMutablePointer<sockaddr_in>.allocate(capacity: 1) 
    private var connectionSocket: Int32!

    init?() {
        listenSocket = socket(AF_INET, Int32(SOCK_STREAM.rawValue), Int32(IPPROTO_TCP))
        var on: Int = 1
        setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int>.size))
        guard listenSocket > 0 else { return nil }
        let sa = sockaddr_in(sin_family: sa_family_t(AF_INET), sin_port: htons(21961), sin_addr: in_addr(s_addr: INADDR_ANY), sin_zero: (0,0,0,0,0,0,0,0))
        socketAddress.initialize(to: sa)
        socketAddress.withMemoryRebound(to: sockaddr.self, capacity: MemoryLayout<sockaddr>.size, { 
            let addr = UnsafePointer<sockaddr>($0)
            bind(listenSocket, addr, socklen_t(MemoryLayout<sockaddr>.size))
        })
    }

    func acceptConnection() {
        listen(listenSocket, SOMAXCONN)
        socketAddress.withMemoryRebound(to: sockaddr.self, capacity: MemoryLayout<sockaddr>.size, {
            let addr = UnsafeMutablePointer<sockaddr>($0)
            var sockLen = socklen_t(MemoryLayout<sockaddr>.size) 
            connectionSocket = accept(listenSocket, addr, &sockLen)
        })
    }
 
    func readData() -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = read(connectionSocket, &buffer, 4096)
        if n <= 0 {
            return nil
        }
        return String(cString: &buffer)
    }
   
    func writeData(data: String) {
        var bytes = Array(data.utf8)
        write(connectionSocket, &bytes, data.utf8.count) 
    }

    func shutdown() {
        close(connectionSocket)
        close(listenSocket)
    }
}

class HTTPServer {

    let socket: TCPSocket 
    
    init?() {
        if let s = TCPSocket() {
            socket = s
        } else { return nil }
    }

    public class func create() -> HTTPServer? {
        return HTTPServer()
    }

    public func listen() {
        socket.acceptConnection()
    }

    public func stop() {
        socket.shutdown()
    }
   
    public func request() -> HTTPRequest {
       return HTTPRequest(request: socket.readData()!) 
    }

    public func respond(with response: HTTPResponse) {
        socket.writeData(data: response.description)
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

    public init(response: Response, headers: String = "", body: String) {
        self.responseCode = response
        self.headers = headers
        self.body = body
    }
   
    public var description: String {
        let statusLine = HTTPUtils.VERSION + HTTPUtils.SPACE + "\(responseCode.rawValue)" + HTTPUtils.SPACE + "\(responseCode)"
        return statusLine + HTTPUtils.CRLF2 + body
    }
}

class TestURLSessionServer {
    let capitals: [String:String] = ["Nepal":"Kathmandu", "Peru":"Lima", "Italy":"Rome", "USA":"Washington, D.C"]
    let httpServer: HTTPServer = HTTPServer.create()!

    public func start() {
        httpServer.listen()
    }
   
    public func readAndRespond() {
        httpServer.respond(with: process(request: httpServer.request()))
    } 

    func process(request: HTTPRequest) -> HTTPResponse {
        if request.method == .GET {
            return getResponse(uri: request.uri)
        } else {
            fatalError("Unsupported method!")
        }
    }

    func getResponse(uri: String) -> HTTPResponse {
        return HTTPResponse(response: .OK, body: capitals[String(uri.characters.dropFirst())]!) 
    }
}

let test = TestURLSessionServer()
test.start()
test.readAndRespond()
