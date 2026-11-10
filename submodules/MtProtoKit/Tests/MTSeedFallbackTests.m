#import <XCTest/XCTest.h>

#import <MtProtoKit/MTDatacenterAddress.h>
#import <MtProtoKit/MTDatacenterAddressSet.h>
#import <MtProtoKit/MTKeychain.h>
#import <MtProtoKit/MTTransportScheme.h>
#import <MtProtoKit/TellomiServerConfig.h>

#import "MTTcpConnection.h"

#import "MTTestSupport.h"

// Overseas paths drop TCP 10443 and pass 443. The seed keeps both. A saved
// datacenter list and a help.getConfig dc_options list that name only 10443
// gain 443, and 10443 stays last so the first dial is still 10443. After that
// port is marked failed, the next choice is 443.

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

    MTDatacenterAddressSet *production = TellomiSeedAddressSets(false)[@1];
    NSArray<MTDatacenterAddress *> *list = production.addressList;
    XCTAssertEqual(list.count, 2u);
    XCTAssertEqualObjects(list[0].ip, @"api.tellomi.cn");
    XCTAssertEqual(list[0].port, 443);
    XCTAssertTrue(list[0].thisPortOnly);
    XCTAssertEqualObjects(list[1].ip, @"api.tellomi.cn");
    XCTAssertEqual(list[1].port, 10443);
    XCTAssertTrue(list[1].thisPortOnly);
    XCTAssertEqualObjects(TellomiSeedAddressSets(true)[@1], production);
}

- (void)testSaved10443OnlyListGains443AndKeepsTheSavedAddressLast {
    MTDatacenterAddress *saved = MTSeedAddress(@"api.tellomi.cn", 10443, false);
    MTDatacenterAddressSet *stored = [[MTDatacenterAddressSet alloc] initWithAddressList:@[saved]];
    NSArray *seed = TellomiSeedAddressSets(false)[@1].addressList;

    MTDatacenterAddressSet *merged = [stored addressSetByAddingSeedAddresses:seed];
    XCTAssertEqualObjects(MTSeedPorts(merged), (@[@443, @10443]));
    XCTAssertEqual(merged.addressList.lastObject, saved);
    XCTAssertFalse(((MTDatacenterAddress *)merged.addressList.lastObject).thisPortOnly);
    XCTAssertEqualObjects([merged addressSetByAddingSeedAddresses:seed], merged);
}

- (void)testServerListThatAlreadyHasBothPortsIsNotDuplicated {
    MTDatacenterAddress *primary = MTSeedAddress(@"api.tellomi.cn", 10443, true);
    MTDatacenterAddress *fallback = MTSeedAddress(@"api.tellomi.cn", 443, true);
    MTDatacenterAddressSet *stored = [[MTDatacenterAddressSet alloc] initWithAddressList:@[primary, fallback]];

    MTDatacenterAddressSet *merged = [stored addressSetByAddingSeedAddresses:TellomiSeedAddressSets(false)[@1].addressList];
    XCTAssertEqualObjects(MTSeedPorts(merged), (@[@443, @10443]));
    XCTAssertEqual(merged.addressList.count, 2u);
}

- (void)testDifferentHostIsKeptAnd10443StaysThePreferredEndpoint {
    MTDatacenterAddress *literal = MTSeedAddress(@"8.137.39.82", 10443, true);
    MTDatacenterAddressSet *stored = [[MTDatacenterAddressSet alloc] initWithAddressList:@[literal]];

    NSArray<MTDatacenterAddress *> *list = [stored addressSetByAddingSeedAddresses:TellomiSeedAddressSets(false)[@1].addressList].addressList;
    XCTAssertEqual(list.count, 3u);
    XCTAssertEqualObjects(list[0].ip, @"8.137.39.82");
    XCTAssertEqual(list[0].port, 10443);
    XCTAssertEqualObjects(list[1].ip, @"api.tellomi.cn");
    XCTAssertEqual(list[1].port, 443);
    XCTAssertEqualObjects(list[2].ip, @"api.tellomi.cn");
    XCTAssertEqual(list[2].port, 10443);
}

- (void)testConfigReplacementAndFailureRotateTo443 {
    MTContext *context = MTTestMakeContext(false);
    [context setSeedAddressSetForDatacenterWithId:1 seedAddressSet:TellomiSeedAddressSets(false)[@1]];

    // What help.getConfig writes when dc_options lists only the old port.
    MTDatacenterAddress *saved = MTSeedAddress(@"api.tellomi.cn", 10443, false);
    [context updateAddressSetForDatacenterWithId:1 addressSet:[[MTDatacenterAddressSet alloc] initWithAddressList:@[saved]] forceUpdateSchemes:false];
    [context updateAddressSetForDatacenterWithId:2 addressSet:[[MTDatacenterAddressSet alloc] initWithAddressList:@[MTSeedAddress(@"203.0.113.10", 443, false)]] forceUpdateSchemes:false];

    MTDatacenterAddressSet *effective = [context addressSetForDatacenterWithId:1];
    XCTAssertEqualObjects(MTSeedPorts(effective), (@[@443, @10443]));
    XCTAssertEqual([context addressSetForDatacenterWithId:2].addressList.count, 1u);

    NSArray<MTTransportScheme *> *schemes = [context transportSchemesForDatacenterWithId:1 media:false enforceMedia:false isProxy:false];
    MTTransportScheme *first = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
    XCTAssertEqual(first.address.port, 10443);

    [context reportTransportSchemeFailureForDatacenterId:1 transportScheme:first];
    MTTransportScheme *second = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
    XCTAssertEqual(second.address.port, 443);
}

- (void)testSuccessOn10443DoesNotMoveTheNextDialTo443 {
    // A client that never sees 10443 fail keeps dialing it. Recording a
    // response only marks that endpoint as proven; it does not change the tie.
    MTContext *context = MTTestMakeContext(false);
    [context setSeedAddressSetForDatacenterWithId:1 seedAddressSet:TellomiSeedAddressSets(false)[@1]];
    NSArray<MTTransportScheme *> *schemes = [context transportSchemesForDatacenterWithId:1 media:false enforceMedia:false isProxy:false];
    MTTransportScheme *first = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
    XCTAssertEqual(first.address.port, 10443);
    XCTAssertFalse([context transportSchemeHasReceivedResponseForDatacenterId:1 transportScheme:first]);

    [context reportTransportSchemeSuccessForDatacenterId:1 transportScheme:first];
    XCTAssertTrue([context transportSchemeHasReceivedResponseForDatacenterId:1 transportScheme:first]);
    MTTransportScheme *again = [context chooseTransportSchemeForConnectionToDatacenterId:1 schemes:schemes];
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

    XCTAssertEqualObjects(MTSeedPorts([context addressSetForDatacenterWithId:1]), (@[@443, @10443]));
    NSDictionary *persisted = [keychain dictionaryForKey:@"datacenterAddressSetById" group:@"persistent"];
    XCTAssertEqualObjects(MTSeedPorts(persisted[@1]), (@[@443, @10443]));
}

@end
