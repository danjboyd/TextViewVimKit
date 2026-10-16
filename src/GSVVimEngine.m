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

static BOOL GSVIsWhitespace(unichar ch)
{
    return (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r');
}

static BOOL GSVTokenIsDigit(NSString *token)
{
    if (token == nil || [token length] != 1) {
        return NO;
    }
    unichar ch = [token characterAtIndex:0];
    return (ch >= '0' && ch <= '9');
}

// The character a one-character token stands for, or 0 for a named key
// such as <Esc>.
static unichar GSVTokenCharacter(NSString *token)
{
    if (token == nil || [token length] != 1) {
        return 0;
    }
    return [token characterAtIndex:0];
}

static NSUInteger GSVCountByAppendingDigit(NSUInteger count, unichar digit)
{
    NSUInteger value = (NSUInteger)(digit - '0');
    if (count > ((NSUIntegerMax - value) / 10)) {
        return NSUIntegerMax;
    }
    return (count * 10) + value;
}

static NSRange GSVLineRangeAt(NSString *text, NSUInteger location)
{
    NSUInteger length = [text length];
    return [text lineRangeForRange:NSMakeRange(MIN(location, length), 0)];
}

// The end of a line's text, before its newline.
static NSUInteger GSVLineContentEnd(NSString *text, NSRange lineRange)
{
    NSUInteger lineEnd = NSMaxRange(lineRange);
    if (lineEnd > lineRange.location && [text characterAtIndex:(lineEnd - 1)] == '\n') {
        lineEnd -= 1;
    }
    return lineEnd;
}

static NSUInteger GSVFirstNonBlankInLine(NSString *text, NSRange lineRange)
{
    NSUInteger index = lineRange.location;
    NSUInteger contentEnd = GSVLineContentEnd(text, lineRange);
    while (index < contentEnd && GSVIsInlineWhitespace([text characterAtIndex:index])) {
        index += 1;
    }
    return index;
}

static BOOL GSVIsOpeningBracket(unichar ch)
{
    return (ch == '(' || ch == '[' || ch == '{' || ch == '<');
}

static unichar GSVMatchingBracket(unichar ch)
{
    switch (ch) {
    case '(': return ')';
    case ')': return '(';
    case '[': return ']';
    case ']': return '[';
    case '{': return '}';
    case '}': return '{';
    case '<': return '>';
    case '>': return '<';
    default: return 0;
    }
}

// The bracket pair a text object character names: b and B are ( and {.
static unichar GSVOpeningBracketForObject(unichar ch)
{
    switch (ch) {
    case '(': case ')': case 'b': return '(';
    case '[': case ']': return '[';
    case '{': case '}': case 'B': return '{';
    case '<': case '>': return '<';
    default: return 0;
    }
}

// The bracket matching the one at index, honouring nesting, or NSNotFound.
static NSUInteger GSVMatchingBracketIndex(NSString *text, NSUInteger index)
{
    NSUInteger length = [text length];
    if (index >= length) {
        return NSNotFound;
    }
    unichar ch = [text characterAtIndex:index];
    unichar match = GSVMatchingBracket(ch);
    if (match == 0) {
        return NSNotFound;
    }
    NSUInteger depth = 0;
    if (GSVIsOpeningBracket(ch)) {
        for (NSUInteger i = index + 1; i < length; i += 1) {
            unichar c = [text characterAtIndex:i];
            if (c == ch) {
                depth += 1;
            } else if (c == match) {
                if (depth == 0) {
                    return i;
                }
                depth -= 1;
            }
        }
        return NSNotFound;
    }
    NSUInteger i = index;
    while (i > 0) {
        i -= 1;
        unichar c = [text characterAtIndex:i];
        if (c == ch) {
            depth += 1;
        } else if (c == match) {
            if (depth == 0) {
                return i;
            }
            depth -= 1;
        }
    }
    return NSNotFound;
}

@interface GSVVimEngine ()
{
    BOOL _pendingGotoPrefix;
    unichar _pendingOperator;
    NSUInteger _pendingOperatorCount;
    unichar _pendingTextObjectType;
    NSUInteger _pendingCount;
    BOOL _pendingRegisterPrefix;
    unichar _activeRegister;
    unichar _pendingFindType;
    BOOL _pendingReplace;
    unichar _lastFindType;
    unichar _lastFindCharacter;
    NSUInteger _visualAnchor;
    NSUInteger _visualCursor;
    NSString *_unnamedRegister;
    BOOL _unnamedRegisterLinewise;
    NSMutableDictionary *_namedRegisters;
    NSMutableArray *_commandTokens;
    NSArray *_lastChangeTokens;
    BOOL _isReplayingLastChange;
    NSArray *_insertRepeatPrefix;
    NSUInteger _insertStartLocation;
    NSUInteger _insertRepeatCount;
}
@end

@implementation GSVVimEngine

- (instancetype)init
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _mode = GSVVimModeNormal;
    _visualAnchor = NSNotFound;
    _visualCursor = NSNotFound;
    _unnamedRegister = @"";
    _unnamedRegisterLinewise = NO;
    _unnamedRegisterUsesClipboard = NO;
    _namedRegisters = [NSMutableDictionary dictionary];
    _commandTokens = [NSMutableArray array];
    _lastChangeTokens = nil;
    _isReplayingLastChange = NO;
    _insertStartLocation = NSNotFound;
    _insertRepeatCount = 1;
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
    _insertRepeatPrefix = nil;
    self.mode = GSVVimModeNormal;
}

#pragma mark - Pending state

- (BOOL)hasPendingState
{
    return (_pendingGotoPrefix || _pendingOperator != 0 || _pendingTextObjectType != 0 ||
            _pendingCount != 0 || _pendingRegisterPrefix || _activeRegister != 0 ||
            _pendingFindType != 0 || _pendingReplace);
}

