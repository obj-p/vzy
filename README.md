<p align="center">
  <img src="assets/hero-icon.svg" width="128" height="128" alt="vzy icon">
</p>

# vzy

`vzy` is a Swift VM harness for provisioning and driving disposable macOS
guests with `Virtualization.framework`.

It can install macOS from an IPSW into a bundle, boot and stop that VM, create
and restore snapshots, provision SSH through Setup Assistant automation, and run
Swift scripts against `VZKit`.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- Xcode command line tools
- Swift 6 toolchain

## Build

Use the wrapper script instead of plain `swift build`; it signs the resulting
binary with the virtualization entitlement required at runtime.

```sh
./build.sh debug
```

The binary is written under SwiftPM's build directory. To make it easy to call
from anywhere:

```sh
ln -sf "$(swift build -c debug --show-bin-path)/vzy" /usr/local/bin/vzy
```

## Basic Flow

Create and install a VM bundle:

```sh
vzy install ~/VMs/work.vm --ipsw latest --cpu-count 4 --memory-mib 8192 --disk-gib 128
```

Run Setup Assistant automation and provision SSH:

```sh
vzy setup ~/VMs/work.vm
```

Boot the VM:

```sh
vzy boot ~/VMs/work.vm
```

Run a command over SSH:

```sh
vzy ssh ~/VMs/work.vm -- uname -a
```

Create a snapshot:

```sh
vzy snapshot ~/VMs/work.vm base
```

Stop the VM:

```sh
vzy stop ~/VMs/work.vm
```

## Notes

- Downloaded IPSWs are cached under `~/.cache/vz/ipsw/`.
- VM bundles contain generated SSH keys and mutable guest disks; keep them out
  of git.
- `Resources/vzy.entitlements` is used by `build.sh` for ad-hoc signing.
