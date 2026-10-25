// Provides themed select and searchable-select controls with overlay menus.
// Used by settings and canvas element option panels.

import 'dart:math' as math;

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/menu_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------- Models ----------

/// Describes one value and label in a select menu.
/// Used by both standard and searchable select controls.
@immutable
class SelectOption<T> {
  const SelectOption({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

// ---------- Geometry ----------

const _selectMinimumWidth = 160.0;
const _selectTriggerHeight = 36.0;
const _selectTriggerHorizontalPadding = 16.0;
const _selectTriggerIconSize = 16.0;
const _selectOptionVerticalPadding = 10.0;

// ---------- Shared rendering ----------

SelectOption<T>? _findOption<T>(List<SelectOption<T>> options, T value) {
  for (final option in options) {
    if (option.value == value) return option;
  }
  return null;
}

double _selectPreferredWidth<T>(
  BuildContext context,
  List<SelectOption<T>> options,
  TextStyle textStyle,
) {
  var widestLabel = 0.0;
  for (final option in options) {
    widestLabel = math.max(
      widestLabel,
      TextPainter.computeWidth(
        text: TextSpan(text: option.label, style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      ),
    );
  }
  return math.max(
    _selectMinimumWidth,
    widestLabel + _selectTriggerHorizontalPadding * 2 + _selectTriggerIconSize,
  );
}

WidgetStateProperty<Color?> _selectForegroundColor(BColors colors) {
  return WidgetStateProperty.resolveWith((states) {
    return states.contains(WidgetState.disabled) ? colors.textPrimary.withValues(alpha: 0.38) : colors.textPrimary;
  });
}

ButtonStyle _selectTriggerStyle({
  required BTheme theme,
  required bool showBorder,
  required double width,
  required bool compact,
}) {
  final colors = theme.colors;
  return ButtonStyle(
    foregroundColor: _selectForegroundColor(colors),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return colors.surface;
      if (states.contains(WidgetState.pressed)) return colors.surfacePressed;
      if (states.contains(WidgetState.hovered)) {
        return colors.surfaceHover;
      }
      return colors.surface;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (!showBorder) return const BorderSide(color: Colors.transparent);
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: colors.borderSubtle.withValues(alpha: 0.38));
      }
      return BorderSide(color: colors.borderSubtle);
    }),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: theme.geo.radiusMedium),
    ),
    textStyle: WidgetStatePropertyAll(theme.typo.body),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: compact ? 8 : _selectTriggerHorizontalPadding,
        vertical: 6,
      ),
    ),
    fixedSize: WidgetStatePropertyAll(
      Size(width, compact ? 32 : _selectTriggerHeight),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    alignment: Alignment.centerLeft,
  );
}

ButtonStyle _selectOptionStyle({
  required BTheme theme,
  required bool isSelected,
  required bool isHighlighted,
}) {
  final colors = theme.colors;
  return ButtonStyle(
    foregroundColor: _selectForegroundColor(colors),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (isHighlighted) return colors.surfaceHover;
      if (isSelected || states.contains(WidgetState.pressed)) return colors.surfacePressed;
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
        return colors.surfaceHover;
      }
      return Colors.transparent;
    }),
    textStyle: WidgetStatePropertyAll(theme.typo.body),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: _selectOptionVerticalPadding),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    alignment: Alignment.centerLeft,
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: theme.geo.radiusSmall),
    ),
  );
}

