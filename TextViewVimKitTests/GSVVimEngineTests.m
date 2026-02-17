#import <XCTest/XCTest.h>

#import "GSVVimEngine.h"

@interface GSVFakeAdapter : NSObject <GSVTextEditing>
@property (nonatomic, assign) NSRange selectedRangeValue;
@property (nonatomic, assign) NSUInteger moveLeftCalls;
@property (nonatomic, assign) NSUInteger moveRightCalls;
@property (nonatomic, assign) NSUInteger moveUpCalls;
@property (nonatomic, assign) NSUInteger moveDownCalls;
@property (nonatomic, assign) NSUInteger deleteForwardCalls;
@property (nonatomic, assign) NSUInteger openLineBelowCalls;
@property (nonatomic, assign) NSUInteger openLineAboveCalls;
@property (nonatomic, assign) NSUInteger moveWordForwardCalls;
@property (nonatomic, assign) NSUInteger moveWordBackwardCalls;
@property (nonatomic, assign) NSUInteger moveWordEndForwardCalls;
@property (nonatomic, assign) NSUInteger moveLineStartCalls;
@property (nonatomic, assign) NSUInteger moveLineFirstNonBlankCalls;
@property (nonatomic, assign) NSUInteger moveLineEndCalls;
@property (nonatomic, assign) NSUInteger moveFirstLineCalls;
@property (nonatomic, assign) NSUInteger moveLastLineCalls;
@property (nonatomic, assign) NSUInteger undoCalls;
@property (nonatomic, assign) NSUInteger redoCalls;
@property (nonatomic, copy) NSString *text;
@end

@implementation GSVFakeAdapter

- (NSUInteger)clampedCharacterLocation:(NSInteger)location
{
    NSUInteger length = [self textLength];
    if (length == 0) {
        return 0;
    }
    if (location < 0) {
        return 0;
    }
    NSUInteger unsignedLocation = (NSUInteger)location;
    if (unsignedLocation >= length) {
        return length - 1;
    }
    return unsignedLocation;
}

- (void)setCaretLocation:(NSUInteger)location
{
    self.selectedRangeValue = NSMakeRange([self clampedCharacterLocation:(NSInteger)location], 0);
}

- (instancetype)init
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _text = @"abc def ghi\nlast";
    _selectedRangeValue = NSMakeRange(0, 0);
    return self;
}

- (BOOL)hasMarkedText
{
    return NO;
}

- (NSUInteger)textLength
{
    return [self.text length];
}

- (NSString *)textString
{
    return self.text;
}

- (NSRange)selectedRange
{
    return self.selectedRangeValue;
}

