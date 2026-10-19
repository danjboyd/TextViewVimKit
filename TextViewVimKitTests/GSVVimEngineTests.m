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
    XCTAssertEqualObjects(adapter.text, @"ac def ghi\nlast");
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
    XCTAssertEqualObjects(adapter.text, @"one\nthree\ntwo");
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
    XCTAssertEqualObjects(adapter.text, @"ccc");
}

- (void)testDeleteToEndOfFileWithDG
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = @"aaa\nbbb\nccc";
    adapter.selectedRangeValue = NSMakeRange(4, 0);

    XCTAssertTrue([engine handleKeyToken:@"d" adapter:adapter]);
    XCTAssertTrue([engine handleKeyToken:@"G" adapter:adapter]);
    XCTAssertEqualObjects(adapter.text, @"aaa");
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
    XCTAssertEqualObjects(adapter.text, @"one\n\nthree");
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
    XCTAssertEqualObjects(adapter.text, @"abc def ghi\n");
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

#pragma mark - Vim fidelity (audit 2026-10)

// Sends each key of a command string; <Esc> is written as \e.
static void GSVKeys(GSVVimEngine *engine, GSVFakeAdapter *adapter, NSString *keys)
{
    for (NSUInteger i = 0; i < [keys length]; i += 1) {
        unichar ch = [keys characterAtIndex:i];
        NSString *token = (ch == 0x1b) ? @"<Esc>" : [NSString stringWithCharacters:&ch length:1];
        [engine handleKeyToken:token adapter:adapter];
    }
}

// Types text in Insert mode, as the text view would.
static void GSVType(GSVFakeAdapter *adapter, NSString *text)
{
    [adapter replaceCharactersInRange:NSMakeRange([adapter selectedRange].location, 0) withString:text];
}

static GSVFakeAdapter *GSVAdapterWithText(NSString *text, NSUInteger cursor)
{
    GSVFakeAdapter *adapter = [[GSVFakeAdapter alloc] init];
    adapter.text = text;
    adapter.selectedRangeValue = NSMakeRange(cursor, 0);
    return adapter;
}

- (void)testUppercaseCommandsAreNotTheirLowercaseOnes
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"  abc\ndef", 3);
    GSVKeys(engine, adapter, @"A");
    XCTAssertEqual(engine.mode, GSVVimModeInsert);
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)5);
    GSVType(adapter, @"!");
    GSVKeys(engine, adapter, @"\eI");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)2);
    GSVType(adapter, @"-");
    GSVKeys(engine, adapter, @"\e");
    XCTAssertEqualObjects(adapter.text, @"  -abc!\ndef");

    adapter = GSVAdapterWithText(@"abcd", 2);
    GSVKeys(engine, adapter, @"X");
    XCTAssertEqualObjects(adapter.text, @"acd");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)1);

    adapter = GSVAdapterWithText(@"one\ntwo", 1);
    GSVKeys(engine, adapter, @"Yjp");
    XCTAssertEqualObjects(adapter.text, @"one\ntwo\none");
}

- (void)testXStaysOnItsLine
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"ab\ncd", 1);
    GSVKeys(engine, adapter, @"5x");
    XCTAssertEqualObjects(adapter.text, @"a\ncd");
    GSVKeys(engine, adapter, @"p");
    XCTAssertEqualObjects(adapter.text, @"ab\ncd");

    adapter = GSVAdapterWithText(@"a\n\nb", 2);
    GSVKeys(engine, adapter, @"x");
    XCTAssertEqualObjects(adapter.text, @"a\n\nb");
}

- (void)testEscapeDoesNotLeaveTheLine
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"one\ntwo", 4);
    GSVKeys(engine, adapter, @"i\e");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)4);
}

- (void)testAppendOnAnEmptyLineStaysOnIt
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"a\n\nb", 2);
    GSVKeys(engine, adapter, @"a");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)2);
    XCTAssertEqual(adapter.moveRightCalls, (NSUInteger)0);
}

- (void)testFindMotionsAndRepeats
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"a,b,c,d", 0);
    GSVKeys(engine, adapter, @"f,");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)1);
    GSVKeys(engine, adapter, @";");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)3);
    GSVKeys(engine, adapter, @",");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)1);
    GSVKeys(engine, adapter, @"2f,");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)5);
    GSVKeys(engine, adapter, @"Fb");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)2);
    GSVKeys(engine, adapter, @"0tc");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)3);
    GSVKeys(engine, adapter, @";");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)3, @"no further c: the repeat stays");
    GSVKeys(engine, adapter, @"$Tb");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)3);

    // A find stays on its line.
    adapter = GSVAdapterWithText(@"ab\nab", 0);
    GSVKeys(engine, adapter, @"fb");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)1);
    GSVKeys(engine, adapter, @";");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)1);
}

