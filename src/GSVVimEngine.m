#import "GSVVimEngine.h"

static BOOL GSVIsWordCharacter(unichar ch)
{
    if (ch == '_') {
        return YES;
    }
    return [[NSCharacterSet alphanumericCharacterSet] characterIsMember:ch];
}

static BOOL GSVIsInlineWhitespace(unichar ch)
{
    return (ch == ' ' || ch == '\t');
}

static BOOL GSVTokenIsDigit(NSString *token)
{
    if (token == nil || [token length] != 1) {
        return NO;
    }
    unichar ch = [token characterAtIndex:0];
    return (ch >= '0' && ch <= '9');
}

static NSUInteger GSVCountByAppendingDigit(NSUInteger count, unichar digit)
{
    NSUInteger value = (NSUInteger)(digit - '0');
    if (count > ((NSUIntegerMax - value) / 10)) {
        return NSUIntegerMax;
    }
    return (count * 10) + value;
}

@interface GSVVimEngine ()
{
    BOOL _pendingGotoPrefix;
    unichar _pendingOperator;
    NSUInteger _pendingOperatorCount;
    unichar _pendingTextObjectType;
    NSUInteger _pendingCount;
    BOOL _pendingRegisterPrefix;
    BOOL _pendingClipboardYankPrefix;
    BOOL _activeClipboardYank;
    BOOL _activeClipboardPut;
    NSUInteger _visualAnchor;
    NSUInteger _visualCursor;
    NSString *_unnamedRegister;
    BOOL _unnamedRegisterLinewise;
    NSArray *_lastChangeTokens;
    BOOL _isReplayingLastChange;
}
- (void)clearPendingState;
- (void)resetVisualState;
- (NSUInteger)consumePendingCountWithDefault:(NSUInteger)defaultValue;
- (NSArray *)tokensForCount:(NSUInteger)count;
- (NSArray *)tokensByPrependingCount:(NSUInteger)count toTokens:(NSArray *)tokens;
- (void)recordLastChangeTokens:(NSArray *)tokens;
- (BOOL)replayLastChangeWithCount:(NSUInteger)count adapter:(id<GSVTextEditing>)adapter;
- (NSUInteger)clampedCursorForAdapter:(id<GSVTextEditing>)adapter location:(NSUInteger)location;
- (void)updateVisualSelectionForAdapter:(id<GSVTextEditing>)adapter;
- (void)enterVisualModeWithAdapter:(id<GSVTextEditing>)adapter linewise:(BOOL)linewise;
- (void)exitVisualModeWithAdapter:(id<GSVTextEditing>)adapter collapseToCursor:(BOOL)collapseToCursor;
- (NSRange)effectiveVisualSelectionRangeForAdapter:(id<GSVTextEditing>)adapter;
- (NSRange)effectiveCurrentLineRangeForAdapter:(id<GSVTextEditing>)adapter;
- (NSRange)wordTextObjectRangeForAdapter:(id<GSVTextEditing>)adapter
                                   around:(BOOL)around
                                    found:(BOOL *)found;
- (BOOL)isLinewiseVisualMode;
- (NSString *)currentUnnamedRegisterString;
- (NSString *)normalizedLinewiseRegisterString:(NSString *)string;
- (void)setUnnamedRegisterString:(NSString *)string linewise:(BOOL)linewise;
- (NSString *)captureUnnamedRegisterFromRange:(NSRange)range
                                      adapter:(id<GSVTextEditing>)adapter
                                     linewise:(BOOL)linewise;
- (void)finishVisualOperationToNormalMode;
- (BOOL)executeMotionToken:(NSString *)keyToken
                normalized:(NSString *)normalized
                     count:(NSUInteger)count
                   adapter:(id<GSVTextEditing>)adapter;
- (BOOL)executeSingleMotionToken:(NSString *)keyToken
                      normalized:(NSString *)normalized
                   adapter:(id<GSVTextEditing>)adapter;
- (BOOL)handleVisualMotionToken:(NSString *)keyToken
                     normalized:(NSString *)normalized
                          count:(NSUInteger)count
                        adapter:(id<GSVTextEditing>)adapter;
- (void)performOperator:(unichar)op
                 onRange:(NSRange)range
                linewise:(BOOL)linewise
                 adapter:(id<GSVTextEditing>)adapter;
- (void)handleDoubleOperatorCommand:(unichar)op
                              count:(NSUInteger)count
                            adapter:(id<GSVTextEditing>)adapter;
- (BOOL)performPendingOperator:(unichar)op
                    motionToken:(NSString *)keyToken
                     normalized:(NSString *)normalized
                    motionCount:(NSUInteger)motionCount
                        adapter:(id<GSVTextEditing>)adapter;
- (BOOL)putFromRegisterAfterCursor:(BOOL)after
                             count:(NSUInteger)count
                           adapter:(id<GSVTextEditing>)adapter;
@end

@implementation GSVVimEngine

- (instancetype)init
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _mode = GSVVimModeNormal;
    _pendingGotoPrefix = NO;
    _pendingOperator = 0;
    _pendingOperatorCount = 0;
    _pendingTextObjectType = 0;
    _pendingCount = 0;
    _pendingRegisterPrefix = NO;
    _pendingClipboardYankPrefix = NO;
    _activeClipboardYank = NO;
    _activeClipboardPut = NO;
    _visualAnchor = NSNotFound;
    _visualCursor = NSNotFound;
    _unnamedRegister = @"";
    _unnamedRegisterLinewise = NO;
    _unnamedRegisterUsesClipboard = NO;
    _lastChangeTokens = nil;
    _isReplayingLastChange = NO;
    return self;
}

