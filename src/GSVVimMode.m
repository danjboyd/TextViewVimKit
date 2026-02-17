#import "GSVVimMode.h"

NSString *GSVVimModeDisplayName(GSVVimMode mode)
{
    switch (mode) {
        case GSVVimModeInsert:
            return @"INSERT";
        case GSVVimModeVisual:
            return @"VISUAL";
        case GSVVimModeVisualLine:
            return @"VISUAL LINE";
        case GSVVimModeNormal:
        default:
            return @"NORMAL";
    }
}
