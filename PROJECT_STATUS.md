# TextViewVimKit Project Status (2026-02-17)

## Current Snapshot
- GNUstep-first Vim bindings layer is working on both plain `NSTextView` and `NSTextView` subclasses.
- Integration is composition-based through `GSVVimBindingController` + `GSVTextViewAdapter`.
- Build/test toolchain is aligned with project constraints: ARC, GNUstep Make, `tools-xctest` compatibility.
- Reference app exists and is usable for manual UAT with two panes (plain view + subclass fixture).

## What We Have Accomplished

### Core architecture
- Adapter protocol for text operations (`GSVTextEditing`) with engine/controller separation.
- Reusable controller that can attach to any `NSTextView` instance.
- IME/marked-text bypass behavior preserved in controller path.

### Modes
- `NORMAL`
- `INSERT`
- `VISUAL` (characterwise)
- `VISUAL LINE` (linewise)

### Implemented commands/features
- Mode transitions: `i`, `a`, `o`, `O`, `Esc`, `v`, `V`.
- Motions: `h`, `j`, `k`, `l`, `w`, `b`, `e`, `0`, `^`, `$`, `gg`, `G`.
- Operators:
- `d{motion}`, `y{motion}`, `c{motion}`
- `dd`, `yy`, `cc`, `C`, `D`
- Visual operators: `d`, `y`, `c`
- Word text objects:
- `ciw`, `caw`, `diw`, `daw`, `yiw`, `yaw`
- Registers/clipboard:
- Unnamed register put: `p`, `P`
- Explicit system clipboard yank: `"+y...`
- Explicit system clipboard put: `"+p`, `"+P`
- Counts:
- Motion counts (e.g. `3j`)
- Operator counts (e.g. `d2w`, `2dd`)
- Edit counts (e.g. `3x`, `2p`)
- Repeat/undo:
- `.` repeat for core mutating commands currently covered
- `u` undo
- `<C-r>` redo

### Config support
- Primary config: `~/.gnustepvimrc`
- Optional compatibility import: `~/.vimrc`
- Precedence: internal config supersedes `.vimrc`
- Supported directives now:
- `inoremap <lhs> <Esc>` (including your `jk`/`Jk`/`jK`/`JK` mappings)
- `set clipboard=unnamed` / `set clipboard=unnamedplus`

### Testing and quality
- Engine, controller, and config loader tests are in place.
- Latest run status: all tests passing (`GSVVimBindingControllerTests`, `GSVVimConfigLoaderTests`, `GSVVimEngineTests`).

## Roadmap Remaining (Prioritized)

### Batch 1 (recommended next)
- Character-find motions: `f`, `F`, `t`, `T`.
- Find-repeat: `;` and `,`.
- Count support + operator-pending support for those motions (e.g. `d2f,`, `ct)`).
- Dot-repeat coverage for the new change/delete flows.

### Batch 2
- Delimiter/quote text objects:
- `ci"`, `ca"`, `ci'`, `ca'`
- `ci(` / `ca(`, `ci[` / `ca[`, `ci{` / `ca{`
- Matching-delimiter motion `%` (including operator usage).

### Batch 3
- Named registers (`"a`..`"z`) and black-hole register (`"_`).
- Register behavior details (append semantics, etc.) as pragmatic subset.

### Batch 4
- Search primitives: `/`, `?`, `n`, `N`.

### Batch 5 (maintenance / naming)
- Symbol-prefix rebrand pass to align code identifiers with project name.
- Migrate internal/public `GSV...` symbols to a `TVK...`-style prefix with compatibility notes.
- Update tests/docs/examples to match renamed symbols.

### Deferred / out of scope (for now)
- Full Ex commandline (`:w`, `:q`, full `:set` semantics).
- Multi-cursor.

## Known Compatibility Notes / Gaps
- Vim parity is intentionally pragmatic; not all edge cases are implemented yet.
- Dot-repeat is implemented for core changes but not yet for every future command family (to be expanded as batches land).

## Quick Resume Checklist for Tomorrow
1. Build:
```sh
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make
```
2. Run tests:
```sh
export GNUSTEP_USER_ROOT=/tmp/gnustep-user-$USER
mkdir -p "$GNUSTEP_USER_ROOT/Defaults/.lck"
xctest TextViewVimKitTests/TextViewVimKitTests.bundle
```
3. Launch reference app for UAT:
```sh
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
openapp /home/danboyd/git/TextViewVimKit/ReferenceApp/TextViewVimKitReferenceApp.app
```
4. Start with Batch 1 above.