- (void)clearPendingState
{
    _pendingGotoPrefix = NO;
    _pendingOperator = 0;
    _pendingOperatorCount = 0;
    _pendingTextObjectType = 0;
    _pendingCount = 0;
    _pendingRegisterPrefix = NO;
    _activeRegister = 0;
    _pendingFindType = 0;
    _pendingReplace = NO;
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

#pragma mark - Repeat (.)

// The keys of the command just completed become what . repeats.
- (void)recordCommandAsLastChange
{
    if (_isReplayingLastChange || [_commandTokens count] == 0) {
        return;
    }
    _lastChangeTokens = [_commandTokens copy];
}

- (BOOL)replayLastChangeWithCount:(NSUInteger)count adapter:(id<GSVTextEditing>)adapter
{
    if (_lastChangeTokens == nil || [_lastChangeTokens count] == 0 || count == 0) {
        return YES;
    }

    NSArray *tokens = _lastChangeTokens;
    BOOL previousReplayState = _isReplayingLastChange;
    _isReplayingLastChange = YES;
    for (NSUInteger repeatIndex = 0; repeatIndex < count; repeatIndex += 1) {
        [self clearPendingState];
        for (NSString *token in tokens) {
            (void)[self handleKeyToken:token adapter:adapter];
        }
        if (self.mode == GSVVimModeInsert) {
            (void)[self handleKeyToken:@"<Esc>" adapter:adapter];
        }
    }
    [self clearPendingState];
    [_commandTokens removeAllObjects];
    _isReplayingLastChange = previousReplayState;
    return YES;
}

#pragma mark - Insert sessions

// Enters Insert mode for a command; what is typed before <Esc> joins the
// command's keys for . (and is inserted count times, as 3ihi<Esc> does).
- (void)beginInsertWithRepeatCount:(NSUInteger)count adapter:(id<GSVTextEditing>)adapter
{
    _insertRepeatPrefix = [_commandTokens copy];
    _insertStartLocation = [adapter selectedRange].location;
    _insertRepeatCount = (count > 0) ? count : 1;
    [self clearPendingState];
    self.mode = GSVVimModeInsert;
}

- (void)finishInsertWithAdapter:(id<GSVTextEditing>)adapter
{
    NSString *text = [adapter textString];
    NSUInteger cursor = [adapter selectedRange].location;
    NSString *inserted = @"";
    if (_insertStartLocation != NSNotFound && cursor >= _insertStartLocation && cursor <= [text length]) {
        inserted = [text substringWithRange:NSMakeRange(_insertStartLocation, cursor - _insertStartLocation)];
    }

    if (_insertRepeatCount > 1 && [inserted length] > 0) {
        NSMutableString *more = [NSMutableString string];
        for (NSUInteger i = 1; i < _insertRepeatCount; i += 1) {
            [more appendString:inserted];
        }
        [adapter replaceCharactersInRange:NSMakeRange(cursor, 0) withString:more];
    }

    if (!_isReplayingLastChange && _insertRepeatPrefix != nil) {
        NSMutableArray *tokens = [NSMutableArray arrayWithArray:_insertRepeatPrefix];
        for (NSUInteger i = 0; i < [inserted length]; i += 1) {
            [tokens addObject:[inserted substringWithRange:NSMakeRange(i, 1)]];
        }
        [tokens addObject:@"<Esc>"];
        _lastChangeTokens = [tokens copy];
    }
    _insertRepeatPrefix = nil;
    _insertStartLocation = NSNotFound;
    _insertRepeatCount = 1;

    // Leaving Insert mode steps back onto the last character typed, but not
    // past the start of the line.
    text = [adapter textString];
    NSRange selected = [adapter selectedRange];
    if (selected.length == 0 && selected.location > 0 &&
        [text characterAtIndex:(selected.location - 1)] != '\n') {
        [adapter setSelectedRange:NSMakeRange(selected.location - 1, 0)];
    }
}

#pragma mark - Geometry helpers

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

- (NSUInteger)cursorForAdapter:(id<GSVTextEditing>)adapter
{
    return [self clampedCursorForAdapter:adapter location:[adapter selectedRange].location];
}

// The first non-blank of line number (1-based), clamped to the last line.
- (NSUInteger)locationOfLineNumber:(NSUInteger)lineNumber inText:(NSString *)text
{
    NSUInteger length = [text length];
    NSUInteger location = 0;
    for (NSUInteger line = 1; line < lineNumber; line += 1) {
        NSRange lineRange = GSVLineRangeAt(text, location);
        if (NSMaxRange(lineRange) >= length) {
            break;
        }
        location = NSMaxRange(lineRange);
    }
    return GSVFirstNonBlankInLine(text, GSVLineRangeAt(text, location));
}

// The start of the line count lines below (or above) the one at location.
- (NSUInteger)lineStartFrom:(NSUInteger)location offset:(NSInteger)offset inText:(NSString *)text
{
    NSUInteger length = [text length];
    NSRange lineRange = GSVLineRangeAt(text, location);
    NSUInteger lineStart = lineRange.location;
    if (offset > 0) {
        for (NSInteger i = 0; i < offset; i += 1) {
            NSUInteger next = NSMaxRange(GSVLineRangeAt(text, lineStart));
            if (next >= length || next == lineStart) {
                break;
            }
            lineStart = next;
        }
    } else {
        for (NSInteger i = 0; i > offset; i -= 1) {
            if (lineStart == 0) {
                break;
            }
            lineStart = GSVLineRangeAt(text, lineStart - 1).location;
        }
    }
    return lineStart;
}

#pragma mark - Visual selection

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

    _visualAnchor = [self cursorForAdapter:adapter];
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

- (void)finishVisualOperationToNormalMode
{
    [self clearPendingState];
    [self resetVisualState];
    self.mode = GSVVimModeNormal;
}

#pragma mark - Text objects

- (NSRange)wordTextObjectRangeForAdapter:(id<GSVTextEditing>)adapter
                                  around:(BOOL)around
                                 bigWord:(BOOL)bigWord
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
    NSUInteger cursor = [self cursorForAdapter:adapter];
    BOOL (^isWord)(unichar) = ^BOOL(unichar ch) {
        return bigWord ? !GSVIsWhitespace(ch) : GSVIsWordCharacter(ch);
    };

    NSUInteger index = cursor;
    if (!isWord([text characterAtIndex:index])) {
        NSUInteger search = index;
        while (search < length && !isWord([text characterAtIndex:search])) {
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
                if (isWord([text characterAtIndex:search])) {
                    index = search;
                    break;
                }
            }
            if (!isWord([text characterAtIndex:index])) {
                return NSMakeRange(0, 0);
            }
        }
    }

    NSUInteger start = index;
    while (start > 0 && isWord([text characterAtIndex:(start - 1)])) {
        start -= 1;
    }

    NSUInteger end = index + 1;
    while (end < length && isWord([text characterAtIndex:end])) {
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

// i" a" and the like, within the cursor's line: the quoted string around
// the cursor, or the first one after it.
- (NSRange)quoteTextObjectRangeForAdapter:(id<GSVTextEditing>)adapter
                                    quote:(unichar)quote
                                   around:(BOOL)around
                                    found:(BOOL *)found
{
    *found = NO;
    NSString *text = [adapter textString];
    if ([text length] == 0) {
        return NSMakeRange(0, 0);
    }
    NSUInteger cursor = [self cursorForAdapter:adapter];
    NSRange lineRange = GSVLineRangeAt(text, cursor);
    NSUInteger contentEnd = GSVLineContentEnd(text, lineRange);

    NSMutableArray *quotes = [NSMutableArray array];
    for (NSUInteger i = lineRange.location; i < contentEnd; i += 1) {
        if ([text characterAtIndex:i] == quote &&
            (i == lineRange.location || [text characterAtIndex:(i - 1)] != '\\')) {
            [quotes addObject:@(i)];
        }
    }

    NSUInteger open = NSNotFound;
    NSUInteger close = NSNotFound;
    for (NSUInteger p = 0; p + 1 < [quotes count]; p += 2) {
        NSUInteger o = [quotes[p] unsignedIntegerValue];
        NSUInteger c = [quotes[p + 1] unsignedIntegerValue];
        if ((o <= cursor && cursor <= c) || o > cursor) {
            open = o;
            close = c;
            break;
        }
    }
    if (open == NSNotFound) {
        return NSMakeRange(0, 0);
    }

    *found = YES;
    if (!around) {
        return NSMakeRange(open + 1, close - open - 1);
    }
    NSUInteger start = open;
    NSUInteger end = close + 1;
    NSUInteger whitespaceEnd = end;
    while (whitespaceEnd < contentEnd && GSVIsInlineWhitespace([text characterAtIndex:whitespaceEnd])) {
        whitespaceEnd += 1;
    }
    if (whitespaceEnd > end) {
        end = whitespaceEnd;
    } else {
        while (start > lineRange.location && GSVIsInlineWhitespace([text characterAtIndex:(start - 1)])) {
            start -= 1;
        }
    }
    return NSMakeRange(start, end - start);
}

// i( a{ ib and the like: the innermost pair around the cursor, across lines.
- (NSRange)bracketTextObjectRangeForAdapter:(id<GSVTextEditing>)adapter
                                    opening:(unichar)opening
                                     around:(BOOL)around
                                      found:(BOOL *)found
{
    *found = NO;
    NSString *text = [adapter textString];
    NSUInteger length = [text length];
    if (length == 0) {
        return NSMakeRange(0, 0);
    }
    unichar closing = GSVMatchingBracket(opening);
    NSUInteger cursor = [self cursorForAdapter:adapter];

    NSUInteger open = NSNotFound;
    unichar atCursor = [text characterAtIndex:cursor];
    if (atCursor == opening) {
        open = cursor;
    } else if (atCursor == closing) {
        open = GSVMatchingBracketIndex(text, cursor);
    } else {
        NSUInteger depth = 0;
        NSUInteger i = cursor;
        while (i > 0) {
            i -= 1;
            unichar c = [text characterAtIndex:i];
            if (c == closing) {
                depth += 1;
            } else if (c == opening) {
                if (depth == 0) {
                    open = i;
                    break;
                }
                depth -= 1;
            }
        }
    }
    if (open == NSNotFound) {
        return NSMakeRange(0, 0);
    }
    NSUInteger close = GSVMatchingBracketIndex(text, open);
    if (close == NSNotFound) {
        return NSMakeRange(0, 0);
    }

    *found = YES;
    if (around) {
        return NSMakeRange(open, close - open + 1);
    }
    NSUInteger start = open + 1;
    NSUInteger end = close;
    // A block's inner lines, as in i{ around an indented body: not the line
    // break after the opening bracket or the indent before the closing one.
    if (start < end && [text characterAtIndex:start] == '\n') {
        NSRange closeLine = GSVLineRangeAt(text, close);
        BOOL onlyIndentBeforeClose = YES;
        for (NSUInteger i = closeLine.location; i < close; i += 1) {
            if (!GSVIsInlineWhitespace([text characterAtIndex:i])) {
                onlyIndentBeforeClose = NO;
                break;
            }
        }
        start += 1;
        if (onlyIndentBeforeClose && closeLine.location > start) {
            end = closeLine.location;
        }
    }
    return NSMakeRange(start, (end > start) ? (end - start) : 0);
}

- (NSRange)textObjectRangeForAdapter:(id<GSVTextEditing>)adapter
                          objectType:(unichar)objectType
                              around:(BOOL)around
                               found:(BOOL *)found
{
    *found = NO;
    if (objectType == 'w' || objectType == 'W') {
        return [self wordTextObjectRangeForAdapter:adapter around:around bigWord:(objectType == 'W') found:found];
    }
    if (objectType == '"' || objectType == '\'' || objectType == '`') {
        return [self quoteTextObjectRangeForAdapter:adapter quote:objectType around:around found:found];
    }
    unichar opening = GSVOpeningBracketForObject(objectType);
    if (opening != 0) {
        return [self bracketTextObjectRangeForAdapter:adapter opening:opening around:around found:found];
    }
    return NSMakeRange(0, 0);
}

#pragma mark - Registers

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

// Stores yanked or deleted text: in the register the command named ("a,
// "A appends, "+ and "* the clipboard, "_ nowhere) and in the unnamed one.
- (void)storeRegisterString:(NSString *)string linewise:(BOOL)linewise
{
    NSString *value = linewise ? [self normalizedLinewiseRegisterString:string] : (string ?: @"");
    unichar name = _activeRegister;
    if (name == '_') {
        return;
    }
    if (name == '+' || name == '*') {
        if (self.clipboard != nil) {
            [self.clipboard writeClipboardString:value];
        }
    } else if (name >= 'a' && name <= 'z') {
        _namedRegisters[[NSString stringWithFormat:@"%C", name]] = @[value, @(linewise)];
    } else if (name >= 'A' && name <= 'Z') {
        NSString *key = [NSString stringWithFormat:@"%C", (unichar)(name - 'A' + 'a')];
        NSArray *existing = _namedRegisters[key];
        NSString *old = existing ? existing[0] : @"";
        BOOL oldLinewise = existing ? [existing[1] boolValue] : NO;
        BOOL newLinewise = linewise || oldLinewise;
        NSString *joined = (newLinewise && [old length] > 0)
            ? [[self normalizedLinewiseRegisterString:old] stringByAppendingString:value]
            : [old stringByAppendingString:value];
        _namedRegisters[key] = @[joined, @(newLinewise)];
        value = joined;
        linewise = newLinewise;
    }
    [self setUnnamedRegisterString:value linewise:linewise];
}

- (NSString *)captureRegisterFromRange:(NSRange)range
                               adapter:(id<GSVTextEditing>)adapter
                              linewise:(BOOL)linewise
{
    NSString *text = [adapter textString];
    NSUInteger length = [text length];
    if (length == 0 || range.length == 0 || range.location >= length) {
        [self storeRegisterString:@"" linewise:linewise];
        return @"";
    }
    if (NSMaxRange(range) > length) {
        range.length = length - range.location;
    }
    NSString *captured = [text substringWithRange:range];
    [self storeRegisterString:captured linewise:linewise];
    return captured;
}

// The text a put uses, from the register the command named.
- (NSString *)registerStringForPut:(BOOL *)linewise
{
    unichar name = _activeRegister;
    if (name == '+' || name == '*') {
        NSString *value = (self.clipboard != nil) ? [self.clipboard readClipboardString] : nil;
        *linewise = [value hasSuffix:@"\n"];
        return value ?: @"";
    }
    if ((name >= 'a' && name <= 'z') || (name >= 'A' && name <= 'Z')) {
        unichar lower = (name >= 'A' && name <= 'Z') ? (unichar)(name - 'A' + 'a') : name;
        NSArray *entry = _namedRegisters[[NSString stringWithFormat:@"%C", lower]];
        *linewise = entry ? [entry[1] boolValue] : NO;
        return entry ? entry[0] : @"";
    }
    if (name == '_') {
        *linewise = NO;
        return @"";
    }
    NSString *value = [self currentUnnamedRegisterString];
    *linewise = _unnamedRegisterLinewise;
    return value;
}

#pragma mark - Motions

// The target of f F t T for count occurrences of ch on the cursor's line,
// or NSNotFound. A repeat (; ,) of t and T skips an adjacent match.
- (NSUInteger)findTargetForType:(unichar)type
                      character:(unichar)ch
                          count:(NSUInteger)count
                         repeat:(BOOL)repeat
                        adapter:(id<GSVTextEditing>)adapter
{
    NSString *text = [adapter textString];
    if ([text length] == 0) {
        return NSNotFound;
    }
    NSUInteger cursor = [self cursorForAdapter:adapter];
    NSRange lineRange = GSVLineRangeAt(text, cursor);
    NSUInteger contentEnd = GSVLineContentEnd(text, lineRange);
    NSUInteger repeats = MAX(count, (NSUInteger)1);

    if (type == 'f' || type == 't') {
        NSUInteger index = cursor + ((repeat && type == 't') ? 2 : 1);
        NSUInteger found = NSNotFound;
        for (NSUInteger n = 0; n < repeats; n += 1) {
            found = NSNotFound;
            for (; index < contentEnd; index += 1) {
                if ([text characterAtIndex:index] == ch) {
                    found = index;
                    index += 1;
                    break;
                }
            }
            if (found == NSNotFound) {
                return NSNotFound;
            }
        }
        return (type == 't') ? found - 1 : found;
    }

    NSUInteger skip = (repeat && type == 'T') ? 2 : 1;
    if (cursor < lineRange.location + skip) {
        return NSNotFound;
    }
    NSInteger index = (NSInteger)cursor - (NSInteger)skip;
    NSUInteger found = NSNotFound;
    for (NSUInteger n = 0; n < repeats; n += 1) {
        found = NSNotFound;
        for (; index >= (NSInteger)lineRange.location; index -= 1) {
            if ([text characterAtIndex:(NSUInteger)index] == ch) {
                found = (NSUInteger)index;
                index -= 1;
                break;
            }
        }
        if (found == NSNotFound) {
            return NSNotFound;
        }
    }
    return (type == 'T') ? found + 1 : found;
}

- (NSUInteger)bigWordForwardFrom:(NSUInteger)cursor inText:(NSString *)text
{
    NSUInteger length = [text length];
    NSUInteger index = cursor;
    while (index < length && !GSVIsWhitespace([text characterAtIndex:index])) {
        index += 1;
    }
    while (index < length && GSVIsWhitespace([text characterAtIndex:index])) {
        // An empty line counts as a WORD.
        if ([text characterAtIndex:index] == '\n' && index + 1 < length &&
            [text characterAtIndex:(index + 1)] == '\n' && index + 1 > cursor) {
            return index + 1;
        }
        index += 1;
    }
    return MIN(index, length - 1);
}

- (NSUInteger)bigWordBackwardFrom:(NSUInteger)cursor inText:(NSString *)text
{
    if (cursor == 0) {
        return 0;
    }
    NSUInteger index = cursor - 1;
    while (index > 0 && GSVIsWhitespace([text characterAtIndex:index])) {
        index -= 1;
    }
    while (index > 0 && !GSVIsWhitespace([text characterAtIndex:(index - 1)])) {
        index -= 1;
    }
    return index;
}

- (NSUInteger)bigWordEndFrom:(NSUInteger)cursor inText:(NSString *)text
{
    NSUInteger length = [text length];
    NSUInteger index = cursor + 1;
    while (index < length && GSVIsWhitespace([text characterAtIndex:index])) {
        index += 1;
    }
    while (index + 1 < length && !GSVIsWhitespace([text characterAtIndex:(index + 1)])) {
        index += 1;
    }
    return MIN(index, length - 1);
}

// { and }: the previous or next empty line, or the start or end of the text.
- (NSUInteger)paragraphFrom:(NSUInteger)cursor forward:(BOOL)forward inText:(NSString *)text
{
    NSUInteger length = [text length];
    NSRange lineRange = GSVLineRangeAt(text, cursor);
    BOOL (^isEmpty)(NSRange) = ^BOOL(NSRange range) {
        return GSVLineContentEnd(text, range) == range.location;
    };
    if (forward) {
        NSUInteger start = NSMaxRange(lineRange);
        while (start < length && isEmpty(GSVLineRangeAt(text, start))) {
            start = NSMaxRange(GSVLineRangeAt(text, start));
        }
        while (start < length) {
            NSRange r = GSVLineRangeAt(text, start);
            if (isEmpty(r)) {
                return r.location;
            }
            start = NSMaxRange(r);
        }
        return (length > 0) ? length - 1 : 0;
    }
    if (lineRange.location == 0) {
        return 0;
    }
    NSUInteger start = GSVLineRangeAt(text, lineRange.location - 1).location;
    while (start > 0 && isEmpty(GSVLineRangeAt(text, start))) {
        start = GSVLineRangeAt(text, start - 1).location;
    }
    while (YES) {
        NSRange r = GSVLineRangeAt(text, start);
        if (isEmpty(r)) {
            return r.location;
        }
        if (start == 0) {
            return 0;
        }
        start = GSVLineRangeAt(text, start - 1).location;
    }
}

// % : from the first bracket at or after the cursor on its line to its match.
- (NSUInteger)matchingBracketTargetForAdapter:(id<GSVTextEditing>)adapter
{
    NSString *text = [adapter textString];
    if ([text length] == 0) {
        return NSNotFound;
    }
    NSUInteger cursor = [self cursorForAdapter:adapter];
    NSUInteger contentEnd = GSVLineContentEnd(text, GSVLineRangeAt(text, cursor));
    for (NSUInteger i = cursor; i < contentEnd; i += 1) {
        unichar ch = [text characterAtIndex:i];
        if (ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}') {
            return GSVMatchingBracketIndex(text, i);
        }
    }
    return NSNotFound;
}

