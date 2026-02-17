#import <XCTest/XCTest.h>

#import <AppKit/AppKit.h>

#import "GSVVimBindingController.h"
#import "GSVVimConfig.h"

#if defined(NSEventTypeKeyDown)
#define GSV_TEST_KEY_DOWN_EVENT NSEventTypeKeyDown
#else
#define GSV_TEST_KEY_DOWN_EVENT NSKeyDown
#endif

@interface GSVTestFixtureTextView : NSTextView
@end

@implementation GSVTestFixtureTextView
@end

static NSEvent *GSVMakeKeyEvent(NSString *characters,
                                NSString *charactersIgnoringModifiers,
                                NSUInteger flags)
{
    return [NSEvent keyEventWithType:GSV_TEST_KEY_DOWN_EVENT
                            location:NSZeroPoint
                       modifierFlags:flags
                           timestamp:0
                        windowNumber:0
                             context:nil
                          characters:characters
         charactersIgnoringModifiers:charactersIgnoringModifiers
                           isARepeat:NO
                             keyCode:0];
}

#if defined(NSPasteboardTypeString)
static NSString *GSVTestPasteboardStringType(void)
{
    return NSPasteboardTypeString;
}
#else
static NSString *GSVTestPasteboardStringType(void)
{
    return NSStringPboardType;
}
#endif

static void GSVInsertLiteralText(NSTextView *textView, NSString *text)
{
    NSRange selected = [textView selectedRange];
    [[textView textStorage] replaceCharactersInRange:selected withString:text];
    [textView setSelectedRange:NSMakeRange(selected.location + [text length], 0)];
}

static NSUInteger GSVLineContentEndForRange(NSString *text, NSRange lineRange)
{
    NSUInteger lineStart = lineRange.location;
    NSUInteger lineEnd = NSMaxRange(lineRange);
    if (lineEnd > lineStart && [text characterAtIndex:(lineEnd - 1)] == '\n') {
        lineEnd -= 1;
    }
    return lineEnd;
}

static NSUInteger GSVFirstNonBlankForRange(NSString *text, NSRange lineRange)
{
    NSUInteger lineStart = lineRange.location;
    NSUInteger contentEnd = GSVLineContentEndForRange(text, lineRange);
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

@interface GSVVimBindingControllerTests : XCTestCase
@end

@implementation GSVVimBindingControllerTests

- (void)setUp
{
    [super setUp];
    (void)[NSApplication sharedApplication];
}

- (GSVVimConfig *)configForTests
{
    return [[GSVVimConfig alloc] initWithInsertModeMappings:@{
        @"jk": @"<Esc>",
        @"Jk": @"<Esc>",
        @"jK": @"<Esc>",
        @"JK": @"<Esc>"
    } diagnostics:nil];
}

- (void)assertEscapeMappingForTextView:(NSTextView *)textView firstKey:(NSString *)firstKey firstKeyFlags:(NSUInteger)firstFlags
{
    [textView setString:@"ab"];
    [textView setSelectedRange:NSMakeRange(2, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    controller.config = [self configForTests];

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"i", @"i", 0)]);
    XCTAssertEqual(controller.mode, GSVVimModeInsert);

    XCTAssertFalse([controller handleKeyEvent:GSVMakeKeyEvent(firstKey, [firstKey lowercaseString], firstFlags)]);
    GSVInsertLiteralText(textView, firstKey);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"k", @"k", 0)]);
    XCTAssertEqualObjects([textView string], @"ab");
    XCTAssertEqual(controller.mode, GSVVimModeNormal);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)1);
}

- (void)testInsertEscapeMappingOnPlainNSTextView
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [self assertEscapeMappingForTextView:textView firstKey:@"j" firstKeyFlags:0];
    [self assertEscapeMappingForTextView:textView firstKey:@"J" firstKeyFlags:NSShiftKeyMask];
}

- (void)testInsertEscapeMappingOnNSTextViewSubclass
{
    GSVTestFixtureTextView *textView = [[GSVTestFixtureTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [self assertEscapeMappingForTextView:textView firstKey:@"j" firstKeyFlags:0];
}

- (void)testOpenLineBelowInNormalMode
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one\ntwo"];
    [textView setSelectedRange:NSMakeRange(1, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"o", @"o", 0)]);

    XCTAssertEqualObjects([textView string], @"one\n\ntwo");
    XCTAssertEqual(controller.mode, GSVVimModeInsert);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)4);
}

