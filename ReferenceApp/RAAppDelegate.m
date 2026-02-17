#import "RAAppDelegate.h"

#import <float.h>

#import "RAFixtureTextView.h"
#import "GSVVimConfig.h"
#import "GSVVimConfigLoader.h"
#import "GSVVimMode.h"

#if defined(NSWindowStyleMaskTitled)
#define RA_WINDOW_STYLE_TITLED NSWindowStyleMaskTitled
#define RA_WINDOW_STYLE_CLOSABLE NSWindowStyleMaskClosable
#define RA_WINDOW_STYLE_RESIZABLE NSWindowStyleMaskResizable
#define RA_WINDOW_STYLE_MINIATURIZABLE NSWindowStyleMaskMiniaturizable
#else
#define RA_WINDOW_STYLE_TITLED NSTitledWindowMask
#define RA_WINDOW_STYLE_CLOSABLE NSClosableWindowMask
#define RA_WINDOW_STYLE_RESIZABLE NSResizableWindowMask
#define RA_WINDOW_STYLE_MINIATURIZABLE NSMiniaturizableWindowMask
#endif

#if defined(NSControlStateValueOn)
#define RA_CONTROL_STATE_ON NSControlStateValueOn
#else
#define RA_CONTROL_STATE_ON NSOnState
#endif

static NSTextField *RAMakeLabel(NSRect frame, CGFloat size, BOOL bold)
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    if (bold) {
        [label setFont:[NSFont boldSystemFontOfSize:size]];
    } else {
        [label setFont:[NSFont systemFontOfSize:size]];
    }
    return label;
}

@interface RAAppDelegate ()
{
    RAReferenceWindow *_window;
    NSView *_statusView;
    NSSplitView *_splitView;

    NSTextField *_headerLabel;
    NSTextField *_modeLabel;
    NSTextField *_focusLabel;
    NSTextField *_configLabel;
    NSButton *_vimEnabledButton;

    NSScrollView *_plainScrollView;
    NSScrollView *_fixtureScrollView;
    NSTextView *_plainTextView;
    RAFixtureTextView *_fixtureTextView;

    GSVVimBindingController *_plainController;
    GSVVimBindingController *_fixtureController;
    GSVVimConfig *_runtimeConfig;
}
@end

@implementation RAAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    [self createWindow];
    [self buildUserInterface];
    [self buildControllers];
    [self refreshStatus];

    [_window makeFirstResponder:_plainTextView];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)createWindow
{
    NSUInteger style = (RA_WINDOW_STYLE_TITLED |
                        RA_WINDOW_STYLE_CLOSABLE |
                        RA_WINDOW_STYLE_RESIZABLE |
                        RA_WINDOW_STYLE_MINIATURIZABLE);
    _window = [[RAReferenceWindow alloc] initWithContentRect:NSMakeRect(100.0, 100.0, 1120.0, 720.0)
                                                    styleMask:style
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    [_window setTitle:@"TextViewVimKit Reference App"];
    [_window setKeyDelegate:self];
}

- (void)buildUserInterface
{
    NSView *contentView = [_window contentView];
    NSRect contentBounds = [contentView bounds];
    CGFloat statusHeight = 76.0;

    _statusView = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                           contentBounds.size.height - statusHeight,
                                                           contentBounds.size.width,
                                                           statusHeight)];
    [_statusView setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [contentView addSubview:_statusView];

    _headerLabel = RAMakeLabel(NSMakeRect(16.0, 48.0, 420.0, 20.0), 13.0, YES);
    [_headerLabel setStringValue:@"Reference App: plain NSTextView + subclass fixture"];
    [_statusView addSubview:_headerLabel];

    _modeLabel = RAMakeLabel(NSMakeRect(16.0, 24.0, 220.0, 20.0), 12.0, YES);
    [_statusView addSubview:_modeLabel];

    _focusLabel = RAMakeLabel(NSMakeRect(248.0, 24.0, 250.0, 20.0), 12.0, NO);
    [_statusView addSubview:_focusLabel];

    _vimEnabledButton = [[NSButton alloc] initWithFrame:NSMakeRect(contentBounds.size.width - 172.0, 42.0, 150.0, 24.0)];
    [_vimEnabledButton setAutoresizingMask:NSViewMinXMargin];
    [_vimEnabledButton setButtonType:NSSwitchButton];
    [_vimEnabledButton setTitle:@"Enable Vim Layer"];
    [_vimEnabledButton setState:RA_CONTROL_STATE_ON];
    [_vimEnabledButton setTarget:self];
    [_vimEnabledButton setAction:@selector(toggleVimBindings:)];
    [_statusView addSubview:_vimEnabledButton];

    _configLabel = RAMakeLabel(NSMakeRect(16.0, 6.0, contentBounds.size.width - 32.0, 16.0), 11.0, NO);
    [_configLabel setAutoresizingMask:NSViewWidthSizable];
    [[_configLabel cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [_statusView addSubview:_configLabel];

    _splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0,
                                                               0.0,
                                                               contentBounds.size.width,
                                                               contentBounds.size.height - statusHeight)];
    [_splitView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_splitView setVertical:YES];
    [contentView addSubview:_splitView];

    _plainScrollView = [self newEditorScrollView];
    _plainTextView = [[NSTextView alloc] initWithFrame:[[_plainScrollView contentView] bounds]];
    [self configureEditorTextView:_plainTextView];
    [_plainTextView setString:[self sampleTextForEditorTitle:@"Plain NSTextView"]];
    [self applyReadableTextStylingToTextView:_plainTextView];
    [_plainTextView setDelegate:self];
    [_plainScrollView setDocumentView:_plainTextView];

    _fixtureScrollView = [self newEditorScrollView];
    _fixtureTextView = [[RAFixtureTextView alloc] initWithFrame:[[_fixtureScrollView contentView] bounds]];
    [self configureEditorTextView:_fixtureTextView];
    [_fixtureTextView setString:[self sampleTextForEditorTitle:@"NSTextView Subclass Fixture"]];
    [self applyReadableTextStylingToTextView:_fixtureTextView];
    [_fixtureTextView setDelegate:self];
    [_fixtureTextView setBackgroundColor:[NSColor colorWithCalibratedWhite:0.99 alpha:1.0]];
    [_fixtureScrollView setDocumentView:_fixtureTextView];

    [_splitView addSubview:_plainScrollView];
    [_splitView addSubview:_fixtureScrollView];
    [_splitView adjustSubviews];

    if ([[_splitView subviews] count] >= 2) {
        CGFloat dividerPosition = floor([_splitView bounds].size.width * 0.5);
        [_splitView setPosition:dividerPosition ofDividerAtIndex:0];
    }
}

