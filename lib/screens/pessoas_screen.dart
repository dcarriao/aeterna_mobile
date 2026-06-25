import 'package:flutter/material.dart';

import '../models/pessoa.dart';
import '../theme/app_theme.dart';
import 'nova_pessoa_screen.dart';
import 'pessoa_detalhe_screen.dart';

class PessoasScreen extends StatefulWidget {
  const PessoasScreen({
    required this.onAbrirMemoria,
    super.key,
  });

  final void Function(int memoriaId) onAbrirMemoria;

  @override
  State<PessoasScreen> createState() => _PessoasScreenState();
}

class _PessoasScreenState extends State<PessoasScreen> {
  List<Pessoa> _pessoas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final pessoas = await PessoaRepository.listar();
    if (mounted) setState(() { _pessoas = pessoas; _carregando = false; });
  }

  Future<void> _adicionarPessoa() async {
    final criada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NovaPessoaScreen()),
    );
    if (criada == true && mounted) _carregar();
  }

  void _abrirDetalhe(Pessoa pessoa) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PessoaDetalheScreen(
          pessoa: pessoa,
          onAbrirMemoria: widget.onAbrirMemoria,
        ),
      ),
    ).then((_) => _carregar());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pessoas')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Adicionar pessoa',
        onPressed: _adicionarPessoa,
        backgroundColor: AppColors.dourado,
        foregroundColor: AppColors.roxo,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _pessoas.isEmpty
                    ? _EstadoVazio(onAdicionar: _adicionarPessoa)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                        itemCount: _pessoas.length,
                        itemBuilder: (context, index) {
                          final pessoa = _pessoas[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _PessoaCard(
                              pessoa: pessoa,
                              onTap: () => _abrirDetalhe(pessoa),
                            ),
                          );
                        },
                      ),
          ),
        ),
      ),
    );
  }
}

class _PessoaCard extends StatelessWidget {
  const _PessoaCard({required this.pessoa, required this.onTap});

  final Pessoa pessoa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borda),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFF0EAF5),
                backgroundImage:
                    pessoa.fotoBytes != null ? MemoryImage(pessoa.fotoBytes!) : null,
                child: pessoa.fotoBytes == null
                    ? const Icon(Icons.person, color: AppColors.roxo)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pessoa.nome,
                      style: const TextStyle(
                        color: AppColors.roxo,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (pessoa.apelido != null && pessoa.apelido!.isNotEmpty)
                      Text(
                        pessoa.apelido!,
                        style: const TextStyle(
                          color: Color(0xFF7A7280),
                          fontSize: 13,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x26D4A84F),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        pessoa.parentesco,
                        style: const TextStyle(
                          color: AppColors.dourado,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9B949D)),
            ],
          ),
        ),
      ),
    );
  }
}

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
          const Icon(Icons.people_outline, size: 58, color: AppColors.dourado),
          const SizedBox(height: 20),
          const Text(
            'As histórias ficam mais ricas quando sabemos quem fez parte delas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cadastre familiares e pessoas importantes para conectar '
            'memórias e preservar relações.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF746D78), fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdicionar,
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Adicionar primeira pessoa'),
          ),
        ],
      ),
    );
  }
}
