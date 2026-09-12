import 'package:flutter/material.dart';

import '../../../core/platform/content_access_models.dart' show ContentCategory;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';

/// VoraFind's primary interaction: a large, quiet search field.
///
/// The field is deliberately controlled — the owning screen owns the
/// [TextEditingController], debounce, and query state (Prompts #12/#16 kept the
/// debounce in the screen; the bar stays a presentation widget). Focus animates
/// the border to the accent ring softly (no layout shift, <300ms).
///
/// The trailing filter button opens the type-filter sheet — the search box is
/// the entrance; narrow filter chips live one tap away (design system §10).
class VoraSearchBar extends StatefulWidget {
  const VoraSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    this.onTapFilter,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback? onTapFilter;
  final bool autofocus;

  @override
  State<VoraSearchBar> createState() => _VoraSearchBarState();
}

class _VoraSearchBarState extends State<VoraSearchBar> {
  final _focus = FocusNode();
  late bool _focused;

  @override
  void initState() {
    super.initState();
    _focused = widget.autofocus;
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) _focus.requestFocus();
      });
    }
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focused != _focus.hasFocus) {
      setState(() => _focused = _focus.hasFocus);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = _focused
        ? context.vora.accentRing
        : context.vora.divider;

    return AnimatedContainer(
      duration: VoraDuration.normal,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: context.vora.surface,
        borderRadius: BorderRadius.circular(VoraRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          const SizedBox(width: VoraSpace.lg),
          AnimatedSwitcher(
            duration: VoraDuration.fast,
            child: Icon(
              Icons.search_rounded,
              key: ValueKey(_focused),
              size: 22,
              color: _focused
                  ? context.vora.accent
                  : context.vora.textSecondary,
            ),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: false,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: context.vora.textTertiary,
                ),
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: VoraSpace.md,
                  vertical: 18,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (_, value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: context.vora.textSecondary,
                      tooltip: 'Clear search',
                      onPressed: widget.onClear,
                    );
                  },
                ),
              ),
            ),
          ),
          if (widget.onTapFilter != null) ...[
            _filterButton(context),
            const SizedBox(width: VoraSpace.sm),
          ],
        ],
      ),
    );
  }

  Widget _filterButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.tune_rounded, size: 20),
      color: context.vora.textSecondary,
      tooltip: 'Filter by type',
      onPressed: widget.onTapFilter,
    );
  }
}

/// Shows the type-filter bottom sheet and returns the user's category
/// selection, or null when dismissed without applying.
///
/// Categories are fixed (images/videos/audio/documents). A cleared selection
/// means "all types". The sheet is non-blocking and touch-friendly
/// (design system §62).
Future<Set<ContentCategory>?> showVoraFilterSheet(
  BuildContext context, {
  required Set<ContentCategory> initial,
}) {
  return showModalBottomSheet<Set<ContentCategory>>(
    context: context,
    builder: (_) => _VoraFilterSheet(initial: initial),
  );
}

class _VoraFilterSheet extends StatefulWidget {
  const _VoraFilterSheet({required this.initial});

  final Set<ContentCategory> initial;

  @override
  State<_VoraFilterSheet> createState() => _VoraFilterSheetState();
}

class _VoraFilterSheetState extends State<_VoraFilterSheet> {
  late Set<ContentCategory> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final all = ContentCategory.values;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VoraSpace.xl,
          VoraSpace.lg,
          VoraSpace.xl,
          VoraSpace.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter by type',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _selected = <ContentCategory>{}),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: VoraSpace.sm),
            RadioGroup<ContentCategory>(
              // Multiple selection is intentionally limited to one type per
              // search; "Screenshots/Documents" live on Explore (design
              // system §21).
              groupValue: _selected.isEmpty ? null : _selected.first,
              onChanged: (value) => setState(() {
                if (value == null) return;
                _selected = {value};
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final category in all)
                    RadioListTile<ContentCategory>(
                      value: category,
                      title: Text(_label(category)),
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(VoraRadius.md),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: VoraSpace.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? () => Navigator.pop(context, <ContentCategory>{})
                    : () => Navigator.pop(context, _selected),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(ContentCategory category) => switch (category) {
    ContentCategory.images => 'Images',
    ContentCategory.videos => 'Videos',
    ContentCategory.audio => 'Audio',
    ContentCategory.documents => 'Documents',
  };
}
