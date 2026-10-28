# Touch requirements

Touch navigation should feel smooth, predictable, and directly connected to the fingers. Brief, consistent input delay is acceptable when needed to preserve stable motion. Unintended zoom or jumps followed by a correction are failures.

These acceptance requirements supplement the [interaction model](Interaction%20model.md). The grid's standalone tests and the app's integration tests verify them on intermediate rendered frames.

## Expected behavior

| Situation | Expected visible behavior |
| --- | --- |
| Both fingers move together | Smooth pan; zoom stays unchanged. |
| One finger stays still while the other moves | Smooth pan and zoom; the canvas point under the stationary finger stays anchored. |
| Fingers spread or close symmetrically | Smooth zoom around their center; no sideways wobble. |
| Translation and separation change together | Pan and zoom together smoothly, including direction reversals. |
| Fingers rotate without changing separation or center | No canvas movement or zoom. |
| Updates arrive separately | No temporary zoom or jump caused by partially updated finger positions. |
| Fingers meet, lift, or cancel | No jump, invalid transform, lost movement, or accidental editing. Follow the interaction model's takeover and release rules. |
| Zoom reaches a limit | Zoom stays bounded; panning continues and reversing responds smoothly. |

Once a gesture has a usable zoom baseline, a stationary finger's anchor takes precedence over centroid anchoring, including when the other finger moves diagonally. If the gesture starts with coincident contacts, keep zoom unchanged and preserve centroid movement while establishing the initial baseline. Stationary-finger zoom anchoring applies after that baseline exists.

Pan and zoom must work together throughout a gesture. Recognizing one must not prevent a smooth transition to the other.

## Responsiveness

- Allow at most one extra display frame for collecting or recognizing input.
- Apply the same response allowance to stationary and moving fingers.
- During that allowance, retaining the previous stable view is acceptable. Displaying unintended intermediate zoom or movement is not.
- Input delay must stay bounded throughout the gesture; it must not accumulate or turn into stalls and catch-up jumps.
- Identical received input histories must have the same response allowance. Tests must not require the app to anticipate an update that has not arrived.
- Buffer durations and filtering techniques are implementation choices. They must satisfy the visible behavior and response budget above.

## Regression coverage

1. Encode these requirements as assertions on intermediate rendered frames, not only final positions or diagnostic logs. Edge cases at zoom limits and coincident touches must also check every rendered frame during the response allowance. Tool/control handoffs, held-touch pauses, and post-cancellation waits must also check every display frame throughout their observation interval.
2. Exercise paired and staggered updates, both finger delivery orders, and independent input and display clocks. Observe frames before and after the trailing update.
3. Verify that deliberately injected wobble, unwanted zoom, jumps, stalls, overshoot, and invalid transforms make the assertions fail, even when endpoints are correct.
4. Verify that stable motion with an allowed brief delay passes.
5. Run the tests against both the grid and the app. Correct contradictory fixtures without weakening the intended behavior to match the implementation.

The grid owns touch sampling, navigation geometry, and frame timing. App tests additionally verify tool and control handoffs, selection, placement, and undo behavior.