- (BOOL)executeSingleMotionToken:(NSString *)keyToken adapter:(id<GSVTextEditing>)adapter
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
    if ([keyToken isEqualToString:@"h"]) {
        [adapter moveCursorLeft];
        return YES;
    }
    if ([keyToken isEqualToString:@"j"]) {
        [adapter moveCursorDown];
        return YES;
    }
    if ([keyToken isEqualToString:@"k"]) {
        [adapter moveCursorUp];
        return YES;
    }
    if ([keyToken isEqualToString:@"l"] || [keyToken isEqualToString:@" "]) {
        [adapter moveCursorRight];
        return YES;
    }
    if ([keyToken isEqualToString:@"w"]) {
        [adapter moveWordForward];
        return YES;
    }
    if ([keyToken isEqualToString:@"b"]) {
        [adapter moveWordBackward];
        return YES;
    }
    if ([keyToken isEqualToString:@"e"]) {
        [adapter moveToWordEndForward];
        return YES;
    }

    NSString *text = [adapter textString];
    NSUInteger length = [text length];
    if (length == 0) {
        return NO;
    }
    NSUInteger cursor = [self cursorForAdapter:adapter];
    NSUInteger target = NSNotFound;
    if ([keyToken isEqualToString:@"W"]) {
        target = [self bigWordForwardFrom:cursor inText:text];
    } else if ([keyToken isEqualToString:@"B"]) {
        target = [self bigWordBackwardFrom:cursor inText:text];
    } else if ([keyToken isEqualToString:@"E"]) {
        target = [self bigWordEndFrom:cursor inText:text];
    } else if ([keyToken isEqualToString:@"}"]) {
        target = [self paragraphFrom:cursor forward:YES inText:text];
    } else if ([keyToken isEqualToString:@"{"]) {
        target = [self paragraphFrom:cursor forward:NO inText:text];
    } else if ([keyToken isEqualToString:@"%"]) {
        target = [self matchingBracketTargetForAdapter:adapter];
    } else if ([keyToken isEqualToString:@"+"] || [keyToken isEqualToString:@"-"]) {
        NSInteger offset = [keyToken isEqualToString:@"+"] ? 1 : -1;
        NSUInteger lineStart = [self lineStartFrom:cursor offset:offset inText:text];
        target = GSVFirstNonBlankInLine(text, GSVLineRangeAt(text, lineStart));
    } else if ([keyToken isEqualToString:@";"] || [keyToken isEqualToString:@","]) {
        if (_lastFindType == 0) {
            return NO;
        }
        unichar type = _lastFindType;
        if ([keyToken isEqualToString:@","]) {
            type = (type == 'f') ? 'F' : (type == 'F') ? 'f' : (type == 't') ? 'T' : 't';
        }
        target = [self findTargetForType:type character:_lastFindCharacter count:1 repeat:YES adapter:adapter];
    } else {
        return NO;
    }
    if (target == NSNotFound) {
        return NO;
    }
    [adapter setSelectedRange:NSMakeRange(target, 0)];
    return YES;
}

