#import <MtProtoKit/TellomiServerConfig.h>

#import <MtProtoKit/MTLogging.h>

#import "TellomiServerConfigJSON.h"

static NSDictionary *TellomiParsedConfig(void) {
    static NSDictionary *config = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSData *data = [TELLOMI_SERVER_CONFIG_JSON dataUsingEncoding:NSUTF8StringEncoding];
        id object = nil;
        if (data != nil) {
            object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }
        if ([object isKindOfClass:[NSDictionary class]]) {
            config = object;
        } else {
            if (MTLogEnabled()) {
                MTLog(@"[Tellomi] server config JSON did not parse; no seed addresses will be installed");
            }
            config = @{};
        }
    });
    return config;
}

static NSDictionary<NSString *, id> *TellomiSeedMap(bool testingEnvironment) {
    NSDictionary *seeds = TellomiParsedConfig()[@"seeds"];
    if (![seeds isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    NSString *name = testingEnvironment ? @"testing" : @"production";
    id map = seeds[name];
    if (![map isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    return map;
}

NSDictionary<NSNumber *, NSArray<NSString *> *> *TellomiSeedAddresses(bool testingEnvironment) {
    NSMutableDictionary<NSNumber *, NSArray<NSString *> *> *result = [[NSMutableDictionary alloc] init];
    [TellomiSeedMap(testingEnvironment) enumerateKeysAndObjectsUsingBlock:^(id key, id obj, __unused BOOL *stop) {
        if (![key isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSArray class]]) {
            return;
        }
        NSInteger datacenterId = [(NSString *)key integerValue];
        if (datacenterId <= 0) {
            return;
        }
        NSMutableArray<NSString *> *hosts = [[NSMutableArray alloc] init];
        for (id host in (NSArray *)obj) {
            if ([host isKindOfClass:[NSString class]] && [(NSString *)host length] != 0) {
                [hosts addObject:host];
            }
        }
        if (hosts.count != 0) {
            result[@(datacenterId)] = hosts;
        }
    }];
    return result;
}

uint16_t TellomiSeedPort(void) {
    id port = TellomiParsedConfig()[@"seed_port"];
    if ([port isKindOfClass:[NSNumber class]]) {
        NSInteger value = [(NSNumber *)port integerValue];
        if (value > 0 && value <= 65535) {
            return (uint16_t)value;
        }
    }
    return 10443;
}

NSInteger TellomiDefaultDatacenterId(void) {
    id datacenterId = TellomiParsedConfig()[@"default_datacenter_id"];
    if ([datacenterId isKindOfClass:[NSNumber class]]) {
        NSInteger value = [(NSNumber *)datacenterId integerValue];
        if (value > 0) {
            return value;
        }
    }
    return 1;
}

bool TellomiDisablesTelegramBackupDiscovery(void) {
    id flag = TellomiParsedConfig()[@"disable_telegram_backup_discovery"];
    if ([flag isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)flag boolValue];
    }
    // A missing flag stays off Telegram's DNS backup. That lookup would replace
    // these seeds with Telegram's datacenters.
    return true;
}

NSArray<NSString *> *TellomiServerPublicKeys(bool isProduction) {
    NSDictionary *keys = TellomiParsedConfig()[@"public_keys"];
    if (![keys isKindOfClass:[NSDictionary class]]) {
        return @[];
    }
    id list = keys[isProduction ? @"production" : @"testing"];
    if (![list isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray<NSString *> *result = [[NSMutableArray alloc] init];
    for (id pem in (NSArray *)list) {
        if ([pem isKindOfClass:[NSString class]] && [(NSString *)pem length] != 0) {
            [result addObject:pem];
        }
    }
    return result;
}
