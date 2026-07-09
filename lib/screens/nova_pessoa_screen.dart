import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/pessoa.dart';
import '../models/tipo_relacionamento.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../theme/app_theme.dart';

class NovaPessoaScreen extends StatefulWidget {
  const NovaPessoaScreen({this.pessoa, super.key});

  final Pessoa? pessoa;

  @override
  State<NovaPessoaScreen> createState() => _NovaPessoaScreenState();
}

class _NovaPessoaScreenState extends State<NovaPessoaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _apelidoController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _picker = ImagePicker();

  // Sprint L — campo simétrico (Sprint J) com tipo estável + gênero.
  // Mantém `parentesco` herdado para compatibilidade do legado
  // (preenchido a partir do tipo + gênero na hora do submit).
  List<TipoRelacionamento> _tipos = TIPOS_RELACIONAMENTO_INICIAIS;
  String? _tipoId; // ex: 'PAI', 'IRMAO', 'COMPANHEIRO'
  String _parentesco = 'Outro'; // mantido para compat legado
  DateTime? _dataNascimento;
  String? _fotoBase64;
  Uint8List? _fotoBytes;
  String? _fotoUrl;
  bool _salvando = false;

  bool get _editando => widget.pessoa != null;

  @override
  @override
  void initState() {
    super.initState();
    if (widget.pessoa != null) {
      final p = widget.pessoa!;
      _nomeController.text = p.nome;
      _apelidoController.text = p.apelido ?? '';
      _emailController.text = p.email ?? '';
      _telefoneController.text = p.telefone ?? '';
      _parentesco = p.parentesco;
      _dataNascimento = p.dataNascimento;
      _fotoBase64 = p.fotoBase64;
      _fotoBytes = p.fotoBytes;
      _fotoUrl = p.fotoUrl;
    }
    // Carrega o catálogo do servidor (com fallback client-side já em
    // TIPOS_RELACIONAMENTO_INICIAIS).
    PessoaRelacionamentoService.instance
        .listarTipos()
        .then((tipos) {
      if (mounted) {
        setState(() {
          _tipos = tipos.isNotEmpty ? tipos : TIPOS_RELACIONAMENTO_INICIAIS;
        });
      }
    });
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _apelidoController.dispose();
    _emailController.dispose();
    _telefoneController.dispose();
    super.dispose();
  }

  Future<({Pessoa pessoa, bool ehRelacionada})?> _buscarDuplicata() async {
    final nome = _nomeController.text.trim();
    final nomeTokens = nome.toLowerCase().split(RegExp(r'\s+'));
    final email = _emailController.text.trim().toLowerCase();
    final telefone = _telefoneController.text.trim();
    if (nome.isEmpty) return null;

    try {
      final db = PessoaRepository.supabaseClient;

      // 1. Token match + data_nascimento nas pessoas RELACIONADAS
      final todas = await PessoaRepository.listar();
      for (final p in todas) {
        final pTokens = p.nome.toLowerCase().split(RegExp(r'\s+'));
        final todosTokensIguais = nomeTokens.every((t) => pTokens.contains(t));
        if (!todosTokensIguais) continue;
        if (_dataNascimento == null ||
            p.dataNascimento == null ||
            p.dataNascimento != _dataNascimento) continue;
        return (pessoa: p, ehRelacionada: true);
      }

      final idsRelacionados = todas.map((p) => p.id).toSet();

      // 2. Email ou telefone iguais em QUALQUER cadastro
      //    Se a pessoa já for relacionada, trata como duplicata relacionada
      if (email.isNotEmpty) {
        final porEmail = await db
            .from('pessoas')
            .select('id, nome, sobrenome, email, telefone, data_nascimento')
            .eq('email', email)
            .maybeSingle();
        if (porEmail != null) {
          final p = Pessoa.fromMap(porEmail);
          return (pessoa: p, ehRelacionada: idsRelacionados.contains(p.id));
        }
      }
      if (telefone.isNotEmpty) {
        final porTelefone = await db
            .from('pessoas')
            .select('id, nome, sobrenome, email, telefone, data_nascimento')
            .eq('telefone', telefone)
            .maybeSingle();
        if (porTelefone != null) {
          final p = Pessoa.fromMap(porTelefone);
          return (pessoa: p, ehRelacionada: idsRelacionados.contains(p.id));
        }
      }

      // 3. Nome + data_nascimento + (email ou telefone) EXATOS
      if (_dataNascimento != null && (email.isNotEmpty || telefone.isNotEmpty)) {
        final dataStr =
            '${_dataNascimento!.year}-${_dataNascimento!.month.toString().padLeft(2, '0')}-${_dataNascimento!.day.toString().padLeft(2, '0')}';
        var query = db
            .from('pessoas')
            .select('id, nome, sobrenome, email, telefone, data_nascimento')
            .eq('nome', nome)
            .eq('data_nascimento', dataStr);
        if (email.isNotEmpty) query = query.eq('email', email);
        if (telefone.isNotEmpty) query = query.eq('telefone', telefone);
        final global = await query.maybeSingle();
        if (global != null) {
          final p = Pessoa.fromMap(global);
          return (pessoa: p, ehRelacionada: idsRelacionados.contains(p.id));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool?> _mostrarDialogDuplicata(Pessoa existente) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Esta pessoa já existe'),
        content: Text(
          'Já existe um cadastro com este nome:\n\n'
          '${existente.nome}${existente.apelido != null ? ' ${existente.apelido}' : ''}'
          '${existente.email != null ? '\n${existente.email}' : ''}'
          '\n\nO que deseja fazer?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
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

  Future<TipoRelacionamento?> _mostrarDialogGlobal(Pessoa existente) async {
    final selecionado = ValueNotifier<TipoRelacionamento?>(null);
    return showDialog<TipoRelacionamento?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pessoa já cadastrada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${existente.nome}${existente.apelido != null ? ' ${existente.apelido}' : ''}'
              '${existente.email != null ? '\n${existente.email}' : ''}'
              '\n\nJá existe na base. Qual seu parentesco?',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _tipoId,
              decoration: const InputDecoration(
                labelText: 'Parentesco',
                border: OutlineInputBorder(),
              ),
              items: _tipos
                  .map((t) => DropdownMenuItem(
                        value: t.id,
                        child: Text(t.rotuloA),
                      ))
                  .toList(),
              onChanged: (v) {
                selecionado.value = _tipos.firstWhere((t) => t.id == v);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final t = selecionado.value;
              if (t == null) return;
              Navigator.of(ctx).pop(t);
            },
            child: const Text('Adicionar como contato'),
          ),
        ],
      ),
    );
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
        _fotoBase64 = base64Encode(bytes);
        _fotoUrl = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível carregar a foto.')),
      );
    }
  }

  Future<void> _escolherData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataNascimento ?? DateTime(1960),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (data != null && mounted) {
      setState(() => _dataNascimento = data);
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_editando) {
      final result = await _buscarDuplicata();
      if (result != null) {
        if (result.ehRelacionada) {
          final usarExistente = await _mostrarDialogDuplicata(result.pessoa);
          if (usarExistente == true) {
            if (mounted) Navigator.of(context).pop(result.pessoa.id);
            return;
          }
          if (usarExistente == null) return;
        } else {
          final tipo = await _mostrarDialogGlobal(result.pessoa);
          if (tipo != null) {
            setState(() => _salvando = true);
            await PessoaRelacionamentoService.instance.criar(
              pessoaAId: PessoaRepository.usuarioId,
              pessoaBId: result.pessoa.id,
              tipo: tipo.id,
              relacaoA: tipo.rotuloA,
              relacaoB: tipo.rotuloB,
            );
            if (mounted) Navigator.of(context).pop(true);
            return;
          }
          return;
        }
      }
    }

    setState(() => _salvando = true);
    try {
      final pessoa = Pessoa(
        id: widget.pessoa?.id,
        nome: _nomeController.text.trim(),
        apelido: _apelidoController.text.trim().isEmpty
            ? null
            : _apelidoController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim().toLowerCase(),
        telefone: _telefoneController.text.trim().isEmpty
            ? null
            : _telefoneController.text.trim(),
        parentesco: _parentesco,
        dataNascimento: _dataNascimento,
        fotoBase64: _fotoBase64,
        createdAt: widget.pessoa?.createdAt,
      );
      print('[NovaPessoaScreen] _salvar() -> chamando PessoaRepository.salvar(${pessoa.nome}) isUpdate=$_editando');
      final novoId = await PessoaRepository.salvar(pessoa, isUpdate: _editando);
      print('[NovaPessoaScreen] _salvar() -> salvar concluido id=$novoId');

      // Se é uma pessoa nova com tipo de relação selecionado, criar o
      // vínculo via PessoaRelacionamentoService (sem o trigger legado
      // indeterminístico).
      if (!_editando && _tipoId != null && novoId != null) {
        final t = _tipos.firstWhere(
          (x) => x.id == _tipoId,
          orElse: () => _tipos.last,
        );
        // A pergunta é "Relação com você": o usuário selecionou o que a
        // NOVA pessoa é para ELE (rotuloA). Mantemos pessoaA = usuário,
        // e trocamos os rótulos para tipos assimétricos.
        await PessoaRelacionamentoService.instance.criar(
          pessoaAId: PessoaRepository.usuarioId,
          pessoaBId: novoId,
          tipo: _tipoId!,
          relacaoA: t.simetrico ? t.rotuloA : t.rotuloB,
          relacaoB: t.simetrico ? t.rotuloB : t.rotuloA,
        );
      }

      if (!mounted) return;
      setState(() => _salvando = false);

      if (pessoa.email != null && pessoa.email!.isNotEmpty) {
        await _oferecerConvite(pessoa.nome, pessoa.email!);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      print('[NovaPessoaScreen] _salvar() ERRO: $e');
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar a pessoa.')),
        );
      }
    }
  }

  String _mensagemPadraoConvite(String nome, String email) {
    return 'Oi${nome.isNotEmpty ? ', $nome' : ''}! Estou usando o app aEterna para guardar '
        'as memórias da nossa família e quero muito que você faça parte também.\n\n'
        '1. Baixe o app aEterna:\n'
        '[cole aqui o link de instalação — Play Store / App Store / APK]\n\n'
        '2. Crie sua conta usando este e-mail: $email\n\n'
        '3. Abra o app, toque em "Convites" e aceite meu convite para vermos '
        'as histórias um do outro.\n\n'
        'Um abraço!';
  }

  /// Convite real (fora do fluxo de memorial): ao cadastrar/editar uma
  /// pessoa com e-mail, oferece registrar o convite e compartilhar o texto
  /// (com o link de instalação) por qualquer app instalado no celular
  /// (WhatsApp, SMS, e-mail...), já que o app não envia e-mails sozinho.
  Future<void> _oferecerConvite(String nome, String email) async {
    final mensagemController = TextEditingController(
      text: _mensagemPadraoConvite(nome, email),
    );
    bool enviando = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Convidar para o aEterna?',
                style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Edite o texto abaixo (inclua o link de instalação do app) e envie para $email.',
                      style: const TextStyle(color: Color(0xFF625B67), fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mensagemController,
                      maxLines: 8,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: enviando ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Agora não', style: TextStyle(color: Color(0xFF9B949D))),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copiar texto',
                      onPressed: enviando
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: mensagemController.text),
                              );
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('Texto copiado!')),
                                );
                              }
                            },
                      icon: const Icon(Icons.copy_outlined, size: 20, color: AppColors.roxo),
                    ),
                    FilledButton.icon(
                      onPressed: enviando
                          ? null
                          : () async {
                              setDialogState(() => enviando = true);
                              try {
                                await PessoaRepository.enviarConviteFamiliar(email: email);
                              } catch (_) {
                                // Pode já existir convite pendente para este
                                // e-mail — segue o compartilhamento mesmo assim.
                              }
                              await Share.share(
                                mensagemController.text,
                                subject: 'Convite aEterna',
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                      style: FilledButton.styleFrom(backgroundColor: AppColors.roxo),
                      icon: enviando
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.share_outlined, size: 16),
                      label: const Text('Compartilhar'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar pessoa' : 'Nova pessoa'),
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
                      'Quem faz parte da sua história?',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Cadastre alguém importante para sua família.',
                      style: TextStyle(
                        color: AppColors.textoSuave,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  _FotoPessoa(
                    fotoBytes: _fotoBytes,
                    fotoUrl: _fotoUrl,
                    onRemover: () => setState(() {
                      _fotoBytes = null;
                      _fotoBase64 = null;
                      _fotoUrl = null;
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
                            onPressed: () =>
                                _capturarFoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Galeria'),
                          ),
                        ),
                      ];

                      if (constraints.maxWidth < 390) {
                        return Column(
                          children: botoes.map((item) {
                            return item is Expanded ? item.child : item;
                          }).toList(),
                        );
                      }
                      return Row(children: botoes);
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nomeController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      hintText: 'Nome completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.trim().isEmpty) {
                        return 'Informe o nome.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _apelidoController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Sobrenome',
                      hintText: 'Como você chama essa pessoa?',
                      prefixIcon: Icon(Icons.favorite_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      hintText: 'exemplo@email.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _telefoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefone / WhatsApp',
                      hintText: '(00) 90000-0000',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Sprint L — seleção de relação com tipo estável.
                  // A UI mostra o rótulo humano (`rotuloA`), o app grava
                  // o id (`'PAI'`, `'IRMAO'`, `'CONJUGE'`, etc.) e mantém
                  // o `parentesco` legado para compatibilidade.
                  DropdownButtonFormField<String>(
                    initialValue: _tipoId,
                    decoration: const InputDecoration(
                      labelText: 'Relação com você',
                      prefixIcon: Icon(Icons.family_restroom_outlined),
                    ),
                    items: _tipos
                        .map((t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(t.rotuloA),
                            ))
                        .toList(),
                    onChanged: (valor) {
                      if (valor != null) {
                        setState(() {
                          _tipoId = valor;
                          // Atualiza o `parentesco` legado para o rótulo
                          // humano do tipo (compatibilidade).
                          final t = _tipos.firstWhere(
                            (x) => x.id == valor,
                            orElse: () => _tipos.last,
                          );
                          _parentesco = t.rotuloA;
                        });
                      }
                    },
                    validator: (valor) {
                      if (valor == null || valor.isEmpty) {
                        return 'Selecione a relação.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: _salvando
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_outlined),
                    label: Text(
                      _salvando
                          ? 'Salvando...'
                          : _editando
                              ? 'Salvar alterações'
                              : 'Salvar pessoa',
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

class _FotoPessoa extends StatelessWidget {
  const _FotoPessoa({required this.fotoBytes, this.fotoUrl, required this.onRemover});

  final Uint8List? fotoBytes;
  final String? fotoUrl;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    final hasImage = fotoBytes != null || (fotoUrl != null && fotoUrl!.isNotEmpty);
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
          Icon(Icons.add_a_photo_outlined, size: 42, color: AppColors.dourado),
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
