class Qcat < Formula
  desc "Hardware-backed post-quantum encrypted transport"
  homepage "https://github.com/ekarulf/quantumcat"
  url "https://github.com/ekarulf/quantumcat/archive/refs/tags/v0.0.5.tar.gz"
  sha256 "f69762b560f9dd59596aa71a646e4b7ab947ae08fcebfaa5b9732ab6dc1509dd"
  license "Apache-2.0"

  depends_on "go" => :build

  on_macos do
    depends_on arch: :arm64
    depends_on macos: :tahoe
  end

  # Homebrew helper discovery and executable-only trust policy. This patch is
  # pinned in the tap, not fetched from a mutable branch. See README.md.
  patch :DATA

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

      This formula builds v0.0.5 with a pinned Homebrew compatibility patch.
      See the tap README for its executable trust policy and build requirements.
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

__END__
diff --git a/README.md b/README.md
index 4dd07e9..05af003 100644
--- a/README.md
+++ b/README.md
@@ -171,14 +171,71 @@ mkdir -p "$HOME/.local/bin"
 install -m 755 qcat "$HOME/.local/bin/qcat"
 ```
 
-On macOS, keep `qcat-se` beside `qcat`:
+On macOS, install `qcat-se` outside your `PATH`:
 
 ```sh
-install -m 755 qcat-se "$HOME/.local/bin/qcat-se"
+mkdir -p "$HOME/.local/libexec/qcat"
+install -m 755 qcat-se "$HOME/.local/libexec/qcat/qcat-se"
 ```
 
 macOS binaries are currently ad-hoc signed rather than Developer ID signed/notarized. Checksums protect against accidental corruption; they are not publisher signatures.
 
+### Homebrew and other package layouts
+
+For a Homebrew formula, install the two binaries separately:
+
+```ruby
+bin.install "qcat"
+libexec.install "qcat-se"
+```
+
+Homebrew keeps `libexec` private to the formula instead of linking it into the
+global `bin` or `sbin`. Prefer it to `sbin`, which Homebrew links and which may
+already be on the user's `PATH`. No wrapper or environment variable is needed.
+
+`qcat` resolves its own executable first, so a Homebrew `bin/qcat` or
+`opt/quantumcat/bin/qcat` symlink finds the helper in the same versioned keg.
+That location is pinned at process startup; restart running services after an
+upgrade, before Homebrew removes their old keg.
+When `qcat` is in a `bin` or `sbin` directory, discovery checks these paths in
+order under that installation prefix:
+
+1. `libexec/qcat/qcat-se`
+2. `libexec/qcat-se`
+3. `sbin/qcat-se`
+4. `qcat-se` beside `qcat` (also the only default for other executable locations)
+
+Adjacent release-archive and `make helper` layouts remain supported. The helper
+is never searched for on `PATH`. A missing candidate allows the next layout;
+an existing but unsafe or broken candidate is an error rather than a fallback.
+For a custom location, an unprivileged process may set an absolute
+`QCAT_ENCLAVE_HELPER` path (`QCAT_SE_HELPER` remains a legacy alias).
+
+Helper symlinks are allowed only after validating every traversed directory and
+link and the final executable. The canonical target is then executed. The helper
+must be a regular executable owned by root or the current user, never writable
+by group or others. Directory and link ownership must also be trusted.
+
+For an ordinary unprivileged invocation, group-writable directories shared by
+the resolved `qcat` and helper paths are allowed to accommodate Homebrew's
+admin-group-managed prefixes. This explicitly trusts that installation's group
+to replace both binaries, including helpers started by an already-running
+`qcat`. Helper-only group-writable directories and non-sticky world-writable
+directories are rejected. These are POSIX owner/mode checks, not an ACL audit.
+
+Set-ID invocations (different real/effective user or group IDs) cannot start a
+helper. Ordinary root invocations, including `sudo`, ignore both environment
+overrides and disable the shared-directory exception. Root will not run a helper
+from a normal user-owned Homebrew keg, even if the helper file itself is root-owned.
+For privileged TUN use with Secure Enclave, install `qcat` and its helper into a
+separate root-owned, non-group/other-writable installation rather than changing
+ownership of Homebrew's prefix. Identity and peer-store symlink and permission
+checks are unchanged.
+
+Secure Enclave long-lived private keys remain non-exportable. Helper-path checks
+protect which code can invoke signing operations and use the process's OS
+privileges; they do not change that key-storage design.
+
 ## Pairing
 
 Configuration defaults to:
diff --git a/deploy/macos/com.quantumcat.server.plist b/deploy/macos/com.quantumcat.server.plist
index 293091d..2316a24 100644
--- a/deploy/macos/com.quantumcat.server.plist
+++ b/deploy/macos/com.quantumcat.server.plist
@@ -19,7 +19,6 @@
     <key>EnvironmentVariables</key>
     <dict>
         <key>HOME</key><string>REPLACE_HOME</string>
-        <key>QCAT_ENCLAVE_HELPER</key><string>REPLACE_HOME/.local/bin/qcat-se</string>
     </dict>
     <key>StandardOutPath</key><string>REPLACE_HOME/Library/Logs/qcat-server.log</string>
     <key>StandardErrorPath</key><string>REPLACE_HOME/Library/Logs/qcat-server.log</string>
diff --git a/internal/crypto/provider/se/lifecycle_test.go b/internal/crypto/provider/se/lifecycle_test.go
index a312309..7a9cb9f 100644
--- a/internal/crypto/provider/se/lifecycle_test.go
+++ b/internal/crypto/provider/se/lifecycle_test.go
@@ -4,77 +4,10 @@ import (
 	"context"
 	"os"
 	"os/exec"
-	"path/filepath"
 	"testing"
 	"time"
 )
 
-func TestHelperEnvironmentNames(t *testing.T) {
-	if os.Geteuid() != 0 {
-		t.Setenv("QCAT_SE_HELPER", "/legacy/qcat-se")
-		t.Setenv("QCAT_ENCLAVE_HELPER", "/new/qcat-se")
-		if path, err := helperPath(); err != nil || path != "/new/qcat-se" {
-			t.Fatalf("new name: %q %v", path, err)
-		}
-		t.Setenv("QCAT_ENCLAVE_HELPER", "")
-		if path, err := helperPath(); err != nil || path != "/legacy/qcat-se" {
-			t.Fatalf("legacy: %q %v", path, err)
-		}
-		t.Setenv("QCAT_ENCLAVE_HELPER", "relative-path")
-		if _, err := helperPath(); err == nil {
-			t.Fatal("invalid canonical path fell back to legacy")
-		}
-	}
-	t.Setenv("QCAT_ENCLAVE_HELPER", "")
-	t.Setenv("QCAT_SE_HELPER", "")
-	exe, err := os.Executable()
-	if err != nil {
-		t.Fatal(err)
-	}
-	if path, err := helperPath(); err != nil || path != filepath.Join(filepath.Dir(exe), "qcat-se") {
-		t.Fatalf("default: %q %v", path, err)
-	}
-}
-
-func TestTrustedHelper(t *testing.T) {
-	dir := t.TempDir()
-	path := filepath.Join(dir, "qcat-se")
-	if err := os.WriteFile(path, []byte("helper"), 0700); err != nil {
-		t.Fatal(err)
-	}
-	if err := trustedHelper(path); err != nil {
-		t.Fatal(err)
-	}
-	if err := os.Chmod(path, 0722); err != nil {
-		t.Fatal(err)
-	}
-	if err := trustedHelper(path); err == nil {
-		t.Fatal("writable helper trusted")
-	}
-	if err := os.Chmod(path, 0600); err != nil {
-		t.Fatal(err)
-	}
-	if err := trustedHelper(path); err == nil {
-		t.Fatal("non-executable helper trusted")
-	}
-	if err := os.Chmod(path, 0700); err != nil {
-		t.Fatal(err)
-	}
-	link := filepath.Join(dir, "helper-link")
-	if err := os.Symlink(path, link); err != nil {
-		t.Fatal(err)
-	}
-	if err := trustedHelper(link); err == nil {
-		t.Fatal("symlink helper trusted")
-	}
-	if err := os.Chmod(dir, 0777); err != nil {
-		t.Fatal(err)
-	}
-	if err := trustedHelper(path); err == nil {
-		t.Fatal("helper beneath writable directory trusted")
-	}
-}
-
 func TestHelperChild(t *testing.T) {
 	if os.Getenv("QCAT_TEST_STALLED_HELPER") != "1" {
 		return
diff --git a/internal/crypto/provider/se/path.go b/internal/crypto/provider/se/path.go
new file mode 100644
index 0000000..99fc440
--- /dev/null
+++ b/internal/crypto/provider/se/path.go
@@ -0,0 +1,241 @@
+package se
+
+import (
+	"errors"
+	"fmt"
+	"os"
+	"path/filepath"
+	"strings"
+
+	"github.com/ekarulf/quantumcat/internal/trust"
+)
+
+// Pin discovery to the startup installation. A running qcat must not switch
+// helper versions when Homebrew retargets a bin/opt alias during an upgrade.
+var qcatExecutable, qcatExecutableErr = resolveExecutable()
+
+func resolveExecutable() (string, error) {
+	exe, err := os.Executable()
+	if err != nil {
+		return "", err
+	}
+	// Homebrew's bin and opt links must select the helper from the same keg,
+	// rather than from the global prefix or another installed version.
+	return filepath.EvalSymlinks(exe)
+}
+
+func helperPath() (string, error) {
+	unprivileged, err := helperProcessPolicy(os.Getuid(), os.Geteuid(), os.Getgid(), os.Getegid())
+	if err != nil {
+		return "", err
+	}
+	if qcatExecutableErr != nil {
+		return "", fmt.Errorf("resolve qcat executable: %w", qcatExecutableErr)
+	}
+	return findHelper(qcatExecutable, helperOverride(unprivileged, os.Getenv), unprivileged)
+}
+
+func helperProcessPolicy(uid, euid, gid, egid int) (unprivileged bool, err error) {
+	// Merely ignoring environment overrides is not enough for setgid: a
+	// user-owned helper would still inherit the process's elevated group.
+	if uid != euid || gid != egid {
+		return false, errors.New("Secure Enclave helper is unsupported in set-ID processes; run qcat without setuid/setgid")
+	}
+	return euid != 0, nil
+}
+
+func helperOverride(unprivileged bool, getenv func(string) string) string {
+	// Environment-controlled executables must never cross a privilege boundary.
+	if !unprivileged {
+		return ""
+	}
+	if path := getenv("QCAT_ENCLAVE_HELPER"); path != "" {
+		return path
+	}
+	return getenv("QCAT_SE_HELPER") // Compatibility with existing LaunchAgents.
+}
+
+func helperCandidates(exe string) []string {
+	dir := filepath.Dir(exe)
+	var paths []string
+	if filepath.Base(dir) == "bin" || filepath.Base(dir) == "sbin" {
+		prefix := filepath.Dir(dir)
+		paths = append(paths,
+			filepath.Join(prefix, "libexec", "qcat", "qcat-se"),
+			filepath.Join(prefix, "libexec", "qcat-se"),
+			filepath.Join(prefix, "sbin", "qcat-se"))
+	}
+	return append(paths, filepath.Join(dir, "qcat-se"))
+}
+
+func findHelper(exe, override string, unprivileged bool) (string, error) {
+	paths := helperCandidates(exe)
+	if override != "" {
+		if !filepath.IsAbs(override) {
+			return "", errors.New("QCAT_ENCLAVE_HELPER must be an absolute path")
+		}
+		paths = []string{override}
+	}
+	for _, path := range paths {
+		// Lstat distinguishes an absent candidate from an invalid/dangling link.
+		// Never silently fall back after finding an unsafe installation.
+		if err := helperCandidateExists(path); errors.Is(err, os.ErrNotExist) && override == "" {
+			continue
+		} else if err != nil {
+			return "", fmt.Errorf("Secure Enclave helper %s: %w", path, err)
+		}
+		resolved, err := trustedHelper(path, exe, unprivileged)
+		if err != nil {
+			return "", fmt.Errorf("untrusted Secure Enclave helper: %w", err)
+		}
+		return resolved, nil
+	}
+	return "", fmt.Errorf("Secure Enclave helper not found (run make helper or install qcat-se); searched %s", strings.Join(paths, ", "))
+}
+
+// A missing ordinary directory is an absent layout. A dangling ancestor link is
+// a broken installation and must not silently select a different helper.
+func helperCandidateExists(path string) error {
+	_, err := os.Lstat(path)
+	if !errors.Is(err, os.ErrNotExist) {
+		return err
+	}
+	for parent := filepath.Dir(path); ; parent = filepath.Dir(parent) {
+		info, parentErr := os.Lstat(parent)
+		if parentErr == nil {
+			if info.Mode()&os.ModeSymlink != 0 {
+				if _, linkErr := filepath.EvalSymlinks(parent); linkErr != nil {
+					return fmt.Errorf("invalid helper directory %s: %v", parent, linkErr)
+				}
+			}
+			return err
+		}
+		if !errors.Is(parentErr, os.ErrNotExist) {
+			return parentErr
+		}
+		if parent == filepath.Dir(parent) {
+			return err
+		}
+	}
+}
+
+// trustedHelper returns the exact canonical path to execute. Resolving and then
+// executing the original alias would allow the alias to be retargeted between
+// the trust check and exec. Configuration and identity files retain their
+// separate, stricter no-symlink policy in internal/trust.
+func trustedHelper(path, exe string, unprivileged bool) (string, error) {
+	resolved, err := resolveHelperLinks(path, exe, unprivileged)
+	if err != nil {
+		return "", err
+	}
+	// Check the canonical chain root-to-leaf without following any new links.
+	// In particular, don't use Ancestors, which independently resolves aliases.
+	var parents []string
+	for parent := filepath.Dir(resolved); ; parent = filepath.Dir(parent) {
+		parents = append(parents, parent)
+		if parent == filepath.Dir(parent) {
+			break
+		}
+	}
+	for i := len(parents) - 1; i >= 0; i-- {
+		parent := parents[i]
+		info, err := os.Lstat(parent)
+		if err != nil {
+			return "", err
+		}
+		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
+			return "", fmt.Errorf("%s: expected non-symlink directory", parent)
+		}
+		if err := trust.Owner(info); err != nil {
+			return "", fmt.Errorf("%s: %w", parent, err)
+		}
+		// Homebrew may make shared installation ancestors admin-group writable.
+		// An unprivileged qcat already trusts those same directories for its own
+		// code. Permit only that existing trust, never helper-only directories,
+		// world-writable directories, or a root/set-ID invocation.
+		shared := unprivileged && pathWithin(exe, parent)
+		if err := helperDirectoryMode(info.Mode(), shared); err != nil {
+			return "", fmt.Errorf("%s: %w", parent, err)
+		}
+	}
+	if err := trust.Path(resolved, false); err != nil {
+		return "", err
+	}
+	info, err := os.Lstat(resolved)
+	if err != nil {
+		return "", err
+	}
+	if info.Mode().Perm()&0111 == 0 {
+		return "", errors.New("helper is not executable")
+	}
+	return resolved, nil
+}
+
+// Validate the entire alias chain, not just the final target: an untrusted link
+// must not be able to select an unrelated, otherwise trusted executable.
+func resolveHelperLinks(path, exe string, unprivileged bool) (string, error) {
+	if !filepath.IsAbs(path) {
+		return "", errors.New("helper must be an absolute path")
+	}
+	resolved := string(filepath.Separator)
+	parts := strings.Split(path, string(filepath.Separator))
+	links := 0
+	for len(parts) > 0 {
+		part := parts[0]
+		parts = parts[1:]
+		if part == "" || part == "." {
+			continue
+		}
+		if part == ".." {
+			resolved = filepath.Dir(resolved)
+			continue
+		}
+		next := filepath.Join(resolved, part)
+		info, err := os.Lstat(next)
+		if err != nil {
+			return "", err
+		}
+		if err := trust.Owner(info); err != nil {
+			return "", fmt.Errorf("%s: %w", next, err)
+		}
+		if info.Mode()&os.ModeSymlink != 0 {
+			links++
+			if links > 255 {
+				return "", errors.New("too many helper symlinks")
+			}
+			target, err := os.Readlink(next)
+			if err != nil {
+				return "", err
+			}
+			if filepath.IsAbs(target) {
+				resolved = string(filepath.Separator)
+			}
+			parts = append(strings.Split(target, string(filepath.Separator)), parts...)
+			continue
+		}
+		if info.IsDir() {
+			if err := helperDirectoryMode(info.Mode(), unprivileged && pathWithin(exe, next)); err != nil {
+				return "", fmt.Errorf("%s: %w", next, err)
+			}
+		} else if len(parts) > 0 {
+			return "", fmt.Errorf("%s: expected directory", next)
+		}
+		resolved = next
+	}
+	return resolved, nil
+}
+
+func pathWithin(path, dir string) bool {
+	rel, err := filepath.Rel(dir, path)
+	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
+}
+
+func helperDirectoryMode(mode os.FileMode, shared bool) error {
+	if mode&os.ModeSticky != 0 {
+		return nil // Trusted sticky directories such as /tmp protect their entries.
+	}
+	if mode.Perm()&0002 != 0 || (mode.Perm()&0020 != 0 && !shared) {
+		return errors.New("ancestor is group/other writable")
+	}
+	return nil
+}
diff --git a/internal/crypto/provider/se/path_test.go b/internal/crypto/provider/se/path_test.go
new file mode 100644
index 0000000..d6cda4c
--- /dev/null
+++ b/internal/crypto/provider/se/path_test.go
@@ -0,0 +1,364 @@
+package se
+
+import (
+	"context"
+	"os"
+	"os/exec"
+	"path/filepath"
+	"strings"
+	"testing"
+	"time"
+)
+
+func testExecutable(t *testing.T, path string) string {
+	t.Helper()
+	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
+		t.Fatal(err)
+	}
+	if err := os.WriteFile(path, []byte("helper"), 0755); err != nil {
+		t.Fatal(err)
+	}
+	return path
+}
+
+func testSymlink(t *testing.T, target, path string) {
+	t.Helper()
+	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
+		t.Fatal(err)
+	}
+	if err := os.Symlink(target, path); err != nil {
+		t.Fatal(err)
+	}
+}
+
+func canonical(t *testing.T, path string) string {
+	t.Helper()
+	path, err := filepath.EvalSymlinks(path)
+	if err != nil {
+		t.Fatal(err)
+	}
+	return path
+}
+
+func TestHelperEnvironmentNames(t *testing.T) {
+	env := map[string]string{"QCAT_SE_HELPER": "/legacy/qcat-se", "QCAT_ENCLAVE_HELPER": "/new/qcat-se"}
+	getenv := func(key string) string { return env[key] }
+	if got := helperOverride(true, getenv); got != "/new/qcat-se" {
+		t.Fatalf("new name: %q", got)
+	}
+	delete(env, "QCAT_ENCLAVE_HELPER")
+	if got := helperOverride(true, getenv); got != "/legacy/qcat-se" {
+		t.Fatalf("legacy: %q", got)
+	}
+	env["QCAT_ENCLAVE_HELPER"] = "relative-path"
+	exe := testExecutable(t, filepath.Join(t.TempDir(), "qcat"))
+	if _, err := findHelper(exe, helperOverride(true, getenv), true); err == nil || !strings.Contains(err.Error(), "absolute") {
+		t.Fatalf("invalid canonical path fell back to legacy: %v", err)
+	}
+	for _, ids := range [][4]int{{1000, 0, 1000, 1000}, {1000, 1001, 1000, 1000}, {1000, 1000, 1000, 1001}, {0, 0, 0, 1000}} {
+		if allowed, err := helperProcessPolicy(ids[0], ids[1], ids[2], ids[3]); err == nil || allowed || helperOverride(allowed, getenv) != "" {
+			t.Fatalf("set-ID process accepted: %v", ids)
+		}
+	}
+	if allowed, err := helperProcessPolicy(0, 0, 0, 0); err != nil || allowed || helperOverride(allowed, getenv) != "" {
+		t.Fatalf("ordinary root invocation: allowed %v, err %v", allowed, err)
+	}
+	if allowed, err := helperProcessPolicy(1000, 1000, 1000, 1000); !allowed || err != nil {
+		t.Fatal("ordinary user treated as privileged")
+	}
+}
+
+func TestHelperExplicitLocationAndNoPathSearch(t *testing.T) {
+	prefix := t.TempDir()
+	exe := canonical(t, testExecutable(t, filepath.Join(prefix, "bin", "qcat")))
+	custom := testExecutable(t, filepath.Join(t.TempDir(), "private", "qcat-se"))
+	t.Setenv("PATH", filepath.Dir(custom))
+	if _, err := findHelper(exe, "", true); err == nil {
+		t.Fatal("helper discovered on PATH")
+	}
+	testExecutable(t, filepath.Join(prefix, "libexec", "qcat-se"))
+	if got, err := findHelper(exe, custom, true); err != nil || got != canonical(t, custom) {
+		t.Fatalf("explicit location: got %q, %v", got, err)
+	}
+	if _, err := findHelper(exe, custom+"-missing", true); err == nil {
+		t.Fatal("missing explicit location fell back to installed helper")
+	}
+}
+
+func TestHelperInstallLayouts(t *testing.T) {
+	for _, layout := range []string{"libexec/qcat/qcat-se", "libexec/qcat-se", "sbin/qcat-se", "bin/qcat-se"} {
+		t.Run(layout, func(t *testing.T) {
+			prefix := filepath.Join(t.TempDir(), "Cellar", "quantumcat", "1.2.3")
+			exe := testExecutable(t, filepath.Join(prefix, "bin", "qcat"))
+			helper := testExecutable(t, filepath.Join(prefix, filepath.FromSlash(layout)))
+			if got, err := findHelper(canonical(t, exe), "", true); err != nil || got != canonical(t, helper) {
+				t.Fatalf("got %q, %v; want %q", got, err, helper)
+			}
+		})
+	}
+	t.Run("development", func(t *testing.T) {
+		dir := t.TempDir()
+		exe := testExecutable(t, filepath.Join(dir, "qcat"))
+		helper := testExecutable(t, filepath.Join(dir, "qcat-se"))
+		if got, err := findHelper(canonical(t, exe), "", true); err != nil || got != canonical(t, helper) {
+			t.Fatalf("got %q, %v", got, err)
+		}
+		if paths := helperCandidates(exe); len(paths) != 1 {
+			t.Fatalf("development build searched unrelated prefix: %v", paths)
+		}
+	})
+}
+
+func TestHomebrewAliasesStayInKeg(t *testing.T) {
+	brew := t.TempDir()
+	keg := filepath.Join(brew, "Cellar", "quantumcat", "1.2.3")
+	exe := testExecutable(t, filepath.Join(keg, "bin", "qcat"))
+	helper := testExecutable(t, filepath.Join(keg, "libexec", "qcat-se"))
+	// A different global helper must never win over the active keg's helper.
+	testExecutable(t, filepath.Join(brew, "bin", "qcat-se"))
+	binLink := filepath.Join(brew, "bin", "qcat")
+	testSymlink(t, "../Cellar/quantumcat/1.2.3/bin/qcat", binLink)
+	optLink := filepath.Join(brew, "opt", "quantumcat")
+	testSymlink(t, "../Cellar/quantumcat/1.2.3", optLink)
+	for _, launch := range []string{exe, binLink, filepath.Join(optLink, "bin", "qcat")} {
+		if got, err := findHelper(canonical(t, launch), "", true); err != nil || got != canonical(t, helper) {
+			t.Fatalf("launch %q: got %q, %v", launch, got, err)
+		}
+	}
+}
+
+func TestHelperDiscoveryPinnedAtStartup(t *testing.T) {
+	if prefix := os.Getenv("QCAT_TEST_DISCOVERY_ROOT"); prefix != "" {
+		launch := filepath.Join(prefix, "bin", "qcat")
+		if err := os.Remove(launch); err != nil {
+			t.Fatal(err)
+		}
+		testSymlink(t, "../Cellar/quantumcat/2/bin/qcat", launch)
+		want := canonical(t, filepath.Join(prefix, "Cellar", "quantumcat", "1", "libexec", "qcat-se"))
+		if got, err := helperPath(); err != nil || got != want {
+			t.Fatalf("upgrade changed running process's helper: got %q, %v; want %q", got, err, want)
+		}
+		return
+	}
+	prefix := t.TempDir()
+	exe, err := os.Executable()
+	if err != nil {
+		t.Fatal(err)
+	}
+	binary, err := os.ReadFile(exe)
+	if err != nil {
+		t.Fatal(err)
+	}
+	old := testExecutable(t, filepath.Join(prefix, "Cellar", "quantumcat", "1", "bin", "qcat"))
+	if err := os.WriteFile(old, binary, 0755); err != nil {
+		t.Fatal(err)
+	}
+	testExecutable(t, filepath.Join(prefix, "Cellar", "quantumcat", "1", "libexec", "qcat-se"))
+	testExecutable(t, filepath.Join(prefix, "Cellar", "quantumcat", "2", "bin", "qcat"))
+	testExecutable(t, filepath.Join(prefix, "Cellar", "quantumcat", "2", "libexec", "qcat-se"))
+	launch := filepath.Join(prefix, "bin", "qcat")
+	testSymlink(t, "../Cellar/quantumcat/1/bin/qcat", launch)
+	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
+	defer cancel()
+	cmd := exec.CommandContext(ctx, launch, "-test.run=^TestHelperDiscoveryPinnedAtStartup$")
+	cmd.Env = append(os.Environ(), "QCAT_TEST_DISCOVERY_ROOT="+prefix, "QCAT_ENCLAVE_HELPER=", "QCAT_SE_HELPER=")
+	if out, err := cmd.CombinedOutput(); err != nil {
+		t.Fatalf("subprocess: %v\n%s", err, out)
+	}
+}
+
+func TestHelperSelectionFailsClosed(t *testing.T) {
+	for _, bad := range []string{"non-executable", "writable", "directory", "dangling", "dangling-ancestor", "loop"} {
+		t.Run(bad, func(t *testing.T) {
+			prefix := t.TempDir()
+			exe := testExecutable(t, filepath.Join(prefix, "bin", "qcat"))
+			testExecutable(t, filepath.Join(prefix, "bin", "qcat-se"))
+			path := filepath.Join(prefix, "libexec", "qcat-se")
+			switch bad {
+			case "non-executable", "writable":
+				testExecutable(t, path)
+				mode := os.FileMode(0644)
+				if bad == "writable" {
+					mode = 0775
+				}
+				if err := os.Chmod(path, mode); err != nil {
+					t.Fatal(err)
+				}
+			case "directory":
+				if err := os.MkdirAll(path, 0755); err != nil {
+					t.Fatal(err)
+				}
+			case "dangling":
+				testSymlink(t, "missing", path)
+			case "dangling-ancestor":
+				testSymlink(t, "missing", filepath.Dir(path))
+			case "loop":
+				testSymlink(t, "qcat-se", path)
+			}
+			if got, err := findHelper(canonical(t, exe), "", true); err == nil {
+				t.Fatalf("unsafe preferred helper %s fell back to %q", bad, got)
+			}
+		})
+	}
+	t.Run("missing", func(t *testing.T) {
+		exe := testExecutable(t, filepath.Join(t.TempDir(), "qcat"))
+		if _, err := findHelper(canonical(t, exe), "", true); err == nil || !strings.Contains(err.Error(), "not found") {
+			t.Fatalf("missing helper: %v", err)
+		}
+	})
+}
+
+func TestHelperRejectsUntrustedAliasSelection(t *testing.T) {
+	for _, mode := range []os.FileMode{0777, 0775} {
+		t.Run(mode.String(), func(t *testing.T) {
+			dir := t.TempDir()
+			exe := testExecutable(t, filepath.Join(dir, "bin", "qcat"))
+			trusted := testExecutable(t, filepath.Join(dir, "safe", "qcat-se"))
+			alias := filepath.Join(dir, "untrusted", "qcat-se")
+			testSymlink(t, trusted, alias)
+			testSymlink(t, "../untrusted", filepath.Join(dir, "libexec", "qcat"))
+			if err := os.Chmod(filepath.Dir(alias), mode); err != nil {
+				t.Fatal(err)
+			}
+			for _, unprivileged := range []bool{false, true} {
+				if _, err := findHelper(canonical(t, exe), "", unprivileged); err == nil {
+					t.Fatal("untrusted alias selected an otherwise trusted executable")
+				}
+			}
+		})
+	}
+}
+
+func TestHelperRelativeLinksAndDotDot(t *testing.T) {
+	dir := t.TempDir()
+	exe := testExecutable(t, filepath.Join(dir, "bin", "qcat"))
+	helper := testExecutable(t, filepath.Join(dir, "private", "qcat-se"))
+	if err := os.Mkdir(filepath.Join(dir, "private", "subdir"), 0755); err != nil {
+		t.Fatal(err)
+	}
+	link := filepath.Join(dir, "libexec", "qcat-se")
+	testSymlink(t, "../private/subdir/../qcat-se", link)
+	got, err := trustedHelper(link, canonical(t, exe), true)
+	if err != nil || got != canonical(t, helper) {
+		t.Fatalf("got %q, %v", got, err)
+	}
+}
+
+func TestHelperMultiHopDirectoryAliases(t *testing.T) {
+	dir := t.TempDir()
+	exe := testExecutable(t, filepath.Join(dir, "bin", "qcat"))
+	helper := testExecutable(t, filepath.Join(dir, "private", "var", "qcat", "qcat-se"))
+	// Model macOS /var -> /private/var, then another relative helper link.
+	testSymlink(t, "private/var", filepath.Join(dir, "var"))
+	testSymlink(t, "../var/qcat", filepath.Join(dir, "libexec", "qcat"))
+	got, err := findHelper(canonical(t, exe), "", true)
+	if err != nil || got != canonical(t, helper) {
+		t.Fatalf("multi-hop directory aliases: got %q, %v", got, err)
+	}
+	if err := os.Chmod(filepath.Join(dir, "private", "var"), 0777); err != nil {
+		t.Fatal(err)
+	}
+	if _, err := findHelper(canonical(t, exe), "", true); err == nil {
+		t.Fatal("writable intermediate directory trusted through aliases")
+	}
+}
+
+func TestHelperSymlinkExecutesCanonicalTarget(t *testing.T) {
+	dir := t.TempDir()
+	exe := testExecutable(t, filepath.Join(dir, "bin", "qcat"))
+	helper := testExecutable(t, filepath.Join(dir, "private", "qcat-se"))
+	link := filepath.Join(dir, "libexec", "qcat-se")
+	testSymlink(t, "../private/qcat-se", link)
+	got, err := findHelper(canonical(t, exe), "", true)
+	if err != nil || got != canonical(t, helper) {
+		t.Fatalf("got %q, %v", got, err)
+	}
+	if err := os.Remove(link); err != nil {
+		t.Fatal(err)
+	}
+	testSymlink(t, "missing", link)
+	if _, err := os.Stat(got); err != nil {
+		t.Fatalf("retargeting original alias changed execution path: %v", err)
+	}
+	if err := os.Chmod(filepath.Dir(helper), 0777); err != nil {
+		t.Fatal(err)
+	}
+	if _, err := trustedHelper(helper, canonical(t, exe), true); err == nil {
+		t.Fatal("writable target ancestor trusted")
+	}
+}
+
+func TestHelperDirectoryTrust(t *testing.T) {
+	for _, tc := range []struct {
+		name   string
+		mode   os.FileMode
+		shared bool
+		ok     bool
+	}{
+		{"ordinary", 0755, false, true},
+		{"homebrew-shared", 0775, true, true},
+		{"privileged", 0775, false, false},
+		{"helper-only", 0775, false, false},
+		{"world-writable", 0777, true, false},
+		{"trusted-sticky", 0777 | os.ModeSticky, false, true},
+	} {
+		t.Run(tc.name, func(t *testing.T) {
+			if err := helperDirectoryMode(tc.mode, tc.shared); (err == nil) != tc.ok {
+				t.Fatalf("mode %v shared %v: %v", tc.mode, tc.shared, err)
+			}
+		})
+	}
+	prefix := t.TempDir()
+	exe := testExecutable(t, filepath.Join(prefix, "bin", "qcat"))
+	helper := testExecutable(t, filepath.Join(prefix, "libexec", "qcat-se"))
+	if err := os.Chmod(prefix, 0775); err != nil {
+		t.Fatal(err)
+	}
+	if _, err := trustedHelper(helper, canonical(t, exe), true); err != nil {
+		t.Fatalf("shared Homebrew prefix: %v", err)
+	}
+	if _, err := trustedHelper(helper, canonical(t, exe), false); err == nil {
+		t.Fatal("privileged process trusted group-writable prefix")
+	}
+	if err := os.Chmod(filepath.Dir(helper), 0775); err != nil {
+		t.Fatal(err)
+	}
+	if _, err := trustedHelper(helper, canonical(t, exe), true); err == nil {
+		t.Fatal("helper-only group-writable directory trusted")
+	}
+	if pathWithin("/prefix-other/bin/qcat", "/prefix") {
+		t.Fatal("common string prefix treated as shared ancestor")
+	}
+}
+
+func TestRootRejectsUserOwnedHelper(t *testing.T) {
+	if os.Geteuid() != 0 {
+		t.Skip("requires root to create foreign-owned fixtures")
+	}
+	for _, target := range []string{"helper", "ancestor", "sticky-ancestor", "symlink"} {
+		t.Run(target, func(t *testing.T) {
+			prefix := t.TempDir()
+			exe := testExecutable(t, filepath.Join(prefix, "bin", "qcat"))
+			helper := testExecutable(t, filepath.Join(prefix, "libexec", "qcat-se"))
+			path := helper
+			if target == "symlink" {
+				path = filepath.Join(prefix, "qcat-se-link")
+				testSymlink(t, helper, path)
+				helper = path
+			} else if target != "helper" {
+				path = filepath.Dir(helper)
+			}
+			if target == "sticky-ancestor" {
+				if err := os.Chmod(path, 0777|os.ModeSticky); err != nil {
+					t.Fatal(err)
+				}
+			}
+			if err := os.Lchown(path, 10001, -1); err != nil {
+				t.Fatal(err)
+			}
+			if _, err := trustedHelper(helper, canonical(t, exe), false); err == nil {
+				t.Fatal("root trusted user-owned helper installation")
+			}
+		})
+	}
+}
diff --git a/internal/crypto/provider/se/se.go b/internal/crypto/provider/se/se.go
index aacf1ca..ff1a248 100644
--- a/internal/crypto/provider/se/se.go
+++ b/internal/crypto/provider/se/se.go
@@ -7,13 +7,10 @@ import (
 	"errors"
 	"fmt"
 	"io"
-	"os"
 	"os/exec"
-	"path/filepath"
 	"sync"
 
 	"github.com/ekarulf/quantumcat/internal/crypto/provider"
-	"github.com/ekarulf/quantumcat/internal/trust"
 )
 
 type Helper struct {
@@ -30,48 +27,9 @@ func Open() (*Helper, error) {
 	if err != nil {
 		return nil, err
 	}
-	if err := trustedHelper(path); err != nil {
-		return nil, fmt.Errorf("untrusted Secure Enclave helper: %w", err)
-	}
 	return start(exec.Command(path))
 }
 
-func helperPath() (string, error) {
-	var path string
-	// Environment-controlled executables must never cross a privilege boundary.
-	if os.Geteuid() != 0 {
-		path = os.Getenv("QCAT_ENCLAVE_HELPER")
-		if path == "" {
-			path = os.Getenv("QCAT_SE_HELPER") // Compatibility with existing LaunchAgents.
-		}
-	}
-	if path == "" {
-		exe, err := os.Executable()
-		if err != nil {
-			return "", err
-		}
-		path = filepath.Join(filepath.Dir(exe), "qcat-se")
-	}
-	if !filepath.IsAbs(path) {
-		return "", errors.New("QCAT_ENCLAVE_HELPER must be an absolute path")
-	}
-	return path, nil
-}
-
-func trustedHelper(path string) error {
-	if err := trust.Path(path, false); err != nil {
-		return err
-	}
-	info, err := os.Stat(path)
-	if err != nil {
-		return err
-	}
-	if info.Mode().Perm()&0111 == 0 {
-		return errors.New("helper is not executable")
-	}
-	return trust.Ancestors(path)
-}
-
 func start(cmd *exec.Cmd) (*Helper, error) {
 	in, err := cmd.StdinPipe()
 	if err != nil {
