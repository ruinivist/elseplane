# Superseded interaction notes

Status: historical notes; the accepted
[interaction model](../specs/interaction-model.md) is authoritative.

aim is to have a coherent ux and an intuitive ui
summarises and tries to maintain a coherent interaction model

remmeber, completion before perfection but often we can get CLOSE to perfection for free and just as fast.

# Tasks

## Tools

There are two models we have

- one click to get into a ONE SHOT place, once you place it on canvas the tool gets disabled
  - it makes sense for text, code, media, ( shape, arrow ) => need to move here, they are sticky
- sticky enabled => once you click it's enabled till you disable
  - pen and eraser

## Canvas objects

Clicking

- text, code, media all focus on the editor, there is not select on clicking state. In fact, enabled is different from selected
- shape, arrow => selected
- draw => no action
- eraser => erases at point

Dragging

- text, code, media => depends on where you click but drags, no selection
- shape, arrow => drag but also get selected

Ctrl + click

- always selects

Resizing behavior

- for text you need to go in edit mode
- code has it always
- shape has it on select
- arrow does not have it
- arrow has it on enable

Deleting

- you need to select and then delete
- for text, code, media you must drag select on canvas to make a rectangle to select
- arrow and shapes are click selectable

Customising

- shapes and draw have a top right panel that pops up when they are enabled
- text only has some setting in edit mode, different from the top right panel

Stacking order

- need atleast pin to top and last and then interacting will move them around.

Right click?
spawns a context meny with specific then shared actions
must also make the object "selected"

esc key?

## Individual tool specific questions

### Text

settings are separate from the usual tool specific settings place like draw and shape have
some live preview mode as well?

### Shapes

They def need a fill option

---

some ideas

define a primary action, a click triggers the primary action which for text and editable fields
is to edit

## Superseded ideas

- Delete the last-interacted element to address selection and delete behavior.
- Treat selected, focused, and interacting as separate states. The current
  specification uses active, selected, and editing; the older terminology is
  not a requirement.
