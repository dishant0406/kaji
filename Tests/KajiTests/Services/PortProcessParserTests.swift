import Testing

@testable import Kaji

struct PortProcessParserTests {
    @Test
    func parsesIPv4ListeningPort() {
        let output = """
        COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    12345 user   20u  IPv4 0x123456789abcdef      0t0  TCP 127.0.0.1:3000 (LISTEN)
        """

        let ports = PortProcessParser.parse(output)

        #expect(ports == [PortProcessSnapshot(
            protocolName: "TCP",
            address: "127.0.0.1",
            port: 3000,
            pid: 12345,
            processName: "node"
        )])
    }

    @Test
    func parsesIPv6WildcardPort() {
        let output = """
        COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        Python  45678 user   10u  IPv6 0x123456789abcdef      0t0  TCP *:8000 (LISTEN)
        """

        let ports = PortProcessParser.parse(output)

        #expect(ports.first?.address == "*")
        #expect(ports.first?.port == 8000)
        #expect(ports.first?.processName == "Python")
    }

    @Test
    func skipsNonListeningAndMalformedRows() {
        let output = """
        COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    12345 user   20u  IPv4 0x123456789abcdef      0t0  TCP 127.0.0.1:3000->127.0.0.1:4000 (ESTABLISHED)
        broken row
        ruby    55555 user   12u  IPv4 0x123456789abcdef      0t0  TCP localhost:http-alt (LISTEN)
        """

        #expect(PortProcessParser.parse(output).isEmpty)
    }

    @Test
    func deduplicatesAndSortsRows() {
        let output = """
        COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    30000 user   20u  IPv4 0x123456789abcdef      0t0  TCP *:5173 (LISTEN)
        node    30000 user   20u  IPv4 0x123456789abcdef      0t0  TCP *:5173 (LISTEN)
        ruby    20000 user   21u  IPv4 0x123456789abcdef      0t0  TCP 127.0.0.1:3000 (LISTEN)
        """

        let ports = PortProcessParser.parse(output)

        #expect(ports.map(\.port) == [3000, 5173])
        #expect(ports.count == 2)
    }
}
