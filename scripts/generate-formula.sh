#!/bin/bash
# Generates a Homebrew formula for vzy
# Usage: generate-formula.sh <version> <url> <sha256>
set -euo pipefail

VERSION="$1"
URL="$2"
SHA256="$3"

cat <<EOF
class Vzy < Formula
  desc "Swift VM harness for reproducible macOS guests via Virtualization.framework"
  homepage "https://github.com/obj-p/vzy"
  license "MIT"
  version "${VERSION}"

  url "${URL}"
  sha256 "${SHA256}"

  depends_on :macos
  depends_on arch: :arm64

  def install
    # \`vzy run\` compiles Swift scripts against the VZKit sources beside
    # the binary's real file, so the whole package tree lands in libexec
    # and bin gets a symlink (the binary resolves symlinks when locating
    # its package root).
    libexec.install Dir["*"]
    bin.install_symlink libexec/"vzy"
  end

  def caveats
    <<~EOS
      vzy requires an Apple Silicon Mac running macOS 14 or newer.
      \`vzy run\` compiles scripts with the Swift toolchain, so Xcode or
      the Command Line Tools must be installed.
    EOS
  end

  test do
    assert_match "vzy", shell_output("#{bin}/vzy --help")
  end
end
EOF
