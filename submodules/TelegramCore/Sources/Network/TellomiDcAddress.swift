import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// One `dcOption` from `help.getConfig`, before the literal filter.
///
/// `flags` is the TL bitfield: bit 0 IPv6, bit 1 media-only, bit 2 TCP-only,
/// bit 3 CDN, bit 4 static/proxy. Bit 5 (`this_port_only`) is not stored on
/// `MTDatacenterAddress` and is not read here.
struct TellomiDcOptionInput: Equatable {
    var datacenterId: Int
    var host: String
    var port: Int
    var flags: Int
    var secret: Data?

    var ipv6: Bool { return (flags & (1 << 0)) != 0 }
    var preferForMedia: Bool { return (flags & (1 << 1)) != 0 }
    var restrictToTcp: Bool { return (flags & (1 << 2)) != 0 }
    var cdn: Bool { return (flags & (1 << 3)) != 0 }
    var preferForProxy: Bool { return (flags & (1 << 4)) != 0 }
}

/// An address `help.getConfig` may write into the persistent datacenter list.
///
/// The seed in `Tellomi/tellomi-server.json` does not pass through this type.
/// iOS still dials that hostname with `getaddrinfo` when the persistent list
/// for the datacenter is missing or empty. A hostname that arrives in
/// `dc_options` is dropped, matching Android `tellomiAcceptDcAddress`.
struct TellomiAcceptedDcAddress: Equatable {
    var datacenterId: Int
    var host: String
    var port: UInt16
    var preferForMedia: Bool
    var restrictToTcp: Bool
    var cdn: Bool
    var preferForProxy: Bool
    var secret: Data?
}

/// Same rule as Android `tellomiAcceptDcAddress` (`inet_pton` of the family
/// selected by the IPv6 flag, port in 1...65535).
func tellomiAcceptDcAddress(host: String, port: Int, ipv6: Bool) -> Bool {
    if port <= 0 || port > 65535 || host.isEmpty {
        return false
    }
    if ipv6 {
        var parsed = in6_addr()
        return host.withCString { inet_pton(AF_INET6, $0, &parsed) == 1 }
    }
    var parsed = in_addr()
    return host.withCString { inet_pton(AF_INET, $0, &parsed) == 1 }
}

/// Datacenters that have at least one usable address.
///
/// A datacenter id that is absent — including a config whose options were all
/// rejected, and an empty `dc_options` — must not be passed to
/// `updateAddressSetForDatacenter`. The seed, or the last saved IP list, stays.
/// Within one datacenter the first `host`+`port`+media flag wins, which is how
/// Android drops a repeated address inside one family. Order of the kept
/// addresses is the order they appeared in `dc_options`.
func tellomiAcceptedDatacenterAddresses(_ options: [TellomiDcOptionInput]) -> [Int: [TellomiAcceptedDcAddress]] {
    var accepted: [Int: [TellomiAcceptedDcAddress]] = [:]
    for option in options {
        if option.datacenterId <= 0 {
            continue
        }
        if !tellomiAcceptDcAddress(host: option.host, port: option.port, ipv6: option.ipv6) {
            continue
        }
        let port = UInt16(option.port)
        var list = accepted[option.datacenterId] ?? []
        let repeated = list.contains { existing in
            return existing.host == option.host && existing.port == port && existing.preferForMedia == option.preferForMedia
        }
        if repeated {
            continue
        }
        list.append(TellomiAcceptedDcAddress(
            datacenterId: option.datacenterId,
            host: option.host,
            port: port,
            preferForMedia: option.preferForMedia,
            restrictToTcp: option.restrictToTcp,
            cdn: option.cdn,
            preferForProxy: option.preferForProxy,
            secret: option.secret
        ))
        accepted[option.datacenterId] = list
    }
    return accepted
}
