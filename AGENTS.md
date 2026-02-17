# AGENTS.md

## Mission
Build a reusable Vim-style bindings layer for text editing on GNUstep and Cocoa/AppKit that can attach to any `NSTextView` or `NSTextView` subclass.

## Platform and Tooling Baseline
- Support both GNUstep and macOS AppKit.
- Treat GNUstep compatibility as first priority when behavior or implementation choices differ.
- Require ARC for Objective-C code. Do not introduce manual retain/release patterns.
- Use GNUstep Make (`GNUmakefile`) as the build system.
- Use GNUstep `tools-xctest` for tests (Apple XCTest compatible).

## Product Scope
- Deliver modal editing behavior with a practical Vim-like UX.
- Prioritize safe integration with host text views over strict Vim fidelity.
- Explicitly out of scope for now: multi-cursor editing.
- Ex command support (`:w`, `:q`, `:set`, etc.) is deferred and may remain unimplemented unless explicitly requested.

## Architecture Requirements
- Use composition, not inheritance, as the primary integration model.
- Keep core Vim logic AppKit-agnostic and testable without UI runtime.
- Define a small adapter boundary for text operations needed by Vim behavior.
- Keep widget integration limited to public `NSTextView` APIs.

## Integration Contract for `NSTextView`
- Public install path must accept `NSTextView *` and operate with subclasses.
- Intercept input through standard responder paths (`keyDown:` and `doCommandBySelector:` or equivalent hook points).
- If Vim layer does not handle an event, preserve native behavior unchanged.
- Respect IME/marked-text composition and bypass command interpretation while composing text.
- Preserve undo/redo expectations via host `NSUndoManager`.

## Config Strategy
- Internal config file is the source of truth: `~/.gnustepvimrc`.
- Optional `.vimrc` import is allowed as a compatibility layer only.
- Internal config always supersedes `.vimrc` settings.
- `.vimrc` support should be subset-based, explicit, and diagnostic-driven.
- Unsupported directives must produce clear warnings and never crash or silently corrupt behavior.

## Vim Compatibility Policy
- Follow pragmatic compatibility similar to editor Vim plugins, not full Vim runtime fidelity.
- Prefer predictable behavior and platform correctness over exact edge-case parity.
- When platform behavior conflicts with Vim expectations, document the tradeoff and discuss before broadening complexity.

## Recommended Delivery Phases
- Phase 1: `Normal` + `Insert` modes, essential motions/operators, repeat/undo core.
- Phase 2: `Visual` mode and expanded text objects/operators.
- Phase 3: extended mapping/config compatibility as needed.

## Reference App Requirement
- Maintain a small in-repo reference app for manual validation during development.
- The reference app must include:
- One plain `NSTextView`.
- One custom `NSTextView` subclass fixture.
- A visible Vim mode/status indicator.
- A simple on/off toggle for the Vim binding layer.
- A config path/status indicator for `~/.gnustepvimrc` and `.vimrc` compatibility/import diagnostics.
- Keep the reference app intentionally minimal and stable; use it for smoke tests and behavior demos, not product UI exploration.

## UAT Handoff
- When asking the user to perform UAT, proactively launch the reference app first.
- Default launch command:
- `. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh; make run`
- In UAT notes, include the exact behaviors to verify and which pane(s) to test (plain `NSTextView` and subclass fixture).

## Testing Requirements
- Parser/state-machine tests must run without AppKit UI dependencies.
- Integration tests must validate behavior on plain `NSTextView`.
- Integration tests must include at least one custom `NSTextView` subclass fixture.
- Every fixed behavior regression should add a regression test when feasible.
- If a test cannot be added, include a short rationale in change notes.

## Change Management Rules
- Keep changes incremental and reviewable.
- Do not silently expand scope beyond the current phase.
- For behavior changes, include a brief compatibility note describing expected Vim-like behavior and known deviations.

## Definition of Done
- Works on GNUstep first and remains compatible with AppKit.
- Works on plain `NSTextView` and at least one `NSTextView` subclass fixture.
- Preserves native behavior for unhandled commands/events.
- Honors config precedence (`~/.gnustepvimrc` over `.vimrc` import).
- Includes tests and concise docs for supported subset and known limitations.