Widget _buildSelectTrigger({
  required GlobalKey triggerKey,
  required FocusNode focusNode,
  required MenuController controller,
  required bool enabled,
  required String label,
  required String keyPrefix,
  required BTheme theme,
  required bool showBorder,
  required double width,
  required bool compact,
}) {
  return Semantics(
    key: triggerKey,
    container: true,
    button: true,
    enabled: enabled,
    expanded: controller.isOpen,
    child: CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (enabled && !controller.isOpen) controller.open();
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (enabled && !controller.isOpen) controller.open();
        },
      },
      child: TextButton(
        key: ValueKey('$keyPrefix-trigger'),
        clipBehavior: Clip.antiAlias,
        onPressed: enabled ? () => controller.isOpen ? controller.close() : controller.open() : null,
        focusNode: focusNode,
        style: _selectTriggerStyle(
          theme: theme,
          showBorder: showBorder,
          width: width,
          compact: compact,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: _selectTriggerIconSize,
              color: theme.colors.textPrimary,
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildSelectOption<T>({
  required SelectOption<T> option,
  required int index,
  required T value,
  required FocusNode? focusNode,
  required ValueChanged<T>? onChanged,
  required BTheme theme,
  required String keyPrefix,
  bool isHighlighted = false,
  bool requestFocusOnHover = true,
}) {
  final isSelected = option.value == value;
  return Semantics(
    container: true,
    selected: isSelected,
    focused: isHighlighted ? true : null,
    inMutuallyExclusiveGroup: true,
    child: MenuItemButton(
      key: ValueKey('$keyPrefix-option-$index'),
      focusNode: focusNode,
      requestFocusOnHover: requestFocusOnHover,
      onPressed: () => onChanged?.call(option.value),
      semanticsLabel: option.label,
      style: _selectOptionStyle(theme: theme, isSelected: isSelected, isHighlighted: isHighlighted),
      child: Text(option.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

// ---------- Select ----------

/// Provides a keyboard-accessible anchored menu for a fixed option list.
/// Used by editor settings with compact enumerated choices.
class Select<T> extends StatefulWidget {
  // ---------- Construction ----------

  const Select({
    required this.value,
    required this.options,
    required this.onChanged,
    this.showBorder = true,
    super.key,
  });

  final T value;
  final List<SelectOption<T>> options;
  final ValueChanged<T>? onChanged;
  final bool showBorder;

  @override
  State<Select<T>> createState() => _SelectState<T>();
}

class _SelectState<T> extends State<Select<T>> {
  // ---------- State ----------

  final _menuController = MenuController();
  final GlobalKey _triggerKey = GlobalKey();
  final _triggerFocusNode = FocusNode();
  late List<FocusNode> _optionFocusNodes;

  bool get _enabled => widget.onChanged != null;
  BTheme get _theme => BTheme.of(context);
  TextStyle get _textStyle => _theme.typo.body;
  double get _preferredWidth => _selectPreferredWidth(context, widget.options, _textStyle);

  double get _triggerWidth {
    final renderBox = _triggerKey.currentContext?.findRenderObject();
    return renderBox is RenderBox && renderBox.hasSize ? renderBox.size.width : _preferredWidth;
  }

  // ---------- Lifecycle ----------

  @override
  void initState() {
    super.initState();
    _optionFocusNodes = _newOptionFocusNodes(widget.options.length);
  }

  @override
  void didUpdateWidget(covariant Select<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      for (final node in _optionFocusNodes) {
        node.dispose();
      }
      _optionFocusNodes = _newOptionFocusNodes(widget.options.length);
    }
    if (!_enabled && oldWidget.onChanged != null) {
      _menuController.close();
    }
  }

  List<FocusNode> _newOptionFocusNodes(int count) {
    return List.generate(
      count,
      (i) => FocusNode(debugLabel: 'Select option $i'),
    );
  }

  @override
  void dispose() {
    for (final node in _optionFocusNodes) {
      node.dispose();
    }
    _triggerFocusNode.dispose();
    super.dispose();
  }

  // ---------- Selection ----------

  SelectOption<T>? get _selectedOption => _findOption(widget.options, widget.value);

  void _focusSelectedOption() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_menuController.isOpen) return;
      var index = widget.options.indexWhere(
        (option) => option.value == widget.value,
      );
      if (index < 0 && widget.options.isNotEmpty) index = 0;
      if (index >= 0) _optionFocusNodes[index].requestFocus();
    });
  }

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final selected = _selectedOption;
    return MenuAnchor(
      key: const ValueKey('select-menu'),
      controller: _menuController,
      childFocusNode: _triggerFocusNode,
      onOpen: _focusSelectedOption,
      alignmentOffset: const Offset(0, 4),
      crossAxisUnconstrained: false,
      style: menuShellStyle(width: () => _triggerWidth, alignment: AlignmentDirectional.bottomStart),
      menuChildren: [
        MenuSurface(
          children: [for (var i = 0; i < widget.options.length; i++) _buildOption(widget.options[i], i)],
        ),
      ],
      builder: (context, controller, child) => _buildSelectTrigger(
        triggerKey: _triggerKey,
        focusNode: _triggerFocusNode,
        controller: controller,
        enabled: _enabled,
        label: selected?.label ?? '',
        keyPrefix: 'select',
        theme: _theme,
        showBorder: widget.showBorder,
        width: _preferredWidth,
        compact: false,
      ),
    );
  }

  Widget _buildOption(SelectOption<T> option, int index) {
    return _buildSelectOption(
      option: option,
      index: index,
      value: widget.value,
      focusNode: _optionFocusNodes[index],
      onChanged: widget.onChanged,
      theme: _theme,
      keyPrefix: 'select',
    );
  }
}

