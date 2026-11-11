class Qcat < Formula
  desc "Hardware-backed post-quantum encrypted transport"
  homepage "https://github.com/ekarulf/quantumcat"
  url "https://github.com/ekarulf/quantumcat/archive/refs/tags/v0.0.6.tar.gz"
  sha256 "ee50087009d532478c74e5f559cd5a188f124deeb90e66fa12ce25d31c30625b"
  license "Apache-2.0"

  depends_on "go" => :build

  on_macos do
    depends_on arch: :arm64
    depends_on macos: :tahoe
  end

  def install
    ENV["CGO_ENABLED"] = "0"
    ldflags = "-X github.com/ekarulf/quantumcat/internal/version.Version=v#{version}"
    system "go", "build", "-mod=readonly", *std_go_args(ldflags:), "./cmd/qcat"

    if OS.mac?
      libexec.mkpath
      system "xcrun", "swiftc", "-O", "-target", "arm64-apple-macosx26.0",
             "-module-cache-path", buildpath/".swift-cache",
             "-o", libexec/"qcat-se", "swift/qcat-se.swift"
      system "codesign", "--force", "--sign", "-", bin/"qcat"
      system "codesign", "--force", "--sign", "-", libexec/"qcat-se"
      system "codesign", "--verify", "--strict", bin/"qcat"
      system "codesign", "--verify", "--strict", libexec/"qcat-se"
    end

    doc.install "README.md", "PROTOCOL.md"
    (pkgshare/"deploy").install Dir["deploy/*"]
  end

  def caveats
    <<~EOS
      On macOS, the Secure Enclave helper is private to this installation:
        #{opt_libexec}/qcat-se
      Only qcat is linked onto PATH. No identities or services are created.
      Secure Enclave use requires Apple Silicon and macOS 26 or newer.

      Restart running qcat services after upgrading, before brew cleanup.
      See the tap README for helper trust and privileged-installation requirements.
    EOS
  end

  test do
    assert_match "v#{version}", shell_output("#{bin}/qcat version")
    assert_match "identity", shell_output("#{bin}/qcat --help")
    if OS.mac?
      assert_predicate libexec/"qcat-se", :executable?
      refute_path_exists bin/"qcat-se"
    end

    # Exercise the installed binary through bin/opt symlinks, with a fixture
    # helper that returns one protocol response and never touches hardware.
    ENV.delete("QCAT_ENCLAVE_HELPER")
    ENV.delete("QCAT_SE_HELPER")
    keg = testpath/"Cellar/qcat/#{version}"
    (keg/"bin").mkpath
    (keg/"libexec").mkpath
    cp bin/"qcat", keg/"bin/qcat"
    (keg/"libexec/qcat-se").write <<~SH
      #!/bin/sh
      dd bs=5 count=1 of=/dev/null 2>/dev/null
      printf '\\000\\000\\000\\006\\000ready'
    SH
    chmod 0755, keg/"libexec/qcat-se"
    (testpath/"bin").mkpath
    (testpath/"opt").mkpath
    ln_s "../Cellar/qcat/#{version}/bin/qcat", testpath/"bin/qcat"
    ln_s "../Cellar/qcat/#{version}", testpath/"opt/qcat"
    chmod 0775, testpath/"Cellar"
    assert_equal "ready\n", shell_output("#{testpath}/bin/qcat debug")
    assert_equal "ready\n", shell_output("#{testpath}/opt/qcat/bin/qcat debug")

    chmod 0775, keg/"libexec"
    assert_match "ancestor is group/other writable",
                 shell_output("#{testpath}/bin/qcat debug 2>&1", 1)
  end
end
