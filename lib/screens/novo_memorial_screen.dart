import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/memorial.dart';
import '../models/pessoa.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class NovoMemorialScreen extends StatefulWidget {
  const NovoMemorialScreen({
    this.pessoaParaVincular,
    this.modoPet = false,
    super.key,
  });

  /// Sprint H — quando aberto a partir de "Criar memorial para esta
  /// pessoa" na PessoaDetalheScreen, pré-preenche o formulário com os
  /// dados da pessoa (nome, parentesco, datas).
  final Pessoa? pessoaParaVincular;

  /// Quando true (ou quando [pessoaParaVincular] é pet): lista e vincula
  /// apenas pets via `memorial_pessoas` (convenção S.9.3).
  final bool modoPet;

  @override
  State<NovoMemorialScreen> createState() => _NovoMemorialScreenState();
}

class _NovoMemorialScreenState extends State<NovoMemorialScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _parentescoController = TextEditingController();
  final _biografiaController = TextEditingController();
  final _picker = ImagePicker();

  DateTime? _dataNascimento;
  DateTime? _dataFalecimento;
  Uint8List? _fotoBytes;
  bool _salvando = false;

  List<Pessoa> _pessoasDisponiveis = [];
  Pessoa? _pessoaSelecionada;
  bool _carregandoPessoas = false;
  Map<int, String> _parentescoPorPessoaId = {};

  bool get _modoPet =>
      widget.modoPet || (widget.pessoaParaVincular?.isPet ?? false);

  @override
  void initState() {
    super.initState();
    // Sprint H — pré-preenchimento a partir de "Criar memorial para esta
    // pessoa" na PessoaDetalheScreen.
    final p = widget.pessoaParaVincular;
    if (p != null) {
      _nomeController.text = p.nome;
      _parentescoController.text = p.parentesco;
      _dataNascimento = p.dataNascimento;
    }
    _carregarPessoas();
    if (p != null) {
      // Pré-seleciona a pessoa no dropdown de vinculação.
      _pessoaSelecionada = p;
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _parentescoController.dispose();
    _biografiaController.dispose();
    super.dispose();
  }

  Future<void> _carregarPessoas() async {
    setState(() => _carregandoPessoas = true);
    try {
      final lista = await PessoaRepository.listar();
      final rels = await PessoaRelacionamentoService.instance
          .listarRelacionamentos(PessoaRepository.usuarioId);
      final parentescoMap = <int, String>{
        for (final r in rels) r.outraPessoaId: r.rotuloDaOutraParaMim,
      };
      if (mounted) {
        setState(() {
          // S.9.3.2 — humano: só humanos; pet: só pets (vínculo memorial_pessoas).
          _pessoasDisponiveis = lista
              .where((x) => _modoPet ? x.isPet : !x.isPet)
              .toList();
          _parentescoPorPessoaId = parentescoMap;
          _carregandoPessoas = false;
        });
        // Se abriu com pessoaParaVincular, atualiza o parentesco
        final p = widget.pessoaParaVincular;
        if (p != null && parentescoMap.containsKey(p.id)) {
          _parentescoController.text = parentescoMap[p.id]!;
        }
      }
    } catch (_) {
      if (mounted) setState(() => _carregandoPessoas = false);
    }
  }

  Future<void> _capturarFoto(ImageSource origem) async {
    try {
      final imagem = await _picker.pickImage(
        source: origem,
        imageQuality: 80,
        maxWidth: 1024,
      );
      if (imagem == null) return;

      final bytes = await imagem.readAsBytes();
      if (!mounted) return;
      setState(() {
        _fotoBytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível carregar a foto.')),
      );
    }
  }

  Future<void> _escolherDataNascimento() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataNascimento ?? DateTime(1950),
      firstDate: DateTime(1850),
      lastDate: DateTime.now(),
    );
    if (data != null && mounted) {
      setState(() => _dataNascimento = data);
    }
  }

  Future<void> _escolherDataFalecimento() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataFalecimento ?? DateTime.now(),
      firstDate: _dataNascimento ?? DateTime(1850),
      lastDate: DateTime.now(),
    );
    if (data != null && mounted) {
      setState(() => _dataFalecimento = data);
    }
  }

  String _formatarData(DateTime? data) {
    if (data == null) return '';
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dataNascimento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_modoPet
              ? 'Por favor, informe a data de nascimento do pet.'
              : 'Por favor, informe a data de nascimento.'),
        ),
      );
      return;
    }
    if (_dataFalecimento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, informe a data de falecimento.')),
      );
      return;
    }

    if (_dataFalecimento!.isBefore(_dataNascimento!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A data de falecimento não pode ser anterior à data de nascimento.')),
      );
      return;
    }

    // Pet memorial precisa de vínculo em memorial_pessoas para aparecer
    // em "Memoriais de pets" (listarMemorialIdsDePets).
    final pessoaVinculo =
        _pessoaSelecionada ?? widget.pessoaParaVincular;
    if (_modoPet && pessoaVinculo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecione um pet cadastrado para vincular ao memorial.',
          ),
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final memorial = Memorial(
        nome: _nomeController.text.trim(),
        parentesco: _parentescoController.text.trim(),
        dataNascimento: _dataNascimento!,
        dataFalecimento: _dataFalecimento!,
        biografia: _biografiaController.text.trim(),
        fotoBytes: _fotoBytes,
        pessoaId: pessoaVinculo?.id,
        usuarioId: SupabaseService.usuarioId,
        createdAt: DateTime.now(),
      );

      final criado = await SupabaseService.instance.salvarMemorial(memorial);
      // pessoa_id não fica em memoriais — vínculo em memorial_pessoas.
      if (criado.id != null && pessoaVinculo != null) {
        await PessoaRepository.atualizarPessoasDoMemorial(
          criado.id!,
          [pessoaVinculo.id],
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao criar memorial: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: Text(_modoPet ? 'Novo Memorial de Pet' : 'Novo Memorial',
            style: const TextStyle(
                color: AppColors.roxo,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _salvando
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.roxo),
                  )
                : Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        Text(
                          _modoPet
                              ? 'Homenagem ao pet'
                              : 'Preste uma Homenagem',
                          style: const TextStyle(
                              color: AppColors.roxo,
                              fontSize: 24,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _modoPet
                              ? 'Registre o memorial de um pet da família para preservar as melhores recordações.'
                              : 'Registre o legado de um ente querido que partiu para preservar suas melhores recordações.',
                          style: const TextStyle(
                              color: Color(0xFF7A7280), fontSize: 14, height: 1.4),
                        ),
                        const SizedBox(height: 24),

                        // Link com Pessoa/Pet do App
                        // S.9.3.2 — se veio do perfil (pessoa ou pet), o
                        // vínculo é fixo com quem originou: não pergunta.
                        if (widget.pessoaParaVincular == null) ...[
                          if (_carregandoPessoas)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 20),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.roxo,
                                  ),
                                ),
                              ),
                            )
                          else if (_pessoasDisponiveis.isEmpty && _modoPet)
                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0x16D4A84F),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.borda),
                              ),
                              child: const Text(
                                'Nenhum pet cadastrado. Cadastre um pet em Pets antes de criar o memorial.',
                                style: TextStyle(
                                  color: AppColors.roxo,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            )
                          else if (_pessoasDisponiveis.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.borda),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _modoPet
                                        ? 'Vincular a um pet já cadastrado (obrigatório):'
                                        : 'Vincular a uma pessoa já cadastrada (Opcional):',
                                    style: const TextStyle(
                                      color: AppColors.roxo,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButtonFormField<Pessoa>(
                                      value: _pessoaSelecionada,
                                      hint: Text(
                                        _modoPet
                                            ? 'Selecione um pet'
                                            : 'Selecione uma pessoa',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.zero,
                                        filled: false,
                                        border: InputBorder.none,
                                      ),
                                      items: _pessoasDisponiveis.map((p) {
                                        final rel = _parentescoPorPessoaId[p.id] ??
                                            p.parentesco;
                                        final extra = p.isPet &&
                                                (p.especieRacaLabel != null)
                                            ? ' · ${p.especieRacaLabel}'
                                            : (rel.isNotEmpty ? ' ($rel)' : '');
                                        return DropdownMenuItem<Pessoa>(
                                          value: p,
                                          child: Text(
                                            '${p.nome}$extra',
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (pessoa) {
                                        if (pessoa != null) {
                                          final rel =
                                              _parentescoPorPessoaId[pessoa.id] ??
                                                  pessoa.parentesco;
                                          setState(() {
                                            _pessoaSelecionada = pessoa;
                                            _nomeController.text = pessoa.nome;
                                            if (rel.isNotEmpty) {
                                              _parentescoController.text = rel;
                                            } else if (_modoPet) {
                                              _parentescoController.text =
                                                  pessoa.especieRacaLabel ??
                                                      'Pet';
                                            }
                                            _dataNascimento =
                                                pessoa.dataNascimento;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],

                        // Foto de Perfil do Homenageado
                        Center(
                          child: Stack(
                            children: [
                              Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(55),
                                  border: Border.all(color: AppColors.borda, width: 3),
                                  image: _fotoBytes != null
                                      ? DecorationImage(
                                          image: MemoryImage(_fotoBytes!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: _fotoBytes == null
                                    ? const Icon(Icons.favorite_outline,
                                        color: AppColors.dourado, size: 44)
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: AppColors.roxo,
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                                    onPressed: () => _mostrarOpcoesFoto(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Form Fields
                        TextFormField(
                          controller: _nomeController,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(fontSize: 15, color: AppColors.roxo, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            labelText: _modoPet ? 'Nome do pet' : 'Nome Completo',
                            hintText: _modoPet
                                ? 'Nome do pet'
                                : 'Nome do ente querido',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return _modoPet
                                  ? 'Por favor, informe o nome do pet.'
                                  : 'Por favor, informe o nome.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _parentescoController,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(fontSize: 15, color: AppColors.roxo, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            labelText: _modoPet
                                ? 'Relação / espécie'
                                : 'Grau de Parentesco / Relação',
                            hintText: _modoPet
                                ? 'Ex: Cachorro, Gato, Pet da família'
                                : 'Ex: Avó, Pai, Amigo',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return _modoPet
                                  ? 'Por favor, informe a relação ou espécie.'
                                  : 'Por favor, informe o parentesco.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Datas de Nascimento e Falecimento (Lado a Lado)
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _escolherDataNascimento,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.borda),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Nascimento',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF9B949D), fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _dataNascimento == null ? 'Selecionar' : _formatarData(_dataNascimento),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _dataNascimento == null ? const Color(0xFFC4BCC7) : AppColors.roxo,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: _escolherDataFalecimento,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.borda),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Falecimento',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF9B949D), fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _dataFalecimento == null ? 'Selecionar' : _formatarData(_dataFalecimento),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _dataFalecimento == null ? const Color(0xFFC4BCC7) : AppColors.roxo,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _biografiaController,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(fontSize: 14, color: AppColors.roxo, height: 1.4),
                          decoration: InputDecoration(
                            labelText: _modoPet
                                ? 'História / Homenagem Inicial'
                                : 'Biografia / Homenagem Inicial',
                            hintText: _modoPet
                                ? 'Escreva um breve resumo da história e das memórias com este pet...'
                                : 'Escreva um breve resumo da história, valores e legado deixados por esta pessoa...',
                            alignLabelWithHint: true,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Por favor, escreva uma homenagem.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),

                        FilledButton(
                          onPressed: _salvar,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.roxo,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Salvar Memorial',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _mostrarOpcoesFoto() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.roxo),
                title: const Text('Tirar Foto', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.of(context).pop();
                  _capturarFoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.roxo),
                title: const Text('Escolher da Galeria', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.of(context).pop();
                  _capturarFoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