- (void)testOpenLineAboveInNormalModeOnSubclass
{
    GSVTestFixtureTextView *textView = [[GSVTestFixtureTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one\ntwo"];
    [textView setSelectedRange:NSMakeRange(5, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"O", @"o", NSShiftKeyMask)]);

    XCTAssertEqualObjects([textView string], @"one\n\ntwo");
    XCTAssertEqual(controller.mode, GSVVimModeInsert);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)4);
}

- (void)testLineMotionsOnPlainNSTextView
{
    NSString *text = @"  alpha beta\n\tgamma\nz";
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:text];
    [textView setSelectedRange:NSMakeRange(8, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"0", @"0", 0)]);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)0);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"^", @"6", NSShiftKeyMask)]);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)2);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"$", @"4", NSShiftKeyMask)]);
    NSRange firstLine = [text lineRangeForRange:NSMakeRange(0, 0)];
    NSUInteger expectedLineEnd = GSVLineContentEndForRange(text, firstLine) - 1;
    XCTAssertEqual([textView selectedRange].location, expectedLineEnd);
}

- (void)testWordMotionsOnPlainNSTextView
{
    NSString *text = @"one two_three\nzz";
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:text];
    [textView setSelectedRange:NSMakeRange(0, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)4);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"e", @"e", 0)]);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)12);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"b", @"b", 0)]);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)4);
}

- (void)testGGAndGOnNSTextViewSubclass
{
    NSString *text = @"  first\nsecond\n  third";
    GSVTestFixtureTextView *textView = [[GSVTestFixtureTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:text];
    [textView setSelectedRange:NSMakeRange(5, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"G", @"g", NSShiftKeyMask)]);
    NSRange lastLine = [text lineRangeForRange:NSMakeRange([text length] - 1, 0)];
    NSUInteger expectedLast = GSVFirstNonBlankForRange(text, lastLine);
    XCTAssertEqual([textView selectedRange].location, expectedLast);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"g", @"g", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"g", @"g", 0)]);
    NSRange firstLine = [text lineRangeForRange:NSMakeRange(0, 0)];
    NSUInteger expectedFirst = GSVFirstNonBlankForRange(text, firstLine);
    XCTAssertEqual([textView selectedRange].location, expectedFirst);
}

- (void)testVisualModeSelectionAndEscapeOnPlainNSTextView
{
    NSString *text = @"alpha beta";
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:text];
    [textView setSelectedRange:NSMakeRange(2, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"v", @"v", 0)]);
    XCTAssertEqual(controller.mode, GSVVimModeVisual);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)2);
    XCTAssertEqual([textView selectedRange].length, (NSUInteger)1);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"l", @"l", 0)]);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)2);
    XCTAssertEqual([textView selectedRange].length, (NSUInteger)2);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)2);
    XCTAssertEqual([textView selectedRange].length, (NSUInteger)5);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"\x1b", @"\x1b", 0)]);
    XCTAssertEqual(controller.mode, GSVVimModeNormal);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)6);
    XCTAssertEqual([textView selectedRange].length, (NSUInteger)0);
}

- (void)testVisualGAndGGOnNSTextViewSubclass
{
    NSString *text = @"  one\nmiddle\n  three";
    GSVTestFixtureTextView *textView = [[GSVTestFixtureTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:text];
    [textView setSelectedRange:NSMakeRange(7, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"v", @"v", 0)]);
    XCTAssertEqual(controller.mode, GSVVimModeVisual);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"G", @"g", NSShiftKeyMask)]);
    NSRange lastLine = [text lineRangeForRange:NSMakeRange([text length] - 1, 0)];
    NSUInteger expectedLast = GSVFirstNonBlankForRange(text, lastLine);
    NSUInteger expectedStart = MIN((NSUInteger)7, expectedLast);
    NSUInteger expectedLength = (MAX((NSUInteger)7, expectedLast) - expectedStart) + 1;
    XCTAssertEqual([textView selectedRange].location, expectedStart);
    XCTAssertEqual([textView selectedRange].length, expectedLength);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"g", @"g", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"g", @"g", 0)]);
    NSRange firstLine = [text lineRangeForRange:NSMakeRange(0, 0)];
    NSUInteger expectedFirst = GSVFirstNonBlankForRange(text, firstLine);
    expectedStart = MIN((NSUInteger)7, expectedFirst);
    expectedLength = (MAX((NSUInteger)7, expectedFirst) - expectedStart) + 1;
    XCTAssertEqual([textView selectedRange].location, expectedStart);
    XCTAssertEqual([textView selectedRange].length, expectedLength);
}

