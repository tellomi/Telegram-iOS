#import <XCTest/XCTest.h>

#import <MtProtoKit/MTDatacenterAddress.h>
#import <MtProtoKit/MTDatacenterAddressSet.h>
#import <MtProtoKit/MTKeychain.h>
#import <MtProtoKit/MTTransportScheme.h>
#import <MtProtoKit/TellomiServerConfig.h>

#import "MTTcpConnection.h"

#import "MTTestSupport.h"

// A fresh production install dials the built-in IP 8.156.40.105 on 10443, then
// that IP on 443, then api.tellomi.cn on 10443, then that name on 443.
// A non-empty learned list is used in the order it was saved. An empty list
// falls back to that seed.

static MTDatacenterAddress *MTSeedAddress(NSString *ip, uint16_t port, bool thisPortOnly) {
    return [[MTDatacenterAddress alloc] initWithIp:ip port:port preferForMedia:false restrictToTcp:false cdn:false preferForProxy:false secret:nil thisPortOnly:thisPortOnly];
}

@interface MTSeedFallbackKeychain : NSObject <MTKeychain>
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *values;
@end

@implementation MTSeedFallbackKeychain

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _values = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSString *)storageKey:(NSString *)key group:(NSString *)group {
    return [NSString stringWithFormat:@"%@/%@", group, key];
}

- (void)setObject:(id)object forKey:(NSString *)key group:(NSString *)group {
    if (object == nil) {
        [_values removeObjectForKey:[self storageKey:key group:group]];
    } else {
        _values[[self storageKey:key group:group]] = object;
    }
}

