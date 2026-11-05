# Shared UI instructions

- Read the [UI architecture](../../docs/arch/ui.md) and
  [documentation map](../../docs/README.md); the accepted
  [interaction model](../../docs/specs/interaction-model.md) governs behavior.
- Keep app-wide Flutter primitives in `common/`; feature-specific widgets stay
  with their owner. Standalone extraction is not a design goal.
- Read semantic values from `BTheme.of(context)` internally. Keep concrete
  palettes, fonts, and syntax themes in `theme/`.
- Expose behavior parameters required by current callers, not speculative
  visual overrides. Ordinary icon/text actions inherit app-theme button states;
  use `SurfaceIconButton` when an action needs its own raised surface.
- Retain shared primitives only with production consumers. Give reusable UI
  widgets annotated previews in `previews/`; shared primitive and preview tests
  belong under `test/ui/`. Canvas-specific controls and tests belong to the
  canvas editor widgets owner.
- Name shared widgets by role (for example `SurfaceIconButton` or
  `LabeledSwitch`); use an import alias only for a real name collision.
