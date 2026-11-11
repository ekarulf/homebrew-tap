# Erik's Homebrew tap

Install [Quantumcat](https://github.com/ekarulf/quantumcat) or
[Keystone](https://github.com/ekarulf/keystone):

```sh
brew install ekarulf/tap/qcat
brew install ekarulf/tap/keystone
```

Update to the latest releases packaged by this tap:

```sh
brew update
brew upgrade ekarulf/tap/qcat ekarulf/tap/keystone
```

Run the upgrade command with just the package you installed if you only use one.
The formulae use checksummed releases and do not pin your installed versions.

## Requirements

- **qcat:** Linux, or Apple Silicon with macOS 26+ and Apple's command-line tools
  with a macOS 26+ SDK. Builds from the upstream release using Go. No tap patch.
- **keystone:** Apple Silicon macOS. Installs the official release binary.

Installation does not create identities, enroll devices, change credentials or
configuration, or start services. Hardware signing requires separate setup.

## qcat helper

On macOS, only `qcat` is linked onto `PATH`. Its Secure Enclave helper stays in
`$(brew --prefix qcat)/libexec/qcat-se` and is found automatically in the same keg.
Restart running qcat services after upgrades, before removing old kegs with
`brew cleanup`.

Helpers must be owned by root or the current user and must not be group- or
world-writable. Symlinks and directories are checked too. Unprivileged qcat trusts
group-writable ancestors shared with its own executable, including Homebrew's
installation group, but rejects helper-only writable directories. These are
POSIX ownership/mode checks, not ACL checks.

Set-ID use is rejected. Root ignores helper environment overrides and requires a
separate root-owned installation; do not use `sudo qcat` with a user-owned
Homebrew helper. Private-data checks remain stricter. See the
[upstream installation guide](https://github.com/ekarulf/quantumcat#install)
for details.

## Keystone consumers

For AWS `credential_process`, use the stable opt path. On a standard Apple Silicon
installation:

```ini
credential_process = /opt/homebrew/opt/keystone/bin/keystone credential-process --profile YOUR_PROFILE
```

Use `brew --prefix keystone` for a custom prefix. Keep configuration, identities,
and token caches outside the Cellar.

The v0.1.3 Google consumer adapter does not accept normal Homebrew symlink and
group-writable layouts. Keep its existing trusted executable path until using a
reviewed Homebrew-aware adapter. Do not bypass permission checks or change
Homebrew directory permissions to work around this.

## Checks

```sh
brew audit --strict ekarulf/tap/qcat ekarulf/tap/keystone
brew test ekarulf/tap/qcat
brew test ekarulf/tap/keystone
```

CI tests qcat on Apple Silicon macOS and Linux, and Keystone on Apple Silicon
macOS. qcat helper-layout tests use a fake protocol helper. Hardware identity and
cloud end-to-end tests are not run.
