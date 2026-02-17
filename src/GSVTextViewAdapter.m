#import "GSVTextViewAdapter.h"

static BOOL GSVIsWordCharacter(unichar ch)
{
    if (ch == '_') {
        return YES;
    }
    return [[NSCharacterSet alphanumericCharacterSet] characterIsMember:ch];
}

static NSUInteger GSVLineContentEnd(NSString *text, NSRange lineRange)
{
    NSUInteger lineStart = lineRange.location;
    NSUInteger lineEnd = NSMaxRange(lineRange);
    if (lineEnd > lineStart && [text characterAtIndex:(lineEnd - 1)] == '\n') {
        lineEnd -= 1;
    }
    return lineEnd;
}

static NSUInteger GSVFirstNonBlankIndexInLine(NSString *text, NSRange lineRange)
{
    NSUInteger lineStart = lineRange.location;
    NSUInteger contentEnd = GSVLineContentEnd(text, lineRange);
    NSUInteger index = lineStart;
    while (index < contentEnd) {
        unichar ch = [text characterAtIndex:index];
        if (ch != ' ' && ch != '\t') {
            break;
        }
        index += 1;
    }
    return index;
}

@interface GSVTextViewAdapter ()
@property (nonatomic, strong, readwrite) NSTextView *textView;
@end

@implementation GSVTextViewAdapter

- (instancetype)initWithTextView:(NSTextView *)textView
{
    NSParameterAssert(textView != nil);
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _textView = textView;
    return self;
}

- (BOOL)hasMarkedText
{
    if ([self.textView respondsToSelector:@selector(hasMarkedText)]) {
        return [self.textView hasMarkedText];
    }
    return NO;
}

- (NSUInteger)textLength
{
    return [[[self.textView textStorage] string] length];
}

- (NSString *)textString
{
    return [[self.textView textStorage] string];
}

- (NSRange)selectedRange
{
    return [self.textView selectedRange];
}

- (void)setSelectedRange:(NSRange)range
{
    NSUInteger length = [self textLength];
    NSUInteger location = MIN(range.location, length);
    NSUInteger maxLength = length - location;
    NSUInteger selectedLength = MIN(range.length, maxLength);
    [self.textView setSelectedRange:NSMakeRange(location, selectedLength)];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string
{
    NSUInteger textLength = [self textLength];
    if (range.location > textLength) {
        return;
    }
    if (range.length > (textLength - range.location)) {
        return;
    }

    NSString *replacement = string != nil ? string : @"";
    if (![self.textView shouldChangeTextInRange:range replacementString:replacement]) {
        return;
    }

    [[self.textView textStorage] replaceCharactersInRange:range withString:replacement];
    [self.textView didChangeText];

    NSUInteger newLocation = range.location + [replacement length];
    [self setSelectedRange:NSMakeRange(newLocation, 0)];
}

- (void)moveCursorLeft
{
    [self.textView moveLeft:self];
}

- (void)moveCursorRight
{
    [self.textView moveRight:self];
}

- (void)moveCursorUp
{
    [self.textView moveUp:self];
}

- (void)moveCursorDown
{
    [self.textView moveDown:self];
}

- (void)deleteForward
{
    [self.textView deleteForward:self];
}

- (void)openLineBelow
{
    NSString *text = [self textString];
    NSUInteger length = [text length];
    NSRange selected = [self selectedRange];
    NSUInteger location = MIN(selected.location, length);
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(location, 0)];
    NSUInteger insertLocation = NSMaxRange(lineRange);

    BOOL charBeforeInsertIsNewline = NO;
    if (insertLocation > 0 && insertLocation <= length) {
        unichar ch = [text characterAtIndex:(insertLocation - 1)];
        charBeforeInsertIsNewline = (ch == '\n');
    }

    [self replaceCharactersInRange:NSMakeRange(insertLocation, 0) withString:@"\n"];

    NSUInteger caretLocation = charBeforeInsertIsNewline ? insertLocation : (insertLocation + 1);
    [self setSelectedRange:NSMakeRange(caretLocation, 0)];
}

- (void)openLineAbove
{
    NSString *text = [self textString];
    NSUInteger length = [text length];
    NSRange selected = [self selectedRange];
    NSUInteger location = MIN(selected.location, length);
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(location, 0)];
    NSUInteger insertLocation = lineRange.location;

    [self replaceCharactersInRange:NSMakeRange(insertLocation, 0) withString:@"\n"];
    [self setSelectedRange:NSMakeRange(insertLocation, 0)];
}

