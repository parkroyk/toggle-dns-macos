import Testing
@testable import ToggleDNS

@Suite("DNSEngine.parseDNSServers")
struct DNSEngineParserTests {
    @Test func dhcpNoticeOldWordingYieldsNoServers() {
        #expect(DNSEngine.parseDNSServers("There aren't any DNS servers set\n") == [])
    }

    @Test func dhcpNoticeNewWordingYieldsNoServers() {
        // macOS 26+ wording: capital "Servers" and a service-name suffix.
        let output = "There aren't any DNS Servers set on Ethernet.\n"
        #expect(DNSEngine.parseDNSServers(output) == [])
    }

    @Test func ipv4ServersAreKept() {
        let output = "1.1.1.1\n8.8.8.8\n"
        #expect(DNSEngine.parseDNSServers(output) == ["1.1.1.1", "8.8.8.8"])
    }

    @Test func ipv6ServersAreKept() {
        let output = "2001:4860:4860::8888\n2606:4700:4700::1111\n"
        #expect(DNSEngine.parseDNSServers(output) == ["2001:4860:4860::8888", "2606:4700:4700::1111"])
    }

    @Test func hostnameServersAreKept() {
        #expect(DNSEngine.parseDNSServers("dns.example.com\n") == ["dns.example.com"])
    }

    @Test func emptyOutputYieldsNoServers() {
        #expect(DNSEngine.parseDNSServers("") == [])
    }

    @Test func noticeLineMixedWithServersIsDropped() {
        let output = "1.1.1.1\nThere aren't any DNS Servers set on Wi-Fi.\n9.9.9.9\n"
        #expect(DNSEngine.parseDNSServers(output) == ["1.1.1.1", "9.9.9.9"])
    }
}
