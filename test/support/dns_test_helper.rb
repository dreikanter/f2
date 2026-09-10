module DnsTestHelper
  # Any public IP works: WebMock intercepts HTTP requests before a connection is made.
  PUBLIC_TEST_IP = "93.184.216.34".freeze

  def stub_dns(records = {}, &block)
    resolver = ->(host, *) { [[nil, nil, nil, records.fetch(host, PUBLIC_TEST_IP)]] }
    Socket.stub(:getaddrinfo, resolver, &block)
  end
end
