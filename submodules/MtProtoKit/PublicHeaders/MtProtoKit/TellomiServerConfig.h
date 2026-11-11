#import <Foundation/Foundation.h>

#import <MtProtoKit/MTDatacenterAddressSet.h>

/// Tellomi's MTProto server, compiled from Tellomi/tellomi-server.json.
/// That JSON file is the only place the seed addresses, ports and RSA key are set.
NS_ASSUME_NONNULL_BEGIN

/// Datacenter id -> seed hosts, in dial preference order. The first host is tried first.
/// `testingEnvironment` selects the JSON's testing or production list.
NSDictionary<NSNumber *, NSArray<NSString *> *> *TellomiSeedAddresses(bool testingEnvironment);

/// TCP ports in dial preference order. Index 0 is `seed_port` (tried first).
NSArray<NSNumber *> *TellomiSeedPorts(void);

/// Preferred TCP port. Equals `TellomiSeedPorts()[0]`. Teamgram's docker gnetway publishes 10443.
uint16_t TellomiSeedPort(void);

/// One address set per datacenter. Seed hosts and ports are in dial preference
/// order. The address list is that order reversed, so the first host's preferred
/// port is last and a transport that breaks ties by picking the last address
/// dials it first, then the next fallback. Every address is `thisPortOnly`, so
/// discovery does not add another port.
NSDictionary<NSNumber *, MTDatacenterAddressSet *> *TellomiSeedAddressSets(bool testingEnvironment);

/// Datacenter the first unauthorized connection opens. Teamgram docker has one, id 1.
NSInteger TellomiDefaultDatacenterId(void);

/// When true, the client does not resolve Telegram's `apv3.stel.com` backup addresses.
bool TellomiDisablesTelegramBackupDiscovery(void);

/// PKCS#1 PEM public keys for the production or the testing environment.
NSArray<NSString *> *TellomiServerPublicKeys(bool isProduction);

NS_ASSUME_NONNULL_END
