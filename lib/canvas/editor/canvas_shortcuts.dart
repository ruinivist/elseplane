// Dispatches canvas keyboard commands after focused surfaces have priority.
// Used by CanvasView alongside native editor and browser clipboard handlers.

import 'dart:async';

import 'package:elseplane/canvas/editor/canvas_input.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show EditableText, FocusManager, FocusNode, SingleActivator;

// ---------- Keyboard dispatch ----------

class CanvasShortcuts {
  CanvasShortcuts({
    required this.input,
    required this.fieldForFocus,
    required this.macOS,
    required this.enabled,
    required this.blocked,
    required this.currentRoute,
    required this.editing,
    required this.menuOpen,
    required this.foreignMenuOpen,
    required this.nativeClipboard,
    required this.openLibrary,
    required this.arrange,
    required this.copy,
    required this.paste,
    required this.delete,
    required this.closeMenu,
    required this.escape,
    required this.selectAll,
  });

  final CanvasInput input;
  final EditorContext? Function(FocusNode) fieldForFocus;
  FocusNode? _pasteField;
  final bool Function() macOS;
  final bool Function() enabled;
  final bool Function() blocked;
  final bool Function() currentRoute;
  final bool Function() editing;
  final bool Function() menuOpen;
  final bool Function() foreignMenuOpen;
  final bool Function() nativeClipboard;
  final Future<void> Function() openLibrary;
  final void Function({required bool forward, required bool toEnd}) arrange;
  final void Function({required bool cut}) copy;
  final VoidCallback paste;
  final VoidCallback delete;
  final VoidCallback closeMenu;
  final VoidCallback escape;
  final VoidCallback selectAll;

  void invalidatePendingEdits() {
    input.session.invalidatePendingEdits();
    _pasteField = null;
  }

  void focusChanged() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || identical(node, _pasteField)) return;
    final field = fieldForFocus(node);
    if (field != null) {
      input.session.editField(field);
      _pasteField = node;
      return;
    }
    final context = node.context;
    if (context?.widget is EditableText || context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      input.session.editField(null);
      invalidatePendingEdits();
      _pasteField = node;
    }
  }

  bool handle(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final mac = macOS();
    input.modifierPressed.value = mac ? keyboard.isMetaPressed : keyboard.isControlPressed;
    final picker = SingleActivator(LogicalKeyboardKey.keyP, meta: mac, control: !mac).accepts(event, keyboard);
    if (blocked()) return picker;
    if (!enabled() || !currentRoute()) return false;
    final plain =
        event is KeyDownEvent &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed;
    if (!menuOpen() && foreignMenuOpen()) return false;
    if (picker) {
      if (event is KeyDownEvent) unawaited(openLibrary());
      return true;
    }
    final command = mac
        ? keyboard.isMetaPressed && !keyboard.isControlPressed
        : keyboard.isControlPressed && !keyboard.isMetaPressed;
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    if ((!editing() || menuOpen()) && down && command && !keyboard.isAltPressed) {
      final right =
          event.logicalKey == LogicalKeyboardKey.bracketRight ||
          keyboard.isShiftPressed && event.logicalKey == LogicalKeyboardKey.braceRight;
      final left =
          event.logicalKey == LogicalKeyboardKey.bracketLeft ||
          keyboard.isShiftPressed && event.logicalKey == LogicalKeyboardKey.braceLeft;
      if (right || left) {
        arrange(forward: right, toEnd: keyboard.isShiftPressed);
        return true;
      }
    }
    if (menuOpen()) {
      if (event is KeyDownEvent && command && !keyboard.isAltPressed && !keyboard.isShiftPressed) {
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyX || key == LogicalKeyboardKey.keyV) {
          if (nativeClipboard()) return false;
          if (key == LogicalKeyboardKey.keyV) {
            paste();
          } else {
            copy(cut: key == LogicalKeyboardKey.keyX);
          }
          return true;
        }
      }
      if (plain &&
          (event.logicalKey == LogicalKeyboardKey.delete || mac && event.logicalKey == LogicalKeyboardKey.backspace)) {
        delete();
        return true;
      }
      if (plain && event.logicalKey == LogicalKeyboardKey.escape) closeMenu();
      return false;
    }
    if (plain && event.logicalKey == LogicalKeyboardKey.escape) {
      escape();
      return true;
    }
    if (editing()) return false;
    if (down && input.modifierPressed.value && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (keyboard.isShiftPressed) {
        input.redo();
      } else {
        input.undo();
      }
      return true;
    }
    if (event is KeyDownEvent && input.modifierPressed.value && !nativeClipboard()) {
      if (event.logicalKey == LogicalKeyboardKey.keyC || event.logicalKey == LogicalKeyboardKey.keyX) {
        if (input.session.selectedIds.isEmpty) return false;
        copy(cut: event.logicalKey == LogicalKeyboardKey.keyX);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        paste();
        return true;
      }
    }
    if (event is KeyDownEvent && input.modifierPressed.value && event.logicalKey == LogicalKeyboardKey.keyA) {
      selectAll();
      return true;
    }
    if (plain) {
      final tool = switch (event.logicalKey) {
        LogicalKeyboardKey.keyT => CanvasTool.text,
        LogicalKeyboardKey.keyC => CanvasTool.code,
        LogicalKeyboardKey.keyM => CanvasTool.media,
        LogicalKeyboardKey.keyS => CanvasTool.shape,
        LogicalKeyboardKey.keyP => CanvasTool.pen,
        LogicalKeyboardKey.keyE => CanvasTool.eraser,
        LogicalKeyboardKey.keyA => CanvasTool.arrow,
        _ => null,
      };
      if (tool != null) {
        input.toggleTool(tool);
        return true;
      }
    }
    if (down &&
        (event.logicalKey == LogicalKeyboardKey.delete || mac && event.logicalKey == LogicalKeyboardKey.backspace)) {
      delete();
      return true;
    }
    if ((input.session.tool != CanvasTool.pen && input.session.tool != CanvasTool.eraser) ||
        event.logicalKey != LogicalKeyboardKey.space) {
      return false;
    }
    input.spaceHeld = event is! KeyUpEvent;
    return true;
  }
}
