import 'package:flutter/material.dart';

import '../models/pessoa.dart';
import '../models/tipo_relacionamento.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../theme/app_theme.dart';

/// Sprint L — Tela para adicionar uma relação pessoa-pessoa.
///
/// Fluxo:
///   1. Escolher o TIPO da relação (ex: CONJUGE, IRMAO, PAI, MÃE).
///   2. Escolher a OUTRA PESSOA (lista de contatos do mesmo usuário,
///      exceto a origem).
///   3. Confirmar — cria a relação (que vai persistir simetricamente
///      na VIEW `grafo_pessoas_relacionamentos`).
class AdicionarRelacionamentoScreen extends StatefulWidget {
  const AdicionarRelacionamentoScreen({
    required this.pessoaOrigemId,
    required this.pessoaOrigemNome,
    super.key,
  });

  final int pessoaOrigemId;
  final String pessoaOrigemNome;

  @override
  State<AdicionarRelacionamentoScreen> createState() =>
      _AdicionarRelacionamentoScreenState();
}

class _AdicionarRelacionamentoScreenState
    extends State<AdicionarRelacionamentoScreen> {
  List<TipoRelacionamento> _tipos = TIPOS_RELACIONAMENTO_INICIAIS;
  List<Pessoa> _contatos = const [];
  bool _carregando = true;
  bool _salvando = false;

  String? _tipoId;
  int? _outraPessoaId;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final tipos = await PessoaRelacionamentoService.instance.listarTipos();
    final contatos = await PessoaRepository.listar();
    if (mounted) {
      setState(() {
        _tipos = tipos;
        _contatos = contatos
            .where((p) => p.id != widget.pessoaOrigemId)
            .toList();
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Adicionar relação',
            style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(child: CircularProgressIndicator(color: AppColors.roxo))
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9F6F0),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.dourado.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.diversity_3,
                                  color: AppColors.dourado, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Conectando ${widget.pessoaOrigemNome} à família',
                                  style: const TextStyle(
                                    color: AppColors.roxo,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Que relação você quer registrar?',
                          style: TextStyle(
                            color: AppColors.roxo,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _tipos.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final t = _tipos[i];
                              final selecionado = _tipoId == t.id;
                              return Material(
                                color: selecionado
                                    ? const Color(0xFFF9F6F0)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: () =>
                                      setState(() => _tipoId = t.id),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selecionado
                                            ? AppColors.dourado
                                            : AppColors.borda,
                                        width: selecionado ? 1.6 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          selecionado
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked,
                                          color: selecionado
                                              ? AppColors.dourado
                                              : const Color(0xFF9B949D),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                t.rotuloA,
                                                style: const TextStyle(
                                                  color: AppColors.roxo,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              Text(
                                                t.categoria,
                                                style: const TextStyle(
                                                  color: Color(0xFF7A7280),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Com quem?',
                          style: TextStyle(
                            color: AppColors.roxo,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_contatos.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borda),
                            ),
                            child: const Text(
                              'Você precisa cadastrar outra pessoa antes de criar uma relação.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF7A7280),
                                fontSize: 13,
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: 200,
                            child: ListView.separated(
                              itemCount: _contatos.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 4),
                              itemBuilder: (_, i) {
                                final p = _contatos[i];
                                final selecionado = _outraPessoaId == p.id;
                                return Material(
                                  color: selecionado
                                      ? const Color(0xFFF9F6F0)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    onTap: () => setState(
                                        () => _outraPessoaId = p.id),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: selecionado
                                              ? AppColors.dourado
                                              : AppColors.borda,
                                          width: 1.4,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            selecionado
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_unchecked,
                                            color: selecionado
                                                ? AppColors.dourado
                                                : const Color(0xFF9B949D),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${p.nome} (${p.parentesco})',
                                              style: const TextStyle(
                                                color: AppColors.roxo,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _salvando
                                ? null
                                : _tipoId != null && _outraPessoaId != null
                                    ? _salvar
                                    : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.roxo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: _salvando
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check, size: 18),
                            label: const Text('Conectar',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _salvar() async {
    if (_tipoId == null || _outraPessoaId == null) return;
    setState(() => _salvando = true);
    final id = await PessoaRelacionamentoService.instance.criar(
      pessoaAId: widget.pessoaOrigemId,
      pessoaBId: _outraPessoaId!,
      tipo: _tipoId!,
    );
    if (mounted) {
      if (id != null) {
        Navigator.of(context).pop();
      } else {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível criar a relação.')),
        );
      }
    }
  }
}