- (BOOL)executeMotionToken:(NSString *)keyToken
                     count:(NSUInteger)count
                   adapter:(id<GSVTextEditing>)adapter
{
    NSUInteger repeats = (count > 0) ? count : 1;
    for (NSUInteger i = 0; i < repeats; i += 1) {
        BOOL moved = [self executeSingleMotionToken:keyToken adapter:adapter];
        if (!moved) {
            return (i > 0);
        }
    }
    return YES;
}

+ (BOOL)motionIsInclusive:(NSString *)keyToken lastFindType:(unichar)lastFindType
{
    if ([keyToken isEqualToString:@"$"] || [keyToken isEqualToString:@"e"] ||
        [keyToken isEqualToString:@"E"] || [keyToken isEqualToString:@"%"]) {
        return YES;
    }
    if ([keyToken isEqualToString:@";"]) {
        return (lastFindType == 'f' || lastFindType == 't');
    }
    if ([keyToken isEqualToString:@","]) {
        return (lastFindType == 'F' || lastFindType == 'T');
    }
    return NO;
}

+ (BOOL)motionIsLinewise:(NSString *)keyToken
{
    return ([keyToken isEqualToString:@"j"] || [keyToken isEqualToString:@"k"] ||
            [keyToken isEqualToString:@"G"] || [keyToken isEqualToString:@"+"] ||
            [keyToken isEqualToString:@"-"]);
}

#pragma mark - Operators

- (void)performOperator:(unichar)op
                onRange:(NSRange)range
               linewise:(BOOL)linewise
                adapter:(id<GSVTextEditing>)adapter
{
    NSUInteger length = [adapter textLength];
    if (length == 0 || range.length == 0 || range.location >= length) {
        if (op == 'c') {
            [adapter setSelectedRange:NSMakeRange(MIN(range.location, length), 0)];
            [self beginInsertWithRepeatCount:1 adapter:adapter];
        }
        return;
    }
    if (NSMaxRange(range) > length) {
        range.length = length - range.location;
    }

    if (op == 'y') {
        (void)[self captureRegisterFromRange:range adapter:adapter linewise:linewise];
        return;
    }

    if (op == 'd' || op == 'c') {
        (void)[self captureRegisterFromRange:range adapter:adapter linewise:linewise];
        [adapter replaceCharactersInRange:range withString:@""];
        NSUInteger newLength = [adapter textLength];
        NSUInteger location = MIN(range.location, newLength);
        [adapter setSelectedRange:NSMakeRange(location, 0)];
        if (op == 'c') {
            [self beginInsertWithRepeatCount:1 adapter:adapter];
        } else {
            [adapter setSelectedRange:NSMakeRange([self cursorForAdapter:adapter], 0)];
        }
    }
}

// d y c over whole lines, from the line at one location to the line at the
// other. c keeps one line, with its indent, to type into.
- (void)performLinewiseOperator:(unichar)op
                   fromLocation:(NSUInteger)from
                     toLocation:(NSUInteger)to
                        adapter:(id<GSVTextEditing>)adapter
{
    NSString *text = [adapter textString];
    NSUInteger length = [text length];
    if (length == 0) {
        if (op == 'c') {
            [self beginInsertWithRepeatCount:1 adapter:adapter];
        }
        return;
    }
    NSUInteger first = MIN(from, to);
    NSUInteger last = MAX(from, to);
    NSRange firstLine = GSVLineRangeAt(text, first);
    NSRange lastLine = GSVLineRangeAt(text, last);
    NSRange range = NSMakeRange(firstLine.location, NSMaxRange(lastLine) - firstLine.location);
    (void)[self captureRegisterFromRange:range adapter:adapter linewise:YES];

    if (op == 'y') {
        [adapter setSelectedRange:NSMakeRange(MIN(first, [self cursorForAdapter:adapter]), 0)];
        return;
    }

    if (op == 'c') {
        NSUInteger indentEnd = GSVFirstNonBlankInLine(text, firstLine);
        NSString *indent = [text substringWithRange:NSMakeRange(firstLine.location, indentEnd - firstLine.location)];
        BOOL endsWithNewline = (NSMaxRange(range) > 0 && [text characterAtIndex:(NSMaxRange(range) - 1)] == '\n');
        NSString *replacement = endsWithNewline ? [indent stringByAppendingString:@"\n"] : indent;
        [adapter replaceCharactersInRange:range withString:replacement];
        [adapter setSelectedRange:NSMakeRange(firstLine.location + [indent length], 0)];
        [self beginInsertWithRepeatCount:1 adapter:adapter];
        return;
    }

    // The last line has no newline of its own: take the one before it.
    BOOL endsWithNewline = ([text characterAtIndex:(NSMaxRange(range) - 1)] == '\n');
    if (!endsWithNewline && range.location > 0) {
        range.location -= 1;
        range.length += 1;
    }
    [adapter replaceCharactersInRange:range withString:@""];
    NSString *after = [adapter textString];
    if ([after length] == 0) {
        [adapter setSelectedRange:NSMakeRange(0, 0)];
        return;
    }
    NSUInteger lineLocation = MIN(firstLine.location, [after length] - 1);
    if (!endsWithNewline && range.location < firstLine.location) {
        lineLocation = MIN(range.location, [after length] - 1);
    }
    NSUInteger target = GSVFirstNonBlankInLine(after, GSVLineRangeAt(after, lineLocation));
    [adapter setSelectedRange:NSMakeRange(MIN(target, [after length] - 1), 0)];
}

- (void)handleDoubleOperatorCommand:(unichar)op
                              count:(NSUInteger)count
                            adapter:(id<GSVTextEditing>)adapter
{
    NSString *text = [adapter textString];
    NSUInteger cursor = [self cursorForAdapter:adapter];
    NSUInteger repeats = (count > 0) ? count : 1;
    NSUInteger lastLineStart = [self lineStartFrom:cursor offset:(NSInteger)(repeats - 1) inText:text];
    [self performLinewiseOperator:op fromLocation:cursor toLocation:lastLineStart adapter:adapter];
    if (op == 'y') {
        [adapter setSelectedRange:NSMakeRange(cursor, 0)];
    }
}

