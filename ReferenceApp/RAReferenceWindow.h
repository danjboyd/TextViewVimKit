#import <AppKit/AppKit.h>

@class RAReferenceWindow;

@protocol RAReferenceWindowKeyDelegate <NSObject>
- (BOOL)referenceWindow:(RAReferenceWindow *)window handleKeyDownEvent:(NSEvent *)event;
@end

@interface RAReferenceWindow : NSWindow
@property (nonatomic, assign) id<RAReferenceWindowKeyDelegate> keyDelegate;
@end