- (void)setMode:(GSVVimMode)mode
{
    if (_mode == mode) {
        return;
    }

    _mode = mode;
    if (mode != GSVVimModeVisual && mode != GSVVimModeVisualLine) {
        [self resetVisualState];
    }
    id<GSVVimEngineDelegate> delegate = self.delegate;
    if (delegate != nil && [delegate respondsToSelector:@selector(vimEngine:didChangeMode:)]) {
        [delegate vimEngine:self didChangeMode:mode];
    }
}

- (void)resetToNormalMode
{
    [self clearPendingState];
    [self resetVisualState];
    self.mode = GSVVimModeNormal;
}

- (void)clearPendingState
{
    _pendingGotoPrefix = NO;
    _pendingOperator = 0;
    _pendingOperatorCount = 0;
    _pendingTextObjectType = 0;
    _pendingCount = 0;
    _pendingRegisterPrefix = NO;
    _pendingClipboardYankPrefix = NO;
    _activeClipboardYank = NO;
    _activeClipboardPut = NO;
}

- (void)resetVisualState
{
    _visualAnchor = NSNotFound;
    _visualCursor = NSNotFound;
}

- (NSUInteger)consumePendingCountWithDefault:(NSUInteger)defaultValue
{
    if (_pendingCount == 0) {
        return defaultValue;
    }
    NSUInteger count = _pendingCount;
    _pendingCount = 0;
    return count;
}

- (NSArray *)tokensForCount:(NSUInteger)count
{
    if (count <= 1) {
        return @[];
    }
    NSString *countString = [NSString stringWithFormat:@"%lu", (unsigned long)count];
    NSMutableArray *tokens = [NSMutableArray arrayWithCapacity:[countString length]];
    for (NSUInteger i = 0; i < [countString length]; i += 1) {
        NSString *digit = [countString substringWithRange:NSMakeRange(i, 1)];
        [tokens addObject:digit];
    }
    return tokens;
}

- (NSArray *)tokensByPrependingCount:(NSUInteger)count toTokens:(NSArray *)tokens
{
    NSMutableArray *result = [NSMutableArray array];
    [result addObjectsFromArray:[self tokensForCount:count]];
    if (tokens != nil) {
        [result addObjectsFromArray:tokens];
    }
    return result;
}

- (void)recordLastChangeTokens:(NSArray *)tokens
{
    if (_isReplayingLastChange) {
        return;
    }
    if (tokens == nil || [tokens count] == 0) {
        return;
    }
    _lastChangeTokens = [tokens copy];
}

- (BOOL)replayLastChangeWithCount:(NSUInteger)count adapter:(id<GSVTextEditing>)adapter
{
    if (_lastChangeTokens == nil || [_lastChangeTokens count] == 0 || count == 0) {
        return YES;
    }

    BOOL previousReplayState = _isReplayingLastChange;
    _isReplayingLastChange = YES;
    for (NSUInteger repeatIndex = 0; repeatIndex < count; repeatIndex += 1) {
        [self clearPendingState];
        for (NSString *token in _lastChangeTokens) {
            (void)[self handleKeyToken:token adapter:adapter];
        }
    }
    [self clearPendingState];
    _isReplayingLastChange = previousReplayState;
    return YES;
}

- (BOOL)isLinewiseVisualMode
{
    return (self.mode == GSVVimModeVisualLine);
}

- (NSUInteger)clampedCursorForAdapter:(id<GSVTextEditing>)adapter location:(NSUInteger)location
{
    NSUInteger length = [adapter textLength];
    if (length == 0) {
        return 0;
    }
    return MIN(location, length - 1);
}

- (void)updateVisualSelectionForAdapter:(id<GSVTextEditing>)adapter
{
    NSUInteger length = [adapter textLength];
    if (length == 0) {
        _visualAnchor = 0;
        _visualCursor = 0;
        [adapter setSelectedRange:NSMakeRange(0, 0)];
        return;
    }

    if (_visualAnchor == NSNotFound) {
        _visualAnchor = [self clampedCursorForAdapter:adapter location:[adapter selectedRange].location];
    }
    if (_visualCursor == NSNotFound) {
        _visualCursor = _visualAnchor;
    }

    _visualAnchor = [self clampedCursorForAdapter:adapter location:_visualAnchor];
    _visualCursor = [self clampedCursorForAdapter:adapter location:_visualCursor];

    if ([self isLinewiseVisualMode]) {
        NSString *text = [adapter textString];
        NSRange anchorLineRange = [text lineRangeForRange:NSMakeRange(_visualAnchor, 0)];
        NSRange cursorLineRange = [text lineRangeForRange:NSMakeRange(_visualCursor, 0)];
        NSUInteger start = MIN(anchorLineRange.location, cursorLineRange.location);
        NSUInteger end = MAX(NSMaxRange(anchorLineRange), NSMaxRange(cursorLineRange));
        [adapter setSelectedRange:NSMakeRange(start, end - start)];
        return;
    }

    NSUInteger start = MIN(_visualAnchor, _visualCursor);
    NSUInteger end = MAX(_visualAnchor, _visualCursor);
    [adapter setSelectedRange:NSMakeRange(start, (end - start) + 1)];
}

