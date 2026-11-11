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
// Overseas paths drop TCP 10443 and pass 443. A saved datacenter list and a
// help.getConfig dc_options list that omit a seed endpoint gain it back, and
// 8.156.40.105:10443 stays last so the first dial is still that endpoint.

static MTDatacenterAddress *MTSeedAddress(NSString *ip, uint16_t port, bool thisPortOnly) {
    return [[MTDatacenterAddress alloc] initWithIp:ip port:port preferForMedia:false restrictToTcp:false cdn:false preferForProxy:false secret:nil thisPortOnly:thisPortOnly];
}

static NSArray<NSNumber *> *MTSeedPorts(MTDatacenterAddressSet *set) {
    NSMutableArray<NSNumber *> *ports = [[NSMutableArray alloc] init];
    for (MTDatacenterAddress *address in set.addressList) {
        [ports addObject:@(address.port)];
    }
    return ports;
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

- (void)testSaved10443OnlyListGains443AndKeepsTheBuiltInIpLast {
    MTDatacenterAddress *saved = MTSeedAddress(@"api.tellomi.cn", 10443, false);
    MTDatacenterAddressSet *stored = [[MTDatacenterAddressSet alloc] initWithAddressList:@[saved]];
    NSArray *seed = TellomiSeedAddressSets(false)[@1].addressList;

    MTDatacenterAddressSet *merged = [stored addressSetByAddingSeedAddresses:seed];
    NSArray<MTDatacenterAddress *> *list = merged.addressList;
    XCTAssertEqual(list.count, 4u);
    XCTAssertEqual(list[0], saved);
    XCTAssertFalse(list[0].thisPortOnly);
    XCTAssertEqualObjects(list[1].ip, @"api.tellomi.cn");
    XCTAssertEqual(list[1].port, 443);
    XCTAssertEqualObjects(list[2].ip, @"8.156.40.105");
    XCTAssertEqual(list[2].port, 443);
    XCTAssertEqualObjects(list[3].ip, @"8.156.40.105");
    XCTAssertEqual(list[3].port, 10443);
    XCTAssertEqualObjects([merged addressSetByAddingSeedAddresses:seed], merged);
}

- (void)testServerListThatAlreadyHasBothPortsIsNotDuplicated {
    MTDatacenterAddress *primary = MTSeedAddress(@"api.tellomi.cn", 10443, true);
    MTDatacenterAddress *fallback = MTSeedAddress(@"api.tellomi.cn", 443, true);
    MTDatacenterAddressSet *stored = [[MTDatacenterAddressSet alloc] initWithAddressList:@[primary, fallback]];

    MTDatacenterAddressSet *merged = [stored addressSetByAddingSeedAddresses:TellomiSeedAddressSets(false)[@1].addressList];
    NSArray<MTDatacenterAddress *> *list = merged.addressList;
    XCTAssertEqual(list.count, 4u);
    XCTAssertEqual(list[0], primary);
    XCTAssertEqual(list[1], fallback);
    XCTAssertEqualObjects(list[2].ip, @"8.156.40.105");
    XCTAssertEqual(list[2].port, 443);
    XCTAssertEqualObjects(list[3].ip, @"8.156.40.105");
    XCTAssertEqual(list[3].port, 10443);
}

- (void)testDifferentHostIsKeptAnd10443StaysThePreferredEndpoint {
    MTDatacenterAddress *literal = MTSeedAddress(@"198.51.100.8", 10443, true);
    MTDatacenterAddressSet *stored = [[MTDatacenterAddressSet alloc] initWithAddressList:@[literal]];

    NSArray<MTDatacenterAddress *> *list = [stored addressSetByAddingSeedAddresses:TellomiSeedAddressSets(false)[@1].addressList].addressList;
    XCTAssertEqual(list.count, 5u);
    XCTAssertEqualObjects(list[0].ip, @"198.51.100.8");
    XCTAssertEqual(list[0].port, 10443);
    XCTAssertEqualObjects(list[1].ip, @"api.tellomi.cn");
    XCTAssertEqual(list[1].port, 443);
    XCTAssertEqualObjects(list[2].ip, @"api.tellomi.cn");
    XCTAssertEqual(list[2].port, 10443);
    XCTAssertEqualObjects(list[3].ip, @"8.156.40.105");
    XCTAssertEqual(list[3].port, 443);
    XCTAssertEqualObjects(list[4].ip, @"8.156.40.105");
    XCTAssertEqual(list[4].port, 10443);
}

- (void)testConfigReplacementAndFailureRotateTo443 {
    MTContext *context = MTTestMakeContext(false);
    [context setSeedAddressSetForDatacenterWithId:1 seedAddressSet:TellomiSeedAddressSets(false)[@1]];

    // What help.getConfig writes when dc_options lists only port 10443.
    MTDatacenterAddress *saved = MTSeedAddress(@"api.tellomi.cn", 10443, false);
    [context updateAddressSetForDatacenterWithId:1 addressSet:[[MTDatacenterAddressSet alloc] initWithAddressList:@[saved]] forceUpdateSchemes:false];
    [context updateAddressSetForDatacenterWithId:2 addressSet:[[MTDatacenterAddressSet alloc] initWithAddressList:@[MTSeedAddress(@"203.0.113.10", 443, false)]] forceUpdateSchemes:false];

    MTDatacenterAddressSet *effective = [context addressSetForDatacenterWithId:1];
    NSArray<MTDatacenterAddress *> *effectiveList = effective.addressList;
    XCTAssertEqual(effectiveList.count, 4u);
    XCTAssertEqualObjects(effectiveList.lastObject.ip, @"8.156.40.105");
    XCTAssertEqual(effectiveList.lastObject.port, 10443);
    XCTAssertEqual([context addressSetForDatacenterWithId:2].addressList.count, 1u);

    NSArray<MTTransportScheme *> *schemes = [context transportSchemesForDatacenterWithId:1 media:false enforceMedia:false isProxy:false];
    MTTransportScheme *first = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
    XCTAssertEqualObjects(first.address.ip, @"8.156.40.105");
    XCTAssertEqual(first.address.port, 10443);

    [context reportTransportSchemeFailureForDatacenterId:1 transportScheme:first];
    MTTransportScheme *second = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
    XCTAssertEqualObjects(second.address.ip, @"8.156.40.105");
    XCTAssertEqual(second.address.port, 443);
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

- (void)testExistingKeychainGainsTheFallbackPort {
    MTContext *context = MTTestMakeContext(false);
    [context setSeedAddressSetForDatacenterWithId:1 seedAddressSet:TellomiSeedAddressSets(false)[@1]];

    MTSeedFallbackKeychain *keychain = [[MTSeedFallbackKeychain alloc] init];
    MTDatacenterAddressSet *saved = [[MTDatacenterAddressSet alloc] initWithAddressList:@[MTSeedAddress(@"api.tellomi.cn", 10443, false)]];
    [keychain setObject:@{@1: saved} forKey:@"datacenterAddressSetById" group:@"persistent"];
    context.keychain = keychain;

    NSArray<MTDatacenterAddress *> *loaded = [context addressSetForDatacenterWithId:1].addressList;
    XCTAssertEqual(loaded.count, 4u);
    XCTAssertEqualObjects(loaded[0].ip, @"api.tellomi.cn");
    XCTAssertEqual(loaded[0].port, 10443);
    XCTAssertEqualObjects(loaded[1].ip, @"api.tellomi.cn");
    XCTAssertEqual(loaded[1].port, 443);
    XCTAssertEqualObjects(loaded.lastObject.ip, @"8.156.40.105");
    XCTAssertEqual(loaded.lastObject.port, 10443);
    NSDictionary *persisted = [keychain dictionaryForKey:@"datacenterAddressSetById" group:@"persistent"];
    MTDatacenterAddressSet *stored = persisted[@1];
    XCTAssertEqualObjects(stored.addressList.lastObject.ip, @"8.156.40.105");
    XCTAssertEqual(stored.addressList.lastObject.port, 10443);
    XCTAssertEqual(stored.addressList.count, 4u);
}

@end
