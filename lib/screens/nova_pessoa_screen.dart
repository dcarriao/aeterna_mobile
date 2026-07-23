import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

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

/// S.9.4 — URL oficial de cadastro enviada no convite.
/// TODO(Darlan): confirmar/ajustar a URL pública oficial.
const String kUrlConviteAeterna = 'https://aeternalegado.com.br';

class _NovaPessoaScreenState extends State<NovaPessoaScreen> {
  // S.9.4 — Convite ao cadastrar/reutilizar pessoa humana.
  bool _convidar = false;

  bool get _emailValido {
    final e = _emailController.text.trim();
    return e.contains('@') && e.contains('.') && e.length >= 6;
  }

  String get _foneDigitos =>
      _telefoneController.text.replaceAll(RegExp(r'\D'), '');

  bool get _foneValido => _foneDigitos.length >= 10;

  /// Checkbox habilita só com humano + (e-mail OU WhatsApp) válido.
  /// (Conta existente e convite pendente são checados no salvar,
  /// com feedback claro — evita query a cada tecla.)
  bool get _podeConvidar =>
      (widget.pessoa?.tipo ?? 'humano') == 'humano' &&
      (_emailValido || _foneValido);

  /// S.9.4 — executa o convite após salvar a pessoa. NUNCA afirma envio
  /// pelo WhatsApp (o usuário confirma manualmente lá).
  Future<void> _processarConvite(int? pessoaId) async {
    final email = _emailController.text.trim().toLowerCase();
    final nome = _nomeController.text.trim();

    if (_emailValido) {
      if (await PessoaRepository.temContaPorEmail(email)) {
        _avisoConvite('$nome já possui conta na aEterna — convite desnecessário.');
        return;
      }
      if (await PessoaRepository.convitePendenteParaEmail(email)) {
        _avisoConvite('Já existe um convite pendente para $email.');
        return;
      }
      try {
        await PessoaRepository.enviarConviteFamiliar(
            email: email, pessoaId: pessoaId);
      } catch (e) {
        _avisoConvite('Não foi possível registrar o convite: $e');
        return;
      }
    }

    if (_foneValido) {
      var fone = _foneDigitos;
      if (fone.length <= 11 && !fone.startsWith('55')) fone = '55$fone';
      final msg = Uri.encodeComponent(
          'Oi, $nome! Estou guardando as memórias da nossa família na '
          'aEterna e criei um espaço para você. '
          '${_emailValido ? 'Cadastre-se com o e-mail $email em ' : 'Cadastre-se em '}'
          '$kUrlConviteAeterna');
      final uri = Uri.parse('https://wa.me/$fone?text=$msg');
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _avisoConvite(_emailValido
            ? 'Convite registrado. Confirme o envio no WhatsApp.'
            : 'WhatsApp aberto — confirme o envio por lá. '
              '(Sem e-mail, o convite não fica registrado no app.)');
      } catch (_) {
        _avisoConvite(_emailValido
            ? 'Convite registrado por e-mail; não foi possível abrir o WhatsApp.'
            : 'Não foi possível abrir o WhatsApp.');
      }
    } else if (_emailValido) {
      _avisoConvite('Convite enviado por e-mail para $email.');
    }
  }

  void _avisoConvite(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    }
  }

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
      // Pré-seleciona o tipo pelo parentesco salvo (catálogo local), para o
      // dropdown não vir vazio ao EDITAR e travar o "Salvar".
      final par = p.parentesco.toLowerCase();
      final idx = TIPOS_RELACIONAMENTO_INICIAIS
          .indexWhere((t) => t.rotuloA.toLowerCase() == par);
      if (idx >= 0) _tipoId = TIPOS_RELACIONAMENTO_INICIAIS[idx].id;
    }
    // Carrega o catálogo do servidor (com fallback client-side já em
    // TIPOS_RELACIONAMENTO_INICIAIS).
    PessoaRelacionamentoService.instance
        .listarTipos()
        .then((tipos) {
      if (mounted) {
        setState(() {
          // S.9.3.1 — sem tipos de pet no cadastro de pessoa humana.
          _tipos = (tipos.isNotEmpty ? tipos : TIPOS_RELACIONAMENTO_INICIAIS)
              .where((t) => t.id != 'TUTOR' && t.id != 'PET_DE' && t.categoria != 'pet')
              .toList();
          if (_editando && _tipoId == null) {
            final par = widget.pessoa!.parentesco.toLowerCase();
            for (final t in _tipos) {
              if (t.rotuloA.toLowerCase() == par) { _tipoId = t.id; break; }
            }
          }
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

  /// Compara datas de calendário (Y/M/D). Nunca usa `DateTime ==` —
  /// parse de `date` do Postgres vira UTC e falha no fuso BR.
  bool _mesmaDataNascimento(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Normaliza nome+sobrenome: minúsculas, sem acento, espaços colapsados.
  String _normalizarNomeCompleto(String nome, [String? sobrenome]) {
    var s = '$nome ${sobrenome ?? ''}'.trim().toLowerCase();
    const from = 'áàãâäéèêëíìîïóòõôöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _nomesCorrespondem(String nomeDigitado, Pessoa p) {
    final input = _normalizarNomeCompleto(nomeDigitado);
    final completo = _normalizarNomeCompleto(p.nome, p.apelido);
    if (input.isEmpty || completo.isEmpty) return false;
    if (input == completo) return true;
    final inputTokens = input.split(' ');
    final completoTokens = completo.split(' ');
    // Todos os tokens digitados estão no cadastro (ex: "Jaqueline Carrião"
    // vs nome=Jaqueline sobrenome=Carrião).
    if (inputTokens.every(completoTokens.contains)) return true;
    // Cadastro completo contido no digitado (ordem invertida de campos).
    if (completoTokens.every(inputTokens.contains)) return true;
    return false;
  }

  Future<({Pessoa pessoa, bool ehRelacionada})?> _buscarDuplicata() async {
    final nome = _nomeController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final telefone = _telefoneController.text.trim();
    if (nome.isEmpty) return null;
    final dataStr = _dataNascimento == null
        ? null
        : '${_dataNascimento!.year}-${_dataNascimento!.month.toString().padLeft(2, '0')}-${_dataNascimento!.day.toString().padLeft(2, '0')}';
    print('[DUPLICIDADE] buscando candidato nome="$nome" data=$dataStr email="$email" telefone="$telefone"');

    try {
      final db = PessoaRepository.supabaseClient;

      // 1. Token match + data_nascimento nas pessoas RELACIONADAS
      final todas = await PessoaRepository.listar();
      for (final p in todas) {
        if (!_nomesCorrespondem(nome, p)) continue;
        if (!_mesmaDataNascimento(_dataNascimento, p.dataNascimento)) continue;
        print('[DUPLICIDADE] hit relacionado id=${p.id}');
        return (pessoa: p, ehRelacionada: true);
      }

      final idsRelacionados = todas.map((p) => p.id).toSet();

      // 2. Email ou telefone iguais em QUALQUER cadastro
      if (email.isNotEmpty) {
        final porEmail = await db
            .from('pessoas')
            .select('id, nome, sobrenome, email, telefone, data_nascimento, tipo')
            .eq('email', email)
            .eq('tipo', 'humano')
            .maybeSingle();
        if (porEmail != null) {
          final p = Pessoa.fromMap(porEmail);
          return (pessoa: p, ehRelacionada: idsRelacionados.contains(p.id));
        }
      }
      if (telefone.isNotEmpty) {
        final porTelefone = await db
            .from('pessoas')
            .select('id, nome, sobrenome, email, telefone, data_nascimento, tipo')
            .eq('telefone', telefone)
            .eq('tipo', 'humano')
            .maybeSingle();
        if (porTelefone != null) {
          final p = Pessoa.fromMap(porTelefone);
          return (pessoa: p, ehRelacionada: idsRelacionados.contains(p.id));
        }
      }

      // 3. Nome + data_nascimento GLOBAL (obrigatório quando há data).
      // Bloqueia segunda linha com mesmo nome+nascimento (ex.: ids 24 e 28).
      if (dataStr != null) {
        final candidatos = await db
            .from('pessoas')
            .select('id, nome, sobrenome, email, telefone, data_nascimento, tipo')
            .eq('data_nascimento', dataStr)
            .eq('tipo', 'humano')
            .neq('situacao', 'inativo');
        print('[DUPLICIDADE] candidatos global data=$dataStr n=${candidatos.length}');
        for (final row in candidatos) {
          final p = Pessoa.fromMap(Map<String, dynamic>.from(row as Map));
          if (_nomesCorrespondem(nome, p)) {
            print('[DUPLICIDADE] hit global id=${p.id} nome=${p.nome} sobrenome=${p.apelido}');
            return (pessoa: p, ehRelacionada: idsRelacionados.contains(p.id));
          }
        }
      }
    } catch (e) {
      print('[DUPLICIDADE] ERRO: $e');
    }
    print('[DUPLICIDADE] nenhum candidato encontrado');
    return null;
  }

  Future<bool?> _mostrarDialogDuplicata(Pessoa existente) async {
    print('[DUPLICIDADE] candidato=${existente.id}/${existente.nome}');
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
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
            onPressed: () {
              print('[DUPLICIDADE] cancelar');
              Navigator.of(ctx).pop(false);
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              print('[DUPLICIDADE] usar_existente pessoa_id=${existente.id}');
              Navigator.of(ctx).pop(true);
            },
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
            // Retorna true para que o caller saiba que a pessoa já existe
            // e pode atualizar a lista sem criar duplicata.
            if (mounted) Navigator.of(context).pop(true);
            return;
          }
          // false ou null = cancelar: manter a tela estável, sem criar pessoa
          return;
        } else {
          final tipo = await _mostrarDialogGlobal(result.pessoa);
          if (tipo != null) {
            setState(() => _salvando = true);
            try {
              // S.9.3.1 — o dropdown "Relação com você" descreve a pessoa
              // cadastrada (B). Convenção: tipo = papel de B;
              // relacaoA = papel do usuário (rotuloB); relacaoB = rotuloA.
              await PessoaRelacionamentoService.instance.criar(
                pessoaAId: PessoaRepository.usuarioId,
                pessoaBId: result.pessoa.id,
                tipo: tipo.id,
                relacaoA: tipo.rotuloB,
                relacaoB: tipo.rotuloA,
              );
              if (mounted) Navigator.of(context).pop(true);
            } catch (e) {
              if (mounted) {
                setState(() => _salvando = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erro ao criar relação: $e')),
                );
              }
            }
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
        // S.9.3.1 — CAUSA RAIZ "pet vira humano": este construtor omitia
        // `tipo`, cujo default é 'humano'. Ao editar um pet por esta tela,
        // o UPDATE gravava tipo='humano' e o pet sumia da área Pets.
        // A identidade (pessoas.tipo) é preservada SEMPRE.
        tipo: widget.pessoa?.tipo ?? 'humano',
        especie: widget.pessoa?.especie,
        raca: widget.pessoa?.raca,
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
        // S.9.3.1 — o dropdown "Relação com você" descreve a pessoa nova (B).
        // Convenção: tipo = papel de B; relacaoA = papel do usuário.
        await PessoaRelacionamentoService.instance.criar(
          pessoaAId: PessoaRepository.usuarioId,
          pessoaBId: novoId,
          tipo: _tipoId!,
          relacaoA: t.rotuloB,
          relacaoB: t.rotuloA,
        );
      }

      // S.9.4 — convite (se marcado); mensagens de status via SnackBar.
      if (_convidar && _podeConvidar) {
        await _processarConvite(novoId ?? widget.pessoa?.id);
      }

      if (!mounted) return;
      setState(() => _salvando = false);

      // S.9.4c — o convite agora é feito EXCLUSIVAMENTE pelo checkbox
      // "Convidar para a aEterna?" (_processarConvite acima, via WhatsApp/
      // e-mail). O diálogo antigo "Edite o texto..." foi removido — ele
      // disparava um segundo pop-up sempre que havia e-mail.

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
                    onChanged: (_) => setState(() {}),
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
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  // S.9.4 — Convite ao cadastrar
                  CheckboxListTile(
                    value: _convidar && _podeConvidar,
                    onChanged: _podeConvidar
                        ? (v) => setState(() => _convidar = v ?? false)
                        : null,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Convidar para a aEterna?',
                        style: TextStyle(
                            color: AppColors.roxo,
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _podeConvidar
                          ? 'Envia convite por e-mail e/ou WhatsApp.'
                          : 'Informe um e-mail ou WhatsApp válido para habilitar.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                      // Ao editar, a relação já existe — não re-exige.
                      if (!_editando && (valor == null || valor.isEmpty)) {
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
