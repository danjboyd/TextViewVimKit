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
        [self clearInsertRecentKeys];
        [self.engine resetToNormalMode];
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
