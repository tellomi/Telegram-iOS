#import <MtProtoKit/MTDatacenterAddressSet.h>

#import <MtProtoKit/MTDatacenterAddress.h>

@implementation MTDatacenterAddressSet

- (instancetype)initWithAddressList:(NSArray *)addressList
{
    self = [super init];
    if (self != nil)
    {
        _addressList = addressList;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self != nil)
    {
        _addressList = [aDecoder decodeObjectForKey:@"addressList"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_addressList forKey:@"addressList"];
}

- (BOOL)isEqual:(MTDatacenterAddressSet *)another
{
    if (![another isKindOfClass:[MTDatacenterAddressSet class]])
        return false;
    
    if (_addressList.count != another.addressList.count)
        return false;
    
    for (NSUInteger i = 0; i < _addressList.count; i++)
    {
        if (![_addressList[i] isEqual:another.addressList[i]])
            return false;
    }
    
    return true;
}

- (NSString *)description
{
    NSMutableString *string = [[NSMutableString alloc] init];
    [string appendString:@"["];
    for (MTDatacenterAddress *address in _addressList)
    {
        if (string.length != 1)
            [string appendString:@", "];
        [string appendString:[address description]];
    }
    [string appendString:@"]"];
    
    return string;
}

- (MTDatacenterAddress *)firstAddress
{
    return _addressList.count == 0 ? nil : _addressList[0];
}

static bool MTDatacenterAddressSameEndpoint(MTDatacenterAddress *address, MTDatacenterAddress *other) {
    if (address.port != other.port || address.preferForMedia != other.preferForMedia || address.cdn != other.cdn) {
        return false;
    }
    if (address.ip == nil || other.ip == nil) {
        return address.ip == other.ip;
    }
    return [address.ip isEqualToString:other.ip];
}

- (instancetype)addressSetByAddingSeedAddresses:(NSArray<MTDatacenterAddress *> *)seedAddresses {
    if (seedAddresses.count == 0) {
        return self;
    }
    NSMutableArray<MTDatacenterAddress *> *result = [[NSMutableArray alloc] initWithArray:_addressList ?: @[]];
    MTDatacenterAddress *preferred = seedAddresses.lastObject;
    for (MTDatacenterAddress *seed in seedAddresses) {
        if (seed == preferred) {
            continue;
        }
        bool found = false;
        for (MTDatacenterAddress *existing in result) {
            if (MTDatacenterAddressSameEndpoint(existing, seed)) {
                found = true;
                break;
            }
        }
        if (!found) {
            [result addObject:seed];
        }
    }

    NSUInteger preferredIndex = NSNotFound;
    for (NSUInteger index = 0; index < result.count; index++) {
        if (MTDatacenterAddressSameEndpoint(result[index], preferred)) {
            preferredIndex = index;
            break;
        }
    }
    if (preferredIndex != NSNotFound) {
        MTDatacenterAddress *existingPreferred = result[preferredIndex];
        [result removeObjectAtIndex:preferredIndex];
        [result addObject:existingPreferred];
    } else if (preferred != nil) {
        [result addObject:preferred];
    }
    return [[MTDatacenterAddressSet alloc] initWithAddressList:[result copy]];
}

@end
