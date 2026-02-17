#import <AppKit/AppKit.h>

@protocol GSVTextEditing <NSObject>
- (BOOL)hasMarkedText;
- (NSUInteger)textLength;
- (NSString *)textString;
- (NSRange)selectedRange;
- (void)setSelectedRange:(NSRange)range;
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string;
- (void)moveCursorLeft;
- (void)moveCursorRight;
- (void)moveCursorUp;
- (void)moveCursorDown;
- (void)deleteForward;
- (void)openLineBelow;
- (void)openLineAbove;
- (void)moveWordForward;
- (void)moveWordBackward;
- (void)moveToWordEndForward;
- (void)moveToLineStart;
- (void)moveToFirstNonBlankInLine;
- (void)moveToLineEnd;
- (void)moveToFirstLine;
- (void)moveToLastLine;
- (void)undoLastChange;
- (void)redoLastUndo;
@end

@interface GSVTextViewAdapter : NSObject <GSVTextEditing>

@property (nonatomic, strong, readonly) NSTextView *textView;

- (instancetype)initWithTextView:(NSTextView *)textView;

@end
