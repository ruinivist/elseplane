// Provides the application settings dialog and its local editing state.
// Used by the canvas shell to configure appearance and transfer projects.

import 'dart:async';
import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    this.onImportCanvas,
    this.onExportCanvas,
    this.onBackupLibrary,
    this.onRestoreLibrary,
    super.key,
  });

  final ThemeMode themeMode;

  /// Enables surface-style selection; null omits its control.
  final Future<void> Function(SurfaceStyle)? onSurfaceStyleChanged;

  /// Enables theme selection; null omits its control.
  final Future<void> Function(ThemeMode)? onThemeModeChanged;
  final CanvasBackgroundKind canvasBackgroundKind;
  final ValueChanged<CanvasBackgroundKind>? onCanvasBackgroundChanged;
  final Future<bool> Function()? onImportCanvas;
  final Future<void> Function()? onExportCanvas;
  final Future<void> Function()? onBackupLibrary;
  final Future<bool> Function()? onRestoreLibrary;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

// ---------- Sections ----------

enum _SettingsSection { about, appearance, canvas }

class _SettingsDialogState extends State<SettingsDialog> {
  static const _aboutLogo = SvgAssetLoader('assets/brand/elseplane-logo.svg');
  static const _repositoryUrl = 'https://github.com/ruinivist/elseplane';
  static const _gitSha = String.fromEnvironment('GIT_SHA');

  // ---------- State ----------

  _SettingsSection _section = _SettingsSection.canvas;
  late ThemeMode _themeMode = widget.themeMode;
  late CanvasBackgroundKind _canvasBackgroundKind = widget.canvasBackgroundKind;
  var _transferActive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_aboutLogo.loadBytes(context));
  }

  // ---------- Theme selection ----------

  Future<void> _changeTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    try {
      await widget.onThemeModeChanged?.call(mode);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save theme preference.')),
        );
      }
    }
  }

  Future<void> _changeSurfaceStyle(SurfaceStyle style) async {
    try {
      await widget.onSurfaceStyleChanged?.call(style);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save surface style preference.')),
        );
      }
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
    icon: const Icon(Icons.close),
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
            padding: const EdgeInsets.all(16),
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
        final horizontalNavigation = constraints.maxWidth >= 480;
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
                padding: const EdgeInsets.all(16),
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
            showBorder: false,
            onChanged: _changeSurfaceStyle,
          ),
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
            showBorder: false,
            onChanged: _changeTheme,
          ),
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
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        foregroundColor: muted ? theme.colors.textSecondary : null,
      ).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? Colors.transparent : null,
        ),
      ),
      onPressed: () => _openAboutLink(url),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 8),
          const Icon(Icons.north_east, size: BSizes.defaultIconSize),
        ],
      ),
    );
  }

  Future<void> _openAboutLink(String url) async {
    try {
      if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) return;
    } on Exception {
      // Failed and unavailable platform launchers use the same feedback.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open link')),
    );
  }

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
          showBorder: false,
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
            TextButton(
              key: const ValueKey('canvas-import-button'),
              onPressed: _transferActive || widget.onImportCanvas == null
                  ? null
                  : () => _closeAfterTransfer(widget.onImportCanvas),
              child: const Text('Import canvas'),
            ),
            TextButton(
              key: const ValueKey('canvas-export-button'),
              onPressed: _transferActive || widget.onExportCanvas == null
                  ? null
                  : () => _runTransfer(widget.onExportCanvas),
              child: const Text('Export canvas'),
            ),
            TextButton(
              key: const ValueKey('library-backup-button'),
              onPressed: _transferActive || widget.onBackupLibrary == null
                  ? null
                  : () => _runTransfer(widget.onBackupLibrary),
              child: const Text('Back up library'),
            ),
            TextButton(
              key: const ValueKey('library-restore-button'),
              onPressed: _transferActive || widget.onRestoreLibrary == null
                  ? null
                  : () => _closeAfterTransfer(widget.onRestoreLibrary),
              child: const Text('Restore library'),
            ),
          ],
        ),
      ],
    );
  }
}
