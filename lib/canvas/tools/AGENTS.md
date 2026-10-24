- the main tool file will have the "tool" suffix
- export the all the other files in the tool suffixed file as well so imports are cleaner. Example: `test_tool.dart` exports classes from
  `text_block_controls.dart` etc.

- Existing models retain presentation resources and read saved values from `EditorSession`. Send edits through named session operations; do not add saved-field or interaction-state writers to a model.
- Creation callbacks return immutable element values. Tools read creation presets from the current session; gesture drafts remain local until the input extraction.
