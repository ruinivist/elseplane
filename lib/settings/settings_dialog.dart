// Provides the application settings dialog and its local editing state.
// Used by the canvas shell to configure appearance and transfer projects.

import 'dart:async';
import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------- Dialog ----------

/// Presents application, canvas, and project transfer settings.
/// Opened from the canvas workspace settings action.
class SettingsDialog extends StatefulWidget {
  // ---------- Construction ----------

  const SettingsDialog({
    this.themeMode = ThemeMode.light,
    this.onSurfaceStyleChanged,
    this.onThemeModeChanged,
    this.canvasBackgroundKind = CanvasBackgroundKind.dotGrid,
    this.onCanvasBackgroundChanged,
    this.onImport,
    this.onExportCanvas,
    this.onExportLibrary,
    this.syncContent,
    this.openSync = false,
    super.key,
  });

  final ThemeMode themeMode;

  /// Enables surface-style selection; null omits its control.
  final Future<void> Function(SurfaceStyle)? onSurfaceStyleChanged;

  /// Enables theme selection; null omits its control.
  final Future<void> Function(ThemeMode)? onThemeModeChanged;
  final CanvasBackgroundKind canvasBackgroundKind;
  final ValueChanged<CanvasBackgroundKind>? onCanvasBackgroundChanged;
  final Future<bool> Function()? onImport;
  final Future<bool> Function()? onExportCanvas;
  final Future<bool> Function()? onExportLibrary;
  final Widget? syncContent;
  final bool openSync;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

// ---------- Sections ----------

enum _SettingsSection { about, appearance, canvas, sync }

class _SettingsDialogState extends State<SettingsDialog> {
  static const _contentPadding = EdgeInsets.fromLTRB(16, 24, 16, 16);
  static const _aboutLogo = SvgAssetLoader('assets/brand/elseplane-logo.svg');
  static const _repositoryUrl = 'https://github.com/ruinivist/elseplane';
  static const _gitSha = String.fromEnvironment('GIT_SHA');

  // ---------- State ----------

