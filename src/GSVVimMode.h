#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GSVVimMode) {
    GSVVimModeNormal = 0,
    GSVVimModeInsert = 1,
    GSVVimModeVisual = 2,
    GSVVimModeVisualLine = 3
};

FOUNDATION_EXPORT NSString *GSVVimModeDisplayName(GSVVimMode mode);
