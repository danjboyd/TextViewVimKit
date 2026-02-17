#import <Foundation/Foundation.h>

@interface GSVVimConfig : NSObject

@property (nonatomic, strong, readonly) NSDictionary *insertModeMappings;
@property (nonatomic, strong, readonly) NSArray *diagnostics;
@property (nonatomic, assign, readonly) BOOL unnamedRegisterUsesSystemClipboard;

- (instancetype)initWithInsertModeMappings:(NSDictionary *)insertModeMappings
                                diagnostics:(NSArray *)diagnostics;

- (instancetype)initWithInsertModeMappings:(NSDictionary *)insertModeMappings
                                diagnostics:(NSArray *)diagnostics
        unnamedRegisterUsesSystemClipboard:(BOOL)unnamedRegisterUsesSystemClipboard;

- (NSString *)insertMappingRHSForSequence:(NSString *)lhs;
- (NSArray *)insertMappingLHSKeys;
- (NSUInteger)maxInsertMappingLength;

@end