- (void)enterVisualModeWithAdapter:(id<GSVTextEditing>)adapter linewise:(BOOL)linewise
{
    [self clearPendingState];
    NSUInteger length = [adapter textLength];
    if (length == 0) {
        _visualAnchor = 0;
        _visualCursor = 0;
        [adapter setSelectedRange:NSMakeRange(0, 0)];
        self.mode = linewise ? GSVVimModeVisualLine : GSVVimModeVisual;
        return;
    }

    NSUInteger location = [adapter selectedRange].location;
    _visualAnchor = [self clampedCursorForAdapter:adapter location:location];
    _visualCursor = _visualAnchor;
    self.mode = linewise ? GSVVimModeVisualLine : GSVVimModeVisual;
    [self updateVisualSelectionForAdapter:adapter];
}

- (void)exitVisualModeWithAdapter:(id<GSVTextEditing>)adapter collapseToCursor:(BOOL)collapseToCursor
{
    [self clearPendingState];

    NSUInteger length = [adapter textLength];
    if (length == 0) {
        [adapter setSelectedRange:NSMakeRange(0, 0)];
    } else {
        NSUInteger anchor = (_visualAnchor != NSNotFound) ? _visualAnchor : [adapter selectedRange].location;
        NSUInteger cursor = (_visualCursor != NSNotFound) ? _visualCursor : [adapter selectedRange].location;
        anchor = [self clampedCursorForAdapter:adapter location:anchor];
        cursor = [self clampedCursorForAdapter:adapter location:cursor];

        NSUInteger location = collapseToCursor ? cursor : MIN(anchor, cursor);
        [adapter setSelectedRange:NSMakeRange(location, 0)];
    }

    [self resetVisualState];
    self.mode = GSVVimModeNormal;
}

- (NSRange)effectiveVisualSelectionRangeForAdapter:(id<GSVTextEditing>)adapter
{
    NSUInteger length = [adapter textLength];
    if (length == 0) {
        return NSMakeRange(0, 0);
    }

    NSRange selected = [adapter selectedRange];
    if (selected.location >= length) {
        selected.location = length - 1;
        selected.length = 1;
    }
    if (selected.length == 0) {
        selected.length = 1;
    }
    if (NSMaxRange(selected) > length) {
        selected.length = length - selected.location;
    }
    return selected;
}

- (NSRange)effectiveCurrentLineRangeForAdapter:(id<GSVTextEditing>)adapter
{
    NSUInteger length = [adapter textLength];
    if (length == 0) {
        return NSMakeRange(0, 0);
    }

    NSString *text = [adapter textString];
    NSUInteger location = [self clampedCursorForAdapter:adapter location:[adapter selectedRange].location];
    return [text lineRangeForRange:NSMakeRange(location, 0)];
}

- (NSRange)wordTextObjectRangeForAdapter:(id<GSVTextEditing>)adapter
                                   around:(BOOL)around
                                    found:(BOOL *)found
{
    if (found != NULL) {
        *found = NO;
    }

    NSUInteger length = [adapter textLength];
    if (length == 0) {
        return NSMakeRange(0, 0);
    }

    NSString *text = [adapter textString];
    NSUInteger cursor = [self clampedCursorForAdapter:adapter location:[adapter selectedRange].location];

    NSUInteger index = cursor;
    if (!GSVIsWordCharacter([text characterAtIndex:index])) {
        NSUInteger search = index;
        while (search < length && !GSVIsWordCharacter([text characterAtIndex:search])) {
            search += 1;
        }
        if (search < length) {
            index = search;
        } else {
            if (index == 0) {
                return NSMakeRange(0, 0);
            }
            search = index;
            while (search > 0) {
                search -= 1;
                if (GSVIsWordCharacter([text characterAtIndex:search])) {
                    index = search;
                    break;
                }
            }
            if (!GSVIsWordCharacter([text characterAtIndex:index])) {
                return NSMakeRange(0, 0);
            }
        }
    }

    NSUInteger start = index;
    while (start > 0 && GSVIsWordCharacter([text characterAtIndex:(start - 1)])) {
        start -= 1;
    }

    NSUInteger end = index + 1;
    while (end < length && GSVIsWordCharacter([text characterAtIndex:end])) {
        end += 1;
    }

    if (around) {
        NSUInteger whitespaceEnd = end;
        while (whitespaceEnd < length && GSVIsInlineWhitespace([text characterAtIndex:whitespaceEnd])) {
            whitespaceEnd += 1;
        }
        if (whitespaceEnd > end) {
            end = whitespaceEnd;
        } else {
            while (start > 0 && GSVIsInlineWhitespace([text characterAtIndex:(start - 1)])) {
                start -= 1;
            }
        }
    }

    if (found != NULL) {
        *found = (end > start);
    }
    return NSMakeRange(start, (end > start ? (end - start) : 0));
}

- (NSString *)currentUnnamedRegisterString
{
    if (self.unnamedRegisterUsesClipboard && self.clipboard != nil) {
        NSString *clipboardString = [self.clipboard readClipboardString];
        if (clipboardString != nil && ![clipboardString isEqualToString:_unnamedRegister]) {
            _unnamedRegister = [clipboardString copy];
            _unnamedRegisterLinewise = [clipboardString hasSuffix:@"\n"];
        }
    }
    return (_unnamedRegister != nil) ? _unnamedRegister : @"";
}

