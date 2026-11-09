

#import <Foundation/Foundation.h>

@interface MTDatacenterAddress : NSObject <NSCoding, NSCopying>

@property (nonatomic, strong, readonly) NSString * _Nullable host;
@property (nonatomic, strong, readonly) NSString * _Nullable ip;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) bool preferForMedia;
@property (nonatomic, readonly) bool restrictToTcp;
@property (nonatomic, readonly) bool cdn;
@property (nonatomic, readonly) bool preferForProxy;
@property (nonatomic, readonly) bool thisPortOnly;
@property (nonatomic, readonly) NSData * _Nullable secret;

- (instancetype _Nonnull)initWithIp:(NSString * _Nonnull)ip port:(uint16_t)port preferForMedia:(bool)preferForMedia restrictToTcp:(bool)restrictToTcp cdn:(bool)cdn preferForProxy:(bool)preferForProxy secret:(NSData * _Nullable)secret;

// `thisPortOnly` is `dcOption.this_port_only` (flags bit 5). The address is still
// used for its own connection, including a media connection. Discovery does not
// add ports 80 and 5222 for it.
- (instancetype _Nonnull)initWithIp:(NSString * _Nonnull)ip port:(uint16_t)port preferForMedia:(bool)preferForMedia restrictToTcp:(bool)restrictToTcp cdn:(bool)cdn preferForProxy:(bool)preferForProxy secret:(NSData * _Nullable)secret thisPortOnly:(bool)thisPortOnly;

- (BOOL)isEqualToAddress:(MTDatacenterAddress * _Nonnull)other;
- (BOOL)isIpv6;

@end
