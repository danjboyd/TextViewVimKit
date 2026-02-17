#import <AppKit/AppKit.h>

#import "GSVVimBindingController.h"
#import "RAReferenceWindow.h"

@interface RAAppDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate, RAReferenceWindowKeyDelegate, GSVVimBindingControllerDelegate>
@end
