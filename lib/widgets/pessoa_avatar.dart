import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'remote_foto.dart';

/// Avatar circular com fitinha preta de luto quando [falecido] é true.
/// Sempre viewport quadrado + [BoxFit.cover] (nunca estica a foto).
class PessoaAvatar extends StatelessWidget {
  const PessoaAvatar({
    required this.radius,
    this.fotoUrl,
    this.fotoBytes,
    this.falecido = false,
    this.isPet = false,
    super.key,
  });

  final double radius;
  final String? fotoUrl;
  final Uint8List? fotoBytes;
  final bool falecido;
  final bool isPet;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final hasBytes = fotoBytes != null;
    final hasUrl = fotoUrl != null && fotoUrl!.isNotEmpty;
    final placeholder = Icon(
      isPet ? Icons.pets : Icons.person,
      color: isPet ? AppColors.dourado : AppColors.roxo,
      size: radius * 0.9,
    );

    final Widget face = SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: hasBytes
            ? Image.memory(
                fotoBytes!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : hasUrl
                ? RemoteFoto.avatar(
                    url: fotoUrl!,
                    size: size,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: const Color(0xFFF0EAF5),
                      child: Center(child: placeholder),
                    ),
                  )
                : ColoredBox(
                    color: const Color(0xFFF0EAF5),
                    child: Center(child: placeholder),
                  ),
      ),
    );

    if (!falecido) return face;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          face,
          Positioned(
            left: 0,
            top: 0,
            child: ClipPath(
              clipper: _FitinhaClipper(),
              child: Container(
                width: size * 0.55,
                height: size * 0.55,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FitinhaClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
