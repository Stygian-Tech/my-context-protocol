package cli

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestInstallMakesCommandAvailableOutsideCheckout(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX make installer")
	}
	makePath, err := exec.LookPath("make")
	if err != nil {
		t.Fatal(err)
	}
	_, source, _, _ := runtime.Caller(0)
	project := filepath.Clean(filepath.Join(filepath.Dir(source), "../.."))
	for _, mode := range []string{"default", "prefix with spaces", "explicit bindir", "missing PATH"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			home := filepath.Join(root, "home")
			checkout := filepath.Join(root, "checkout")
			tools := filepath.Join(root, "tools")
			for _, dir := range []string{home, checkout, tools, filepath.Join(checkout, "scripts")} {
				if err := os.MkdirAll(dir, 0755); err != nil {
					t.Fatal(err)
				}
			}
			for _, name := range []string{"Makefile", "scripts/install.sh"} {
				b, err := os.ReadFile(filepath.Join(project, name))
				if err != nil {
					t.Fatal(err)
				}
				if err = os.WriteFile(filepath.Join(checkout, name), b, 0644); err != nil {
					t.Fatal(err)
				}
			}
			fakeGo := `#!/bin/sh
set -eu
while [ "$1" != "-o" ]; do shift; done
shift
printf '#!/bin/sh\nprintf "myctx-install-test\\n"\n' > "$1"
`
			if err = os.WriteFile(filepath.Join(tools, "go"), []byte(fakeGo), 0755); err != nil {
				t.Fatal(err)
			}
			bindir := filepath.Join(home, ".local", "bin")
			args := []string{"install"}
			if mode == "prefix with spaces" {
				prefix := filepath.Join(root, "custom prefix")
				bindir = filepath.Join(prefix, "bin")
				args = append(args, "PREFIX="+prefix)
			}
			if mode == "explicit bindir" {
				bindir = filepath.Join(root, "custom-bin")
				args = append(args, "BINDIR="+bindir)
			}
			taskPath := tools + ":/usr/bin:/bin"
			if mode != "missing PATH" {
				taskPath = bindir + ":" + taskPath
			}
			cmd := exec.Command(makePath, args...)
			cmd.Dir = checkout
			// Explicit HOME/PATH keeps the test away from installed user binaries.
			cmd.Env = []string{"HOME=" + home, "PATH=" + taskPath}
			output, err := cmd.CombinedOutput()
			if mode == "missing PATH" {
				if err == nil || !strings.Contains(string(output), "not on PATH") {
					t.Fatalf("expected actionable PATH failure: %v %s", err, output)
				}
				if _, err = os.Stat(bindir); !os.IsNotExist(err) {
					t.Fatalf("preflight created destination: %v", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("make install: %v %s", err, output)
			}
			run := exec.Command("/bin/sh", "-c", "myctx help")
			run.Dir = root
			run.Env = cmd.Env
			output, err = run.CombinedOutput()
			if err != nil || string(output) != "myctx-install-test\n" {
				t.Fatalf("outside-checkout invocation: %v %q", err, output)
			}
		})
	}
}
