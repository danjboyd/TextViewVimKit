#import <AppKit/AppKit.h>

#import "GSVVimConfig.h"
#import "GSVVimEngine.h"

@class GSVVimBindingController;

typedef NS_ENUM(NSInteger, GSVVimExAction) {
    GSVVimExActionWrite = 0,
    GSVVimExActionQuit = 1,
    GSVVimExActionWriteQuit = 2,
    GSVVimExActionUnknown = 3
};

@protocol GSVVimBindingControllerDelegate <NSObject>
- (void)vimBindingController:(GSVVimBindingController *)controller
               didChangeMode:(GSVVimMode)mode
                 forTextView:(NSTextView *)textView;
@optional
- (BOOL)vimBindingController:(GSVVimBindingController *)controller
              handleExAction:(GSVVimExAction)action
                       force:(BOOL)force
                  rawCommand:(NSString *)rawCommand
                 forTextView:(NSTextView *)textView;
- (void)vimBindingController:(GSVVimBindingController *)controller
        didUpdateCommandLine:(NSString *)commandLine
                      active:(BOOL)active
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