- (void)setSelectedRange:(NSRange)range
{
    NSUInteger length = [self textLength];
    if (length == 0) {
        self.selectedRangeValue = NSMakeRange(0, 0);
        return;
    }

    NSUInteger location = MIN(range.location, length - 1);
    NSUInteger maxLength = length - location;
    NSUInteger selectedLength = MIN(range.length, maxLength);
    self.selectedRangeValue = NSMakeRange(location, selectedLength);
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string
{
    NSMutableString *mutable = [self.text mutableCopy];
    [mutable replaceCharactersInRange:range withString:(string != nil ? string : @"")];
    self.text = mutable;
    self.selectedRangeValue = NSMakeRange(range.location + [string length], 0);
}

- (void)moveCursorLeft
{
    self.moveLeftCalls += 1;
    NSUInteger location = [self selectedRange].location;
    [self setCaretLocation:(location > 0 ? (location - 1) : 0)];
}

- (void)moveCursorRight
{
    self.moveRightCalls += 1;
    [self setCaretLocation:([self selectedRange].location + 1)];
}

- (void)moveCursorUp
{
    self.moveUpCalls += 1;
    NSUInteger location = [self selectedRange].location;
    [self setCaretLocation:(location > 4 ? (location - 4) : 0)];
}

- (void)moveCursorDown
{
    self.moveDownCalls += 1;
    [self setCaretLocation:([self selectedRange].location + 4)];
}

- (void)deleteForward
{
    self.deleteForwardCalls += 1;
}

- (void)openLineBelow
{
    self.openLineBelowCalls += 1;
}

- (void)openLineAbove
{
    self.openLineAboveCalls += 1;
}

- (void)moveWordForward
{
    self.moveWordForwardCalls += 1;
    [self setCaretLocation:([self selectedRange].location + 3)];
}

- (void)moveWordBackward
{
    self.moveWordBackwardCalls += 1;
    NSUInteger location = [self selectedRange].location;
    [self setCaretLocation:(location > 3 ? (location - 3) : 0)];
}

- (void)moveToWordEndForward
{
    self.moveWordEndForwardCalls += 1;
    [self setCaretLocation:([self selectedRange].location + 2)];
}

- (void)moveToLineStart
{
    self.moveLineStartCalls += 1;
    [self setCaretLocation:0];
}

- (void)moveToFirstNonBlankInLine
{
    self.moveLineFirstNonBlankCalls += 1;
    [self setCaretLocation:1];
}

- (void)moveToLineEnd
{
    self.moveLineEndCalls += 1;
    NSString *text = [self textString];
    NSUInteger length = [text length];
    if (length == 0) {
        [self setCaretLocation:0];
        return;
    }

    NSUInteger location = [self selectedRange].location;
    if (location >= length) {
        location = length - 1;
    }
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(location, 0)];
    NSUInteger lineEnd = NSMaxRange(lineRange);
    if (lineEnd > lineRange.location && [text characterAtIndex:(lineEnd - 1)] == '\n') {
        lineEnd -= 1;
    }
    NSUInteger target = (lineEnd > lineRange.location) ? (lineEnd - 1) : lineRange.location;
    [self setCaretLocation:target];
}

- (void)moveToFirstLine
{
    self.moveFirstLineCalls += 1;
    [self setCaretLocation:0];
}

- (void)moveToLastLine
{
    self.moveLastLineCalls += 1;
    NSUInteger length = [self textLength];
    [self setCaretLocation:(length == 0 ? 0 : (length - 1))];
}

- (void)undoLastChange
{
    self.undoCalls += 1;
}

- (void)redoLastUndo
{
    self.redoCalls += 1;
}

@end

@interface GSVFakeClipboard : NSObject <GSVVimClipboard>
@property (nonatomic, copy) NSString *value;
@end

@implementation GSVFakeClipboard

- (void)writeClipboardString:(NSString *)string
{
    self.value = (string != nil) ? string : @"";
}

- (NSString *)readClipboardString
{
    return self.value;
}

@end

@interface GSVVimEngineTests : XCTestCase
@end

@implementation GSVVimEngineTests

- (void)testInsertModeToggleAndEscapeCursorAdjustment
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.selectedRangeValue = NSMakeRange(4, 0);

    XCTAssertEqual(engine.mode, GSVVimModeNormal);
    XCTAssertTrue([engine handleKeyToken:@"i" adapter:adapter]);
    XCTAssertEqual(engine.mode, GSVVimModeInsert);

    XCTAssertTrue([engine handleKeyToken:@"<Esc>" adapter:adapter]);
    XCTAssertEqual(engine.mode, GSVVimModeNormal);
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)3);
}

- (void)testNormalModeCommandsDispatchToAdapter
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];

    XCTAssertTrue([engine handleKeyToken:@"h" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"j" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"k" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"l" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"x" adapter:adapter]);

    XCTAssertEqual(adapter.moveLeftCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.moveDownCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.moveUpCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.moveRightCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.deleteForwardCalls, (NSUInteger)1);
}

- (void)testOpenLineCommandsEnterInsertMode
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];

    XCTAssertTrue([engine handleKeyToken:@"o" adapter:adapter]);
    XCTAssertEqual(adapter.openLineBelowCalls, (NSUInteger)1);
    XCTAssertEqual(engine.mode, GSVVimModeInsert);

    XCTAssertTrue([engine handleKeyToken:@"<Esc>" adapter:adapter]);
    XCTAssertEqual(engine.mode, GSVVimModeNormal);

    XCTAssertTrue([engine handleKeyToken:@"O" adapter:adapter]);
    XCTAssertEqual(adapter.openLineAboveCalls, (NSUInteger)1);
    XCTAssertEqual(engine.mode, GSVVimModeInsert);
}