- (void)buildControllers
{
    _runtimeConfig = [GSVVimConfigLoader loadDefaultConfig];

    _plainController = [[GSVVimBindingController alloc] initWithTextView:_plainTextView];
    _plainController.delegate = self;
    _plainController.config = _runtimeConfig;

    _fixtureController = [[GSVVimBindingController alloc] initWithTextView:_fixtureTextView];
    _fixtureController.delegate = self;
    _fixtureController.config = _runtimeConfig;

    [self applyVimEnabledState];
}

- (NSScrollView *)newEditorScrollView
{
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
    [scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:YES];
    [scrollView setBorderType:NSBezelBorder];
    return scrollView;
}

- (void)configureEditorTextView:(NSTextView *)textView
{
    [textView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [textView setMinSize:NSMakeSize(0.0, 0.0)];
    [textView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [textView setVerticallyResizable:YES];
    [textView setHorizontallyResizable:YES];
    [textView setRichText:NO];
    [textView setUsesFontPanel:YES];
    [textView setFont:[NSFont userFixedPitchFontOfSize:13.0]];
    [textView setTextContainerInset:NSMakeSize(10.0, 10.0)];
    [textView setBackgroundColor:[NSColor whiteColor]];

    NSTextContainer *container = [textView textContainer];
    [container setContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [container setWidthTracksTextView:NO];
}

- (void)applyReadableTextStylingToTextView:(NSTextView *)textView
{
    if (textView == nil) {
        return;
    }

    NSColor *foreground = [NSColor blackColor];
    if ([textView respondsToSelector:@selector(setTextColor:)]) {
        [textView setTextColor:foreground];
    }
    if ([textView respondsToSelector:@selector(setInsertionPointColor:)]) {
        [textView setInsertionPointColor:foreground];
    }

    NSFont *font = [textView font];
    if (font == nil) {
        font = [NSFont userFixedPitchFontOfSize:13.0];
    }
    if (font == nil) {
        font = [NSFont systemFontOfSize:13.0];
    }

    NSMutableDictionary *typing = [[textView typingAttributes] mutableCopy];
    if (typing == nil) {
        typing = [NSMutableDictionary dictionary];
    }
    [typing setObject:foreground forKey:NSForegroundColorAttributeName];
    if (font != nil) {
        [typing setObject:font forKey:NSFontAttributeName];
    }
    [textView setTypingAttributes:typing];

    NSTextStorage *storage = [textView textStorage];
    NSUInteger length = [storage length];
    if (length == 0) {
        return;
    }
    NSRange full = NSMakeRange(0, length);
    [storage addAttribute:NSForegroundColorAttributeName value:foreground range:full];
    if (font != nil) {
        [storage addAttribute:NSFontAttributeName value:font range:full];
    }
}

- (NSString *)sampleTextForEditorTitle:(NSString *)title
{
    return [NSString stringWithFormat:
            @"%@\n"
            @"\n"
            @"Reference controls:\n"
            @"  v   -> enter VISUAL mode (characterwise)\n"
            @"  V   -> enter VISUAL LINE mode (linewise)\n"
            @"  d/y -> delete or yank active VISUAL selection\n"
            @"  d{motion}, y{motion} -> operator-pending (w b e 0 ^ $ gg G)\n"
            @"  dd / yy -> delete or yank current line\n"
            @"  ciw / caw -> change inner/a word and enter INSERT\n"
            @"  cc / C / D -> change line, change-to-EOL, delete-to-EOL\n"
            @"  diw/daw/yiw/yaw -> word text objects for delete/yank\n"
            @"  \"+y... -> yank explicitly to system clipboard\n"
            @"  p / P / \"+p / \"+P -> put after/before from unnamed or clipboard register\n"
            @"  [count] motions and edits -> e.g. 3j, d2w, 2dd, 3x, 2p\n"
            @"  .   -> repeat last change\n"
            @"  u / <C-r> -> undo / redo\n"
            @"  i   -> enter INSERT mode\n"
            @"  Esc -> return to NORMAL mode\n"
            @"  h j k l -> cursor movement in NORMAL mode\n"
            @"  w b e -> word motions in NORMAL mode\n"
            @"  0 ^ $ -> line start/first-nonblank/end\n"
            @"  gg / G -> first line / last line\n"
            @"  x   -> delete forward in NORMAL mode\n"
            @"  a   -> append + enter INSERT mode\n"
            @"  o/O -> open line below/above and enter INSERT mode\n"
            @"\n"
            @"Config precedence target:\n"
            @"  1) ~/.gnustepvimrc\n"
            @"  2) optional ~/.vimrc subset import\n"
            @"\n"
            @"Start editing below.\n",
            title];
}

- (void)toggleVimBindings:(id)sender
{
    (void)sender;
    [self applyVimEnabledState];
    [self refreshStatus];
}

- (void)applyVimEnabledState
{
    BOOL enabled = ([_vimEnabledButton state] == RA_CONTROL_STATE_ON);
    _plainController.enabled = enabled;
    _fixtureController.enabled = enabled;
}

- (GSVVimBindingController *)controllerForTextView:(NSTextView *)textView
{
    if (textView == _plainTextView) {
        return _plainController;
    }
    if (textView == _fixtureTextView) {
        return _fixtureController;
    }
    return nil;
}

- (GSVVimBindingController *)activeController
{
    NSResponder *responder = [_window firstResponder];
    if (![responder isKindOfClass:[NSTextView class]]) {
        return nil;
    }
    return [self controllerForTextView:(NSTextView *)responder];
}

- (void)refreshConfigLabel
{
    NSString *gnustepConfigPath = [@"~/.gnustepvimrc" stringByExpandingTildeInPath];
    NSString *vimrcPath = [@"~/.vimrc" stringByExpandingTildeInPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL hasLocalConfig = [fileManager fileExistsAtPath:gnustepConfigPath];
    BOOL hasVimrc = [fileManager fileExistsAtPath:vimrcPath];

    NSString *localState = hasLocalConfig ? @"found" : @"missing";
    NSString *vimrcState = hasVimrc ? @"found" : @"missing";
    NSUInteger mappingCount = [[_runtimeConfig insertModeMappings] count];
    NSUInteger diagnosticCount = [[_runtimeConfig diagnostics] count];
    NSString *clipboardState = _runtimeConfig.unnamedRegisterUsesSystemClipboard ? @"unnamed->system ON" : @"unnamed->system OFF";
    [_configLabel setStringValue:[NSString stringWithFormat:@"Config: %@ (%@) | .vimrc: %@ (%@) | inoremap=%lu diag=%lu | %@",
                                                                 gnustepConfigPath,
                                                                 localState,
                                                                 vimrcPath,
                                                                 vimrcState,
                                                                 (unsigned long)mappingCount,
                                                                 (unsigned long)diagnosticCount,
                                                                 clipboardState]];
}

- (void)refreshStatus
{
    [self refreshConfigLabel];

    BOOL enabled = ([_vimEnabledButton state] == RA_CONTROL_STATE_ON);
    GSVVimBindingController *active = [self activeController];
    NSString *focus = @"none";
    if (active == _plainController) {
        focus = @"plain NSTextView";
    } else if (active == _fixtureController) {
        focus = @"NSTextView subclass";
    }

    NSString *modeText = @"DISABLED";
    if (enabled) {
        if (active != nil) {
            modeText = GSVVimModeDisplayName(active.mode);
        } else {
            modeText = @"NORMAL";
        }
    }

    [_modeLabel setStringValue:[NSString stringWithFormat:@"Mode: %@", modeText]];
    [_focusLabel setStringValue:[NSString stringWithFormat:@"Focus: %@", focus]];
}

- (BOOL)referenceWindow:(RAReferenceWindow *)window handleKeyDownEvent:(NSEvent *)event
{
    (void)window;
    GSVVimBindingController *controller = [self activeController];
    if (controller == nil || !controller.isEnabled) {
        return NO;
    }

    BOOL handled = [controller handleKeyEvent:event];
    if (handled) {
        [self refreshStatus];
    }
    return handled;
}

- (void)textViewDidChangeSelection:(NSNotification *)notification
{
    (void)notification;
    [self refreshStatus];
}

- (void)vimBindingController:(GSVVimBindingController *)controller
               didChangeMode:(GSVVimMode)mode
                 forTextView:(NSTextView *)textView
{
    (void)controller;
    (void)mode;
    (void)textView;
    [self refreshStatus];
}

@end