// Applies an operator from the cursor to a motion's target.
- (BOOL)performOperator:(unichar)op
            toTarget:(NSUInteger)target
               start:(NSUInteger)start
           inclusive:(BOOL)inclusive
            linewise:(BOOL)linewise
         wordMotion:(BOOL)wordMotion
             adapter:(id<GSVTextEditing>)adapter
{
    if (linewise) {
        [self performLinewiseOperator:op fromLocation:start toLocation:target adapter:adapter];
        return YES;
    }

    NSString *text = [adapter textString];
    NSRange range;
    if (start <= target) {
        range = NSMakeRange(start, (target - start) + (inclusive ? 1 : 0));
        // dw on a line's last word stops at the line's end rather than
        // taking the line break and the next line's indent.
        if (wordMotion && !inclusive && target > start && [text characterAtIndex:start] != '\n') {
            NSRange crossed = [text rangeOfString:@"\n"
                                          options:NSBackwardsSearch
                                            range:NSMakeRange(start, target - start)];
            if (crossed.location != NSNotFound) {
                BOOL onlyBlankAfter = YES;
                for (NSUInteger i = crossed.location + 1; i < target; i += 1) {
                    if (!GSVIsInlineWhitespace([text characterAtIndex:i])) {
                        onlyBlankAfter = NO;
                        break;
                    }
                }
                if (onlyBlankAfter) {
                    range = NSMakeRange(start, crossed.location - start);
                }
            }
        }
    } else {
        range = NSMakeRange(target, (start - target) + (inclusive ? 1 : 0));
    }

    [adapter setSelectedRange:NSMakeRange(start, 0)];
    [self performOperator:op onRange:range linewise:NO adapter:adapter];
    if (op == 'y') {
        [adapter setSelectedRange:NSMakeRange(MIN(start, target), 0)];
    }
    return YES;
}

- (BOOL)performPendingOperator:(unichar)op
                   motionToken:(NSString *)keyToken
                   motionCount:(NSUInteger)motionCount
                      hadCount:(BOOL)hadCount
                       adapter:(id<GSVTextEditing>)adapter
{
    NSUInteger length = [adapter textLength];
    if (length == 0) {
        [adapter setSelectedRange:NSMakeRange(0, 0)];
        if (op == 'c') {
            [self beginInsertWithRepeatCount:1 adapter:adapter];
        }
        return YES;
    }

    NSUInteger repeats = (motionCount > 0) ? motionCount : 1;
    NSUInteger start = [self cursorForAdapter:adapter];
    NSString *text = [adapter textString];

    // cw on a word changes to the word's end, like ce.
    if (op == 'c' && ([keyToken isEqualToString:@"w"] || [keyToken isEqualToString:@"W"]) &&
        !GSVIsWhitespace([text characterAtIndex:start])) {
        BOOL bigWord = [keyToken isEqualToString:@"W"];
        BOOL wordClass = GSVIsWordCharacter([text characterAtIndex:start]);
        NSUInteger target = start;
        while (target + 1 < length) {
            unichar next = [text characterAtIndex:(target + 1)];
            BOOL sameWord = bigWord ? !GSVIsWhitespace(next)
                                    : (!GSVIsWhitespace(next) && GSVIsWordCharacter(next) == wordClass);
            if (!sameWord) {
                break;
            }
            target += 1;
        }
        if (repeats > 1) {
            [adapter setSelectedRange:NSMakeRange(target, 0)];
            (void)[self executeMotionToken:(bigWord ? @"E" : @"e") count:(repeats - 1) adapter:adapter];
            target = [self cursorForAdapter:adapter];
        }
        return [self performOperator:op toTarget:target start:start inclusive:YES linewise:NO wordMotion:NO adapter:adapter];
    }

    if ([keyToken isEqualToString:@"G"]) {
        NSUInteger target = hadCount ? [self locationOfLineNumber:repeats inText:text] : length - 1;
        return [self performOperator:op toTarget:target start:start inclusive:NO linewise:YES wordMotion:NO adapter:adapter];
    }

    [adapter setSelectedRange:NSMakeRange(start, 0)];
    BOOL moved = [self executeMotionToken:keyToken count:repeats adapter:adapter];
    if (!moved) {
        [adapter setSelectedRange:NSMakeRange(start, 0)];
        return NO;
    }
    NSUInteger target = [adapter selectedRange].location;
    if (target >= length) {
        target = length - 1;
    }
    BOOL inclusive = [[self class] motionIsInclusive:keyToken lastFindType:_lastFindType];
    BOOL linewise = [[self class] motionIsLinewise:keyToken];
    BOOL wordMotion = ([keyToken isEqualToString:@"w"] || [keyToken isEqualToString:@"W"]);
    // w to the very end of the text takes the last character too.
    if (wordMotion && target == length - 1 && target > start &&
        !GSVIsWhitespace([text characterAtIndex:target])) {
        BOOL movedToNextWord = NO;
        for (NSUInteger i = start; i < target; i += 1) {
            if (GSVIsWhitespace([text characterAtIndex:i])) {
                movedToNextWord = YES;
                break;
            }
        }
        if (!movedToNextWord) {
            inclusive = YES;
        }
    }
    return [self performOperator:op toTarget:target start:start inclusive:inclusive linewise:linewise wordMotion:wordMotion adapter:adapter];
}

#pragma mark - Simple edits

- (BOOL)putFromRegisterAfterCursor:(BOOL)after
                             count:(NSUInteger)count
                           adapter:(id<GSVTextEditing>)adapter
{
    BOOL registerLinewise = NO;
    NSString *registerString = [self registerStringForPut:&registerLinewise];
    if (registerString == nil || [registerString length] == 0 || count == 0) {
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
                insertion = [@"\n" stringByAppendingString:[linewiseString substringToIndex:([linewiseString length] - 1)]];
                cursorLocation = insertLocation + 1;
            } else {
                cursorLocation = insertLocation;
            }
            [adapter replaceCharactersInRange:NSMakeRange(insertLocation, 0) withString:insertion];
            NSString *text = [adapter textString];
            NSUInteger target = GSVFirstNonBlankInLine(text, GSVLineRangeAt(text, cursorLocation));
            [adapter setSelectedRange:NSMakeRange(target, 0)];
            continue;
        }

        NSUInteger insertLocation = 0;
        if (textLength > 0) {
            NSUInteger clampedCursor = [self clampedCursorForAdapter:adapter location:cursor];
            NSString *text = [adapter textString];
            BOOL onLineEnd = ([text characterAtIndex:clampedCursor] == '\n');
            insertLocation = (after && !onLineEnd) ? (clampedCursor + 1) : clampedCursor;
        }
        [adapter replaceCharactersInRange:NSMakeRange(insertLocation, 0) withString:registerString];
        NSUInteger newCursor = insertLocation + [registerString length] - 1;
        [adapter setSelectedRange:NSMakeRange(newCursor, 0)];
    }
    return YES;
}

// x and X: count characters after (or before) the cursor, within the line.
- (void)deleteCharactersForward:(BOOL)forward count:(NSUInteger)count adapter:(id<GSVTextEditing>)adapter
{
    NSString *text = [adapter textString];
    if ([text length] == 0) {
        return;
    }
    NSUInteger cursor = [self cursorForAdapter:adapter];
    NSRange lineRange = GSVLineRangeAt(text, cursor);
    NSRange range;
    if (forward) {
        NSUInteger contentEnd = GSVLineContentEnd(text, lineRange);
        if (cursor >= contentEnd) {
            return;
        }
        range = NSMakeRange(cursor, MIN(count, contentEnd - cursor));
    } else {
        NSUInteger available = cursor - lineRange.location;
        if (available == 0) {
            return;
        }
        NSUInteger n = MIN(count, available);
        range = NSMakeRange(cursor - n, n);
    }
    (void)[self captureRegisterFromRange:range adapter:adapter linewise:NO];
    [adapter replaceCharactersInRange:range withString:@""];
    NSString *after = [adapter textString];
    NSRange newLine = GSVLineRangeAt(after, range.location);
    NSUInteger contentEnd = GSVLineContentEnd(after, newLine);
    NSUInteger target = range.location;
    if (target >= contentEnd && contentEnd > newLine.location) {
        target = contentEnd - 1;
    }
    [adapter setSelectedRange:NSMakeRange(target, 0)];
}

// r{char}: count characters from the cursor become ch, if the line has them.
- (void)replaceCharacters:(NSUInteger)count with:(unichar)ch adapter:(id<GSVTextEditing>)adapter
{
    NSString *text = [adapter textString];
    if ([text length] == 0) {
        return;
    }
    NSUInteger cursor = [self cursorForAdapter:adapter];
    NSUInteger contentEnd = GSVLineContentEnd(text, GSVLineRangeAt(text, cursor));
    if (cursor + count > contentEnd) {
        return;
    }
    NSMutableString *replacement = [NSMutableString string];
    for (NSUInteger i = 0; i < count; i += 1) {
        [replacement appendFormat:@"%C", ch];
    }
    [adapter replaceCharactersInRange:NSMakeRange(cursor, count) withString:replacement];
    [adapter setSelectedRange:NSMakeRange(cursor + count - 1, 0)];
}