- (NSString *)normalizedLinewiseRegisterString:(NSString *)string
{
    if (string == nil || [string length] == 0) {
        return @"";
    }
    if ([string hasSuffix:@"\n"]) {
        return string;
    }
    return [string stringByAppendingString:@"\n"];
}

- (void)setUnnamedRegisterString:(NSString *)string linewise:(BOOL)linewise
{
    NSString *value = (string != nil) ? string : @"";
    _unnamedRegister = [value copy];
    _unnamedRegisterLinewise = linewise;
    if (self.unnamedRegisterUsesClipboard && self.clipboard != nil) {
        [self.clipboard writeClipboardString:_unnamedRegister];
    }
}

- (NSString *)captureUnnamedRegisterFromRange:(NSRange)range
                                      adapter:(id<GSVTextEditing>)adapter
                                     linewise:(BOOL)linewise
{
    NSString *text = [adapter textString];
    NSUInteger length = [text length];
    if (length == 0 || range.length == 0 || range.location >= length) {
        [self setUnnamedRegisterString:@"" linewise:linewise];
        return @"";
    }
    if (NSMaxRange(range) > length) {
        range.length = length - range.location;
    }
    NSString *captured = [text substringWithRange:range];
    [self setUnnamedRegisterString:captured linewise:linewise];
    return captured;
}

- (void)finishVisualOperationToNormalMode
{
    [self clearPendingState];
    [self resetVisualState];
    self.mode = GSVVimModeNormal;
}

- (BOOL)executeSingleMotionToken:(NSString *)keyToken
                      normalized:(NSString *)normalized
                         adapter:(id<GSVTextEditing>)adapter
{
    if ([keyToken isEqualToString:@"G"]) {
        [adapter moveToLastLine];
        return YES;
    }
    if ([keyToken isEqualToString:@"0"]) {
        [adapter moveToLineStart];
        return YES;
    }
    if ([keyToken isEqualToString:@"^"]) {
        [adapter moveToFirstNonBlankInLine];
        return YES;
    }
    if ([keyToken isEqualToString:@"$"]) {
        [adapter moveToLineEnd];
        return YES;
    }
    if ([normalized isEqualToString:@"h"]) {
        [adapter moveCursorLeft];
        return YES;
    }
    if ([normalized isEqualToString:@"j"]) {
        [adapter moveCursorDown];
        return YES;
    }
    if ([normalized isEqualToString:@"k"]) {
        [adapter moveCursorUp];
        return YES;
    }
    if ([normalized isEqualToString:@"l"]) {
        [adapter moveCursorRight];
        return YES;
    }
    if ([normalized isEqualToString:@"w"]) {
        [adapter moveWordForward];
        return YES;
    }
    if ([normalized isEqualToString:@"b"]) {
        [adapter moveWordBackward];
        return YES;
    }
    if ([normalized isEqualToString:@"e"]) {
        [adapter moveToWordEndForward];
        return YES;
    }
    return NO;
}

