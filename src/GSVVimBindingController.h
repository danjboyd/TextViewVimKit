#import <AppKit/AppKit.h>

#import "GSVVimConfig.h"
#import "GSVVimEngine.h"

@class GSVVimBindingController;

@protocol GSVVimBindingControllerDelegate <NSObject>
- (void)vimBindingController:(GSVVimBindingController *)controller
               didChangeMode:(GSVVimMode)mode
                 forTextView:(NSTextView *)textView;
@end

@interface GSVVimBindingController : NSObject

@property (nonatomic, strong, readonly) NSTextView *textView;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, assign) id<GSVVimBindingControllerDelegate> delegate;
@property (nonatomic, strong) GSVVimConfig *config;
@property (nonatomic, assign, readonly) GSVVimMode mode;

- (instancetype)initWithTextView:(NSTextView *)textView;
- (BOOL)handleKeyEvent:(NSEvent *)event;

@end
