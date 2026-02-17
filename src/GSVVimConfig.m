#import "GSVVimConfig.h"

@implementation GSVVimConfig

- (instancetype)initWithInsertModeMappings:(NSDictionary *)insertModeMappings
                                diagnostics:(NSArray *)diagnostics
{
    return [self initWithInsertModeMappings:insertModeMappings
                                 diagnostics:diagnostics
         unnamedRegisterUsesSystemClipboard:NO];
}

- (instancetype)initWithInsertModeMappings:(NSDictionary *)insertModeMappings
                                diagnostics:(NSArray *)diagnostics
        unnamedRegisterUsesSystemClipboard:(BOOL)unnamedRegisterUsesSystemClipboard
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    if (insertModeMappings != nil) {
        _insertModeMappings = [insertModeMappings copy];
    } else {
        _insertModeMappings = @{};
    }

    if (diagnostics != nil) {
        _diagnostics = [diagnostics copy];
    } else {
        _diagnostics = @[];
    }
    _unnamedRegisterUsesSystemClipboard = unnamedRegisterUsesSystemClipboard;

    return self;
}

- (NSString *)insertMappingRHSForSequence:(NSString *)lhs
{
    if (lhs == nil || [lhs length] == 0) {
        return nil;
    }
    return [self.insertModeMappings objectForKey:lhs];
}

- (NSArray *)insertMappingLHSKeys
{
    return [[self.insertModeMappings allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSUInteger)maxInsertMappingLength
{
    NSUInteger maxLength = 0;
    for (NSString *lhs in [self insertMappingLHSKeys]) {
        if ([lhs length] > maxLength) {
            maxLength = [lhs length];
        }
    }
    return maxLength;
}

@end
