import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onComecar, super.key});

  final VoidCallback onComecar;

  static const _onboardingVistoKey = 'onboarding_visto';

  static Future<bool> jaVisto() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingVistoKey) ?? false;
  }

  static Future<void> marcarComoVisto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingVistoKey, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _paginaAtual = 0;

  void _proximo() {
    if (_paginaAtual < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finalizar();
    }
  }

  void _finalizar() async {
    await OnboardingScreen.marcarComoVisto();
    if (mounted) widget.onComecar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (index) {
                  setState(() => _paginaAtual = index);
                },
                children: const [
                  _PaginaOnboarding(
                    icone: Icons.auto_stories_outlined,
                    titulo: 'Preserve histórias',
                    texto: 'Guarde momentos importantes antes que eles se percam.',
                  ),
                  _PaginaOnboarding(
                    icone: Icons.lightbulb_outline,
                    titulo: 'Registre aprendizados',
                    texto:
                        'Conselhos, experiências e lições podem atravessar gerações.',
                  ),
                  _PaginaOnboarding(
                    icone: Icons.favorite_outline,
                    titulo: 'Construa um legado',
                    texto:
                        'Suas memórias podem permanecer vivas para sua família.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _paginaAtual == i
                              ? AppColors.dourado
                              : AppColors.borda,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _proximo,
                    child: Text(_paginaAtual == 2 ? 'Começar' : 'Próximo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaginaOnboarding extends StatelessWidget {
  const _PaginaOnboarding({
    required this.icone,
    required this.titulo,
    required this.texto,
  });

  final IconData icone;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              color: Color(0x26D4A84F),
              shape: BoxShape.circle,
            ),
            child: Icon(icone, size: 48, color: AppColors.dourado),
          ),
          const SizedBox(height: 32),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.roxo,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textoSuave,
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