static NSString *GSVCaseChanged(NSString *string, unichar how)
{
    if (how == 'u') {
        return [string lowercaseString];
    }
    if (how == 'U') {
        return [string uppercaseString];
    }
    NSMutableString *result = [NSMutableString stringWithCapacity:[string length]];
    for (NSUInteger i = 0; i < [string length]; i += 1) {
        NSString *ch = [string substringWithRange:NSMakeRange(i, 1)];
        NSString *upper = [ch uppercaseString];
        [result appendString:([ch isEqualToString:upper] ? [ch lowercaseString] : upper)];
    }
    return result;
}

// ~ : toggles the case of count characters and moves past them.
- (void)toggleCaseOfCharacters:(NSUInteger)count adapter:(id<GSVTextEditing>)adapter
{
    NSString *text = [adapter textString];
    if ([text length] == 0) {
        return;
    }
    NSUInteger cursor = [self cursorForAdapter:adapter];
    NSRange lineRange = GSVLineRangeAt(text, cursor);
    NSUInteger contentEnd = GSVLineContentEnd(text, lineRange);
    if (cursor >= contentEnd) {
        return;
    }
    NSRange range = NSMakeRange(cursor, MIN(count, contentEnd - cursor));
    NSString *changed = GSVCaseChanged([text substringWithRange:range], '~');
    [adapter replaceCharactersInRange:range withString:changed];
    NSUInteger target = MIN(NSMaxRange(range), contentEnd - 1);
    [adapter setSelectedRange:NSMakeRange(target, 0)];
}

// J: joins count lines (at least two) with single spaces.
- (void)joinLines:(NSUInteger)count fromLocation:(NSUInteger)location adapter:(id<GSVTextEditing>)adapter
{
    NSUInteger joins = (count > 2) ? count - 1 : 1;
    NSUInteger cursorTarget = NSNotFound;
    NSUInteger lineLocation = location;
    for (NSUInteger n = 0; n < joins; n += 1) {
        NSString *text = [adapter textString];
        NSRange lineRange = GSVLineRangeAt(text, lineLocation);
        NSUInteger contentEnd = GSVLineContentEnd(text, lineRange);
        if (contentEnd >= [text length]) {
            break;
        }
        NSUInteger nextStart = contentEnd + 1;
        NSUInteger nextContent = nextStart;
        while (nextContent < [text length] && GSVIsInlineWhitespace([text characterAtIndex:nextContent])) {
            nextContent += 1;
        }
        NSUInteger trimmedEnd = contentEnd;
        while (trimmedEnd > lineRange.location && GSVIsInlineWhitespace([text characterAtIndex:(trimmedEnd - 1)])) {
            trimmedEnd -= 1;
        }
        BOOL nextEmpty = (nextContent >= [text length] || [text characterAtIndex:nextContent] == '\n');
        BOOL nextIsCloser = (!nextEmpty && [text characterAtIndex:nextContent] == ')');
        NSString *separator = (nextEmpty || nextIsCloser || trimmedEnd == lineRange.location) ? @"" : @" ";
        [adapter replaceCharactersInRange:NSMakeRange(trimmedEnd, nextContent - trimmedEnd) withString:separator];
        cursorTarget = trimmedEnd;
    }
    if (cursorTarget != NSNotFound) {
        [adapter setSelectedRange:NSMakeRange([self clampedCursorForAdapter:adapter location:cursorTarget], 0)];
    }
}

#pragma mark - Key handling

- (BOOL)handleInsertModeToken:(NSString *)keyToken adapter:(id<GSVTextEditing>)adapter
{
    if ([keyToken isEqualToString:@"<Esc>"]) {
        [self finishInsertWithAdapter:adapter];
        [self clearPendingState];
        [self resetVisualState];
        self.mode = GSVVimModeNormal;
        return YES;
    }
    // Replaying . types what was typed; live typing goes to the text view.
    if (_isReplayingLastChange) {
        NSUInteger location = [adapter selectedRange].location;
        [adapter replaceCharactersInRange:NSMakeRange(MIN(location, [adapter textLength]), 0) withString:keyToken];
        return YES;
    }
    return NO;
}