// ---------- Searchable select ----------

/// Provides a searchable anchored menu with preferred values.
/// Used by editor settings with long option lists such as font families.
class SearchableSelect<T> extends StatefulWidget {
  // ---------- Construction ----------

  const SearchableSelect({
    required this.value,
    required this.options,
    required this.searchHint,
    required this.onChanged,
    this.onMenuPointerDown,
    this.preferredValues = const [],
    this.showBorder = true,
    super.key,
  });

  final T value;
  final List<SelectOption<T>> options;
  final List<T> preferredValues;
  final String searchHint;
  final ValueChanged<T>? onChanged;
  final ValueChanged<PointerDownEvent>? onMenuPointerDown;
  final bool showBorder;

  @override
  State<SearchableSelect<T>> createState() => _SearchableSelectState<T>();
}

class _SearchableSelectState<T> extends State<SearchableSelect<T>> {
  // ---------- State ----------

  final _menuController = MenuController();
  final GlobalKey _triggerKey = GlobalKey();
  final _triggerFocusNode = FocusNode();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'Searchable select search');
  final _resultsScrollController = ScrollController();
  int? _highlightedIndex;
  String _query = '';

  double get _optionExtent {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: _textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final height = math.max<double>(32, painter.height + _selectOptionVerticalPadding * 2);
    painter.dispose();
    return height;
  }

  bool get _enabled => widget.onChanged != null;
  BTheme get _theme => BTheme.of(context);
  BColors get _colors => _theme.colors;
  TextStyle get _textStyle => _theme.typo.body;
  double get _preferredWidth => 280;

  double get _compactTriggerWidth {
    final label = _selectedOption?.label ?? '';
    return TextPainter.computeWidth(
          text: TextSpan(text: label, style: _textStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        ) +
        32;
  }

  double get _triggerWidth {
    final renderBox = _triggerKey.currentContext?.findRenderObject();
    return renderBox is RenderBox && renderBox.hasSize ? renderBox.size.width : _preferredWidth;
  }

  // ---------- Lifecycle ----------

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void didUpdateWidget(covariant SearchableSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled && oldWidget.onChanged != null) {
      _menuController.close();
    }
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _resultsScrollController.dispose();
    _searchFocusNode.dispose();
    _triggerFocusNode.dispose();
    super.dispose();
  }

  // ---------- Search and selection ----------

  void _handleSearchChanged() {
    if (_query == _searchController.text) return;
    _query = _searchController.text;
    setState(() => _highlightedIndex = null);
    if (_resultsScrollController.hasClients) _resultsScrollController.jumpTo(0);
  }

  void _moveHighlight(int direction) {
    final options = _visibleOptions;
    if (options.isEmpty) return;
    final index = _highlightedIndex == null
        ? (direction > 0 ? 0 : options.length - 1)
        : (_highlightedIndex! + direction).clamp(0, options.length - 1);
    setState(() => _highlightedIndex = index);
    if (!_resultsScrollController.hasClients) return;
    final position = _resultsScrollController.position;
    final top = index * _optionExtent;
    final bottom = top + _optionExtent;
    final offset = top < position.pixels ? top : math.max(position.pixels, bottom - position.viewportDimension);
    _resultsScrollController.jumpTo(offset.clamp(0, position.maxScrollExtent));
  }

  void _confirmHighlight() {
    if (_searchController.value.composing.isValid && !_searchController.value.composing.isCollapsed) return;
    final options = _visibleOptions;
    if (options.isEmpty) return;
    final index = (_highlightedIndex ?? 0).clamp(0, options.length - 1);
    _chooseOption(options[index].value);
  }

  void _chooseOption(T value) {
    _menuController.close();
    widget.onChanged?.call(value);
  }

  void _prepareSearch() {
    _highlightedIndex = null;
    _searchController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_menuController.isOpen) return;
      _searchFocusNode.requestFocus();
    });
  }

  List<SelectOption<T>> get _visibleOptions {
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      return widget.options.where((option) => option.label.toLowerCase().contains(query)).toList()
        ..sort(_compareOptions);
    }

    final preferred = <SelectOption<T>>[];
    for (final value in widget.preferredValues) {
      final option = _findOption(widget.options, value);
      if (option != null && !preferred.any((current) => current.value == value)) {
        preferred.add(option);
      }
    }

    final remaining =
        widget.options
            .where(
              (option) => !preferred.any((current) => current.value == option.value),
            )
            .toList()
          ..sort(_compareOptions);
    return [...preferred, ...remaining];
  }

  int _compareOptions(SelectOption<T> a, SelectOption<T> b) {
    final comparison = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    return comparison == 0 ? a.label.compareTo(b.label) : comparison;
  }

  SelectOption<T>? get _selectedOption => _findOption(widget.options, widget.value);

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final selected = _selectedOption;
    final compact = !widget.showBorder;
    final menuWidth = (compact ? _preferredWidth : _triggerWidth) - 8;
    final visibleOptions = _visibleOptions;
    return MenuAnchor(
      key: const ValueKey('searchable-select-menu'),
      controller: _menuController,
      childFocusNode: _triggerFocusNode,
      onOpen: _prepareSearch,
      alignmentOffset: const Offset(0, 4),
      crossAxisUnconstrained: false,
      style: menuShellStyle(
        alignment: AlignmentDirectional.bottomStart,
        width: () => compact ? _preferredWidth : _triggerWidth,
      ),
      menuChildren: [
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: widget.onMenuPointerDown,
          child: MenuSurface(
            scrollable: false,
            children: <Widget>[
              SizedBox(
                width: menuWidth,
                child: DefaultTextEditingShortcuts(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveHighlight(1),
                      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveHighlight(-1),
                      const SingleActivator(LogicalKeyboardKey.enter): _confirmHighlight,
                      const SingleActivator(LogicalKeyboardKey.numpadEnter): _confirmHighlight,
                      const SingleActivator(LogicalKeyboardKey.escape): _menuController.close,
                    },
                    child: TextField(
                      key: const ValueKey('searchable-select-search'),
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: _textStyle,
                      decoration: InputDecoration(
                        hintText: widget.searchHint,
                        hintStyle: _textStyle.copyWith(color: _colors.textMuted),
                        isDense: true,
                        filled: true,
                        fillColor: _colors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: _theme.geo.radiusSmall,
                          borderSide: BorderSide(color: _colors.borderSubtle),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: _theme.geo.radiusSmall,
                          borderSide: BorderSide(color: _colors.focusRing, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (visibleOptions.isEmpty)
                SizedBox(
                  width: menuWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Text(
                      'No results',
                      style: _textStyle.copyWith(color: _colors.textSecondary),
                    ),
                  ),
                )
              else
                Flexible(
                  child: SizedBox(
                    height: 280,
                    width: menuWidth,
                    child: ListView.builder(
                      controller: _resultsScrollController,
                      itemExtent: _optionExtent,
                      padding: EdgeInsets.zero,
                      primary: false,
                      itemCount: visibleOptions.length,
                      itemBuilder: (_, index) => _buildSearchableOption(visibleOptions[index], index),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      builder: (context, controller, child) => _buildSelectTrigger(
        triggerKey: _triggerKey,
        focusNode: _triggerFocusNode,
        controller: controller,
        enabled: _enabled,
        label: selected?.label ?? '',
        keyPrefix: 'searchable-select',
        theme: _theme,
        showBorder: widget.showBorder,
        width: compact ? _compactTriggerWidth : _preferredWidth,
        compact: compact,
      ),
    );
  }

  Widget _buildSearchableOption(SelectOption<T> option, int index) {
    return _buildSelectOption(
      option: option,
      index: index,
      value: widget.value,
      focusNode: null,
      isHighlighted: index == _highlightedIndex,
      requestFocusOnHover: false,
      onChanged: _chooseOption,
      theme: _theme,
      keyPrefix: 'searchable-select',
    );
  }
}
