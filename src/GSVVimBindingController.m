#import "GSVVimBindingController.h"

#import "GSVTextViewAdapter.h"

#if defined(NSEventTypeKeyDown)
#define GSV_KEY_DOWN_EVENT NSEventTypeKeyDown
#else
#define GSV_KEY_DOWN_EVENT NSKeyDown
#endif

static NSString *GSVKeyTokenFromEvent(NSEvent *event)
{
    NSString *characters = [event characters];
    if (characters == nil || [characters length] == 0) {
        characters = [event charactersIgnoringModifiers];
    }
    if (characters == nil || [characters length] == 0) {
        return nil;
    }

    unichar ch = [characters characterAtIndex:0];
    if (ch == 0x1b) {
        return @"<Esc>";
    }
    NSUInteger flags = [event modifierFlags];
    if ((flags & NSControlKeyMask) != 0) {
        NSString *ignoring = [event charactersIgnoringModifiers];
        if (ignoring != nil && [ignoring length] > 0) {
            unichar lower = [[ignoring lowercaseString] characterAtIndex:0];
            if (lower == 'r') {
                return @"<C-r>";
            }
        }
        if (ch == 0x12) {
            return @"<C-r>";
        }
    }
    return [characters substringToIndex:1];
}

static BOOL GSVTokenIsColonCommandStart(NSString *token)
{
    return token != nil && [token isEqualToString:@":"];
}

static BOOL GSVEventHasUnsupportedInsertModifiers(NSEvent *event)
{
    NSUInteger flags = [event modifierFlags];
    NSUInteger normalized = flags & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask);
    return normalized != 0;
}

static BOOL GSVTokenIsSingleInsertableCharacter(NSString *token)
{
    if (token == nil || [token length] != 1) {
        return NO;
    }
    unichar ch = [token characterAtIndex:0];
    if (ch < 0x20 || ch == 0x7f) {
        return NO;
    }
    return YES;
}

static BOOL GSVIsCommandLineBackspace(unichar ch)
{
    return ch == 0x08 || ch == 0x7f;
}

static BOOL GSVIsCommandLineEnter(unichar ch)
{
    return ch == '\r' || ch == '\n';
}

