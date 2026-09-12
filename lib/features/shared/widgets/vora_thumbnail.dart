import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import 'vora_image_cache.dart';

/// Small, theme-aware image thumbnail for indexed content.
///
/// Decodes a bounded PNG preview through [voraImageCacheProvider] (derived
/// data, never persisted, never uploaded). While loading it renders a quiet
/// placeholder; on failure it falls back to [fallback]. Always square with the
/// requested [size]; prefers to stay tiny (48–72 px) so grids scroll fast.
class VoraThumbnail extends ConsumerStatefulWidget {
  const VoraThumbnail({
    super.key,
    required this.contentUri,
    required this.size,
    this.borderRadius = VoraRadius.md,
    required this.fallback,
    this.semanticLabel,
  });

  final String contentUri;
  final double size;
  final double borderRadius;
  final Widget fallback;
  final String? semanticLabel;

  @override
  ConsumerState<VoraThumbnail> createState() => _VoraThumbnailState();
}

class _VoraThumbnailState extends ConsumerState<VoraThumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VoraThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentUri != widget.contentUri) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final bytes = await ref
        .read(voraImageCacheProvider)
        .load(widget.contentUri, maxDimension: 384);
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final placeholder = Semantics(
      image: true,
      label: widget.semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.vora.surfaceElevated,
          borderRadius: radius,
        ),
        child: SizedBox(
          width: widget.size.isFinite ? widget.size : double.infinity,
          height: widget.size.isFinite ? widget.size : double.infinity,
          child: Center(
            child: SizedBox(
              width: VoraIconSize.md,
              height: VoraIconSize.md,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.vora.accent.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );

    final bytes = _bytes;
    final child = (bytes == null || _failed)
        ? (_failed ? widget.fallback : placeholder)
        : ClipRRect(
            borderRadius: radius,
            child: Image.memory(
              bytes,
              width: widget.size.isFinite ? widget.size : double.infinity,
              height: widget.size.isFinite ? widget.size : double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, _, _) => widget.fallback,
            ),
          );

    return Semantics(
      image: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: widget.size.isFinite ? widget.size : double.infinity,
        height: widget.size.isFinite ? widget.size : double.infinity,
        child: child,
      ),
    );
  }
}