- (BOOL)handleVisualModeToken:(NSString *)keyToken adapter:(id<GSVTextEditing>)adapter
{
    BOOL linewiseMode = [self isLinewiseVisualMode];
    unichar ch = GSVTokenCharacter(keyToken);

    if (_pendingFindType != 0 || _pendingReplace) {
        if (ch == 0) {
            [self clearPendingState];
            return YES;
        }
        if (_pendingReplace) {
            NSRange range = [self effectiveVisualSelectionRangeForAdapter:adapter];
            NSString *text = [adapter textString];
            NSMutableString *replaced = [[text substringWithRange:range] mutableCopy];
            for (NSUInteger i = 0; i < [replaced length]; i += 1) {
                if ([replaced characterAtIndex:i] != '\n') {
                    [replaced replaceCharactersInRange:NSMakeRange(i, 1) withString:keyToken];
                }
            }
            [adapter replaceCharactersInRange:range withString:replaced];
            [adapter setSelectedRange:NSMakeRange(range.location, 0)];
            [self finishVisualOperationToNormalMode];
            return YES;
        }
        unichar type = _pendingFindType;
        NSUInteger count = [self consumePendingCountWithDefault:1];
        _pendingFindType = 0;
        NSUInteger cursor = (_visualCursor != NSNotFound) ? _visualCursor : [adapter selectedRange].location;
        [adapter setSelectedRange:NSMakeRange([self clampedCursorForAdapter:adapter location:cursor], 0)];
        NSUInteger target = [self findTargetForType:type character:ch count:count repeat:NO adapter:adapter];
        _lastFindType = type;
        _lastFindCharacter = ch;
        if (target != NSNotFound) {
            _visualCursor = target;
        }
        [self updateVisualSelectionForAdapter:adapter];
        return YES;
    }

    if (_pendingTextObjectType != 0) {
        BOOL around = (_pendingTextObjectType == 'a');
        _pendingTextObjectType = 0;
        BOOL found = NO;
        NSRange range = [self textObjectRangeForAdapter:adapter objectType:ch around:around found:&found];
        if (found && range.length > 0) {
            _visualAnchor = range.location;
            _visualCursor = NSMaxRange(range) - 1;
            [self updateVisualSelectionForAdapter:adapter];
        } else {
            [self updateVisualSelectionForAdapter:adapter];
        }
        return YES;
    }

    if (GSVTokenIsDigit(keyToken)) {
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
    if ((!linewiseMode && [keyToken isEqualToString:@"v"]) || (linewiseMode && [keyToken isEqualToString:@"V"])) {
        [self exitVisualModeWithAdapter:adapter collapseToCursor:YES];
        return YES;
    }
    if ([keyToken isEqualToString:@"V"] || [keyToken isEqualToString:@"v"]) {
        self.mode = [keyToken isEqualToString:@"V"] ? GSVVimModeVisualLine : GSVVimModeVisual;
        [self updateVisualSelectionForAdapter:adapter];
        return YES;
    }
    if ([keyToken isEqualToString:@"o"]) {
        NSUInteger anchor = _visualAnchor;
        _visualAnchor = _visualCursor;
        _visualCursor = anchor;
        [self updateVisualSelectionForAdapter:adapter];
        return YES;
    }
    if (!linewiseMode && ([keyToken isEqualToString:@"i"] || [keyToken isEqualToString:@"a"])) {
        _pendingTextObjectType = ch;
        return YES;
    }
    if ([keyToken isEqualToString:@"f"] || [keyToken isEqualToString:@"F"] ||
        [keyToken isEqualToString:@"t"] || [keyToken isEqualToString:@"T"]) {
        _pendingFindType = ch;
        return YES;
    }
    if ([keyToken isEqualToString:@"r"]) {
        _pendingReplace = YES;
        return YES;
    }

    NSRange selection = [self effectiveVisualSelectionRangeForAdapter:adapter];
    if ([keyToken isEqualToString:@"d"] || [keyToken isEqualToString:@"x"]) {
        if (linewiseMode) {
            [self performLinewiseOperator:'d' fromLocation:selection.location toLocation:NSMaxRange(selection) - 1 adapter:adapter];
        } else {
            [self performOperator:'d' onRange:selection linewise:NO adapter:adapter];
        }
        [self finishVisualOperationToNormalMode];
        return YES;
    }
    if ([keyToken isEqualToString:@"X"] || [keyToken isEqualToString:@"D"]) {
        [self performLinewiseOperator:'d' fromLocation:selection.location toLocation:NSMaxRange(selection) - 1 adapter:adapter];
        [self finishVisualOperationToNormalMode];
        return YES;
    }
    if ([keyToken isEqualToString:@"y"]) {
        [self performOperator:'y' onRange:selection linewise:linewiseMode adapter:adapter];
        [self exitVisualModeWithAdapter:adapter collapseToCursor:NO];
        return YES;
    }
    if ([keyToken isEqualToString:@"Y"]) {
        [self performLinewiseOperator:'y' fromLocation:selection.location toLocation:NSMaxRange(selection) - 1 adapter:adapter];
        [self exitVisualModeWithAdapter:adapter collapseToCursor:NO];
        return YES;
    }
    if ([keyToken isEqualToString:@"c"] || [keyToken isEqualToString:@"s"]) {
        [self resetVisualState];
        [_commandTokens removeAllObjects];
        if (linewiseMode) {
            [self performLinewiseOperator:'c' fromLocation:selection.location toLocation:NSMaxRange(selection) - 1 adapter:adapter];
        } else {
            [self performOperator:'c' onRange:selection linewise:NO adapter:adapter];
        }
        _insertRepeatPrefix = nil;
        return YES;
    }
    if ([keyToken isEqualToString:@"~"] || [keyToken isEqualToString:@"u"] || [keyToken isEqualToString:@"U"]) {
        NSString *text = [adapter textString];
        NSString *changed = GSVCaseChanged([text substringWithRange:selection], ch);
        [adapter replaceCharactersInRange:selection withString:changed];
        [adapter setSelectedRange:NSMakeRange(selection.location, 0)];
        [self finishVisualOperationToNormalMode];
        return YES;
    }
    if ([keyToken isEqualToString:@"J"]) {
        NSString *text = [adapter textString];
        NSUInteger lines = 1;
        for (NSUInteger i = selection.location; i + 1 < NSMaxRange(selection); i += 1) {
            if ([text characterAtIndex:i] == '\n') {
                lines += 1;
            }
        }
        [self joinLines:MAX(lines, (NSUInteger)2) fromLocation:selection.location adapter:adapter];
        [self finishVisualOperationToNormalMode];
        return YES;
    }
    if ([keyToken isEqualToString:@"p"] || [keyToken isEqualToString:@"P"]) {
        BOOL registerLinewise = NO;
        NSString *value = [self registerStringForPut:&registerLinewise];
        if ([value length] > 0) {
            NSString *replacement = value;
            if (registerLinewise && !linewiseMode) {
                replacement = [@"\n" stringByAppendingString:value];
            } else if (!registerLinewise && linewiseMode) {
                replacement = [value stringByAppendingString:@"\n"];
            }
            NSString *text = [adapter textString];
            NSString *replaced = [text substringWithRange:selection];
            [adapter replaceCharactersInRange:selection withString:replacement];
            [adapter setSelectedRange:NSMakeRange([self clampedCursorForAdapter:adapter location:selection.location + [replacement length] - 1], 0)];
            _activeRegister = 0;
            [self storeRegisterString:replaced linewise:linewiseMode];
        }
        [self finishVisualOperationToNormalMode];
        return YES;
    }

    if (_pendingGotoPrefix) {
        _pendingGotoPrefix = NO;
        if ([keyToken isEqualToString:@"g"]) {
            NSString *text = [adapter textString];
            if ([text length] == 0) {
                [adapter setSelectedRange:NSMakeRange(0, 0)];
                return YES;
            }
            NSUInteger lineNumber = [self consumePendingCountWithDefault:1];
            _visualCursor = [self clampedCursorForAdapter:adapter location:[self locationOfLineNumber:lineNumber inText:text]];
            [self updateVisualSelectionForAdapter:adapter];
        }
        return YES;
    }
    if ([keyToken isEqualToString:@"g"]) {
        _pendingGotoPrefix = YES;
        return YES;
    }

    NSUInteger length = [adapter textLength];
    if (length == 0) {
        [adapter setSelectedRange:NSMakeRange(0, 0)];
        _pendingCount = 0;
        return YES;
    }
    BOOL hadCount = (_pendingCount > 0);
    NSUInteger motionCount = [self consumePendingCountWithDefault:1];
    NSUInteger cursor = (_visualCursor != NSNotFound) ? _visualCursor : [adapter selectedRange].location;
    cursor = [self clampedCursorForAdapter:adapter location:cursor];
    [adapter setSelectedRange:NSMakeRange(cursor, 0)];
    BOOL moved = NO;
    if ([keyToken isEqualToString:@"G"] && hadCount) {
        [adapter setSelectedRange:NSMakeRange([self locationOfLineNumber:motionCount inText:[adapter textString]], 0)];
        moved = YES;
    } else {
        moved = [self executeMotionToken:keyToken count:motionCount adapter:adapter];
    }
    if (moved) {
        _visualCursor = [self cursorForAdapter:adapter];
    }
    [self updateVisualSelectionForAdapter:adapter];
    return YES;
}

- (BOOL)handleKeyToken:(NSString *)keyToken adapter:(id<GSVTextEditing>)adapter
{
    if (adapter == nil || keyToken == nil || [keyToken length] == 0) {
        return NO;
    }

    if (self.mode == GSVVimModeInsert) {
        return [self handleInsertModeToken:keyToken adapter:adapter];
    }

    if (![self hasPendingState]) {
        [_commandTokens removeAllObjects];
    }
    [_commandTokens addObject:keyToken];

    unichar ch = GSVTokenCharacter(keyToken);

    if (_pendingRegisterPrefix) {
        _pendingRegisterPrefix = NO;
        _activeRegister = ch;
        return YES;
    }
    if ([keyToken isEqualToString:@"\""] && _pendingOperator == 0 && _pendingFindType == 0 &&
        !_pendingReplace && _pendingTextObjectType == 0) {
        _pendingRegisterPrefix = YES;
        return YES;
    }

    if (self.mode == GSVVimModeVisual || self.mode == GSVVimModeVisualLine) {
        return [self handleVisualModeToken:keyToken adapter:adapter];
    }

    // A character for f F t T or r.
    if (_pendingFindType != 0 || _pendingReplace) {
        if (ch == 0) {
            [self clearPendingState];
            return YES;
        }
        if (_pendingReplace) {
            NSUInteger count = [self consumePendingCountWithDefault:1];
            [self replaceCharacters:count with:ch adapter:adapter];
            [self recordCommandAsLastChange];
            [self clearPendingState];
            return YES;
        }
        unichar type = _pendingFindType;
        _pendingFindType = 0;
        _lastFindType = type;
        _lastFindCharacter = ch;
        if (_pendingOperator != 0) {
            unichar op = _pendingOperator;
            NSUInteger count = MAX(_pendingOperatorCount, (NSUInteger)1) * [self consumePendingCountWithDefault:1];
            NSUInteger start = [self cursorForAdapter:adapter];
            NSUInteger target = [self findTargetForType:type character:ch count:count repeat:NO adapter:adapter];
            if (target != NSNotFound) {
                BOOL inclusive = (type == 'f' || type == 't');
                [self performOperator:op toTarget:target start:start inclusive:inclusive linewise:NO wordMotion:NO adapter:adapter];
                if (op != 'y' && op != 'c') {
                    [self recordCommandAsLastChange];
                }
            }
            if (self.mode != GSVVimModeInsert) {
                [self clearPendingState];
            }
            return YES;
        }
        NSUInteger count = [self consumePendingCountWithDefault:1];
        NSUInteger target = [self findTargetForType:type character:ch count:count repeat:NO adapter:adapter];
        if (target != NSNotFound) {
            [adapter setSelectedRange:NSMakeRange(target, 0)];
        }
        [self clearPendingState];
        return YES;
    }

    BOOL isDigitToken = GSVTokenIsDigit(keyToken);
    if (isDigitToken && _pendingTextObjectType == 0) {
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

    // An operator's text object: iw a" i( and so on.
    if (_pendingOperator != 0 && _pendingTextObjectType != 0) {
        unichar op = _pendingOperator;
        BOOL around = (_pendingTextObjectType == 'a');
        BOOL found = NO;
        NSRange range = [self textObjectRangeForAdapter:adapter objectType:ch around:around found:&found];
        if (found) {
            [self performOperator:op onRange:range linewise:NO adapter:adapter];
            if (op == 'y') {
                [adapter setSelectedRange:NSMakeRange(range.location, 0)];
            } else if (op == 'd') {
                [self recordCommandAsLastChange];
            } else if (op == 'c' && range.length == 0) {
                [adapter setSelectedRange:NSMakeRange(range.location, 0)];
                [self beginInsertWithRepeatCount:1 adapter:adapter];
            }
        }
        if (self.mode != GSVVimModeInsert) {
            [self clearPendingState];
        }
        return YES;
    }

    if (_pendingGotoPrefix) {
        _pendingGotoPrefix = NO;
        if ([keyToken isEqualToString:@"g"]) {
            NSString *text = [adapter textString];
            BOOL hadCount = (_pendingCount > 0);
            NSUInteger lineNumber = [self consumePendingCountWithDefault:1];
            if (_pendingOperator != 0) {
                unichar op = _pendingOperator;
                NSUInteger target = [self locationOfLineNumber:(hadCount ? lineNumber : MAX(_pendingOperatorCount, (NSUInteger)1)) inText:text];
                if (!hadCount && _pendingOperatorCount == 0) {
                    target = 0;
                }
                [self performOperator:op toTarget:target start:[self cursorForAdapter:adapter] inclusive:NO linewise:YES wordMotion:NO adapter:adapter];
                if (op == 'd') {
                    [self recordCommandAsLastChange];
                }
                if (self.mode != GSVVimModeInsert) {
                    [self clearPendingState];
                }
                return YES;
            }
            if (hadCount) {
                [adapter setSelectedRange:NSMakeRange([self locationOfLineNumber:lineNumber inText:text], 0)];
            } else {
                [adapter moveToFirstLine];
            }
            [self clearPendingState];
            return YES;
        }
        [self clearPendingState];
        return YES;
    }

    if (_pendingOperator != 0) {
        unichar op = _pendingOperator;
        NSUInteger opCount = MAX(_pendingOperatorCount, (NSUInteger)1);
        if ([keyToken isEqualToString:@"i"] || [keyToken isEqualToString:@"a"]) {
            _pendingTextObjectType = ch;
            return YES;
        }
        if ([keyToken isEqualToString:@"f"] || [keyToken isEqualToString:@"F"] ||
            [keyToken isEqualToString:@"t"] || [keyToken isEqualToString:@"T"]) {
            _pendingFindType = ch;
            return YES;
        }
        if (ch == op) {
            NSUInteger totalCount = opCount * [self consumePendingCountWithDefault:1];
            [self handleDoubleOperatorCommand:op count:totalCount adapter:adapter];
            if (op == 'd') {
                [self recordCommandAsLastChange];
            }
            if (self.mode != GSVVimModeInsert) {
                [self clearPendingState];
            }
            return YES;
        }
        if ([keyToken isEqualToString:@"g"]) {
            _pendingGotoPrefix = YES;
            return YES;
        }
        BOOL hadCount = (_pendingCount > 0 || _pendingOperatorCount > 0);
        NSUInteger totalMotionCount = opCount * [self consumePendingCountWithDefault:1];
        BOOL performed = [self performPendingOperator:op
                                          motionToken:keyToken
                                          motionCount:totalMotionCount
                                             hadCount:hadCount
                                              adapter:adapter];
        if (performed && op == 'd') {
            [self recordCommandAsLastChange];
        }
        if (self.mode != GSVVimModeInsert) {
            [self clearPendingState];
        }
        return YES;
    }

    if ([keyToken isEqualToString:@"u"] || [keyToken isEqualToString:@"U"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        for (NSUInteger i = 0; i < count; i += 1) {
            [adapter undoLastChange];
        }
        [self clearPendingState];
        return YES;
    }
    if ([keyToken isEqualToString:@"<C-r>"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        for (NSUInteger i = 0; i < count; i += 1) {
            [adapter redoLastUndo];
        }
        [self clearPendingState];
        return YES;
    }
    if ([keyToken isEqualToString:@"."]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        [self clearPendingState];
        return [self replayLastChangeWithCount:count adapter:adapter];
    }
    if ([keyToken isEqualToString:@"V"] || [keyToken isEqualToString:@"v"]) {
        _pendingCount = 0;
        [self enterVisualModeWithAdapter:adapter linewise:[keyToken isEqualToString:@"V"]];
        return YES;
    }
    if ([keyToken isEqualToString:@"p"] || [keyToken isEqualToString:@"P"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        BOOL handled = [self putFromRegisterAfterCursor:[keyToken isEqualToString:@"p"] count:count adapter:adapter];
        [self recordCommandAsLastChange];
        [self clearPendingState];
        return handled;
    }
    if ([keyToken isEqualToString:@"d"] || [keyToken isEqualToString:@"y"] || [keyToken isEqualToString:@"c"]) {
        _pendingOperator = ch;
        _pendingOperatorCount = _pendingCount;
        _pendingCount = 0;
        return YES;
    }
    if ([keyToken isEqualToString:@"Y"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        [self handleDoubleOperatorCommand:'y' count:count adapter:adapter];
        [self clearPendingState];
        return YES;
    }
    if ([keyToken isEqualToString:@"C"] || [keyToken isEqualToString:@"D"]) {
        unichar op = ([keyToken isEqualToString:@"C"]) ? 'c' : 'd';
        NSUInteger count = [self consumePendingCountWithDefault:1];
        NSString *text = [adapter textString];
        NSUInteger start = [self cursorForAdapter:adapter];
        NSUInteger end = start;
        if ([text length] > 0) {
            NSUInteger lastLine = [self lineStartFrom:start offset:(NSInteger)(count - 1) inText:text];
            end = GSVLineContentEnd(text, GSVLineRangeAt(text, lastLine));
        }
        if (end > start) {
            [adapter setSelectedRange:NSMakeRange(start, 0)];
            [self performOperator:op onRange:NSMakeRange(start, end - start) linewise:NO adapter:adapter];
        } else if (op == 'c') {
            [adapter setSelectedRange:NSMakeRange(MIN(start, [text length]), 0)];
            [self beginInsertWithRepeatCount:1 adapter:adapter];
        }
        if (op == 'd') {
            [self recordCommandAsLastChange];
            [self clearPendingState];
        }
        return YES;
    }
    if ([keyToken isEqualToString:@"s"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        NSString *text = [adapter textString];
        NSUInteger start = [self cursorForAdapter:adapter];
        NSUInteger contentEnd = ([text length] > 0) ? GSVLineContentEnd(text, GSVLineRangeAt(text, start)) : 0;
        if (start < contentEnd) {
            [self performOperator:'c' onRange:NSMakeRange(start, MIN(count, contentEnd - start)) linewise:NO adapter:adapter];
        } else {
            [self beginInsertWithRepeatCount:1 adapter:adapter];
        }
        return YES;
    }
    if ([keyToken isEqualToString:@"S"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        [self handleDoubleOperatorCommand:'c' count:count adapter:adapter];
        return YES;
    }
    if ([keyToken isEqualToString:@"x"] || [keyToken isEqualToString:@"X"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        [self deleteCharactersForward:[keyToken isEqualToString:@"x"] count:count adapter:adapter];
        [self recordCommandAsLastChange];
        [self clearPendingState];
        return YES;
    }
    if ([keyToken isEqualToString:@"r"]) {
        _pendingReplace = YES;
        return YES;
    }
    if ([keyToken isEqualToString:@"f"] || [keyToken isEqualToString:@"F"] ||
        [keyToken isEqualToString:@"t"] || [keyToken isEqualToString:@"T"]) {
        _pendingFindType = ch;
        return YES;
    }
    if ([keyToken isEqualToString:@"~"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        [self toggleCaseOfCharacters:count adapter:adapter];
        [self recordCommandAsLastChange];
        [self clearPendingState];
        return YES;
    }
    if ([keyToken isEqualToString:@"J"]) {
        NSUInteger count = [self consumePendingCountWithDefault:2];
        [self joinLines:count fromLocation:[self cursorForAdapter:adapter] adapter:adapter];
        [self recordCommandAsLastChange];
        [self clearPendingState];
        return YES;
    }
    if ([keyToken isEqualToString:@"O"] || [keyToken isEqualToString:@"o"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        for (NSUInteger i = 0; i < count; i += 1) {
            if ([keyToken isEqualToString:@"o"]) {
                [adapter openLineBelow];
            } else {
                [adapter openLineAbove];
            }
        }
        [self beginInsertWithRepeatCount:1 adapter:adapter];
        return YES;
    }
    if ([keyToken isEqualToString:@"i"] || [keyToken isEqualToString:@"a"] ||
        [keyToken isEqualToString:@"I"] || [keyToken isEqualToString:@"A"]) {
        NSUInteger count = [self consumePendingCountWithDefault:1];
        NSString *text = [adapter textString];
        if ([text length] > 0) {
            NSUInteger cursor = [self cursorForAdapter:adapter];
            NSRange lineRange = GSVLineRangeAt(text, cursor);
            if ([keyToken isEqualToString:@"a"]) {
                if ([text characterAtIndex:cursor] != '\n') {
                    [adapter moveCursorRight];
                }
            } else if ([keyToken isEqualToString:@"A"]) {
                [adapter setSelectedRange:NSMakeRange(GSVLineContentEnd(text, lineRange), 0)];
            } else if ([keyToken isEqualToString:@"I"]) {
                [adapter setSelectedRange:NSMakeRange(GSVFirstNonBlankInLine(text, lineRange), 0)];
            }
        }
        [self beginInsertWithRepeatCount:count adapter:adapter];
        return YES;
    }
    if ([keyToken isEqualToString:@"g"]) {
        _pendingGotoPrefix = YES;
        return YES;
    }

    BOOL hadCount = (_pendingCount > 0);
    NSUInteger motionCount = [self consumePendingCountWithDefault:1];
    if ([keyToken isEqualToString:@"G"] && hadCount) {
        [adapter setSelectedRange:NSMakeRange([self locationOfLineNumber:motionCount inText:[adapter textString]], 0)];
        [self clearPendingState];
        return YES;
    }
    if ([self executeMotionToken:keyToken count:motionCount adapter:adapter]) {
        [self clearPendingState];
        return YES;
    }

    [self clearPendingState];
    // In Normal mode, typed characters are Vim commands. Unimplemented commands are consumed.
    return YES;
}

@end
