

#import <Foundation/Foundation.h>

@class MTDatacenterAddress;

@interface MTDatacenterAddressSet : NSObject <NSCoding>

@property (nonatomic, strong, readonly) NSArray *addressList;

- (instancetype)initWithAddressList:(NSArray *)addressList;

- (MTDatacenterAddress *)firstAddress;

// Addresses already present (same ip, port, media flag and cdn flag) are kept.
// Missing seed addresses are added. The last seed address is moved to the end
// so a tie in failure time dials that endpoint first and the next retry reaches
// the fallback that was inserted just before it.
- (instancetype)addressSetByAddingSeedAddresses:(NSArray<MTDatacenterAddress *> *)seedAddresses;

@end