- (NSDictionary *)dictionaryForKey:(NSString *)key group:(NSString *)group {
    id value = _values[[self storageKey:key group:group]];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSNumber *)numberForKey:(NSString *)key group:(NSString *)group {
    id value = _values[[self storageKey:key group:group]];
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

- (void)removeObjectForKey:(NSString *)key group:(NSString *)group {
    [_values removeObjectForKey:[self storageKey:key group:group]];
}

@end

@interface MTSeedFallbackTests : XCTestCase
@end

@implementation MTSeedFallbackTests

- (void)testCompiledSeedPrefers10443Then443 {
    XCTAssertEqualObjects(TellomiSeedPorts(), (@[@10443, @443]));
    XCTAssertEqual(TellomiSeedPort(), 10443);
    XCTAssertEqualObjects(TellomiSeedAddresses(false)[@1], (@[@"8.156.40.105", @"api.tellomi.cn"]));
    XCTAssertEqualObjects(TellomiSeedAddresses(true)[@1], (@[@"api.tellomi.cn"]));

    // The address list is the preference order reversed. The last address is
    // the first dial: the built-in IP on 10443.
    NSArray<MTDatacenterAddress *> *list = TellomiSeedAddressSets(false)[@1].addressList;
    XCTAssertEqual(list.count, 4u);
    XCTAssertEqualObjects(list[0].ip, @"api.tellomi.cn");
    XCTAssertEqual(list[0].port, 443);
    XCTAssertTrue(list[0].thisPortOnly);
    XCTAssertEqualObjects(list[1].ip, @"api.tellomi.cn");
    XCTAssertEqual(list[1].port, 10443);
    XCTAssertTrue(list[1].thisPortOnly);
    XCTAssertEqualObjects(list[2].ip, @"8.156.40.105");
    XCTAssertEqual(list[2].port, 443);
    XCTAssertTrue(list[2].thisPortOnly);
    XCTAssertEqualObjects(list[3].ip, @"8.156.40.105");
    XCTAssertEqual(list[3].port, 10443);
    XCTAssertTrue(list[3].thisPortOnly);

    NSArray<MTDatacenterAddress *> *testing = TellomiSeedAddressSets(true)[@1].addressList;
    XCTAssertEqual(testing.count, 2u);
    XCTAssertEqualObjects(testing[0].ip, @"api.tellomi.cn");
    XCTAssertEqual(testing[0].port, 443);
    XCTAssertEqualObjects(testing[1].ip, @"api.tellomi.cn");
    XCTAssertEqual(testing[1].port, 10443);
}

- (void)testFreshInstallTriesBuiltInIpThen443ThenHostname {
    MTContext *context = MTTestMakeContext(false);
    [context setSeedAddressSetForDatacenterWithId:1 seedAddressSet:TellomiSeedAddressSets(false)[@1]];
    NSArray<MTTransportScheme *> *schemes = [context transportSchemesForDatacenterWithId:1 media:false enforceMedia:false isProxy:false];
    NSArray<NSArray *> *expected = @[
        @[@"8.156.40.105", @10443],
        @[@"8.156.40.105", @443],
        @[@"api.tellomi.cn", @10443],
        @[@"api.tellomi.cn", @443],
    ];
    for (NSArray *endpoint in expected) {
        MTTransportScheme *chosen = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
        XCTAssertEqualObjects(chosen.address.ip, endpoint[0]);
        XCTAssertEqual(chosen.address.port, [endpoint[1] unsignedShortValue]);
        [context reportTransportSchemeFailureForDatacenterId:1 transportScheme:chosen];
    }
}

- (void)testLearnedConfigIsUsedAsReceived {
    MTContext *context = MTTestMakeContext(false);
    [context setSeedAddressSetForDatacenterWithId:1 seedAddressSet:TellomiSeedAddressSets(false)[@1]];

    // The built-in IP is in the middle. Moving the preferred seed to the end
    // would make the first dial 8.156.40.105:10443.
    MTDatacenterAddress *first = MTSeedAddress(@"203.0.113.10", 10443, true);
    MTDatacenterAddress *second = MTSeedAddress(@"203.0.113.10", 443, true);
    MTDatacenterAddress *third = MTSeedAddress(@"8.156.40.105", 10443, true);
    MTDatacenterAddress *fourth = MTSeedAddress(@"203.0.113.11", 443, true);
    NSArray<MTDatacenterAddress *> *received = @[first, second, third, fourth];
    [context updateAddressSetForDatacenterWithId:1 addressSet:[[MTDatacenterAddressSet alloc] initWithAddressList:received] forceUpdateSchemes:false];

    NSArray<MTDatacenterAddress *> *list = [context addressSetForDatacenterWithId:1].addressList;
    XCTAssertEqual(list.count, received.count);
    XCTAssertEqual(list[0], first);
    XCTAssertEqual(list[1], second);
    XCTAssertEqual(list[2], third);
    XCTAssertEqual(list[3], fourth);

    NSArray<MTTransportScheme *> *schemes = [context transportSchemesForDatacenterWithId:1 media:false enforceMedia:false isProxy:false];
    MTTransportScheme *chosen = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
    XCTAssertEqualObjects(chosen.address.ip, @"203.0.113.11");
    XCTAssertEqual(chosen.address.port, 443);
}

- (void)testEmptyConfigFallsBackToTheSeed {
    MTContext *context = MTTestMakeContext(false);
    [context setSeedAddressSetForDatacenterWithId:1 seedAddressSet:TellomiSeedAddressSets(false)[@1]];
    [context updateAddressSetForDatacenterWithId:1 addressSet:[[MTDatacenterAddressSet alloc] initWithAddressList:@[]] forceUpdateSchemes:false];

    NSArray<MTTransportScheme *> *schemes = [context transportSchemesForDatacenterWithId:1 media:false enforceMedia:false isProxy:false];
    MTTransportScheme *chosen = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
    XCTAssertEqualObjects(chosen.address.ip, @"8.156.40.105");
    XCTAssertEqual(chosen.address.port, 10443);
    XCTAssertEqual([context addressSetForDatacenterWithId:1].addressList.count, 4u);
}

- (void)testSuccessOn10443DoesNotMoveTheNextDialTo443 {
    // A client that never sees 10443 fail keeps dialing it. Recording a
    // response only marks that endpoint as proven; it does not change the tie.
    MTContext *context = MTTestMakeContext(false);
    [context setSeedAddressSetForDatacenterWithId:1 seedAddressSet:TellomiSeedAddressSets(false)[@1]];
    NSArray<MTTransportScheme *> *schemes = [context transportSchemesForDatacenterWithId:1 media:false enforceMedia:false isProxy:false];
    MTTransportScheme *first = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
    XCTAssertEqualObjects(first.address.ip, @"8.156.40.105");
    XCTAssertEqual(first.address.port, 10443);
    XCTAssertFalse([context transportSchemeHasReceivedResponseForDatacenterId:1 transportScheme:first]);

    [context reportTransportSchemeSuccessForDatacenterId:1 transportScheme:first];
    XCTAssertTrue([context transportSchemeHasReceivedResponseForDatacenterId:1 transportScheme:first]);
    MTTransportScheme *again = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
    XCTAssertEqualObjects(again.address.ip, @"8.156.40.105");
    XCTAssertEqual(again.address.port, 10443);
}

- (void)testConnectTimeoutStaysLongAfterTheEndpointHasAnswered {
    XCTAssertEqualWithAccuracy(MTTcpConnectTimeoutInterval(false), 5.0, 0.001);
    XCTAssertEqualWithAccuracy(MTTcpConnectTimeoutInterval(true), 12.0, 0.001);
}

- (void)testExistingKeychainKeepsTheLearnedList {
    MTContext *context = MTTestMakeContext(false);
    [context setSeedAddressSetForDatacenterWithId:1 seedAddressSet:TellomiSeedAddressSets(false)[@1]];

    MTSeedFallbackKeychain *keychain = [[MTSeedFallbackKeychain alloc] init];
    MTDatacenterAddress *savedAddress = MTSeedAddress(@"203.0.113.10", 443, false);
    MTDatacenterAddressSet *saved = [[MTDatacenterAddressSet alloc] initWithAddressList:@[savedAddress]];
    [keychain setObject:@{@1: saved} forKey:@"datacenterAddressSetById" group:@"persistent"];
    context.keychain = keychain;

    NSArray<MTDatacenterAddress *> *loaded = [context addressSetForDatacenterWithId:1].addressList;
    XCTAssertEqual(loaded.count, 1u);
    XCTAssertEqualObjects(loaded[0].ip, @"203.0.113.10");
    XCTAssertEqual(loaded[0].port, 443);
    NSDictionary *persisted = [keychain dictionaryForKey:@"datacenterAddressSetById" group:@"persistent"];
    MTDatacenterAddressSet *stored = persisted[@1];
    XCTAssertEqual(stored.addressList.count, 1u);
    MTDatacenterAddress *persistedAddress = stored.addressList[0];
    XCTAssertEqualObjects(persistedAddress.ip, @"203.0.113.10");
    XCTAssertEqual(persistedAddress.port, 443);
}

@end