- (void)testOperatorsWithFindMotions
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"call(arg, more)", 5);
    GSVKeys(engine, adapter, @"dt)");
    XCTAssertEqualObjects(adapter.text, @"call()");

    adapter = GSVAdapterWithText(@"a-b-c-d", 0);
    GSVKeys(engine, adapter, @"d2f-");
    XCTAssertEqualObjects(adapter.text, @"c-d");
    GSVKeys(engine, adapter, @".");
    XCTAssertEqualObjects(adapter.text, @"c-d", @"no second pair of dashes to delete through");

    adapter = GSVAdapterWithText(@"key = value;", 6);
    GSVKeys(engine, adapter, @"ct;");
    XCTAssertEqual(engine.mode, GSVVimModeInsert);
    GSVType(adapter, @"42");
    GSVKeys(engine, adapter, @"\e");
    XCTAssertEqualObjects(adapter.text, @"key = 42;");
}

- (void)testReplaceToggleCaseAndJoin
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"abcd", 1);
    GSVKeys(engine, adapter, @"rX");
    XCTAssertEqualObjects(adapter.text, @"aXcd");
    GSVKeys(engine, adapter, @"0");
    GSVKeys(engine, adapter, @"3r-");
    XCTAssertEqualObjects(adapter.text, @"---d");
    GSVKeys(engine, adapter, @"9rz");
    XCTAssertEqualObjects(adapter.text, @"---d", @"r with more characters than the line has does nothing");

    adapter = GSVAdapterWithText(@"Hello", 0);
    GSVKeys(engine, adapter, @"3~");
    XCTAssertEqualObjects(adapter.text, @"hELlo");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)3);

    adapter = GSVAdapterWithText(@"one\n   two\nthree\nfour", 0);
    GSVKeys(engine, adapter, @"J");
    XCTAssertEqualObjects(adapter.text, @"one two\nthree\nfour");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)3);
    GSVKeys(engine, adapter, @"3J");
    XCTAssertEqualObjects(adapter.text, @"one two three four");
}

- (void)testCountedGoToLine
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"one\n  two\nthree", 0);
    GSVKeys(engine, adapter, @"2G");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)6);
    GSVKeys(engine, adapter, @"3gg");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)10);
    GSVKeys(engine, adapter, @"1G");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)0);
    XCTAssertEqual(adapter.moveLastLineCalls, (NSUInteger)0);
}

- (void)testLinewiseOperatorsOverLineMotions
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"aaa\nbbb\nccc", 1);
    GSVKeys(engine, adapter, @"dj");
    XCTAssertEqualObjects(adapter.text, @"ccc");
    GSVKeys(engine, adapter, @"P");
    XCTAssertEqualObjects(adapter.text, @"aaa\nbbb\nccc");

    adapter = GSVAdapterWithText(@"aaa\nbbb\nccc", 9);
    GSVKeys(engine, adapter, @"dd");
    XCTAssertEqualObjects(adapter.text, @"aaa\nbbb", @"dd on the last line takes the newline before it");
}

- (void)testDeleteWordStopsAtTheEndOfTheLine
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    // The fake adapter's w moves three characters: from "ab" to "cd" here.
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"ab\ncd", 0);
    GSVKeys(engine, adapter, @"dw");
    XCTAssertEqualObjects(adapter.text, @"\ncd");
}

- (void)testDotRepeatsChangesWithTheirTypedText
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"x = 1;\ny = 2;", 4);
    GSVKeys(engine, adapter, @"ct;");
    GSVType(adapter, @"10");
    GSVKeys(engine, adapter, @"\e");
    XCTAssertEqualObjects(adapter.text, @"x = 10;\ny = 2;");
    adapter.selectedRangeValue = NSMakeRange(12, 0);
    GSVKeys(engine, adapter, @".");
    XCTAssertEqualObjects(adapter.text, @"x = 10;\ny = 10;");
    XCTAssertEqual(engine.mode, GSVVimModeNormal);

    adapter = GSVAdapterWithText(@"a\nb\n", 0);
    GSVKeys(engine, adapter, @"A");
    GSVType(adapter, @";");
    GSVKeys(engine, adapter, @"\ej.");
    XCTAssertEqualObjects(adapter.text, @"a;\nb;\n");
}

- (void)testInsertCountRepeatsTheTypedText
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"[]", 1);
    GSVKeys(engine, adapter, @"3i");
    GSVType(adapter, @"ab");
    GSVKeys(engine, adapter, @"\e");
    XCTAssertEqualObjects(adapter.text, @"[ababab]");
}

