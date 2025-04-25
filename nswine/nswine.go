//go:build linux && (amd64 || arm64)

// Command nswine creates a standalone wineprefix of a Wine 10.0 build for use
// with nswrap.
//
// We could build Wine ourselves if needed, but our changes aren't too intrusive
// and it's much simpler and faster to iterate this way. It also wasn't possible
// before with older versions of wine since they had bugs we needed to patch,
// and they weren't entirely modular out of the box to the same extent as Wine
// 10.
//
// It does not currently support cross-compiling since it needs to run wineboot
// to initialize the prefix.
//
// It supports x86_64, and arm64 (via fex arm64ec).
//
// The generated wineprefix works independently of the system wine.
//
// It forces the use of nulldrv for display and no audio driver.
//
// Optionally, it can remove a bunch of unused libraries and services to
// significantly reduce the size and number of processes.
//
// Optionally, it can copy non-libc system libs into the output folder for
// completely standalone usage on any glibc distro. The build host should be
// running Debian, as this is what the wine binaries were built on, and is also
// where this logic was tested.
//
// While there are no official ARM64 wine builds, hangover on 10.x is close
// enough, as it's mostly converged with official wine now, especially when only
// looking at non-WoW64 arm64ec and ignoring arm32/i386.
package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"iter"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/lmittmann/tint"
)

var (
	Prefix   = flag.String("prefix", "/usr", "wine install prefix (will be modified in-place)")
	Output   = flag.String("output", "/opt/northstar-runtime", "output directory")
	Optimize = flag.Bool("optimize", false, "remove unused libraries and services")
	Vendor   = flag.Bool("vendor", false, "copy native libs from the build host")
)

func main() {
	flag.Parse()

	slog.SetDefault(slog.New(tint.NewHandler(os.Stdout, &tint.Options{
		AddSource:  true,
		TimeFormat: time.Kitchen,
	})))

	if err := run(); err != nil {
		slog.Error("failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	slog.Info("getting wine version")
	var wineBuildID string
	if buf, err := exec.Command(filepath.Join(*Prefix, "bin", "wine"), "--version").Output(); err != nil {
		if xx, ok := err.(*exec.ExitError); ok {
			err = fmt.Errorf("%v (stderr: %q)", err, xx.Stderr)
		}
		return err
	} else {
		wineBuildID = strings.TrimRight(string(buf), "\n")
	}
	slog.Info("got wine version", "build_id", wineBuildID)

	// TODO: patch unix/ntdll.so asciiz string "wine-#.## (Type)" kind of thing (wine --version output) to change the output of wine_get_build_id to "nsSHA[:7]"

	slog.Info("patching default graphics driver to null")
	// this is the only way other than recompiling to get it to use nulldrv
	// during prefix initialization
	if err := transform(filepath.Join(*Prefix, "lib", "wine", archt("x86_64-windows", "aarch64-windows"), "explorer.exe"), func(buf []byte) ([]byte, error) {
		i := bytes.Index(buf, u8to16[string, []byte]("mac,x11,wayland\x00"))
		if i == -1 {
			return nil, fmt.Errorf("couldn't find default graphics driver value")
		}
		copy(buf[:i], u8to16[string, []byte]("null\x00"))
		return buf, nil
	}); err != nil {
		return err
	}

	slog.Info("patching wine.inf")
	// 	- mostly so wineboot doesn't complain as much or error out
	// 	- a little bit of extra tidying
	if err := transform(filepath.Join(*Prefix, "share", "wine", "wine.inf"),
		trdiff(infilt(func(emit func(section string, line string), inf iter.Seq2[string, string]) error {
			for section, line := range inf {
				if line != "" {
					var keep bool
					switch {
					default:
						keep = true
					case *Optimize && section == "Wow64":
					case *Optimize && section == "FakeDllsWow64":
					case *Optimize && section == "FakeDllsWin32":
					case *Optimize && section == "Tapi": // telephony
					case *Optimize && section == "DirectX":
					}
					if !keep {
						continue // ignore section contents
					}
				}
				emit(section, line)
			}
			return nil
		})),
	); err != nil {
		return err
	}

	// TODO: everything else
	return errors.ErrUnsupported
}
