#import "RAReferenceWindow.h"

#if defined(NSEventTypeKeyDown)
#define RA_KEY_DOWN_EVENT NSEventTypeKeyDown
#else
#define RA_KEY_DOWN_EVENT NSKeyDown
#endif

@implementation RAReferenceWindow

- (void)sendEvent:(NSEvent *)event
{
    if (event != nil && [event type] == RA_KEY_DOWN_EVENT) {
        id<RAReferenceWindowKeyDelegate> delegate = self.keyDelegate;
        if (delegate != nil && [delegate respondsToSelector:@selector(referenceWindow:handleKeyDownEvent:)]) {
            if ([delegate referenceWindow:self handleKeyDownEvent:event]) {
                return;
            }
        }
    }

    [super sendEvent:event];
}

@end