- (void)testMotionCommandsDispatchToAdapter
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];

    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"b" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"e" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"0" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"^" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"$" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"G" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"g" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"g" adapter:adapter]);

    XCTAssertEqual(adapter.moveWordForwardCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.moveWordBackwardCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.moveWordEndForwardCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.moveLineStartCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.moveLineFirstNonBlankCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.moveLineEndCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.moveLastLineCalls, (NSUInteger)1);
    XCTAssertEqual(adapter.moveFirstLineCalls, (NSUInteger)1);
}

- (void)testPendingGConsumesUnsupportedSecondKey
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];

    XCTAssertTrue([engine handleKeyToken:@"g" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"h" adapter:adapter]);

    XCTAssertEqual(adapter.moveLeftCalls, (NSUInteger)0);
    XCTAssertEqual(adapter.moveFirstLineCalls, (NSUInteger)0);
}

- (void)testVisualModeEntryAndEscape
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.selectedRangeValue = NSMakeRange(2, 0);

    XCTAssertTrue([engine handleKeyToken:@"v" adapter:adapter]);
    XCTAssertEqual(engine.mode, GSVVimModeVisual);
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)2);
    XCTAssertEqual([adapter selectedRange].length, (NSUInteger)1);

    XCTAssertTrue([engine handleKeyToken:@"<Esc>" adapter:adapter]);
    XCTAssertEqual(engine.mode, GSVVimModeNormal);
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)2);
    XCTAssertEqual([adapter selectedRange].length, (NSUInteger)0);
}

- (void)testVisualModeSelectionMovesWithMotions
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.selectedRangeValue = NSMakeRange(2, 0);

    XCTAssertTrue([engine handleKeyToken:@"v" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"l" adapter:adapter]);
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)2);
    XCTAssertEqual([adapter selectedRange].length, (NSUInteger)2);

    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)2);
    XCTAssertEqual([adapter selectedRange].length, (NSUInteger)5);
}

- (void)testVisualLineModeEntrySelectsWholeLine
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.selectedRangeValue = NSMakeRange(4, 0);

    XCTAssertTrue([engine handleKeyToken:@"V" adapter:adapter]);
    XCTAssertEqual(engine.mode, GSVVimModeVisualLine);
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)0);
    XCTAssertEqual([adapter selectedRange].length, (NSUInteger)12);
}

- (void)testVisualDeleteCharwise
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"abcd";
    adapter.selectedRangeValue = NSMakeRange(1, 0);

    XCTAssertTrue([engine handleKeyToken:@"v" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"l" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);

    XCTAssertEqual(engine.mode, GSVVimModeNormal);
    XCTAssertEqualObjects(adapter.text, @"ad");
}

- (void)testVisualDeleteLinewise
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one\ntwo\nthree";
    adapter.selectedRangeValue = NSMakeRange(5, 0);

    XCTAssertTrue([engine handleKeyToken:@"V" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);

    XCTAssertEqual(engine.mode, GSVVimModeNormal);
    XCTAssertEqualObjects(adapter.text, @"one\nthree");
}

- (void)testVisualYankDoesNotModifyText
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"abcd";
    adapter.selectedRangeValue = NSMakeRange(1, 0);

    XCTAssertTrue([engine handleKeyToken:@"v" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"l" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"y" adapter:adapter]);

    XCTAssertEqual(engine.mode, GSVVimModeNormal);
    XCTAssertEqualObjects(adapter.text, @"abcd");
}

- (void)testDoubleDeleteLineAndPutLinewise
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one\ntwo\nthree";
    adapter.selectedRangeValue = NSMakeRange(5, 0);

    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"one\nthree");

    XCTAssertTrue([engine handleKeyToken:@"p" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"one\nthree\ntwo\n");
}

- (void)testDoubleYankLineAndPutBefore
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one\ntwo\nthree";
    adapter.selectedRangeValue = NSMakeRange(5, 0);

    XCTAssertTrue([engine handleKeyToken:@"y" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"y" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"one\ntwo\nthree");

    XCTAssertTrue([engine handleKeyToken:@"P" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"one\ntwo\ntwo\nthree");
}

- (void)testDeleteWithMotionThenPutBeforeRestoresContent
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"abcXYZ";
    adapter.selectedRangeValue = NSMakeRange(0, 0);

    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"XYZ");

    XCTAssertTrue([engine handleKeyToken:@"P" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"abcXYZ");
}