static NSString *GSVTrimmedCommandString(NSString *value)
{
    if (value == nil) {
        return @"";
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static GSVVimExAction GSVParseExAction(NSString *rawCommand, BOOL *force)
{
    if (force != NULL) {
        *force = NO;
    }

    NSString *trimmed = GSVTrimmedCommandString(rawCommand);
    if ([trimmed length] == 0) {
        return GSVVimExActionUnknown;
    }

    BOOL parsedForce = NO;
    if ([trimmed hasSuffix:@"!"]) {
        parsedForce = YES;
        trimmed = [trimmed substringToIndex:([trimmed length] - 1)];
        trimmed = GSVTrimmedCommandString(trimmed);
    }
    if (force != NULL) {
        *force = parsedForce;
    }

    NSString *lower = [trimmed lowercaseString];
    if ([lower isEqualToString:@"w"]) {
        return GSVVimExActionWrite;
    }
    if ([lower isEqualToString:@"q"]) {
        return GSVVimExActionQuit;
    }
    if ([lower isEqualToString:@"wq"] || [lower isEqualToString:@"x"]) {
        return GSVVimExActionWriteQuit;
    }
    return GSVVimExActionUnknown;
}

#if defined(NSPasteboardTypeString)
static NSString *GSVPasteboardStringType(void)
{
    return NSPasteboardTypeString;
}
#else
static NSString *GSVPasteboardStringType(void)
{
    return NSStringPboardType;
}
#endif

@interface GSVSystemClipboard : NSObject <GSVVimClipboard>
@end

@implementation GSVSystemClipboard

- (void)writeClipboardString:(NSString *)string
{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    if (pasteboard == nil) {
        return;
    }

    NSString *value = (string != nil) ? string : @"";
    NSString *type = GSVPasteboardStringType();
    [pasteboard declareTypes:@[type] owner:nil];
    [pasteboard setString:value forType:type];
}

- (NSString *)readClipboardString
{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    if (pasteboard == nil) {
        return nil;
    }

    return [pasteboard stringForType:GSVPasteboardStringType()];
}

@end

@interface GSVVimBindingController () <GSVVimEngineDelegate>
@property (nonatomic, strong, readwrite) NSTextView *textView;
@property (nonatomic, strong) GSVVimEngine *engine;
@property (nonatomic, strong) GSVTextViewAdapter *adapter;
@property (nonatomic, strong) NSMutableString *insertRecentKeys;
@property (nonatomic, assign) BOOL commandLineActive;
@property (nonatomic, strong) NSMutableString *commandLineBuffer;
@end

@implementation GSVVimBindingController

- (instancetype)initWithTextView:(NSTextView *)textView
{
    NSParameterAssert(textView != nil);
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _textView = textView;
    _adapter = [[GSVTextViewAdapter alloc] initWithTextView:textView];
    _engine = [[GSVVimEngine alloc] init];
    _engine.clipboard = [[GSVSystemClipboard alloc] init];
    _engine.delegate = self;
    _config = [[GSVVimConfig alloc] initWithInsertModeMappings:nil diagnostics:nil];
    _engine.unnamedRegisterUsesClipboard = _config.unnamedRegisterUsesSystemClipboard;
    _insertRecentKeys = [NSMutableString string];
    _commandLineBuffer = [NSMutableString string];
    _commandLineActive = NO;
    _enabled = YES;
    return self;
}

- (GSVVimMode)mode
{
    return self.engine.mode;
}

- (void)setEnabled:(BOOL)enabled
{
    _enabled = enabled;
    if (!enabled) {
        [self setCommandLineActive:NO];
        [self.commandLineBuffer setString:@""];
        [self clearInsertRecentKeys];
        [self.engine resetToNormalMode];
        id<GSVVimBindingControllerDelegate> delegate = self.delegate;
        if (delegate != nil &&
            [delegate respondsToSelector:@selector(vimBindingController:didUpdateCommandLine:active:forTextView:)]) {
            [delegate vimBindingController:self
                      didUpdateCommandLine:nil
                                    active:NO
                               forTextView:self.textView];
        }
    }
}

- (void)setConfig:(GSVVimConfig *)config
{
    if (config != nil) {
        _config = config;
    } else {
        _config = [[GSVVimConfig alloc] initWithInsertModeMappings:nil diagnostics:nil];
    }
    self.engine.unnamedRegisterUsesClipboard = _config.unnamedRegisterUsesSystemClipboard;
    [self clearInsertRecentKeys];
}

- (void)clearInsertRecentKeys
{
    [self.insertRecentKeys setString:@""];
}

- (void)notifyCommandLineState
{
    id<GSVVimBindingControllerDelegate> delegate = self.delegate;
    if (delegate != nil &&
        [delegate respondsToSelector:@selector(vimBindingController:didUpdateCommandLine:active:forTextView:)]) {
        NSString *value = nil;
        if (self.commandLineActive) {
            value = [NSString stringWithFormat:@":%@", self.commandLineBuffer];
        }
        [delegate vimBindingController:self
                  didUpdateCommandLine:value
                                active:self.commandLineActive
                           forTextView:self.textView];
    }
}

- (void)beginCommandLineCapture
{
    self.commandLineActive = YES;
    [self.commandLineBuffer setString:@""];
    [self notifyCommandLineState];
}

- (void)cancelCommandLineCapture
{
    self.commandLineActive = NO;
    [self.commandLineBuffer setString:@""];
    [self notifyCommandLineState];
}

- (void)appendCommandLineCharacter:(unichar)ch
{
    [self.commandLineBuffer appendFormat:@"%C", ch];
    [self notifyCommandLineState];
}

- (void)deleteLastCommandLineCharacter
{
    NSUInteger length = [self.commandLineBuffer length];
    if (length == 0) {
        return;
    }
    [self.commandLineBuffer deleteCharactersInRange:NSMakeRange(length - 1, 1)];
    [self notifyCommandLineState];
}

- (BOOL)dispatchCommandLineAction
{
    NSString *rawCommand = [self.commandLineBuffer copy];
    NSString *trimmed = GSVTrimmedCommandString(rawCommand);
    [self cancelCommandLineCapture];
    if ([trimmed length] == 0) {
        return YES;
    }

    BOOL force = NO;
    GSVVimExAction action = GSVParseExAction(rawCommand, &force);
    BOOL handled = NO;
    id<GSVVimBindingControllerDelegate> delegate = self.delegate;
    if (delegate != nil &&
        [delegate respondsToSelector:@selector(vimBindingController:handleExAction:force:rawCommand:forTextView:)]) {
        handled = [delegate vimBindingController:self
                                  handleExAction:action
                                           force:force
                                      rawCommand:rawCommand
                                     forTextView:self.textView];
    }

    if (!handled && action == GSVVimExActionUnknown) {
        NSBeep();
    }
    return YES;
}

- (BOOL)handleCommandLineEvent:(NSEvent *)event
{
    NSString *characters = [event characters];
    if (characters == nil || [characters length] == 0) {
        characters = [event charactersIgnoringModifiers];
    }
    if (characters == nil || [characters length] == 0) {
        return YES;
    }

    unichar ch = [characters characterAtIndex:0];
    if (ch == 0x1b) {
        [self cancelCommandLineCapture];
        return YES;
    }
    if (GSVIsCommandLineEnter(ch)) {
        return [self dispatchCommandLineAction];
    }
    if (GSVIsCommandLineBackspace(ch)) {
        [self deleteLastCommandLineCharacter];
        return YES;
    }

    NSUInteger flags = [event modifierFlags];
    NSUInteger normalized = flags & (NSCommandKeyMask | NSControlKeyMask);
    if (normalized != 0) {
        return YES;
    }

    if (ch >= 0x20 && ch != 0x7f) {
        [self appendCommandLineCharacter:ch];
    }
    return YES;
}

- (BOOL)handleInsertMappingMatchForToken:(NSString *)token event:(NSEvent *)event
{
    if (self.config == nil || [self.config.insertModeMappings count] == 0) {
        return NO;
    }
    if (!GSVTokenIsSingleInsertableCharacter(token)) {
        return NO;
    }
    if (GSVEventHasUnsupportedInsertModifiers(event)) {
        return NO;
    }

    for (NSString *lhs in [self.config insertMappingLHSKeys]) {
        NSUInteger lhsLength = [lhs length];
        if (lhsLength == 0) {
            continue;
        }

        NSString *lastChar = [lhs substringFromIndex:(lhsLength - 1)];
        if (![lastChar isEqualToString:token]) {
            continue;
        }

        NSUInteger prefixLength = lhsLength - 1;
        NSString *prefix = (prefixLength > 0) ? [lhs substringToIndex:prefixLength] : @"";
        if (prefixLength > 0 && ![self.insertRecentKeys hasSuffix:prefix]) {
            continue;
        }

        NSRange selected = [self.adapter selectedRange];
        if (selected.length != 0) {
            continue;
        }
        if (selected.location < prefixLength) {
            continue;
        }

        NSString *text = [self.adapter textString];
        NSRange prefixRange = NSMakeRange(selected.location - prefixLength, prefixLength);
        if (prefixLength > 0) {
            if (NSMaxRange(prefixRange) > [text length]) {
                continue;
            }
            NSString *bufferPrefix = [text substringWithRange:prefixRange];
            if (![bufferPrefix isEqualToString:prefix]) {
                continue;
            }
            [self.adapter replaceCharactersInRange:prefixRange withString:@""];
        }

        [self clearInsertRecentKeys];
        NSString *rhs = [self.config insertMappingRHSForSequence:lhs];
        if ([rhs isEqualToString:@"<Esc>"]) {
            return [self.engine handleKeyToken:@"<Esc>" adapter:self.adapter];
        }
        return YES;
    }

    return NO;
}

- (void)recordInsertToken:(NSString *)token event:(NSEvent *)event
{
    if (!GSVTokenIsSingleInsertableCharacter(token)) {
        [self clearInsertRecentKeys];
        return;
    }
    if (GSVEventHasUnsupportedInsertModifiers(event)) {
        [self clearInsertRecentKeys];
        return;
    }

    [self.insertRecentKeys appendString:token];

    NSUInteger maxLength = [self.config maxInsertMappingLength];
    if (maxLength == 0) {
        [self clearInsertRecentKeys];
        return;
    }

    NSUInteger limit = (maxLength > 0) ? (maxLength - 1) : 0;
    if (limit == 0) {
        [self clearInsertRecentKeys];
        return;
    }
    if ([self.insertRecentKeys length] > limit) {
        NSUInteger start = [self.insertRecentKeys length] - limit;
        NSString *suffix = [self.insertRecentKeys substringFromIndex:start];
        [self.insertRecentKeys setString:suffix];
    }
}

- (BOOL)handleKeyEvent:(NSEvent *)event
{
    if (!self.isEnabled || self.textView == nil || event == nil) {
        return NO;
    }
    if ([event type] != GSV_KEY_DOWN_EVENT) {
        return NO;
    }
    if ([self.adapter hasMarkedText]) {
        return NO;
    }

    NSString *token = GSVKeyTokenFromEvent(event);
    if (token == nil) {
        return NO;
    }

    if (self.commandLineActive) {
        return [self handleCommandLineEvent:event];
    }

    if (self.engine.mode == GSVVimModeNormal && GSVTokenIsColonCommandStart(token)) {
        [self beginCommandLineCapture];
        return YES;
    }

    if (self.engine.mode == GSVVimModeInsert) {
        if ([token isEqualToString:@"<Esc>"]) {
            [self clearInsertRecentKeys];
            return [self.engine handleKeyToken:token adapter:self.adapter];
        }

        BOOL handledInsertMapping = [self handleInsertMappingMatchForToken:token event:event];
        if (handledInsertMapping) {
            return YES;
        }

        [self recordInsertToken:token event:event];
        return [self.engine handleKeyToken:token adapter:self.adapter];
    }

    [self clearInsertRecentKeys];
    return [self.engine handleKeyToken:token adapter:self.adapter];
}

- (void)vimEngine:(GSVVimEngine *)engine didChangeMode:(GSVVimMode)mode
{
    (void)engine;
    if (mode != GSVVimModeInsert) {
        [self clearInsertRecentKeys];
    }
    id<GSVVimBindingControllerDelegate> delegate = self.delegate;
    if (delegate != nil && [delegate respondsToSelector:@selector(vimBindingController:didChangeMode:forTextView:)]) {
        [delegate vimBindingController:self didChangeMode:mode forTextView:self.textView];
    }
}

@end
