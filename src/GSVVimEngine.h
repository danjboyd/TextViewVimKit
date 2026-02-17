#import <Foundation/Foundation.h>

#import "GSVTextViewAdapter.h"
#import "GSVVimMode.h"

@class GSVVimEngine;

@protocol GSVVimClipboard <NSObject>
- (void)writeClipboardString:(NSString *)string;
- (NSString *)readClipboardString;
@end

@protocol GSVVimEngineDelegate <NSObject>
- (void)vimEngine:(GSVVimEngine *)engine didChangeMode:(GSVVimMode)mode;
@end

@interface GSVVimEngine : NSObject

@property (nonatomic, assign) id<GSVVimEngineDelegate> delegate;
@property (nonatomic, assign) GSVVimMode mode;
@property (nonatomic, assign) BOOL unnamedRegisterUsesClipboard;
@property (nonatomic, strong) id<GSVVimClipboard> clipboard;

- (BOOL)handleKeyToken:(NSString *)keyToken adapter:(id<GSVTextEditing>)adapter;
- (void)resetToNormalMode;

@end