- (void)testDeleteToLineEndWithDollarMotion
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one two";
    adapter.selectedRangeValue = NSMakeRange(4, 0);

    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"$" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"one ");
}

- (void)testDeleteToLineStartWithZeroMotion
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"abc def";
    adapter.selectedRangeValue = NSMakeRange(4, 0);

    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"0" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"def");
}

- (void)testDeleteFromFirstLineWithDgg
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"aaa\nbbb\nccc";
    adapter.selectedRangeValue = NSMakeRange(5, 0);

    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"g" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"g" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"bb\nccc");
}

- (void)testDeleteToEndOfFileWithDG
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"aaa\nbbb\nccc";
    adapter.selectedRangeValue = NSMakeRange(4, 0);

    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"G" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"aaa\n");
}

- (void)testClipboardMirrorsUnnamedRegisterWhenEnabled
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    GSVFakeClipboard *clipboard = [[GSVFakeClipboard alloc] init];
    engine.clipboard = clipboard;
    engine.unnamedRegisterUsesClipboard = YES;
    adapter.text = @"abcd";
    adapter.selectedRangeValue = NSMakeRange(1, 0);

    XCTAssertTrue([engine handleKeyToken:@"v" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"l" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"y" adapter:adapter]);
    XCTAssertEqualObjects(clipboard.value, @"bc");

    clipboard.value = @"ZZ";
    adapter.selectedRangeValue = NSMakeRange(0, 0);
    XCTAssertTrue([engine handleKeyToken:@"p" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"aZZbcd");
}

- (void)testChangeInnerWordEntersInsertAndDeletesWordOnly
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one two three";
    adapter.selectedRangeValue = NSMakeRange(5, 0);

    XCTAssertTrue([engine handleKeyToken:@"c" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"i" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);

    XCTAssertEqual(engine.mode, GSVVimModeInsert);
    XCTAssertEqualObjects(adapter.text, @"one  three");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)4);
}

- (void)testChangeAWordConsumesTrailingWhitespace
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one two three";
    adapter.selectedRangeValue = NSMakeRange(5, 0);

    XCTAssertTrue([engine handleKeyToken:@"c" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"a" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);

    XCTAssertEqual(engine.mode, GSVVimModeInsert);
    XCTAssertEqualObjects(adapter.text, @"one three");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)4);
}

- (void)testQuotePlusYankInnerWordWritesClipboard
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    GSVFakeClipboard *clipboard = [[GSVFakeClipboard alloc] init];
    engine.clipboard = clipboard;
    adapter.text = @"one two three";
    adapter.selectedRangeValue = NSMakeRange(5, 0);

    XCTAssertTrue([engine handleKeyToken:@"\"" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"+" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"y" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"i" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);

    XCTAssertEqual(engine.mode, GSVVimModeNormal);
    XCTAssertEqualObjects(adapter.text, @"one two three");
    XCTAssertEqualObjects(clipboard.value, @"two");
}

- (void)testChangeWordDoesNotConsumeTrailingWhitespace
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one two three";
    adapter.selectedRangeValue = NSMakeRange(4, 0);

    XCTAssertTrue([engine handleKeyToken:@"c" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);

    XCTAssertEqual(engine.mode, GSVVimModeInsert);
    XCTAssertEqualObjects(adapter.text, @"one  three");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)4);
}

- (void)testUppercaseCChangesToLineEndAndEntersInsert
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one two\nthree";
    adapter.selectedRangeValue = NSMakeRange(4, 0);

    XCTAssertTrue([engine handleKeyToken:@"C" adapter:adapter]);
    XCTAssertEqual(engine.mode, GSVVimModeInsert);
    XCTAssertEqualObjects(adapter.text, @"one \nthree");
}

