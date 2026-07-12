// lib/screens/nova_pet_screen.dart
// Sprint S.9.3 — Seção de Pets
//
// Tela de cadastro e edição de pet.
// Regras absolutas:
//   - tipo = 'pet' sempre
//   - auth_user_id = null (nunca coletado)
//   - Sem campos de e-mail, telefone, CPF, senha
//   - Após salvar novo pet: cria relação TUTOR automaticamente
//   - Não transforma pet em humano por acidente

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/pessoa.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../theme/app_theme.dart';

class NovaPetScreen extends StatefulWidget {
  const NovaPetScreen({this.pet, super.key});

  /// Passado apenas no modo edição. null = cadastro novo.
  final Pessoa? pet;

  @override
  State<NovaPetScreen> createState() => _NovaPetScreenState();
}

/// S.9.3.1 — Sugestões de espécie. Lista aberta: "Outro" libera texto livre.
const _kEspecies = <String>[
  'Cachorro', 'Gato', 'Galinha', 'Pássaro', 'Coelho', 'Rato', 'Hamster',
  'Cobra', 'Lagarto', 'Tartaruga', 'Peixe', 'Cavalo', 'Outro',
];
const _kEspecieOutro = 'Outro';

class _NovaPetScreenState extends State<NovaPetScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _nomeCtrl  = TextEditingController();
  final _especieOutroCtrl = TextEditingController();
  final _racaCtrl  = TextEditingController();
  final _picker    = ImagePicker();

  String?   _especie;
  DateTime? _dataNascimento;
  bool      _falecido    = false;
  String?   _fotoBase64;
  Uint8List? _fotoBytes;
  String?   _fotoUrl;
  bool      _salvando    = false;

  bool get _editando => widget.pet != null;

  @override
  void initState() {
    super.initState();
    if (widget.pet != null) {
      final p = widget.pet!;
      assert(p.isPet, 'NovaPetScreen recebeu uma Pessoa que não é pet');
      _nomeCtrl.text    = p.nome;
      _dataNascimento   = p.dataNascimento;
      _falecido         = p.falecido;
      _fotoBase64       = p.fotoBase64;
      _fotoBytes        = p.fotoBytes;
      _fotoUrl          = p.fotoUrl;
      // S.9.3.1 — espécie/raça
      final esp = p.especie?.trim();
      if (esp != null && esp.isNotEmpty) {
        if (_kEspecies.contains(esp)) {
          _especie = esp;
        } else {
          _especie = _kEspecieOutro;
          _especieOutroCtrl.text = esp;
        }
      }
      _racaCtrl.text = p.raca ?? '';
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _especieOutroCtrl.dispose();
    _racaCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Foto
  // ---------------------------------------------------------------------------

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
        _fotoBytes  = bytes;
        _fotoBase64 = base64Encode(bytes);
        _fotoUrl    = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível carregar a foto.')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Duplicidade
  // ---------------------------------------------------------------------------

  /// Verifica duplicidade apenas entre pets.
  /// 1. Pets já vinculados ao usuário (via TUTOR) com nome+dataNascimento iguais.
  /// 2. Pets globais com nome+dataNascimento iguais (outra família).
  Future<({Pessoa pet, bool ehMeu})?> _buscarDuplicata() async {
    final nome   = _nomeCtrl.text.trim();
    if (nome.isEmpty) return null;
    final tokens = nome.toLowerCase().split(RegExp(r'\s+'));

    try {
      // 1. Pets do usuário
      final todos = await PessoaRepository.listar();
      for (final p in todos) {
        if (!p.isPet) continue;
        final pTokens = p.nome.toLowerCase().split(RegExp(r'\s+'));
        if (!tokens.every(pTokens.contains)) continue;
        if (_dataNascimento == null ||
            p.dataNascimento == null ||
            p.dataNascimento != _dataNascimento) continue;
        return (pet: p, ehMeu: true);
      }

      // 2. Pets globais (outra família) — só se tiver data de nascimento
      if (_dataNascimento != null) {
        final dataStr =
            '${_dataNascimento!.year}-${_dataNascimento!.month.toString().padLeft(2, '0')}-${_dataNascimento!.day.toString().padLeft(2, '0')}';
        final rows = await PessoaRepository.supabaseClient
            .from('pessoas')
            .select('id, nome, sobrenome, data_nascimento, tipo')
            .eq('tipo', 'pet')
            .eq('nome', nome)
            .eq('data_nascimento', dataStr)
            .limit(1);
        if (rows.isNotEmpty) {
          final p = Pessoa.fromMap(rows.first as Map<String, dynamic>);
          final ehMeu = todos.any((x) => x.id == p.id);
          if (!ehMeu) return (pet: p, ehMeu: false);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool?> _mostrarDialogDuplicataMeu(Pessoa existente) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Pet já cadastrado'),
        content: Text(
          'Você já tem um pet chamado ${existente.nome}'
          '${existente.dataNascimento != null ? ' com esta data de nascimento' : ''}.'
          '\n\nDeseja usar o cadastro existente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Usar existente'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _mostrarDialogDuplicataGlobal(Pessoa existente) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Pet encontrado'),
        content: Text(
          'Um pet chamado ${existente.nome}'
          '${existente.dataNascimento != null ? ' com esta data de nascimento' : ''}'
          ' já existe na base.\n\n'
          'É o mesmo animal e você é o tutor?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Não, criar novo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sim, usar existente'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Salvar
  // ---------------------------------------------------------------------------

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_editando) {
      final dup = await _buscarDuplicata();
      if (dup != null) {
        if (dup.ehMeu) {
          final usar = await _mostrarDialogDuplicataMeu(dup.pet);
          if (usar == true) {
            if (mounted) Navigator.of(context).pop(true);
          }
          return;
        } else {
          final usar = await _mostrarDialogDuplicataGlobal(dup.pet);
          if (usar == true) {
            // Cria vínculo TUTOR com o pet existente de outra família
            setState(() => _salvando = true);
            try {
              // Convenção: tipo = papel de B (o pet é 'Pet de' do usuário)
              await PessoaRelacionamentoService.instance.criar(
                pessoaAId: PessoaRepository.usuarioId,
                pessoaBId: dup.pet.id,
                tipo: 'PET_DE',
                relacaoA: 'Tutor',
                relacaoB: 'Pet de',
              );
              if (mounted) Navigator.of(context).pop(true);
            } catch (e) {
              if (mounted) {
                setState(() => _salvando = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erro ao criar vínculo: $e')),
                );
              }
            }
            return;
          }
          // null = "Não, criar novo" — segue o fluxo normal
        }
      }
    }

    setState(() => _salvando = true);
    try {
      // Resolve URL da foto (upload se houver bytes novos).
      // S.9.3.1 — usa uploadFoto() (PURO). A antiga uploadFotoPerfil()
      // gravava a URL em pessoas.id = usuarioId e sobrescrevia o avatar
      // do usuário logado com a foto do pet (bug Mili).
      String? fotoUrl = _fotoUrl;
      if (_fotoBytes != null) {
        print('[PET_PHOTO] pet_id=${widget.pet?.id ?? 'novo'}');
        print('[PET_PHOTO] usuario_logado_id=${PessoaRepository.usuarioId}');
        final url = await PessoaRepository.uploadFoto(
          _fotoBytes!,
          'pet_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        if (url != null) fotoUrl = url;
      }

      final pet = Pessoa(
        id:             widget.pet?.id,
        nome:           _nomeCtrl.text.trim(),
        tipo:           'pet',            // imutável
        especie:        _especie == _kEspecieOutro
            ? _especieOutroCtrl.text.trim()
            : _especie,
        raca:           _racaCtrl.text.trim(),
        dataNascimento: _dataNascimento,
        falecido:       _falecido,
        fotoBase64:     fotoUrl ?? _fotoBase64,
        createdAt:      widget.pet?.createdAt,
        // Campos deliberadamente ausentes: email, telefone, authUserId, authId
      );
      print('[PET_PHOTO] update_filter=pessoas.id=${widget.pet?.id ?? '(insert novo)'}');

      final novoId = await PessoaRepository.salvar(pet, isUpdate: _editando);

      // Novo pet: criar relação TUTOR automaticamente
      if (!_editando && novoId != null) {
        try {
          // Convenção: tipo = papel de B (o pet é 'Pet de' do usuário)
          await PessoaRelacionamentoService.instance.criar(
            pessoaAId: PessoaRepository.usuarioId,
            pessoaBId: novoId,
            tipo:      'PET_DE',
            relacaoA:  'Tutor',
            relacaoB:  'Pet de',
          );
        } catch (e) {
          // Se já existe relação (raro), não bloqueia
          print('[NovaPetScreen] Erro ao criar relação TUTOR: $e');
        }
      }

      if (!mounted) return;
      setState(() => _salvando = false);
      Navigator.of(context).pop(true);
    } catch (e) {
      print('[NovaPetScreen] _salvar() ERRO: $e');
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar o pet.')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Data de nascimento
  // ---------------------------------------------------------------------------

  Future<void> _escolherData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataNascimento ?? DateTime(2018),
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
    );
    if (data != null && mounted) {
      setState(() => _dataNascimento = data);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar pet' : 'Cadastrar pet'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  if (!_editando) ...[
                    const Text(
                      'Seu companheiro merece ter histórias também.',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Cadastre seu pet para incluí-lo em memórias e preservar seu legado.',
                      style: TextStyle(
                        color: AppColors.textoSuave,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],

                  // Foto
                  _FotoPet(
                    fotoBytes: _fotoBytes,
                    fotoUrl: _fotoUrl,
                    onRemover: () => setState(() {
                      _fotoBytes  = null;
                      _fotoBase64 = null;
                      _fotoUrl    = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final botoes = [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _capturarFoto(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Tirar foto'),
                          ),
                        ),
                        const SizedBox(width: 12, height: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _capturarFoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Galeria'),
                          ),
                        ),
                      ];
                      if (constraints.maxWidth < 390) {
                        return Column(
                          children: botoes
                              .map((b) => b is Expanded ? b.child : b)
                              .toList(),
                        );
                      }
                      return Row(children: botoes);
                    },
                  ),
                  const SizedBox(height: 20),

                  // Nome
                  TextFormField(
                    controller: _nomeCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome do pet',
                      hintText: 'Como ele/ela se chama?',
                      prefixIcon: Icon(Icons.pets),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Informe o nome do pet.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // S.9.3.1 — Espécie (obrigatória)
                  DropdownButtonFormField<String>(
                    initialValue: _especie,
                    decoration: const InputDecoration(
                      labelText: 'Espécie',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: _kEspecies
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => _especie = v),
                    validator: (v) {
                      // Obrigatória para novos pets; em edição de pet antigo
                      // (sem espécie) não bloqueia o salvamento.
                      if (!_editando && (v == null || v.isEmpty)) {
                        return 'Informe a espécie do pet.';
                      }
                      return null;
                    },
                  ),
                  if (_especie == _kEspecieOutro) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _especieOutroCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Qual espécie?',
                        hintText: 'Ex: Furão, Porquinho-da-índia...',
                        prefixIcon: Icon(Icons.edit_outlined),
                      ),
                      validator: (v) {
                        if (_especie == _kEspecieOutro &&
                            (v == null || v.trim().isEmpty)) {
                          return 'Descreva a espécie.';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 16),

                  // S.9.3.1 — Raça (opcional, texto livre)
                  TextFormField(
                    controller: _racaCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Raça (opcional)',
                      hintText: 'Ex: Siamês, Labrador...',
                      prefixIcon: Icon(Icons.pets_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Data de nascimento
                  InkWell(
                    onTap: _escolherData,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data de nascimento',
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                      child: Text(
                        _dataNascimento != null
                            ? '${_dataNascimento!.day.toString().padLeft(2, '0')}/'
                                '${_dataNascimento!.month.toString().padLeft(2, '0')}/'
                                '${_dataNascimento!.year}'
                            : 'Toque para selecionar',
                        style: TextStyle(
                          color: _dataNascimento != null
                              ? AppColors.roxo
                              : const Color(0xFF9B949D),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Falecido
                  SwitchListTile(
                    value: _falecido,
                    onChanged: (v) => setState(() => _falecido = v),
                    title: const Text(
                      'Falecido(a)',
                      style: TextStyle(color: AppColors.roxo),
                    ),
                    subtitle: const Text(
                      'Marque se este pet já partiu.',
                      style: TextStyle(color: AppColors.textoSuave, fontSize: 13),
                    ),
                    activeColor: AppColors.roxo,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 24),

                  // Botão salvar
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
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
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.pets, size: 18),
                    label: Text(
                      _salvando
                          ? 'Salvando...'
                          : _editando
                              ? 'Salvar alterações'
                              : 'Cadastrar pet',
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
}

// ---------------------------------------------------------------------------
// Widget de foto do pet
// ---------------------------------------------------------------------------

class _FotoPet extends StatelessWidget {
  const _FotoPet({
    required this.fotoBytes,
    this.fotoUrl,
    required this.onRemover,
  });

  final Uint8List? fotoBytes;
  final String? fotoUrl;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        fotoBytes != null || (fotoUrl != null && fotoUrl!.isNotEmpty);

    if (hasImage) {
      return Stack(
        children: [
          Center(
            child: ClipOval(
              child: SizedBox(
                width: 140,
                height: 140,
                child: fotoBytes != null
                    ? Image.memory(fotoBytes!, fit: BoxFit.cover)
                    : Image.network(fotoUrl!, fit: BoxFit.cover),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton.filled(
              tooltip: 'Remover foto',
              onPressed: onRemover,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      );
    }

    return const SizedBox(
      height: 160,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pets, size: 48, color: AppColors.dourado),
          SizedBox(height: 12),
          Text(
            'Adicione uma foto',
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Use a câmera ou escolha uma imagem',
            style: TextStyle(color: Color(0xFF7A7280)),
          ),
        ],
      ),
    );
  }
}
