class Keystone < Formula
  desc "Hardware-backed temporary AWS credentials and Secure Enclave SSH agent"
  homepage "https://github.com/ekarulf/keystone"
  url "https://github.com/ekarulf/keystone/releases/download/v0.1.3/keystone-0.1.3-aarch64-apple-darwin.tar.gz"
  sha256 "bfe6eca7394f353aa922a6f589c0827977a4c13632bf3c3dca4d5097ac842d5f"
  license "MIT"

  depends_on arch: :arm64
  depends_on :macos

  def install
    bin.install "keystone"
    doc.install "README.md"
  end

  def caveats
    <<~EOS
      Keystone requires Apple Silicon and a Secure Enclave for hardware signing.
      This formula does not create identities or change cloud credentials.

      For a stable AWS credential_process path, use:
        #{opt_bin}/keystone

      Keep Keystone's private data outside the Homebrew Cellar. The Google
      adapter has separate executable-path trust checks; see the tap README
      before switching an existing Google consumer to this installation.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/keystone --version")
    assert_match "credential-process", shell_output("#{bin}/keystone --help")
  end
end
