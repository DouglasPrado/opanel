require "rails_helper"

# The adapter between the preflight and the operating system, tested where it
# meets the OS: the shell-outs are stood in for with the exact text the real
# tools produce, because that text is where the two defects this file guards
# against came from.
RSpec.describe SystemProbe, type: :unit do
  subject(:probe) { described_class.new }

  def answer(stdout, ok: true)
    status = instance_double(Process::Status, success?: ok)
    [ stdout, "", status ]
  end

  describe "#clock_synchronized? on macOS" do
    before { allow(probe).to receive(:operating_system).and_return("darwin") }

    # The regression that blocked a healthy machine. `systemsetup` exits 0 while
    # refusing, so success + "no On in the output" used to read as "not
    # synchronized". A refusal is an unknown, not a failing clock.
    it "answers unknown when systemsetup refuses without root, not false" do
      allow(Open3).to receive(:capture3).with("systemsetup", "-getusingnetworktime")
        .and_return(answer("You need administrator access to run this tool... exiting!\n"))

      expect(probe.clock_synchronized?).to be_nil
    end

    it "answers true when the tool says On" do
      allow(Open3).to receive(:capture3).with("systemsetup", "-getusingnetworktime")
        .and_return(answer("Network Time: On\n"))

      expect(probe.clock_synchronized?).to be(true)
    end

    it "answers false only when the tool says Off" do
      allow(Open3).to receive(:capture3).with("systemsetup", "-getusingnetworktime")
        .and_return(answer("Network Time: Off\n"))

      expect(probe.clock_synchronized?).to be(false)
    end

    it "answers unknown when the tool is absent" do
      allow(Open3).to receive(:capture3).with("systemsetup", "-getusingnetworktime")
        .and_raise(Errno::ENOENT)

      expect(probe.clock_synchronized?).to be_nil
    end
  end

  describe "#clock_synchronized? on Linux" do
    before { allow(probe).to receive(:operating_system).and_return("linux") }

    it "reads timedatectl's NTPSynchronized" do
      allow(Open3).to receive(:capture3).with("timedatectl", "show", "-p", "NTPSynchronized", "--value")
        .and_return(answer("yes\n"))

      expect(probe.clock_synchronized?).to be(true)
    end

    it "answers unknown when timedatectl fails" do
      allow(Open3).to receive(:capture3).with("timedatectl", "show", "-p", "NTPSynchronized", "--value")
        .and_return(answer("", ok: false))

      expect(probe.clock_synchronized?).to be_nil
    end
  end

  describe "disk measurements" do
    # The second regression: measuring `/` on macOS reported the sealed system
    # volume. The caller passes the Engine's data root; a path that is not on
    # this host is unmeasurable, and unmeasurable is nil — never "enough".
    it "refuses to measure a path that is not a directory here" do
      expect(probe.free_disk_bytes("/var/lib/docker-does-not-exist-here")).to be_nil
      expect(probe.free_inodes("/var/lib/docker-does-not-exist-here")).to be_nil
    end

    it "parses df's kilobytes and inodes for a real directory" do
      df = "Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted on\n" \
           "/dev/disk1 100000000 40000000 60000000 40% 1000 2000000 0% /\n"
      allow(Open3).to receive(:capture3).with("df", "-k", "-i", "/").and_return(answer(df))

      expect(probe.free_disk_bytes("/")).to eq(60_000_000 * 1024)
      expect(probe.free_inodes("/")).to eq(2_000_000)
    end

    it "answers nil rather than guessing when df's output is not the shape it knows" do
      allow(Open3).to receive(:capture3).with("df", "-k", "-i", "/").and_return(answer("garbage\n"))

      expect(probe.free_disk_bytes("/")).to be_nil
    end
  end

  describe "#port_free?" do
    it "sees a port something else holds" do
      server = TCPServer.new("0.0.0.0", 0)

      expect(probe.port_free?(server.addr[1])).to be(false)
    ensure
      server&.close
    end

    it "sees a UDP port something else holds" do
      socket = UDPSocket.new
      socket.bind("0.0.0.0", 0)

      expect(probe.port_free?(socket.addr[1], protocol: :udp)).to be(false)
    ensure
      socket&.close
    end
  end

  describe "#interfaces" do
    # nil, not []: "could not list" and "has none" are different answers and the
    # preflight treats them differently (unknown versus blocked).
    it "answers nil when the interfaces cannot be enumerated" do
      allow(Socket).to receive(:getifaddrs).and_raise(Errno::EACCES)

      expect(probe.interfaces).to be_nil
    end

    it "marks loopback as not advertisable and keeps the rest" do
      found = probe.interfaces

      expect(found).not_to be_nil
      expect(found.select(&:loopback?)).to all(satisfy { |i| !i.advertisable? })
    end
  end

  describe "#supported_platform?" do
    it "accepts the platforms doc 06 §3.2 targets" do
      allow(probe).to receive_messages(operating_system: "linux", architecture: "x86_64")

      expect(probe.supported_platform?).to be(true)
    end

    it "refuses everything else" do
      allow(probe).to receive_messages(operating_system: "aix", architecture: "ppc64")

      expect(probe.supported_platform?).to be(false)
    end
  end
end
