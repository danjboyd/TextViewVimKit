# TextViewVimKit

Reusable Vim-style key bindings for GNUstep/Cocoa text editing, designed to attach to any `NSTextView` or `NSTextView` subclass.

## Status
- GNUstep-first implementation.
- Works on plain `NSTextView` and subclass fixtures.
- Pragmatic Vim subset (not full Vim runtime parity).
- Reusable Ex action dispatch for host-provided save/quit behavior.

## What This Library Provides
- Modal editing engine: `NORMAL`, `INSERT`, `VISUAL`, `VISUAL LINE`.
- `NSTextView` integration controller (`GSVVimBindingController`).
- Text adapter boundary (`GSVTextEditing`) for reusable engine logic.
- Config loading with precedence:
- `~/.gnustepvimrc` (primary)
- optional `~/.vimrc` compatibility import (lower priority)

## Supported Feature Subset (Current)
- Modes: `i`, `a`, `o`, `O`, `Esc`, `v`, `V`.
- Motions: `h`, `j`, `k`, `l`, `w`, `b`, `e`, `0`, `^`, `$`, `gg`, `G`.
- Operators: `d{motion}`, `y{motion}`, `c{motion}`, plus `dd`, `yy`, `cc`, `C`, `D`.
- Word text objects: `ciw`, `caw`, `diw`, `daw`, `yiw`, `yaw`.
- Put/yank registers:
- unnamed register: `p`, `P`
- explicit clipboard register: `"+y...`, `"+p`, `"+P`
- Counts: examples `3j`, `d2w`, `2dd`, `3x`, `2p`.
- Repeat/undo/redo: `.`, `u`, `<C-r>`.
- Ex command-line capture from `:` in normal mode.
- Parsed Ex actions: `:w`, `:q`, `:wq`, `:x`, plus `!` force suffix variants.
- Command-line keys: `<Esc>` cancels, `<Enter>` dispatches.

## Integrating Into Your App

### 1. Add source files
Add `src/*.h` and `src/*.m` to your target, and link AppKit/Foundation.

### 2. Create a controller per text view
```objc
#import "GSVVimBindingController.h"
#import "GSVVimConfigLoader.h"

self.vimController = [[GSVVimBindingController alloc] initWithTextView:self.textView];
self.vimController.delegate = self;
self.vimController.config = [GSVVimConfigLoader loadDefaultConfig];
```

### 3. Forward key events
Forward key-down events to the controller before normal handling.

Example from a window-level event hook:
```objc
- (void)sendEvent:(NSEvent *)event
{
    if ([event type] == NSKeyDown) {
        NSTextView *activeTextView = (NSTextView *)[self firstResponder];
        if ([activeTextView isKindOfClass:[NSTextView class]]) {
            GSVVimBindingController *controller = [self controllerForTextView:activeTextView];
            if (controller != nil && controller.isEnabled && [controller handleKeyEvent:event]) {
                return;
            }
        }
    }
    [super sendEvent:event];
}
```

Notes:
- If `handleKeyEvent:` returns `NO`, keep native behavior unchanged.
- IME/marked text is already respected by the controller.

### 4. (Optional) Handle Ex actions in your host app
If your app should support `:w`, `:q`, `:wq`, and `:x`, implement the optional delegate callback.

```objc
- (BOOL)vimBindingController:(GSVVimBindingController *)controller
              handleExAction:(GSVVimExAction)action
                       force:(BOOL)force
                  rawCommand:(NSString *)rawCommand
                 forTextView:(NSTextView *)textView
{
    (void)controller;
    (void)rawCommand;
    (void)textView;

    switch (action) {
        case GSVVimExActionWrite:
            return [self saveCurrentDocument];
        case GSVVimExActionQuit:
            [self closeCurrentDocumentForce:force];
            return YES;
        case GSVVimExActionWriteQuit:
            if (![self saveCurrentDocument]) {
                return NO;
            }
            [self closeCurrentDocumentForce:force];
            return YES;
        case GSVVimExActionUnknown:
        default:
            return NO;
    }
}
```

Notes:
- `force` is `YES` when a trailing `!` is present (for example `:q!`).
- Unknown commands arrive as `GSVVimExActionUnknown`.
- If unknown commands are not handled, the controller emits a beep.

### 5. (Optional) Show command-line/status text
Use the optional status callback to mirror Vim command-line input in your UI.

```objc
- (void)vimBindingController:(GSVVimBindingController *)controller
        didUpdateCommandLine:(NSString *)commandLine
                      active:(BOOL)active
                 forTextView:(NSTextView *)textView;
```

## Configuration
Load defaults:
```objc
GSVVimConfig *config = [GSVVimConfigLoader loadDefaultConfig];
controller.config = config;
```

Current supported config directives:
- `inoremap <lhs> <Esc>`
- `set clipboard=unnamed`
- `set clipboard=unnamedplus`

Example `~/.gnustepvimrc`:
```vim
inoremap jk <ESC>
inoremap Jk <ESC>
inoremap jK <ESC>
inoremap JK <ESC>
set clipboard=unnamed
```

## Build and Test (GNUstep)
Build:
```sh
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make
```

Run tests:
```sh
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
export GNUSTEP_USER_ROOT=/tmp/gnustep-user-$USER
mkdir -p "$GNUSTEP_USER_ROOT/Defaults/.lck"
xctest TextViewVimKitTests/TextViewVimKitTests.bundle
```

Run reference app:
```sh
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
openapp /home/danboyd/git/TextViewVimKit/ReferenceApp/TextViewVimKitReferenceApp.app
```

## Roadmap
See `PROJECT_STATUS.md` for completed work and prioritized next batches.

## License
Following GNUstep's library/tool split:
- Library code (`src/`) is under GNU LGPL v2.1 or later (`COPYING.LIB`).
- Reference app and tests are under GNU GPL v2.0 or later (`COPYING`).
