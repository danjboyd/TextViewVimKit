#import <Foundation/Foundation.h>

#import "GSVVimConfig.h"

@interface GSVVimConfigLoader : NSObject

+ (GSVVimConfig *)loadDefaultConfig;

+ (GSVVimConfig *)loadConfigWithInternalConfigPath:(NSString *)internalConfigPath
                                         vimrcPath:(NSString *)vimrcPath;

@end