- (void)testUppercaseDDeletesToLineEnd
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one two\nthree";
    adapter.selectedRangeValue = NSMakeRange(4, 0);

    XCTAssertTrue([engine handleKeyToken:@"D" adapter:adapter]);
    XCTAssertEqual(engine.mode, GSVVimModeNormal);
    XCTAssertEqualObjects(adapter.text, @"one \nthree");
}

- (void)testChangeCurrentLineWithCc
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one\ntwo\nthree";
    adapter.selectedRangeValue = NSMakeRange(5, 0);

    XCTAssertTrue([engine handleKeyToken:@"c" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"c" adapter:adapter]);

    XCTAssertEqual(engine.mode, GSVVimModeInsert);
    XCTAssertEqualObjects(adapter.text, @"one\nthree");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)4);
}

- (void)testDeleteInnerWordDiwAndDeleteAWordDaw
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one two three";
    adapter.selectedRangeValue = NSMakeRange(5, 0);

    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"i" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"one  three");
    XCTAssertEqual(engine.mode, GSVVimModeNormal);

    adapter.text = @"one two three";
    adapter.selectedRangeValue = NSMakeRange(5, 0);
    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"a" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"one three");
}

- (void)testYankInnerWordYiwAndYankAWordYaw
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"one two three";
    adapter.selectedRangeValue = NSMakeRange(5, 0);

    XCTAssertTrue([engine handleKeyToken:@"y" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"i" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"P" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"one twotwo three");

    adapter.text = @"one two three";
    adapter.selectedRangeValue = NSMakeRange(5, 0);
    XCTAssertTrue([engine handleKeyToken:@"y" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"a" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"P" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"one two two three");
}

- (void)testCountPrefixesApplyToMotionsAndDeleteForward
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];

    XCTAssertTrue([engine handleKeyToken:@"3" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"j" adapter:adapter]);
    XCTAssertEqual(adapter.moveDownCalls, (NSUInteger)3);

    XCTAssertTrue([engine handleKeyToken:@"4" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"x" adapter:adapter]);
    XCTAssertEqual(adapter.deleteForwardCalls, (NSUInteger)4);
}

- (void)testOperatorCountsAndPutCounts
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];

    adapter.text = @"abcdefghi";
    adapter.selectedRangeValue = NSMakeRange(0, 0);
    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"2" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"ghi");

    adapter.selectedRangeValue = NSMakeRange(0, 0);
    XCTAssertTrue([engine handleKeyToken:@"2" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"p" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"gabcdefabcdefhi");
}

- (void)testDotRepeatsDeleteChangeAndHonorsDotCount
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"abcdefghijklmnop";
    adapter.selectedRangeValue = NSMakeRange(0, 0);

    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"w" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"defghijklmnop");

    XCTAssertTrue([engine handleKeyToken:@"." adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"ghijklmnop");

    XCTAssertTrue([engine handleKeyToken:@"2" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"." adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"mnop");
}

- (void)testUndoAndRedoCommandsUseAdapterUndoHooks
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];

    XCTAssertTrue([engine handleKeyToken:@"u" adapter:adapter]);
    XCTAssertEqual(adapter.undoCalls, (NSUInteger)1);

    XCTAssertTrue([engine handleKeyToken:@"2" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"u" adapter:adapter]);
    XCTAssertEqual(adapter.undoCalls, (NSUInteger)3);

    XCTAssertTrue([engine handleKeyToken:@"<C-r>" adapter:adapter]);
    XCTAssertEqual(adapter.redoCalls, (NSUInteger)1);
}

- (void)testQuotePlusPutUsesClipboardRegister
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    GSVFakeClipboard *clipboard = [[GSVFakeClipboard alloc] init];
    engine.clipboard = clipboard;

    adapter.text = @"abcd";
    adapter.selectedRangeValue = NSMakeRange(1, 0);
    clipboard.value = @"ZZ";

    XCTAssertTrue([engine handleKeyToken:@"\"" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"+" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"p" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"abZZcd");

    adapter.text = @"abcd";
    adapter.selectedRangeValue = NSMakeRange(2, 0);
    clipboard.value = @"YY";
    XCTAssertTrue([engine handleKeyToken:@"\"" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"+" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"P" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"abYYcd");
}

@end