- (void)moveWordForward
{
    NSString *text = [self textString];
    NSUInteger length = [text length];
    if (length == 0) {
        [self setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    NSUInteger index = MIN([self selectedRange].location, length - 1);
    if (GSVIsWordCharacter([text characterAtIndex:index])) {
        while (index < length && GSVIsWordCharacter([text characterAtIndex:index])) {
            index += 1;
        }
    } else {
        while (index < length && !GSVIsWordCharacter([text characterAtIndex:index])) {
            index += 1;
        }
    }

    while (index < length && !GSVIsWordCharacter([text characterAtIndex:index])) {
        index += 1;
    }

    NSUInteger target = (index < length) ? index : (length - 1);
    [self setSelectedRange:NSMakeRange(target, 0)];
}

- (void)moveWordBackward
{
    NSString *text = [self textString];
    NSUInteger length = [text length];
    if (length == 0) {
        [self setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    NSUInteger location = MIN([self selectedRange].location, length);
    if (location == 0) {
        [self setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    NSUInteger index = location - 1;
    if (index >= length) {
        index = length - 1;
    }

    while (index > 0 && !GSVIsWordCharacter([text characterAtIndex:index])) {
        index -= 1;
    }
    if (!GSVIsWordCharacter([text characterAtIndex:index])) {
        [self setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    while (index > 0 && GSVIsWordCharacter([text characterAtIndex:(index - 1)])) {
        index -= 1;
    }

    [self setSelectedRange:NSMakeRange(index, 0)];
}

- (void)moveToWordEndForward
{
    NSString *text = [self textString];
    NSUInteger length = [text length];
    if (length == 0) {
        [self setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    NSUInteger index = MIN([self selectedRange].location, length - 1);
    if (GSVIsWordCharacter([text characterAtIndex:index])) {
        while ((index + 1) < length && GSVIsWordCharacter([text characterAtIndex:(index + 1)])) {
            index += 1;
        }
        [self setSelectedRange:NSMakeRange(index, 0)];
        return;
    }

    while (index < length && !GSVIsWordCharacter([text characterAtIndex:index])) {
        index += 1;
    }
    if (index >= length) {
        [self setSelectedRange:NSMakeRange(length - 1, 0)];
        return;
    }

    while ((index + 1) < length && GSVIsWordCharacter([text characterAtIndex:(index + 1)])) {
        index += 1;
    }
    [self setSelectedRange:NSMakeRange(index, 0)];
}

- (void)moveToLineStart
{
    NSString *text = [self textString];
    NSUInteger length = [text length];
    if (length == 0) {
        [self setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    NSUInteger location = MIN([self selectedRange].location, length);
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(location, 0)];
    [self setSelectedRange:NSMakeRange(lineRange.location, 0)];
}

- (void)moveToFirstNonBlankInLine
{
    NSString *text = [self textString];
    NSUInteger length = [text length];
    if (length == 0) {
        [self setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    NSUInteger location = MIN([self selectedRange].location, length);
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(location, 0)];
    NSUInteger target = GSVFirstNonBlankIndexInLine(text, lineRange);
    [self setSelectedRange:NSMakeRange(target, 0)];
}

- (void)moveToLineEnd
{
    NSString *text = [self textString];
    NSUInteger length = [text length];
    if (length == 0) {
        [self setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    NSUInteger location = MIN([self selectedRange].location, length);
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(location, 0)];
    NSUInteger lineEnd = GSVLineContentEnd(text, lineRange);
    NSUInteger target = (lineEnd > lineRange.location) ? (lineEnd - 1) : lineRange.location;
    [self setSelectedRange:NSMakeRange(target, 0)];
}

- (void)moveToFirstLine
{
    NSString *text = [self textString];
    NSUInteger length = [text length];
    if (length == 0) {
        [self setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    NSRange lineRange = [text lineRangeForRange:NSMakeRange(0, 0)];
    NSUInteger target = GSVFirstNonBlankIndexInLine(text, lineRange);
    [self setSelectedRange:NSMakeRange(target, 0)];
}

- (void)moveToLastLine
{
    NSString *text = [self textString];
    NSUInteger length = [text length];
    if (length == 0) {
        [self setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    if ([text characterAtIndex:(length - 1)] == '\n') {
        [self setSelectedRange:NSMakeRange(length, 0)];
        return;
    }

    NSRange lineRange = [text lineRangeForRange:NSMakeRange(length - 1, 0)];
    NSUInteger target = GSVFirstNonBlankIndexInLine(text, lineRange);
    [self setSelectedRange:NSMakeRange(target, 0)];
}

- (void)undoLastChange
{
    NSUndoManager *undoManager = [self.textView undoManager];
    if (undoManager == nil || ![undoManager canUndo]) {
        return;
    }
    [undoManager undo];
}

- (void)redoLastUndo
{
    NSUndoManager *undoManager = [self.textView undoManager];
    if (undoManager == nil || ![undoManager canRedo]) {
        return;
    }
    [undoManager redo];
}

@end
