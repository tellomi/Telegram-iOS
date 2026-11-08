#import <Foundation/Foundation.h>

/// Tellomi's MTProto server, compiled from Tellomi/tellomi-server.json.
/// That JSON file is the only place the seed addresses, port and RSA key are set.
NS_ASSUME_NONNULL_BEGIN

/// Datacenter id -> hostnames. `testingEnvironment` selects the JSON's testing or production list.
NSDictionary<NSNumber *, NSArray<NSString *> *> *TellomiSeedAddresses(bool testingEnvironment);

/// TCP port for every seed address. Teamgram's docker gnetway publishes 10443.
uint16_t TellomiSeedPort(void);

/// Datacenter the first unauthorized connection opens. Teamgram docker has one, id 1.
NSInteger TellomiDefaultDatacenterId(void);

/// When true, the client does not resolve Telegram's `apv3.stel.com` backup addresses.
bool TellomiDisablesTelegramBackupDiscovery(void);

/// PKCS#1 PEM public keys for the production or the testing environment.
NSArray<NSString *> *TellomiServerPublicKeys(bool isProduction);

NS_ASSUME_NONNULL_END
