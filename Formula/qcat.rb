class Qcat < Formula
  desc "Hardware-backed post-quantum encrypted transport"
  homepage "https://github.com/ekarulf/quantumcat"
  if OS.mac?
    url "https://github.com/ekarulf/quantumcat/releases/download/v0.0.6/qcat-darwin-arm64.tar.gz"
    sha256 "08b06a036b3cb5bef638d1a95e492c6908086a07f1c1d4cf95196ad2e86caeef"
  elsif Hardware::CPU.arm?
    url "https://github.com/ekarulf/quantumcat/releases/download/v0.0.6/qcat-linux-arm64.tar.gz"
    sha256 "ba77393b7d2609f976221cd038f481891dcff85d69157c4c345ef93c29d2dc4d"
  else
    url "https://github.com/ekarulf/quantumcat/releases/download/v0.0.6/qcat-linux-amd64.tar.gz"
    sha256 "c2843965f5f0f07db33632eaa86f3ba6773cd27d951e0b098c0d5b35c9374e6e"
  end
  license "Apache-2.0"
  revision 1

  on_macos do
    depends_on arch: :arm64
    depends_on macos: :tahoe
  end

  def install
    bin.install "qcat"
    if OS.mac?
      libexec.install "qcat-se"
      system "codesign", "--verify", "--strict", bin/"qcat"
      system "codesign", "--verify", "--strict", libexec/"qcat-se"
    end

    doc.install "README.md", "BUILD_COMMIT", "BUILD_TOOLCHAIN"
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
    version_output = shell_output("#{bin}/qcat version")
    assert_match "v#{version}", version_output
    assert_match "commit    #{(doc/"BUILD_COMMIT").read.strip}", version_output
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
