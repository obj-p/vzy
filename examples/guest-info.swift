import VZYKit

let script = Script(
    usage: "vzy run examples/guest-info.swift <bundle> [admin-password]",
    min: 2
)
let bundle = try script.bundle()
let adminPassword = script[optional: 2] ?? "vzvz"

try await Guest.session(bundle: bundle, adminPass: adminPassword) { guest in
    print(try await guest.sh("sw_vers"))
}
