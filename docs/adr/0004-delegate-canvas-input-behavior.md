# Delegate canvas input behavior to feature owners

Status: deferred

Date: 2026-11-09

The proposal and migration are deferred. Before resuming, evaluate the
[alternative completion contract](#alternative-to-explore) and revise the
decision and plan to match the chosen contract. The decision below retains the
original proposal; it is not accepted architecture.

## Context

`CanvasInput` correctly owns pointer admission and cross-element arbitration, but
it also contains shape-label and empty-canvas double-click recognition, arrow
body dragging, marquee and eraser mechanics, placement dispatch, and editing
decisions based on concrete element types. `CanvasInputTarget` already binds
generic activation, movement, transforms, and operation completion to a live
element. Element views and retained resources own some, but not all, of their
own tap and editing behavior.

That split makes a local feature change depend on central pointer state and
repeated tool checks. Moving behavior without preserving the existing host-to-root
pointer route, native editor gestures, stale-target guards, and history grouping
could instead create double dispatch, delayed activation, or lost native text
selection.

The accepted [interaction model](../specs/interaction-model.md),
[editor lifecycle contract](../arch/editor-lifecycles.md), and
[ownership contract](../arch/ownership.md) remain authoritative. This ADR
proposes an ownership change without changing saved values or accepted user
behavior. The [input delegation migration plan](../plans/input-delegation.md)
defines the implementation sequence and its evidence requirements.

## Decision

Keep `CanvasInput` as the single owner of enabled state, device and button
admission, pointer ownership, blocked held pointers, navigation precedence,
stale callback generations, and common cross-element selection, group movement,
Auto promotion, and history orchestration. Keep `CanvasInputTarget` as the
concrete, cached-per-element binding for those common accepted operations.

Separate arbitration from feature behavior. Preserve the existing child-host-root
event path and register a hit role (`body`, `native field`, or `control`) before
the root accepts a pointer sequence. The root admits and routes down once, captures
the recipient, and retains that sequence until accepted completion, regardless of
whether completion occurs before or after root raw up. Ordinary recognizer-based
body callbacks typically complete after root up. The inactive Code preview is
the known exception: its child raw listener calls its edit action synchronously
on child raw up, before ancestor/root raw up.

Expose `completeTap(action, {PointerUpEvent? up})`. Ordinary `GestureDetector.onTap`
callers omit `up` and use the router's captured root up; Code preview forwards its
actual child `PointerUpEvent`. Validate supplied events against the admitted
pointer, down, target, and generation; record the same physical release
idempotently and never fabricate an event. Invoke the accepted feature action
synchronously in its original Flutter callback, then finish once unless the
session remains logically editing. If the child callback completes first, later
root up only releases bookkeeping and cannot redispatch or fall through; if root
up arrives first, retain the sequence until the accepted callback. This preserves
trusted user-gesture context for media actions. One-shot output may terminalize
the captured route first; it still consumes the matching release but does not
require an up callback.

A control or native field takes precedence over an enclosing body. Native fields
keep Flutter's pointer handling; the canvas may observe them for shared policy
but must not synthesize a body tap or take native text selection. Code's role is
state- and surface-dependent: inactive source/title preview is `body`, even when
rendered by a read-only `CodeEditor`, and its existing raw preview listener owns
activation/drag and cancels transient `re_editor` selection. Active editable
source/title is `native field`; caret, selection, IME, and native interaction
remain untouched. Do not classify all `CodeEditor` widgets as fields. Interruption
blocks the held pointer until release and does not hand the gesture to another
recipient.

This root route covers only the viewport inside
`CanvasView._buildCanvasViewport`'s `Overlay.wrap`: its body, native fields, and
viewport controls. `CanvasPage` supplies `widget.chromeBuilder`; `CanvasView`
inserts its output as a sibling of `LazyCanvas` in `CanvasView`'s `Stack`, outside
the grid raw listener. Page options,
toolbar, and menus remain native UI controls; their existing UI-gated callbacks
issue generic notifications through composition/current cached target, not raw
canvas routes. Add no global listener or grid callback for page chrome.

Element views and their existing resources own feature-local tap, edit, and
control policy. `CanvasInputTarget` retains common activation and non-pointer
admission, adds one admitted body-tap callback carrying the captured raw down/up
events, and exposes narrow optional interruption, control-press, and end-editing
callbacks. `CanvasView` configures these callbacks from existing feature owners
and uses its existing target cache to fan out lifecycle notifications. Do not add
an element-handler hierarchy or a second registry.

Route the closed `CanvasTool` set through one exhaustive binding lookup
definition. Down captures the sequence binding; idle hover/exit uses the current
tool's optional callback without fabricating a down. Keep concrete creation tools
owned by `CanvasInput`; move empty
Select marquee and quick-text policy to `SelectTool`, and eraser hit-test/remove
sampling to `EraserTool`. Keep placement factories in the view that already owns
them. Use raw Flutter pointer events as the shared binding input and convert
coordinates only at the existing feature boundaries.

Keep arrow body tap and pan behavior in `ArrowElementView`, while retaining
path-level painter hit testing and common target movement. Keep shape double-click
recognition in `ShapeEditorResources`; share only the timing and distance
predicate with Select's empty-canvas quick-text behavior. Do not delay the first
tap or use a Flutter double-tap recognizer that defers it.

## Alternatives

- Keep all feature policy in `CanvasInput`: rejected because feature behavior
  would continue to require central type checks and shared transient state.
- Add a polymorphic input-handler hierarchy for every element: rejected because
  `CanvasInputTarget` already supplies the required common binding, while each
  feature needs only a few callbacks.
- Replace the child-host-root route or change `infinite_lazy_grid` or Flutter:
  rejected because the current route supplies the needed raw events and the grid
  has no takeover contract. Ordering-sensitive changes must first be proved by
  focused tests; no dependency or platform change is proposed.
- Route all input through one synthesized event model: rejected because pen
  sampling needs raw pressure events and native fields must retain Flutter's
  gestures and text selection.

### Alternative to explore

Keep the proposed routing and feature ownership boundaries, but separate
activation, pointer completion, and history completion. The rule is: the input
path that accepts an action owns its completion. Activation must not change its
completion behavior depending on whether it runs inside `completeTap`.

- `activate` performs common activation and Auto promotion without finishing a
  pointer sequence. Preserve the guards required before running a post-activation
  action. Feature owners retain focus, editing, and media policy.
- `completeTap` validates the captured pointer sequence and marks the tap action
  consumed before invoking the feature action synchronously. It then finalizes
  only that captured action; a reentrant callback cannot finish a newer sequence.
  Activation does not need a flag or calling-context check to suppress finishing.
- Keyboard and semantics actions use an explicit command path with their existing
  admission checks and completion boundary. They do not fabricate pointer events
  or require a pointer sequence.
- Pointer route retirement and history completion are separate decisions. Once
  the action is settled and root release is observed, retire the route even if
  logical editing continues. Keep an ongoing typing group open; otherwise close
  the completed operation under the existing history rules.

```text
Viewport hit registration
          |
          v
Root admits once and captures recipient
          |
          v
completeTap(action)                 Keyboard / semantics command
  validate + consume once            check command eligibility
          |                                   |
          +----------------+------------------+
                           |
                           v
                  Synchronous feature action
                    activate + promote
                    local focus/edit/media policy
                           |
                           v
                  Return to the accepting path
                    pointer: settle captured action,
                             consume release, retire route
                    command: finish command

History: keep typing group open while editing continues;
         otherwise close the completed operation.
```

Both callback orders remain necessary: the inactive Code preview acts before
root raw up, while an ordinary body recognizer may act afterward. Early
completion leaves the matching release consumed; root up arriving first retains
the captured route for the accepted callback. Root up alone must not activate or
open an object. Native fields retain Flutter input, and media launch stays
synchronous in its trusted callback with the existing launch guards.

This alternative is not implemented or proven. Before adopting it, trace every
caller relying on implicit completion, including `interact`, Markdown links,
native editors, picker controls, and keyboard/semantics actions. Prove both
callback orders, exactly-once action delivery, stale and reentrant callback
rejection, cancellation, and history grouping with focused browser tests. Then
revise the migration plan; its current steps describe the original contract.

## Consequences

Feature owners gain a small amount of local callback wiring, while the router
keeps the safety and cross-element rules that must stay uniform. The migration
must preserve immediate activation, native field behavior, Auto promotion,
selection, operation boundaries, culling and restoration lifetimes, and media
launch guards. It must not change document schemas, persistence, tool history,
touch support, or the grid/Flutter dependency contract.

The proposal is not authorization to implement. Until accepted, current
architecture and behavior documents remain the contract. If source behavior,
event-role order, or grid delivery contradicts this decision, stop and resolve
that discrepancy before changing the design. See the
[deferred migration plan](../plans/input-delegation.md).
