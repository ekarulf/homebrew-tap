# Erik's Homebrew tap

Install [Quantumcat](https://github.com/ekarulf/quantumcat) and
[Keystone](https://github.com/ekarulf/keystone):

```sh
brew install ekarulf/tap/qcat
brew install ekarulf/tap/keystone
```

Fully qualified install names select this tap even if another tap has a package
with the same name. On Homebrew versions that require tap trust, these explicit
install commands trust only the named formulae, not every formula in the tap.

## Packages

- **qcat 0.0.5:** builds from checksum-pinned source with the Homebrew compatibility
  patch embedded in `Formula/qcat.rb`. Supports Apple Silicon macOS 26+ and Linux.
  Building on macOS also requires Apple command-line tools with a macOS 26 or newer
  SDK (`xcode-select --install` if the tools are absent). Go is a build dependency.
- **keystone 0.1.3:** installs the official, checksum-verified Apple Silicon macOS
  release archive. Intel macOS and Linux are not supported by that release.

Installing either formula does **not** create identities, enroll devices, request
cloud credentials, edit configuration, or start background services. Hardware
signing still requires compatible hardware and separate setup. Formula smoke
tests do not exercise real identities or cloud access. qcat layout tests use a
fake protocol helper, never the Secure Enclave helper.

## qcat's private helper

Only `qcat` is linked onto `PATH`. On macOS its `qcat-se` helper lives at:

```sh
$(brew --prefix qcat)/libexec/qcat-se
```

The patched executable resolves its own Homebrew keg and finds the helper from
that same installation without a wrapper or environment override. A running
process keeps its startup keg; restart your qcat services after upgrading and
before removing old versions with `brew cleanup`.

The helper must be a regular executable owned by the current user or root and
not writable by group or others. All traversed helper links and directories are
checked. Ordinary unprivileged qcat invocations permit group-writable ancestors
shared with the qcat executable, because that group can already replace qcat
itself. This trusts those installation-group members to replace the helper too.
Helper-only group-writable directories and non-sticky world-writable ancestors
are rejected. The existing trusted-sticky-directory exception is preserved.
These checks validate POSIX ownership/modes, not ACLs.

Set-ID helper invocation is rejected. Root ignores helper environment overrides
and does not use the shared-directory exception; `sudo qcat` will not use a
normal user-owned Homebrew helper. Privileged Secure Enclave deployments need a
separate root-owned installation. The formula does not change Homebrew ownership,
permissions, system security settings, or qcat's stricter private-data checks.

### Patch provenance

Upstream v0.0.5 is commit
[`961226e51ffc95b076cbe03a9a366a2997965b70`](https://github.com/ekarulf/quantumcat/commit/961226e51ffc95b076cbe03a9a366a2997965b70).
Its source archive SHA-256 is
`f69762b560f9dd59596aa71a646e4b7ab947ae08fcebfaa5b9732ab6dc1509dd`.

The inline patch adds helper discovery, executable-path validation, regression
tests, and matching upstream documentation. It was reconstructed from the prior
Homebrew work and revalidated against that exact source, rather than represented
as the original lost commit or a published upstream release. Its SHA-256 is
`d212124ee5645307252394171d48d1c0a607f7a50bf607c666bab3598bbc9b60`.
It is versioned with this tap and never downloaded from a mutable branch:

```sh
sed '1,/^__END__$/d' Formula/qcat.rb | shasum -a 256
```

A later upstream release can replace this patch after the same layout and
permission tests pass. The upstream v0.0.5 release binaries are not modified.

## Keystone consumer paths

For an AWS `credential_process`, use the stable opt path rather than a versioned
Cellar path. For the standard Apple Silicon prefix:

```ini
credential_process = /opt/homebrew/opt/keystone/bin/keystone credential-process --profile YOUR_PROFILE
```

Use `brew --prefix keystone` to find the right prefix for a custom installation.
Keep Keystone configuration, enrolled identities, and token caches outside the
Cellar so upgrades and cleanup cannot remove them.

The example Google consumer adapter has its own stricter executable-path checks.
The v0.1.3 adapter does not accept normal Homebrew symlink/group-writable layouts.
Installing this CLI does not update or relax that adapter. Existing Google
consumers should keep their current trusted executable path until they adopt a
reviewed Homebrew-aware adapter. Do not use an unsafe-permissions flag or change
Homebrew directory permissions as a workaround.

## Validation

```sh
brew audit --strict ekarulf/tap/qcat ekarulf/tap/keystone
brew test ekarulf/tap/qcat
brew test ekarulf/tap/keystone
```

CI builds and tests qcat on Apple Silicon macOS and Linux, tests Keystone on
Apple Silicon macOS, and runs the patched qcat Go tests with hardware tests
explicitly disabled. No test initializes a real Secure Enclave identity or
contacts a cloud account. Hardware and cloud end-to-end validation are separate.