- (void)testVisualLineModeSelectionAndDeleteOnPlainNSTextView
{
    NSString *text = @"one\ntwo\nthree";
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:text];
    [textView setSelectedRange:NSMakeRange(5, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"V", @"v", NSShiftKeyMask)]);
    XCTAssertEqual(controller.mode, GSVVimModeVisualLine);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)4);
    XCTAssertEqual([textView selectedRange].length, (NSUInteger)4);

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"d", @"d", 0)]);
    XCTAssertEqual(controller.mode, GSVVimModeNormal);
    XCTAssertEqualObjects([textView string], @"one\nthree");
}

- (void)testVisualLineModeExpandsByLineWithMotion
{
    NSString *text = @"one\ntwo\nthree\n";
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:text];
    [textView setSelectedRange:NSMakeRange(4, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"V", @"v", NSShiftKeyMask)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"j", @"j", 0)]);
    XCTAssertEqual(controller.mode, GSVVimModeVisualLine);
    XCTAssertEqual([textView selectedRange].location, (NSUInteger)4);
    XCTAssertEqual([textView selectedRange].length, (NSUInteger)10);
}

- (void)testVisualYankCharwiseOnSubclassDoesNotDelete
{
    GSVTestFixtureTextView *textView = [[GSVTestFixtureTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"abcd"];
    [textView setSelectedRange:NSMakeRange(1, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"v", @"v", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"l", @"l", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"y", @"y", 0)]);

    XCTAssertEqual(controller.mode, GSVVimModeNormal);
    XCTAssertEqualObjects([textView string], @"abcd");
}

- (void)testDeleteLineAndPutLinewiseOnPlainNSTextView
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one\ntwo\nthree"];
    [textView setSelectedRange:NSMakeRange(5, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"d", @"d", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"d", @"d", 0)]);
    XCTAssertEqualObjects([textView string], @"one\nthree");

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"p", @"p", 0)]);
    XCTAssertEqualObjects([textView string], @"one\nthree\ntwo\n");
}

- (void)testYankLineAndPutBeforeOnSubclass
{
    GSVTestFixtureTextView *textView = [[GSVTestFixtureTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one\ntwo\nthree"];
    [textView setSelectedRange:NSMakeRange(5, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"y", @"y", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"y", @"y", 0)]);
    XCTAssertEqualObjects([textView string], @"one\ntwo\nthree");

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"P", @"p", NSShiftKeyMask)]);
    XCTAssertEqualObjects([textView string], @"one\ntwo\ntwo\nthree");
}

- (void)testDeleteWordMotionAndPutBeforeRestoresOnPlainNSTextView
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"alpha beta"];
    [textView setSelectedRange:NSMakeRange(0, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"d", @"d", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);
    XCTAssertEqualObjects([textView string], @"beta");

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"P", @"p", NSShiftKeyMask)]);
    XCTAssertEqualObjects([textView string], @"alpha beta");
}

- (void)testDeleteToLineEndAndFileEndMotionsOnPlainNSTextView
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one two\nthree"];
    [textView setSelectedRange:NSMakeRange(4, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"d", @"d", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"$", @"4", NSShiftKeyMask)]);
    XCTAssertEqualObjects([textView string], @"one \nthree");

    [textView setString:@"one\ntwo\nthree"];
    [textView setSelectedRange:NSMakeRange(4, 0)];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"d", @"d", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"G", @"g", NSShiftKeyMask)]);
    XCTAssertEqualObjects([textView string], @"one\n");
}

- (void)testChangeInnerWordOnPlainNSTextView
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one two three"];
    [textView setSelectedRange:NSMakeRange(5, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"c", @"c", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"i", @"i", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);

    XCTAssertEqual(controller.mode, GSVVimModeInsert);
    XCTAssertEqualObjects([textView string], @"one  three");
}

- (void)testChangeAWordOnSubclass
{
    GSVTestFixtureTextView *textView = [[GSVTestFixtureTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one two three"];
    [textView setSelectedRange:NSMakeRange(5, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"c", @"c", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"a", @"a", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);

    XCTAssertEqual(controller.mode, GSVVimModeInsert);
    XCTAssertEqualObjects([textView string], @"one three");
}

- (void)testQuotePlusYankInnerWordThenPutUsesRegister
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one two"];
    [textView setSelectedRange:NSMakeRange(4, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"\"", @"\"", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"+", @"+", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"y", @"y", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"i", @"i", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);
    XCTAssertEqual(controller.mode, GSVVimModeNormal);
    XCTAssertEqualObjects([textView string], @"one two");

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"P", @"p", NSShiftKeyMask)]);
    XCTAssertEqualObjects([textView string], @"one twotwo");
}