- (void)testQuoteAndBracketTextObjects
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"say \"hello there\" now", 8);
    GSVKeys(engine, adapter, @"ci\"");
    XCTAssertEqual(engine.mode, GSVVimModeInsert);
    GSVType(adapter, @"bye");
    GSVKeys(engine, adapter, @"\e");
    XCTAssertEqualObjects(adapter.text, @"say \"bye\" now");

    adapter = GSVAdapterWithText(@"say \"hi\" now", 0);
    GSVKeys(engine, adapter, @"da\"");
    XCTAssertEqualObjects(adapter.text, @"say now", @"the cursor before the quotes uses the first quoted string");

    adapter = GSVAdapterWithText(@"f(a, (b), c)", 6);
    GSVKeys(engine, adapter, @"di(");
    XCTAssertEqualObjects(adapter.text, @"f(a, (), c)");
    GSVKeys(engine, adapter, @"0f,");
    GSVKeys(engine, adapter, @"dab");
    XCTAssertEqualObjects(adapter.text, @"f");

    adapter = GSVAdapterWithText(@"if {\n  body;\n}", 8);
    GSVKeys(engine, adapter, @"yi{");
    adapter.selectedRangeValue = NSMakeRange(8, 0);
    GSVKeys(engine, adapter, @"di}");
    XCTAssertEqualObjects(adapter.text, @"if {\n}", @"i{ on a block takes its inner lines");

    adapter = GSVAdapterWithText(@"x foo.bar(1) y", 4);
    GSVKeys(engine, adapter, @"diW");
    XCTAssertEqualObjects(adapter.text, @"x  y");
}

- (void)testNamedAndBlackHoleRegisters
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"one\ntwo\nthree", 0);
    GSVKeys(engine, adapter, @"\"ayy");
    GSVKeys(engine, adapter, @"j\"Ayy");
    GSVKeys(engine, adapter, @"j\"_dd");
    XCTAssertEqualObjects(adapter.text, @"one\ntwo");
    GSVKeys(engine, adapter, @"\"ap");
    XCTAssertEqualObjects(adapter.text, @"one\ntwo\none\ntwo");
    GSVKeys(engine, adapter, @"gg0p");
    XCTAssertEqualObjects(adapter.text, @"one\none\ntwo\ntwo\none\ntwo",
                          @"the unnamed register has the last yank, not the black-hole delete");
}

- (void)testWordParagraphAndBracketMotions
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"a.b c-d  e", 0);
    GSVKeys(engine, adapter, @"W");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)4);
    GSVKeys(engine, adapter, @"E");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)6);
    GSVKeys(engine, adapter, @"B");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)4);

    adapter = GSVAdapterWithText(@"p1\np1\n\np2\n\np3", 0);
    GSVKeys(engine, adapter, @"}");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)6);
    GSVKeys(engine, adapter, @"}");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)10);
    GSVKeys(engine, adapter, @"{");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)6);

    adapter = GSVAdapterWithText(@"x = f(a[1], {b});", 0);
    GSVKeys(engine, adapter, @"%");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)15);
    GSVKeys(engine, adapter, @"%");
    XCTAssertEqual([adapter selectedRange].location, (NSUInteger)5);
    GSVKeys(engine, adapter, @"d%");
    XCTAssertEqualObjects(adapter.text, @"x = f;");
}

- (void)testVisualModeCommands
{
    GSVVimEngine *engine = [[GSVVimEngine alloc] init];
    GSVFakeAdapter *adapter = GSVAdapterWithText(@"one two three", 5);
    GSVKeys(engine, adapter, @"viwd");
    XCTAssertEqualObjects(adapter.text, @"one  three");
    XCTAssertEqual(engine.mode, GSVVimModeNormal);

    adapter = GSVAdapterWithText(@"abcdef", 1);
    GSVKeys(engine, adapter, @"vfd~");
    XCTAssertEqualObjects(adapter.text, @"aBCDef");

    adapter = GSVAdapterWithText(@"abcdef", 1);
    GSVKeys(engine, adapter, @"vllohx");
    XCTAssertEqualObjects(adapter.text, @"ef", @"o moves the cursor to the other end");

    adapter = GSVAdapterWithText(@"abcdef", 1);
    GSVKeys(engine, adapter, @"vllr*");
    XCTAssertEqualObjects(adapter.text, @"a***ef");

    adapter = GSVAdapterWithText(@"one\ntwo\nthree", 0);
    GSVKeys(engine, adapter, @"VjJ");
    XCTAssertEqualObjects(adapter.text, @"one two\nthree");

    adapter = GSVAdapterWithText(@"keep cut", 0);
    GSVKeys(engine, adapter, @"yiw");
    adapter.selectedRangeValue = NSMakeRange(5, 0);
    GSVKeys(engine, adapter, @"viwp");
    XCTAssertEqualObjects(adapter.text, @"keep keep");
}

@end
