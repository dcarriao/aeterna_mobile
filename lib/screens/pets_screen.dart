// lib/screens/pets_screen.dart
// Sprint S.9.3 — Seção de Pets
//
// Lista somente registros com tipo = 'pet' vinculados ao usuário via
// relação TUTOR (que passa por pessoas_relacionamentos).
// Reutiliza PessoaRepository.listar() + filtra isPet.
// Reutiliza PessoaDetalheScreen para perfil, timeline, memorial.

import 'package:flutter/material.dart';

import '../models/pessoa.dart';
import '../theme/app_theme.dart';
import 'nova_pet_screen.dart';
import 'pessoa_detalhe_screen.dart';

class PetsScreen extends StatefulWidget {
  const PetsScreen({
    required this.onAbrirMemoria,
    this.titulosMemorias = const {},
    super.key,
  });

  final void Function(int memoriaId) onAbrirMemoria;
  final Map<int, String> titulosMemorias;

  @override
  State<PetsScreen> createState() => _PetsScreenState();
}

class _PetsScreenState extends State<PetsScreen> {
  List<Pessoa> _pets     = [];
  bool         _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final sw = Stopwatch()..start();
    print('[PERF] tela=Pets inicio=${DateTime.now().toIso8601String()}');
    setState(() => _carregando = true);
    try {
      final resultados = await Future.wait([
        PessoaRepository.listar(),
        PessoaRepository.listarPessoasComMemorial(),
      ]);
      final todas = resultados[0] as List<Pessoa>;
      final comMemorial = resultados[1] as Set<int>;
      if (mounted) {
        setState(() {
          // Regra: a lista Pets exibe SOMENTE pessoas.tipo = 'pet'.
          // S.9.3.2 — pet com memorial vive no memorial, não na lista.
          _pets = todas
              .where((p) =>
                  p.isPet && !(p.falecido && comMemorial.contains(p.id)))
              .toList();
          _carregando = false;
        });
      }
      print('[PERF] tela=Pets pronta_em_ms=${sw.elapsedMilliseconds}');
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _adicionarPet() async {
    final criado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NovaPetScreen()),
    );
    if (criado == true && mounted) _carregar();
  }

  void _abrirDetalhe(Pessoa pet) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PessoaDetalheScreen(
          pessoa: pet,
          onAbrirMemoria: widget.onAbrirMemoria,
          titulosMemorias: widget.titulosMemorias,
        ),
      ),
    ).then((_) => _carregar());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 44),
        centerTitle: false,
        backgroundColor: AppColors.fundo,
        elevation: 0,
      ),
      bottomNavigationBar: _pets.isEmpty || _carregando
          ? null
          : Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borda)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: FilledButton.icon(
                    onPressed: _adicionarPet,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.roxo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.pets, size: 18),
                    label: const Text('Adicionar pet'),
                  ),
                ),
              ),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _pets.isEmpty
                    ? _EstadoVazio(onAdicionar: _adicionarPet)
                    : ListView(
                        padding:
                            const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16, left: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Meus Pets',
                                  style: TextStyle(
                                    color: AppColors.roxo,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Companheiros que também fazem parte da sua história.',
                                  style: TextStyle(
                                    color: AppColors.textoSuave,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (var i = 0; i < _pets.length; i++) ...[
                            if (i > 0) const SizedBox(height: 12),
                            _PetCard(
                              pet: _pets[i],
                              onTap: () => _abrirDetalhe(_pets[i]),
                            ),
                          ],
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card de pet
// ---------------------------------------------------------------------------

class _PetCard extends StatelessWidget {
  const _PetCard({required this.pet, required this.onTap});

  final Pessoa      pet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE8DC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x062B1747),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFF0EAF5),
                  // S.9.3.1 — a foto do pet é salva como URL do Storage;
                  // antes só base64 era exibido e a foto "não aparecia".
                  backgroundImage: pet.fotoBytes != null
                      ? MemoryImage(pet.fotoBytes!)
                      : (pet.fotoUrl != null
                          ? NetworkImage(pet.fotoUrl!) as ImageProvider
                          : null),
                  child: (pet.fotoBytes == null && pet.fotoUrl == null)
                      ? const Icon(Icons.pets,
                          color: AppColors.dourado, size: 26)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pet.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (pet.falecido)
                            _Chip(texto: 'In memoriam',
                                cor: const Color(0xFF9B949D)),
                          if (!pet.falecido)
                            // S.9.3.1 — "Gato • Siamês" quando informado
                            _Chip(
                                texto: pet.especieRacaLabel ?? 'Pet',
                                cor: AppColors.dourado),
                          if (pet.dataNascimento != null) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.cake_outlined,
                                size: 13,
                                color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(
                              '${pet.dataNascimento!.day.toString().padLeft(2, '0')}/'
                              '${pet.dataNascimento!.month.toString().padLeft(2, '0')}/'
                              '${pet.dataNascimento!.year}',
                              style: const TextStyle(
                                color: Color(0xFF817987),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto, required this.cor});
  final String texto;
  final Color  cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: cor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estado vazio
// ---------------------------------------------------------------------------

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.onAdicionar});
  final VoidCallback onAdicionar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0x26D4A84F),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.pets,
                size: 32, color: AppColors.dourado),
          ),
          const SizedBox(height: 20),
          const Text(
            'Seus pets também merecem ter histórias.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cadastre um pet para incluí-lo em memórias, '
            'fotos e preservar seu legado.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Color(0xFF746D78), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdicionar,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.roxo,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.pets, size: 18),
            label: const Text('Adicionar primeiro pet'),
          ),
        ],
      ),
    );
  }
}
