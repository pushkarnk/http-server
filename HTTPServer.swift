import Foundation
import Glibc

class TCPSocket {
  
    private let listenSocket: Int32
    private var socketAddress = UnsafeMutablePointer<sockaddr_in>.allocate(capacity: 1) 
    private var connectionSocket: Int32!

    //start 
    public init?() {
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

    //accept connection
    public func acceptConnection() {
        listen(listenSocket, SOMAXCONN)
        socketAddress.withMemoryRebound(to: sockaddr.self, capacity: MemoryLayout<sockaddr>.size, {
            let addr = UnsafeMutablePointer<sockaddr>($0)
            var sockLen = socklen_t(MemoryLayout<sockaddr>.size) 
            print("Waiting ...")
            connectionSocket = accept(listenSocket, addr, &sockLen)
        })
        print("connection accepted")
    }
 
    //read from socket
    public func readData() -> String?{
        var buffer = [UInt8](repeating: 0, count: 2048)
        let n = read(connectionSocket, &buffer, 2048)
        if n <= 0 {
            return nil
        }
        return String(cString: &buffer)
    }
   
    //write to socket 
    public func writeData(data: String) {
        var bytes = Array(data.utf8)
        write(connectionSocket, &bytes, data.utf8.count) 
    }

    //shutdown
    public func shutdown() {
        close(connectionSocket)
        close(listenSocket)
    }
}

if let tcpSocket = TCPSocket() {
    tcpSocket.acceptConnection()
    print(tcpSocket.readData())
    tcpSocket.writeData(data: "HTTP/1.1 200 OK\r\n\r\nHello\r\n")
    tcpSocket.shutdown()
}