  late _SettingsSection _section = widget.openSync && widget.syncContent != null
      ? _SettingsSection.sync
      : _SettingsSection.canvas;
  late ThemeMode _themeMode = widget.themeMode;
  late CanvasBackgroundKind _canvasBackgroundKind = widget.canvasBackgroundKind;
  var _transferActive = false;
  var _themeSaveAttempt = 0;
  var _surfaceSaveAttempt = 0;
  var _linkAttempt = 0;
  var _themeSaveFailed = false;
  var _surfaceSaveFailed = false;
  String? _failedLink;
  ({String message, bool error})? _exportStatus;
  final GlobalKey _exportStatusKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_aboutLogo.loadBytes(context));
  }

  // ---------- Theme selection ----------

  Future<void> _changeTheme(ThemeMode mode) async {
    final attempt = ++_themeSaveAttempt;
    setState(() {
      _themeMode = mode;
      _themeSaveFailed = false;
    });
    try {
      await widget.onThemeModeChanged?.call(mode);
    } on Object {
      if (mounted && attempt == _themeSaveAttempt) setState(() => _themeSaveFailed = true);
    }
  }

  Future<void> _changeSurfaceStyle(SurfaceStyle style) async {
    final attempt = ++_surfaceSaveAttempt;
    setState(() => _surfaceSaveFailed = false);
    try {
      await widget.onSurfaceStyleChanged?.call(style);
    } on Object {
      if (mounted && attempt == _surfaceSaveAttempt) setState(() => _surfaceSaveFailed = true);
    }
  }

  // ---------- Transfer actions ----------

  Future<T?> _runTransfer<T>(Future<T> Function()? callback) async {
    if (_transferActive || callback == null) return null;
    setState(() => _transferActive = true);
    try {
      return await callback();
    } finally {
      if (mounted) setState(() => _transferActive = false);
    }
  }

  Future<void> _closeAfterTransfer(Future<bool> Function()? callback) async {
    final completed = await _runTransfer(callback);
    if (mounted && completed == true) Navigator.of(context).pop();
  }

  Future<void> _export(Future<bool> Function()? callback, {required String success, required String failure}) async {
    if (callback == null) return;
    await _runTransfer(() async {
      setState(() => _exportStatus = null);
      try {
        final saved = await callback();
        if (saved) _showExportStatus(success, error: false);
      } on Object {
        _showExportStatus(failure, error: true);
      }
    });
  }

  void _showExportStatus(String message, {required bool error}) {
    if (!mounted) return;
    setState(() => _exportStatus = (message: message, error: error));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _exportStatusKey.currentContext;
      if (context == null || ModalRoute.isCurrentOf(context) == false) return;
      Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    });
  }

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(800, math.max(0, viewport.width - 32)).toDouble();
    final height = math.min(540, math.max(0, viewport.height - 32)).toDouble();

    return SurfaceDialog(
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth < 520 ? _compactBody(context) : _wideBody(context),
            ),
            Positioned(top: 16, right: 16, child: _closeButton(context)),
          ],
        ),
      ),
    );
  }

  Widget _closeButton(BuildContext context) => IconButton(
    key: const ValueKey('settings-close'),
    tooltip: 'Close',
    onPressed: () => Navigator.of(context).pop(),
    icon: const Icon(LucideIcons.x),
    style: BSizes.compactIconButtonStyle,
  );

  Widget _wideBody(BuildContext context) {
    final theme = BTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 180,
          child: _navigation(
            context,
            padding: const EdgeInsets.all(16),
          ),
        ),
        _divider(theme),
        Expanded(
          child: SingleChildScrollView(
            padding: _contentPadding,
            child: _sectionContent(context),
          ),
        ),
      ],
    );
  }

  Widget _compactBody(BuildContext context) {
    final theme = BTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalNavigation = constraints.maxWidth >= 480 && widget.syncContent == null;
        final navigation = _navigation(
          context,
          padding: const EdgeInsets.all(16),
          horizontal: horizontalNavigation,
        );
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              navigation,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(
                  height: 25,
                  color: theme.colors.borderSubtle.withValues(alpha: 0.55),
                ),
              ),
              Padding(
                padding: _contentPadding,
                child: _sectionContent(context),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------- Navigation ----------

  Widget _navigation(
    BuildContext context, {
    required EdgeInsets padding,
    bool horizontal = false,
  }) {
    final children = [
      if (widget.onThemeModeChanged != null || widget.onSurfaceStyleChanged != null)
        _navigationItem(
          context,
          section: _SettingsSection.appearance,
          icon: Icons.palette_outlined,
          label: 'Appearance',
        ),
      _navigationItem(
        context,
        section: _SettingsSection.canvas,
        icon: Icons.grid_view,
        label: 'Canvas',
      ),
      if (widget.syncContent != null)
        _navigationItem(
          context,
          section: _SettingsSection.sync,
          icon: Icons.sync,
          label: 'Sync',
        ),
      _navigationItem(
        context,
        section: _SettingsSection.about,
        icon: Icons.info_outline,
        label: 'About',
      ),
    ];

    return Padding(
      padding: padding,
      child: horizontal
          ? Row(
              children: [
                for (final child in children) Expanded(child: child),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
    );
  }

  Widget _navigationItem(
    BuildContext context, {
    required _SettingsSection section,
    required IconData icon,
    required String label,
  }) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    final selected = _section == section;
    final foreground = selected ? colors.accent : colors.textPrimary;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? colors.accentSoft : Colors.transparent,
        borderRadius: theme.geo.radiusSmall,
        child: InkWell(
          borderRadius: theme.geo.radiusSmall,
          hoverColor: colors.surfaceHover,
          focusColor: colors.surfaceHover,
          splashColor: colors.surfacePressed,
          onTap: () => setState(() => _section = section),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: theme.typo.body.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Section content ----------

  Widget _divider(BTheme theme) {
    return SizedBox(
      width: 1,
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          child: SizedBox(
            width: 1,
            height: constraints.maxHeight * 0.75,
            child: ColoredBox(
              color: theme.colors.borderSubtle.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionContent(BuildContext context) {
    return switch (_section) {
      _SettingsSection.about => _aboutContent(context),
      _SettingsSection.appearance => _appearanceContent(context),
      _SettingsSection.canvas => _canvasContent(context),
      _SettingsSection.sync => widget.syncContent!,
    };
  }

  Widget _appearanceContent(BuildContext context) {
    final theme = BTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.onSurfaceStyleChanged != null) ...[
          Text('Surface style', style: theme.typo.label),
          const SizedBox(height: 10),
          Select<SurfaceStyle>(
            key: const ValueKey('surface-style-select'),
            value: theme.surfaceStyle,
            options: const [
              SelectOption(value: SurfaceStyle.solid, label: 'Solid'),
              SelectOption(value: SurfaceStyle.glass, label: 'Glass'),
            ],
            onChanged: _changeSurfaceStyle,
          ),
          if (_surfaceSaveFailed) _status(theme, 'Could not save surface style preference.'),
        ],
        if (widget.onSurfaceStyleChanged != null && widget.onThemeModeChanged != null) const SizedBox(height: 20),
        if (widget.onThemeModeChanged != null) ...[
          Text('Theme', style: theme.typo.label),
          const SizedBox(height: 10),
          Select<ThemeMode>(
            key: const ValueKey('theme-select'),
            value: _themeMode,
            options: const [
              SelectOption(value: ThemeMode.light, label: 'Light'),
              SelectOption(value: ThemeMode.dark, label: 'Dark'),
            ],
            onChanged: _changeTheme,
          ),
          if (_themeSaveFailed) _status(theme, 'Could not save theme preference.'),
        ],
      ],
    );
  }

  Widget _aboutContent(BuildContext context) {
    final theme = BTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SvgPicture(
          _aboutLogo,
          width: 80,
          height: 80,
          semanticsLabel: 'elseplane logo',
        ),
        const SizedBox(height: 20),
        Text('elseplane', style: theme.typo.heading),
        const SizedBox(height: 20),
        _aboutLink(context, label: 'GitHub', url: _repositoryUrl),
        const SizedBox(height: 20),
        if (_gitSha.isEmpty)
          Text(
            'Development build',
            style: theme.typo.body.copyWith(color: theme.colors.textSecondary),
          )
        else
          _aboutLink(
            context,
            label: 'Build ${_gitSha.substring(0, math.min(7, _gitSha.length))}',
            url: '$_repositoryUrl/commit/$_gitSha',
            muted: true,
          ),
      ],
    );
  }

  Widget _aboutLink(BuildContext context, {required String label, required String url, bool muted = false}) {
    final theme = BTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            foregroundColor: muted ? theme.colors.textSecondary : null,
          ),
          onPressed: () => _openAboutLink(url),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(decoration: TextDecoration.underline)),
              const SizedBox(width: 8),
              const Icon(Icons.north_east, size: BSizes.defaultIconSize),
            ],
          ),
        ),
        if (_failedLink == url) _status(theme, 'Could not open link'),
      ],
    );
  }

  Future<void> _openAboutLink(String url) async {
    final attempt = ++_linkAttempt;
    setState(() => _failedLink = null);
    try {
      if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) return;
    } on Exception {
      // Failed and unavailable platform launchers use the same feedback.
    }
    if (mounted && attempt == _linkAttempt) setState(() => _failedLink = url);
  }

  Widget _status(BTheme theme, String message, {bool error = true, Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.only(top: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: theme.typo.body.copyWith(color: error ? theme.colors.destructive : theme.colors.textSecondary),
      ),
    ),
  );

  Widget _canvasContent(BuildContext context) {
    final theme = BTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Background',
          style: theme.typo.label,
        ),
        const SizedBox(height: 10),
        Select<CanvasBackgroundKind>(
          key: const ValueKey('canvas-background-select'),
          value: _canvasBackgroundKind,
          options: const [
            SelectOption(
              value: CanvasBackgroundKind.dotGrid,
              label: 'Dot grid',
            ),
            SelectOption(value: CanvasBackgroundKind.plain, label: 'Plain'),
          ],
          onChanged: (kind) {
            setState(() => _canvasBackgroundKind = kind);
            widget.onCanvasBackgroundChanged?.call(kind);
          },
        ),
        const SizedBox(height: 20),
        Text(
          'Data',
          style: theme.typo.label,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('canvas-import-button'),
              onPressed: _transferActive || widget.onImport == null ? null : () => _closeAfterTransfer(widget.onImport),
              child: const Text('Import'),
            ),
            OutlinedButton(
              key: const ValueKey('canvas-export-button'),
              onPressed: _transferActive || widget.onExportCanvas == null
                  ? null
                  : () => _export(
                      widget.onExportCanvas,
                      success: 'Canvas exported',
                      failure: 'Could not export canvas',
                    ),
              child: const Text('Export current canvas'),
            ),
            OutlinedButton(
              key: const ValueKey('library-export-button'),
              onPressed: _transferActive || widget.onExportLibrary == null
                  ? null
                  : () => _export(
                      widget.onExportLibrary,
                      success: 'Library exported',
                      failure: 'Could not export library',
                    ),
              child: const Text('Export library'),
            ),
          ],
        ),
        if (_exportStatus case final status?)
          _status(theme, status.message, error: status.error, key: _exportStatusKey),
      ],
    );
  }
}
