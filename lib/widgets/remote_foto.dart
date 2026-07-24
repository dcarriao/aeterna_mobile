import 'package:flutter/material.dart';

import '../models/pessoa.dart';

/// Foto remota (Supabase Storage / URL http) decodificada no tamanho de
/// exibição — evita baixar+decodificar originais de vários MB em listas.
///
/// Não usa `cached_network_image` (risco de deps Android). O [ImageCache]
/// do Flutter já guarda o bitmap redimensionado em memória.
class RemoteFoto extends StatelessWidget {
  const RemoteFoto({
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.decodeLogicalWidth,
    this.decodeLogicalHeight,
    this.gaplessPlayback = true,
    super.key,
  });

  /// Avatar circular / miniatura quadrada.
  const RemoteFoto.avatar({
    required this.url,
    required double size,
    this.errorBuilder,
    this.gaplessPlayback = true,
    super.key,
  })  : width = size,
        height = size,
        fit = BoxFit.cover,
        alignment = Alignment.center,
        decodeLogicalWidth = size,
        decodeLogicalHeight = size;

  /// Card de lista (capa ~largura da tela × altura fixa, ou só largura se
  /// [height] for null — ex.: dentro de [AspectRatio]).
  const RemoteFoto.card({
    required this.url,
    this.height = 200,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.errorBuilder,
    this.gaplessPlayback = true,
    super.key,
  })  : width = double.infinity,
        decodeLogicalWidth = null,
        decodeLogicalHeight = null;

  /// Hero / detalhe (contain ou cover, decode limitado à largura da tela).
  const RemoteFoto.hero({
    required this.url,
    this.width = double.infinity,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.gaplessPlayback = true,
    super.key,
  })  : decodeLogicalWidth = null,
        decodeLogicalHeight = null;

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final ImageErrorWidgetBuilder? errorBuilder;
  final double? decodeLogicalWidth;
  final double? decodeLogicalHeight;
  final bool gaplessPlayback;

  /// Provider para [DecorationImage] / [CircleAvatar.backgroundImage].
  static ImageProvider provider(
    BuildContext context,
    String url, {
    required double logicalWidth,
    double? logicalHeight,
  }) {
    final resolvida = PessoaRepository.resolverUrlFoto(url) ?? url;
    return ResizeImage(
      NetworkImage(resolvida),
      width: cachePx(context, logicalWidth),
      height: logicalHeight != null ? cachePx(context, logicalHeight) : null,
    );
  }

  static int? cachePx(BuildContext context, double? logical) {
    if (logical == null || !logical.isFinite || logical <= 0) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Cap evita decode gigante em tablets / telas densas.
    return (logical * dpr).round().clamp(1, 1600);
  }

  @override
  Widget build(BuildContext context) {
    final resolvida = PessoaRepository.resolverUrlFoto(url) ?? url;
    final screenW = MediaQuery.sizeOf(context).width;

    final logicalW = decodeLogicalWidth ??
        (width != null && width!.isFinite ? width! : screenW);
    // Para cards com height fixa e width infinito: passa só cacheWidth
    // (mantém aspect ratio no decode). Avatars passam ambos.
    final logicalH = decodeLogicalHeight != null &&
            decodeLogicalWidth != null &&
            decodeLogicalWidth == decodeLogicalHeight
        ? decodeLogicalHeight
        : null;

    final cw = cachePx(context, logicalW);
    final ch = cachePx(context, logicalH);

    return Image.network(
      resolvida,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      cacheWidth: cw,
      cacheHeight: ch,
      gaplessPlayback: gaplessPlayback,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        final w = width != null && width!.isFinite ? width : null;
        final h = height != null && height!.isFinite ? height : null;
        return ColoredBox(
          color: const Color(0xFFF0EAF5),
          child: SizedBox(width: w, height: h),
        );
      },
      errorBuilder: errorBuilder ??
          (context, error, stackTrace) {
            final w = width != null && width!.isFinite ? width : null;
            final h = height != null && height!.isFinite ? height : null;
            return ColoredBox(
              color: const Color(0xFFF0EAF5),
              child: SizedBox(
                width: w,
                height: h,
                child: const Center(
                  child: Icon(Icons.image_outlined,
                      color: Color(0xFF6B4C8A), size: 28),
                ),
              ),
            );
          },
    );
  }
}
