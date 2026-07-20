<p align="center">
  <img src="assets/hero-icon.svg" width="128" height="128" alt="vzy icon">
</p>

# vzy

`vzy` is a Swift VM harness for provisioning and driving reproducible macOS
guests with `Virtualization.framework`.

It can install macOS from an IPSW into a bundle, boot and stop that VM, create
and restore snapshots, provision SSH through Setup Assistant automation, and run
Swift scripts against `VZYKit`.

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

## Swift Scripts

`vzy run` compiles and signs a Swift file against `VZYKit`, then runs it with
the virtualization entitlement. For example, the bundled
[`guest-info.swift`](examples/guest-info.swift) script boots a guest, waits for
SSH, prints its macOS version, and stops it:

```sh
vzy run examples/guest-info.swift ~/VMs/work.vm
```