- (void)testCwDoesNotConsumeTrailingWhitespaceOnPlainNSTextView
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one two three"];
    [textView setSelectedRange:NSMakeRange(4, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"c", @"c", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);

    XCTAssertEqual(controller.mode, GSVVimModeInsert);
    XCTAssertEqualObjects([textView string], @"one  three");
}

- (void)testUppercaseCChangesToLineEndOnSubclass
{
    GSVTestFixtureTextView *textView = [[GSVTestFixtureTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one two\nthree"];
    [textView setSelectedRange:NSMakeRange(4, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"C", @"c", NSShiftKeyMask)]);
    XCTAssertEqual(controller.mode, GSVVimModeInsert);
    XCTAssertEqualObjects([textView string], @"one \nthree");
}

- (void)testUppercaseDDeletesToLineEndOnPlainNSTextView
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one two\nthree"];
    [textView setSelectedRange:NSMakeRange(4, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"D", @"d", NSShiftKeyMask)]);
    XCTAssertEqual(controller.mode, GSVVimModeNormal);
    XCTAssertEqualObjects([textView string], @"one \nthree");
}

- (void)testCcChangesCurrentLineOnPlainNSTextView
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"one\ntwo\nthree"];
    [textView setSelectedRange:NSMakeRange(5, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"c", @"c", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"c", @"c", 0)]);
    XCTAssertEqual(controller.mode, GSVVimModeInsert);
    XCTAssertEqualObjects([textView string], @"one\nthree");
}

- (void)testDiwDawYiwYawOnPlainNSTextView
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];

    [textView setString:@"one two three"];
    [textView setSelectedRange:NSMakeRange(5, 0)];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"d", @"d", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"i", @"i", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);
    XCTAssertEqualObjects([textView string], @"one  three");

    [textView setString:@"one two three"];
    [textView setSelectedRange:NSMakeRange(5, 0)];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"d", @"d", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"a", @"a", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);
    XCTAssertEqualObjects([textView string], @"one three");

    [textView setString:@"one two three"];
    [textView setSelectedRange:NSMakeRange(5, 0)];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"y", @"y", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"i", @"i", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"P", @"p", NSShiftKeyMask)]);
    XCTAssertEqualObjects([textView string], @"one twotwo three");

    [textView setString:@"one two three"];
    [textView setSelectedRange:NSMakeRange(5, 0)];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"y", @"y", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"a", @"a", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"P", @"p", NSShiftKeyMask)]);
    XCTAssertEqualObjects([textView string], @"one two two three");
}

- (void)testCountPrefixAppliesToXAndDotRepeatsDelete
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];

    [textView setString:@"abcdef"];
    [textView setSelectedRange:NSMakeRange(0, 0)];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"3", @"3", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"x", @"x", 0)]);
    XCTAssertEqualObjects([textView string], @"def");

    [textView setString:@"one two three four"];
    [textView setSelectedRange:NSMakeRange(0, 0)];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"d", @"d", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"w", @"w", 0)]);
    XCTAssertEqualObjects([textView string], @"two three four");

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@".", @".", 0)]);
    XCTAssertEqualObjects([textView string], @"three four");
}

- (void)testUndoAndControlRRedoOnPlainNSTextView
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"abcd"];
    [textView setSelectedRange:NSMakeRange(0, 0)];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"x", @"x", 0)]);
    XCTAssertEqualObjects([textView string], @"bcd");

    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"u", @"u", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"\x12", @"r", NSControlKeyMask)]);
}

- (void)testQuotePlusPutUsesSystemClipboard
{
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
    [textView setString:@"abcd"];
    [textView setSelectedRange:NSMakeRange(1, 0)];

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSString *type = GSVTestPasteboardStringType();
    [pasteboard declareTypes:@[type] owner:nil];
    [pasteboard setString:@"ZZ" forType:type];

    GSVVimBindingController *controller = [[GSVVimBindingController alloc] initWithTextView:textView];
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"\"", @"\"", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"+", @"+", 0)]);
    XCTAssertTrue([controller handleKeyEvent:GSVMakeKeyEvent(@"p", @"p", 0)]);
    XCTAssertEqualObjects([textView string], @"abZZcd");
}

@end
