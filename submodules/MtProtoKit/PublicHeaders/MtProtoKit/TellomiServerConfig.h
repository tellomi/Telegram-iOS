#import <Foundation/Foundation.h>

@class MTDatacenterAddressSet;

/// Tellomi's MTProto server, compiled from Tellomi/tellomi-server.json.
/// That JSON file is the only place the seed addresses, ports and RSA key are set.
NS_ASSUME_NONNULL_BEGIN

/// Datacenter id -> hostnames. `testingEnvironment` selects the JSON's testing or production list.
NSDictionary<NSNumber *, NSArray<NSString *> *> *TellomiSeedAddresses(bool testingEnvironment);

/// TCP ports in dial preference order. Index 0 is `seed_port` (tried first).
/// Later entries are `seed_fallback_ports`, tried after the preferred port fails.
NSArray<NSNumber *> *TellomiSeedPorts(void);

/// Preferred TCP port. Equals `TellomiSeedPorts()[0]`. Teamgram's docker gnetway publishes 10443.
uint16_t TellomiSeedPort(void);

/// One address set per datacenter. Within each set the preferred port is last:
/// a transport that breaks ties by picking the last address dials it first, then
/// a fallback. Every address is `thisPortOnly`, so discovery does not add 80 or 5222.
NSDictionary<NSNumber *, MTDatacenterAddressSet *> *TellomiSeedAddressSets(bool testingEnvironment);

/// Datacenter the first unauthorized connection opens. Teamgram docker has one, id 1.
NSInteger TellomiDefaultDatacenterId(void);

/// When true, the client does not resolve Telegram's `apv3.stel.com` backup addresses.
bool TellomiDisablesTelegramBackupDiscovery(void);

/// PKCS#1 PEM public keys for the production or the testing environment.
NSArray<NSString *> *TellomiServerPublicKeys(bool isProduction);

NS_ASSUME_NONNULL_END