- (BOOL)executeMotionToken:(NSString *)keyToken
                normalized:(NSString *)normalized
                     count:(NSUInteger)count
                   adapter:(id<GSVTextEditing>)adapter
{
    NSUInteger repeats = (count > 0) ? count : 1;
    for (NSUInteger i = 0; i < repeats; i += 1) {
        BOOL moved = [self executeSingleMotionToken:keyToken normalized:normalized adapter:adapter];
        if (!moved) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)handleVisualMotionToken:(NSString *)keyToken
                     normalized:(NSString *)normalized
                          count:(NSUInteger)count
                        adapter:(id<GSVTextEditing>)adapter
{
    NSUInteger length = [adapter textLength];
    if (length == 0) {
        [adapter setSelectedRange:NSMakeRange(0, 0)];
        return YES;
    }

    NSUInteger cursor = (_visualCursor != NSNotFound) ? _visualCursor : [adapter selectedRange].location;
    cursor = [self clampedCursorForAdapter:adapter location:cursor];
    [adapter setSelectedRange:NSMakeRange(cursor, 0)];

    BOOL moved = [self executeMotionToken:keyToken normalized:normalized count:count adapter:adapter];
    if (!moved) {
        return NO;
    }

    _visualCursor = [self clampedCursorForAdapter:adapter location:[adapter selectedRange].location];
    [self updateVisualSelectionForAdapter:adapter];
    return YES;
}

- (void)performOperator:(unichar)op
                 onRange:(NSRange)range
                linewise:(BOOL)linewise
                 adapter:(id<GSVTextEditing>)adapter
{
    NSUInteger length = [adapter textLength];
    if (length == 0 || range.length == 0 || range.location >= length) {
        return;
    }
    if (NSMaxRange(range) > length) {
        range.length = length - range.location;
    }
    if (range.length == 0) {
        return;
    }

    if (op == 'y') {
        NSString *captured = [self captureUnnamedRegisterFromRange:range adapter:adapter linewise:linewise];
        if (_activeClipboardYank && self.clipboard != nil) {
            [self.clipboard writeClipboardString:captured];
        }
        _activeClipboardYank = NO;
        return;
    }

    if (op == 'd' || op == 'c') {
        (void)[self captureUnnamedRegisterFromRange:range adapter:adapter linewise:linewise];
        [adapter replaceCharactersInRange:range withString:@""];
        NSUInteger newLength = [adapter textLength];
        NSUInteger location = MIN(range.location, newLength);
        [adapter setSelectedRange:NSMakeRange(location, 0)];
        if (op == 'c') {
            self.mode = GSVVimModeInsert;
        }
        _activeClipboardYank = NO;
    }
}

- (void)handleDoubleOperatorCommand:(unichar)op
                              count:(NSUInteger)count
                            adapter:(id<GSVTextEditing>)adapter
{
    NSUInteger repeats = (count > 0) ? count : 1;
    NSString *text = [adapter textString];
    NSUInteger length = [text length];

    NSUInteger cursor = [adapter selectedRange].location;
    NSRange lineRange = [self effectiveCurrentLineRangeForAdapter:adapter];
    if (lineRange.length == 0) {
        return;
    }

    NSUInteger end = NSMaxRange(lineRange);
    for (NSUInteger i = 1; i < repeats; i += 1) {
        if (end >= length) {
            break;
        }
        NSRange nextLineRange = [text lineRangeForRange:NSMakeRange(end, 0)];
        if (nextLineRange.length == 0) {
            break;
        }
        end = NSMaxRange(nextLineRange);
    }
    NSRange multiLineRange = NSMakeRange(lineRange.location, end - lineRange.location);
    [self performOperator:op onRange:multiLineRange linewise:YES adapter:adapter];
    if (op == 'y') {
        [adapter setSelectedRange:NSMakeRange(cursor, 0)];
    }
}

- (BOOL)performPendingOperator:(unichar)op
                    motionToken:(NSString *)keyToken
                     normalized:(NSString *)normalized
                    motionCount:(NSUInteger)motionCount
                        adapter:(id<GSVTextEditing>)adapter
{
    NSUInteger length = [adapter textLength];
    if (length == 0) {
        [adapter setSelectedRange:NSMakeRange(0, 0)];
        return YES;
    }

    NSUInteger repeats = (motionCount > 0) ? motionCount : 1;
    NSUInteger start = [self clampedCursorForAdapter:adapter location:[adapter selectedRange].location];
    NSRange range = NSMakeRange(start, 0);

    // Vim-like special case: "cw" on a word behaves like "ce" (no trailing space).
    if (op == 'c' && repeats == 1 && [normalized isEqualToString:@"w"]) {
        NSString *text = [adapter textString];
        if (start < length && GSVIsWordCharacter([text characterAtIndex:start])) {
            NSUInteger end = start;
            while (end < length && GSVIsWordCharacter([text characterAtIndex:end])) {
                end += 1;
            }
            range = NSMakeRange(start, end - start);
        } else {
            [adapter setSelectedRange:NSMakeRange(start, 0)];
            BOOL moved = [self executeMotionToken:keyToken
                                       normalized:normalized
                                            count:repeats
                                          adapter:adapter];
            if (!moved) {
                [adapter setSelectedRange:NSMakeRange(start, 0)];
                return NO;
            }
            NSUInteger target = [self clampedCursorForAdapter:adapter location:[adapter selectedRange].location];
            if (start <= target) {
                range = NSMakeRange(start, target - start);
            } else {
                range = NSMakeRange(target, start - target);
            }
        }
    } else if ([keyToken isEqualToString:@"G"]) {
        range = NSMakeRange(start, length - start);
    } else {
        [adapter setSelectedRange:NSMakeRange(start, 0)];
        BOOL moved = [self executeMotionToken:keyToken
                                   normalized:normalized
                                        count:repeats
                                      adapter:adapter];
        if (!moved) {
            [adapter setSelectedRange:NSMakeRange(start, 0)];
            return NO;
        }

        NSUInteger target = [self clampedCursorForAdapter:adapter location:[adapter selectedRange].location];
        BOOL inclusive = ([keyToken isEqualToString:@"$"] || [normalized isEqualToString:@"e"]);
        if (start <= target) {
            NSUInteger delta = target - start;
            range = NSMakeRange(start, delta + (inclusive ? 1 : 0));
        } else {
            NSUInteger delta = start - target;
            range = NSMakeRange(target, delta + (inclusive ? 1 : 0));
        }
    }

    [adapter setSelectedRange:NSMakeRange(start, 0)];
    [self performOperator:op onRange:range linewise:NO adapter:adapter];
    if (op == 'y') {
        [adapter setSelectedRange:NSMakeRange(start, 0)];
    }
    return YES;
}

- (BOOL)putFromRegisterAfterCursor:(BOOL)after
                             count:(NSUInteger)count
                           adapter:(id<GSVTextEditing>)adapter
{
    NSString *registerString = nil;
    BOOL registerLinewise = NO;
    if (_activeClipboardPut && self.clipboard != nil) {
        registerString = [self.clipboard readClipboardString];
        registerLinewise = [registerString hasSuffix:@"\n"];
    } else {
        registerString = [self currentUnnamedRegisterString];
        registerLinewise = _unnamedRegisterLinewise;
    }

    if (registerString == nil || [registerString length] == 0 || count == 0) {
        _activeClipboardPut = NO;
        return YES;
    }

    NSUInteger repeats = (count > 0) ? count : 1;
    for (NSUInteger repeatIndex = 0; repeatIndex < repeats; repeatIndex += 1) {
        NSUInteger textLength = [adapter textLength];
        NSUInteger cursor = [adapter selectedRange].location;

        if (registerLinewise) {
            NSString *linewiseString = [self normalizedLinewiseRegisterString:registerString];
            NSUInteger insertLocation = 0;
            NSUInteger cursorLocation = 0;
            BOOL needsLeadingNewline = NO;
            if (textLength > 0) {
                NSString *text = [adapter textString];
                NSUInteger lineLocation = [self clampedCursorForAdapter:adapter location:cursor];
                NSRange lineRange = [text lineRangeForRange:NSMakeRange(lineLocation, 0)];
                insertLocation = after ? NSMaxRange(lineRange) : lineRange.location;
                if (after && insertLocation == textLength && insertLocation > 0) {
                    unichar before = [text characterAtIndex:(insertLocation - 1)];
                    needsLeadingNewline = (before != '\n');
                }
            }

            NSString *insertion = linewiseString;
            if (needsLeadingNewline) {
                insertion = [@"\n" stringByAppendingString:linewiseString];
                cursorLocation = insertLocation + 1;
            } else {
                cursorLocation = insertLocation;
            }
            [adapter replaceCharactersInRange:NSMakeRange(insertLocation, 0) withString:insertion];
            [adapter setSelectedRange:NSMakeRange(cursorLocation, 0)];
            continue;
        }

        NSUInteger insertLocation = 0;
        if (textLength > 0) {
            NSUInteger clampedCursor = [self clampedCursorForAdapter:adapter location:cursor];
            insertLocation = after ? (clampedCursor + 1) : clampedCursor;
        }
        [adapter replaceCharactersInRange:NSMakeRange(insertLocation, 0) withString:registerString];
        NSUInteger newCursor = insertLocation;
        if ([registerString length] > 0) {
            newCursor = insertLocation + [registerString length] - 1;
        }
        [adapter setSelectedRange:NSMakeRange(newCursor, 0)];
    }

    _activeClipboardPut = NO;
    return YES;
}

- (BOOL)handleKeyToken:(NSString *)keyToken adapter:(id<GSVTextEditing>)adapter
{
    if (adapter == nil || keyToken == nil || [keyToken length] == 0) {
        return NO;
    }

    if (self.mode == GSVVimModeInsert) {
        if ([keyToken isEqualToString:@"<Esc>"]) {
            NSRange selected = [adapter selectedRange];
            if (selected.length == 0 && selected.location > 0) {
                [adapter setSelectedRange:NSMakeRange(selected.location - 1, 0)];
            }
            [self clearPendingState];
            [self resetVisualState];
            self.mode = GSVVimModeNormal;
            return YES;
        }
        return NO;
    }

    NSString *normalized = [keyToken lowercaseString];
    BOOL isDigitToken = GSVTokenIsDigit(keyToken);

    if (_pendingRegisterPrefix) {
        _pendingRegisterPrefix = NO;
        _pendingClipboardYankPrefix = [keyToken isEqualToString:@"+"];
        _activeClipboardYank = NO;
        _activeClipboardPut = NO;
        return YES;
    }
    if ([keyToken isEqualToString:@"\""]) {
        [self clearPendingState];
        _pendingRegisterPrefix = YES;
        return YES;
    }
    if (_pendingClipboardYankPrefix) {
        _activeClipboardYank = ([normalized isEqualToString:@"y"] || _pendingOperator == 'y');
        _activeClipboardPut = ([normalized isEqualToString:@"p"] || [keyToken isEqualToString:@"P"]);
        _pendingClipboardYankPrefix = NO;
    }

    if (self.mode == GSVVimModeVisual || self.mode == GSVVimModeVisualLine) {
        BOOL linewiseMode = [self isLinewiseVisualMode];
        if (isDigitToken) {
            unichar digit = [keyToken characterAtIndex:0];
            if (!(digit == '0' && _pendingCount == 0)) {
                _pendingCount = GSVCountByAppendingDigit(_pendingCount, digit);
                return YES;
            }
        }
        if ([keyToken isEqualToString:@"<Esc>"]) {
            [self exitVisualModeWithAdapter:adapter collapseToCursor:YES];
            return YES;
        }
        if (!linewiseMode && [keyToken isEqualToString:@"v"]) {
            [self exitVisualModeWithAdapter:adapter collapseToCursor:YES];
            return YES;
        }
        if (linewiseMode && [keyToken isEqualToString:@"V"]) {
            [self exitVisualModeWithAdapter:adapter collapseToCursor:YES];
            return YES;
        }
        if (!linewiseMode && [keyToken isEqualToString:@"V"]) {
            self.mode = GSVVimModeVisualLine;
            [self updateVisualSelectionForAdapter:adapter];
            return YES;
        }
        if (linewiseMode && [keyToken isEqualToString:@"v"]) {
            self.mode = GSVVimModeVisual;
            [self updateVisualSelectionForAdapter:adapter];
            return YES;
        }
        if ([normalized isEqualToString:@"d"]) {
            NSRange range = [self effectiveVisualSelectionRangeForAdapter:adapter];
            [self performOperator:'d' onRange:range linewise:linewiseMode adapter:adapter];
            [self finishVisualOperationToNormalMode];
            return YES;
        }
        if ([normalized isEqualToString:@"y"]) {
            NSRange range = [self effectiveVisualSelectionRangeForAdapter:adapter];
            [self performOperator:'y' onRange:range linewise:linewiseMode adapter:adapter];
            [self exitVisualModeWithAdapter:adapter collapseToCursor:YES];
            return YES;
        }
        if ([normalized isEqualToString:@"c"]) {
            NSRange range = [self effectiveVisualSelectionRangeForAdapter:adapter];
            [self performOperator:'c' onRange:range linewise:linewiseMode adapter:adapter];
            [self clearPendingState];
            [self resetVisualState];
            return YES;
        }

        if (_pendingGotoPrefix) {
            _pendingGotoPrefix = NO;
            if ([keyToken isEqualToString:@"g"]) {
                NSUInteger length = [adapter textLength];
                if (length == 0) {
                    [adapter setSelectedRange:NSMakeRange(0, 0)];
                    return YES;
                }
                NSUInteger cursor = (_visualCursor != NSNotFound) ? _visualCursor : [adapter selectedRange].location;
                cursor = [self clampedCursorForAdapter:adapter location:cursor];
                [adapter setSelectedRange:NSMakeRange(cursor, 0)];
                [adapter moveToFirstLine];
                _visualCursor = [self clampedCursorForAdapter:adapter location:[adapter selectedRange].location];
                [self updateVisualSelectionForAdapter:adapter];
            }
            return YES;
        }

        if ([keyToken isEqualToString:@"g"]) {
            _pendingGotoPrefix = YES;
            return YES;
        }

        NSUInteger motionCount = [self consumePendingCountWithDefault:1];
        if ([self handleVisualMotionToken:keyToken
                                normalized:normalized
                                     count:motionCount
                                   adapter:adapter]) {
            return YES;
        }

        _pendingCount = 0;
        return YES;
    }

    if (_pendingOperator != 0 && isDigitToken) {
        unichar digit = [keyToken characterAtIndex:0];
        if (!(digit == '0' && _pendingCount == 0)) {
            _pendingCount = GSVCountByAppendingDigit(_pendingCount, digit);
            return YES;
        }
    }
    if (_pendingOperator == 0 && isDigitToken) {
        unichar digit = [keyToken characterAtIndex:0];
        if (!(digit == '0' && _pendingCount == 0)) {
            _pendingCount = GSVCountByAppendingDigit(_pendingCount, digit);
            return YES;
        }
    }

    if ([keyToken isEqualToString:@"<Esc>"]) {
        [self clearPendingState];
        return YES;
    }
    if ([normalized isEqualToString:@"u"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        for (NSUInteger i = 0; i < count; i += 1) {
            [adapter undoLastChange];
        }
        return YES;
    }
    if ([keyToken isEqualToString:@"<C-r>"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        for (NSUInteger i = 0; i < count; i += 1) {
            [adapter redoLastUndo];
        }
        return YES;
    }
    if ([keyToken isEqualToString:@"."]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        return [self replayLastChangeWithCount:count adapter:adapter];
    }
    if (_pendingGotoPrefix) {
        _pendingGotoPrefix = NO;
        if ([keyToken isEqualToString:@"g"]) {
            if (_pendingOperator != 0) {
                NSUInteger length = [adapter textLength];
                NSUInteger start = [adapter selectedRange].location;
                if (length > 0) {
                    start = [self clampedCursorForAdapter:adapter location:start];
                } else {
                    start = 0;
                }
                NSRange range = NSMakeRange(0, start);
                [self performOperator:_pendingOperator onRange:range linewise:NO adapter:adapter];
                if (_pendingOperator == 'y') {
                    [adapter setSelectedRange:NSMakeRange(start, 0)];
                } else if (_pendingOperator == 'd') {
                    NSUInteger opCount = (_pendingOperatorCount > 0) ? _pendingOperatorCount : 1;
                    [self recordLastChangeTokens:[self tokensByPrependingCount:opCount
                                                                       toTokens:@[[NSString stringWithFormat:@"%C", _pendingOperator], @"g", @"g"]]];
                }
                [self clearPendingState];
                return YES;
            }
            [adapter moveToFirstLine];
            return YES;
        }
        [self clearPendingState];
        return YES;
    }
    if (_pendingOperator != 0) {
        unichar op = _pendingOperator;
        NSUInteger opCount = (_pendingOperatorCount > 0) ? _pendingOperatorCount : 1;
        if (_pendingTextObjectType != 0) {
            if ([normalized isEqualToString:@"w"]) {
                BOOL found = NO;
                NSRange range = [self wordTextObjectRangeForAdapter:adapter
                                                              around:(_pendingTextObjectType == 'a')
                                                               found:&found];
                if (found) {
                    [self performOperator:op onRange:range linewise:NO adapter:adapter];
                    if (op == 'y') {
                        [adapter setSelectedRange:NSMakeRange(range.location, 0)];
                    } else if (op == 'd') {
                        NSString *objectToken = [NSString stringWithFormat:@"%C", _pendingTextObjectType];
                        [self recordLastChangeTokens:[self tokensByPrependingCount:opCount
                                                                           toTokens:@[@"d", objectToken, @"w"]]];
                    }
                }
            }
            [self clearPendingState];
            return YES;
        }
        if ([normalized isEqualToString:@"i"] || [normalized isEqualToString:@"a"]) {
            _pendingTextObjectType = [normalized characterAtIndex:0];
            return YES;
        }
        if ([normalized length] == 1 && [normalized characterAtIndex:0] == _pendingOperator) {
            NSUInteger suffixCount = [self consumePendingCountWithDefault:1];
            NSUInteger totalCount = opCount * suffixCount;
            [self handleDoubleOperatorCommand:_pendingOperator count:totalCount adapter:adapter];
            if (op == 'd') {
                NSString *opToken = [NSString stringWithFormat:@"%C", _pendingOperator];
                [self recordLastChangeTokens:[self tokensByPrependingCount:totalCount toTokens:@[opToken, opToken]]];
            }
            [self clearPendingState];
            return YES;
        }
        if ([keyToken isEqualToString:@"g"]) {
            _pendingGotoPrefix = YES;
            return YES;
        }
        NSUInteger suffixCount = [self consumePendingCountWithDefault:1];
        NSUInteger totalMotionCount = opCount * suffixCount;
        BOOL performed = [self performPendingOperator:_pendingOperator
                                          motionToken:keyToken
                                           normalized:normalized
                                         motionCount:totalMotionCount
                                              adapter:adapter];
        if (performed && op == 'd') {
            NSString *opToken = [NSString stringWithFormat:@"%C", _pendingOperator];
            [self recordLastChangeTokens:[self tokensByPrependingCount:totalMotionCount toTokens:@[opToken, keyToken]]];
        }
        [self clearPendingState];
        return YES;
    }
    if ([keyToken isEqualToString:@"V"]) {
        _pendingCount = 0;
        [self enterVisualModeWithAdapter:adapter linewise:YES];
        return YES;
    }
    if ([normalized isEqualToString:@"v"]) {
        _pendingCount = 0;
        [self enterVisualModeWithAdapter:adapter linewise:NO];
        return YES;
    }
    if ([keyToken isEqualToString:@"P"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        BOOL explicitClipboard = _activeClipboardPut;
        BOOL handled = [self putFromRegisterAfterCursor:NO count:count adapter:adapter];
        NSMutableArray *tokens = [NSMutableArray array];
        if (explicitClipboard) {
            [tokens addObject:@"\""];
            [tokens addObject:@"+"];
        }
        [tokens addObjectsFromArray:[self tokensByPrependingCount:count toTokens:@[@"P"]]];
        [self recordLastChangeTokens:tokens];
        return handled;
    }
    if ([keyToken isEqualToString:@"C"]) {
        (void)[self performPendingOperator:'c'
                               motionToken:@"$"
                                normalized:@"$"
                              motionCount:1
                                   adapter:adapter];
        [self clearPendingState];
        return YES;
    }
    if ([keyToken isEqualToString:@"D"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        (void)[self performPendingOperator:'d'
                               motionToken:@"$"
                                normalized:@"$"
                              motionCount:count
                                   adapter:adapter];
        [self recordLastChangeTokens:[self tokensByPrependingCount:count toTokens:@[@"D"]]];
        [self clearPendingState];
        return YES;
    }
    if ([normalized isEqualToString:@"p"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        BOOL explicitClipboard = _activeClipboardPut;
        BOOL handled = [self putFromRegisterAfterCursor:YES count:count adapter:adapter];
        NSMutableArray *tokens = [NSMutableArray array];
        if (explicitClipboard) {
            [tokens addObject:@"\""];
            [tokens addObject:@"+"];
        }
        [tokens addObjectsFromArray:[self tokensByPrependingCount:count toTokens:@[@"p"]]];
        [self recordLastChangeTokens:tokens];
        return handled;
    }
    if ([normalized isEqualToString:@"d"]) {
        _pendingOperator = 'd';
        _pendingOperatorCount = [self consumePendingCountWithDefault:1];
        return YES;
    }
    if ([normalized isEqualToString:@"y"]) {
        _pendingOperator = 'y';
        _pendingOperatorCount = [self consumePendingCountWithDefault:1];
        return YES;
    }
    if ([normalized isEqualToString:@"c"]) {
        _pendingOperator = 'c';
        _pendingOperatorCount = [self consumePendingCountWithDefault:1];
        return YES;
    }
    if ([keyToken isEqualToString:@"O"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        for (NSUInteger i = 0; i < count; i += 1) {
            [adapter openLineAbove];
        }
        self.mode = GSVVimModeInsert;
        return YES;
    }
    if ([keyToken isEqualToString:@"g"]) {
        _pendingGotoPrefix = YES;
        return YES;
    }
    NSUInteger motionCount = [self consumePendingCountWithDefault:1];
    if ([self executeMotionToken:keyToken normalized:normalized count:motionCount adapter:adapter]) {
        return YES;
    }
    if ([normalized isEqualToString:@"o"]) {
        NSUInteger count = motionCount;
        for (NSUInteger i = 0; i < count; i += 1) {
            [adapter openLineBelow];
        }
        self.mode = GSVVimModeInsert;
        return YES;
    }
    if ([normalized isEqualToString:@"i"]) {
        _pendingCount = 0;
        self.mode = GSVVimModeInsert;
        return YES;
    }
    if ([normalized isEqualToString:@"a"]) {
        _pendingCount = 0;
        [adapter moveCursorRight];
        self.mode = GSVVimModeInsert;
        return YES;
    }
    if ([normalized isEqualToString:@"x"]) {
        NSUInteger count = (motionCount > 0) ? motionCount : 1;
        for (NSUInteger i = 0; i < count; i += 1) {
            [adapter deleteForward];
        }
        [self recordLastChangeTokens:[self tokensByPrependingCount:count toTokens:@[@"x"]]];
        return YES;
    }

    _pendingCount = 0;
    // In Normal mode, typed characters are Vim commands. Unimplemented commands are consumed.
    return YES;
}

@end
