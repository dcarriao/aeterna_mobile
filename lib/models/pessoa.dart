import 'dart:convert';
import 'dart:math' as dart_math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase/supabase.dart';

import 'convite_familiar.dart';

class Pessoa {
  Pessoa({
    required this.nome,
    this.apelido,
    this.parentesco = 'Outro',
    this.tipo = 'humano',
    this.dataNascimento,
    this.fotoBase64,
    this.email,
    this.telefone,
    this.authUserId,
    this.authId,
    this.criadoPorId,
    this.situacao = 'pendente',
    this.falecido = false,
    DateTime? createdAt,
    int? id,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch,
        createdAt = createdAt ?? DateTime.now();

  final int id;
  final String nome;
  final String? apelido;
  final String parentesco;
  final String tipo;
  final DateTime? dataNascimento;
  final String? fotoBase64;
  final String? email;
  final String? telefone;
  final String? authUserId;
  final String? authId;
  final int? criadoPorId;
  final String situacao;
  final bool falecido;
  final DateTime createdAt;

  Uint8List? get fotoBytes {
    if (fotoBase64 == null || fotoBase64!.isEmpty) return null;
    if (fotoBase64!.startsWith('http')) return null;
    try {
      return base64Decode(fotoBase64!);
    } catch (_) {
      return null;
    }
  }

  String? get fotoUrl =>
      fotoBase64 != null && fotoBase64!.startsWith('http')
          ? fotoBase64
          : null;

  bool get isPet => tipo == 'pet';
  bool get isHumano => tipo == 'humano';
  bool get isAutenticavel => isHumano && authUserId != null;

  Map<String, dynamic> toMap() {
    return {
      if (id > 0) 'id': id,
      'nome': nome,
      'sobrenome': apelido,
      'email': email,
      'telefone': telefone,
      'data_nascimento': dataNascimento?.toIso8601String(),
      'foto_perfil': fotoBase64,
      'tipo': tipo,
      'situacao': situacao,
      'falecido': falecido,
      if (authUserId != null) 'auth_user_id': authUserId,
      if (authId != null) 'auth_id': authId,
      if (criadoPorId != null) 'criado_por_id': criadoPorId,
    };
  }

  factory Pessoa.fromMap(Map<String, dynamic> map) {
    final criadaEm = map['created_at'] != null
        ? DateTime.tryParse('${map['created_at']}')
        : (map['data_criacao'] != null
            ? DateTime.tryParse('${map['data_criacao']}')
            : null);
    return Pessoa(
      id: map['id'] is int ? map['id'] as int : int.tryParse('${map['id']}') ?? 0,
      nome: (map['nome'] as String?) ?? '',
      apelido: (map['sobrenome'] as String?) ?? (map['apelido'] as String?),
      parentesco: (map['parentesco'] as String?) ?? 'Outro',
      tipo: (map['tipo'] as String?) ?? 'humano',
      dataNascimento: map['data_nascimento'] != null
          ? DateTime.tryParse('${map['data_nascimento']}')
          : null,
      fotoBase64: (map['foto_perfil'] as String?) ?? (map['fotoBase64'] as String?),
      email: map['email'] as String?,
      telefone: map['telefone'] as String?,
      authUserId: map['auth_user_id'] as String?,
      authId: map['auth_id'] as String?,
      criadoPorId: (map['criado_por_id'] as num?)?.toInt(),
      situacao: (map['situacao'] as String?) ?? 'pendente',
      falecido: map['falecido'] as bool? ?? false,
      createdAt: criadaEm ?? DateTime.now(),
    );
  }
}

class PessoaRepository {
  PessoaRepository._();

  static const _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zfpvfljmnlgsqiqdxmka.supabase.co',
  );
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  
  // ID de usuário dinâmico para isolamento de dados
  static int usuarioId = 2;

  // ID legado (usuarios.id) para queries que ainda usam a FK antiga
  static int? legadoUsuarioId;

  // E-mail do usuário logado, usado para localizar memórias que outras
  // contas compartilharam com este usuário (vínculo por e-mail do contato).
  static String? usuarioEmail;

  static bool get isConfigured => _anonKey.isNotEmpty;

  static SupabaseClient? _client;

  /// Getter público (Sprint H) — usado por `PessoaTimelineService` para
  /// chamar funções RPC do Supabase sem precisar replicar a inicialização
  /// do cliente. Lança exceção se `isConfigured` for false; para
  /// checagem segura, sempre prefira `isConfigured` antes de chamar.
  static SupabaseClient get supabaseClient {
    if (!isConfigured) {
      throw Exception('SUPABASE_ANON_KEY não configurada.');
    }
    return _client ??= SupabaseClient(
      _url,
      _anonKey,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
  }

  static SupabaseClient get _supabase {
    if (!isConfigured) {
      throw Exception('SUPABASE_ANON_KEY não configurada.');
    }
    // BUG 2: o fluxo padrão do pacote `supabase` é PKCE, que exige um
    // `GotrueAsyncStorage` para guardar o code_verifier localmente. Como
    // este cliente não fornece esse storage (nem há tela de callback para
    // trocar o "code" recebido por e-mail), qualquer chamada de auth como
    // `resetPasswordForEmail` acabava caindo em `_asyncStorage!.setItem(...)`
    // com `_asyncStorage == null`, gerando
    // "Null check operator used on a null value". Usamos o fluxo `implicit`,
    // que não depende de storage local — o link recebido por e-mail já
    // contém o token de redefinição de senha diretamente.
    return _client ??= SupabaseClient(
      _url,
      _anonKey,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
  }

  static Future<int?> obterUsuarioIdPorEmail(String email) async {
    if (!isConfigured) return null;
    try {
      final rows = await _supabase
          .from('pessoas')
          .select('id, situacao')
          .eq('email', email.trim().toLowerCase())
          .order('situacao', ascending: true)
          .limit(1);
      if (rows.isEmpty) return null;
      return (rows.first['id'] as num).toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<int?> autenticarUsuario(String email, String senha) async {
    if (!isConfigured) return null;

    // ── 1. SHA-256 (senha_hash + salt na própria tabela pessoas) ──
    try {
      final emailLimpo = email.trim().toLowerCase();
      final rows = await _supabase
          .from('pessoas')
          .select('id, senha_hash, salt, _legacy_usuario_id')
          .eq('email', emailLimpo)
          .limit(1);
      if (rows.isNotEmpty) {
        final hashEsperado = rows.first['senha_hash'] as String?;
        final salt = rows.first['salt'] as String?;
        if (hashEsperado != null && salt != null) {
          final hashCalculado = sha256.convert(utf8.encode(senha + salt)).toString();
          if (hashCalculado == hashEsperado) {
            final pid = (rows.first['id'] as num).toInt();
            legadoUsuarioId = (rows.first['_legacy_usuario_id'] as num?)?.toInt();
            return pid;
          }
        }
      }
    } catch (e) {
      print('[PessoaRepo] autenticarUsuario SHA-256 ERRO: $e');
    }

    // ── 2. Fallback: Supabase Auth (para usuários criados via signUp) ──
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: senha,
      );
      if (response.user == null) return null;
      final rows = await _supabase
          .from('pessoas')
          .select('id, _legacy_usuario_id')
          .eq('auth_user_id', response.user!.id);
      if (rows.isEmpty) return null;
      final pid = (rows.first['id'] as num).toInt();
      legadoUsuarioId = (rows.first['_legacy_usuario_id'] as num?)?.toInt();
      return pid;
    } catch (e) {
      print('[PessoaRepo] autenticarUsuario Supabase ERRO: $e');
      return null;
    }
  }

  static Future<int?> criarUsuario({
    required String nome,
    required String sobrenome,
    required String email,
    required String senha,
  }) async {
    if (!isConfigured) return null;
    try {
      final emailLimpo = email.trim().toLowerCase();
      final existentes = await _supabase
          .from('pessoas')
          .select('id')
          .eq('email', emailLimpo);
      if (existentes.isNotEmpty) return -1;

      final response = await _supabase.auth.signUp(
        email: emailLimpo,
        password: senha,
      );
      if (response.user == null) return null;

      final salt = _gerarSalt();
      final hash = sha256.convert(utf8.encode(senha + salt)).toString();

      final resp = await _supabase.from('pessoas').insert({
        'nome': nome.trim(),
        'sobrenome': sobrenome.trim(),
        'email': emailLimpo,
        'auth_user_id': response.user!.id,
        'senha_hash': hash,
        'salt': salt,
        'situacao': 'ativo',
      }).select('id').single();
      return resp['id'] as int?;
    } catch (e) {
      print('[PessoaRepo] criarUsuario ERRO: $e');
      return null;
    }
  }

  static String _gerarSalt() {
    final random = dart_math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ── CONTATOS (Supabase) ──

  static Future<List<Pessoa>> listar() async {
    if (!isConfigured) return [];
    try {
      final rows = await _supabase
          .from('pessoas')
          .select('id, nome, sobrenome, email, telefone, tipo, data_nascimento, foto_perfil, situacao, falecido, created_at')
          .eq('criado_por_id', usuarioId)
          .order('nome');
      return rows.map((r) => Pessoa.fromMap(r)).toList();
    } catch (e) {
      print('[PessoaRepo] listar() ERRO: $e');
      return [];
    }
  }

  static Future<int?> salvar(Pessoa pessoa, {bool isUpdate = false}) async {
    if (!isConfigured) return null;

    print('[PessoaRepo] salvar() isUpdate=$isUpdate nome=${pessoa.nome} id=${pessoa.id}');
    
    String? fotoUrl = pessoa.fotoUrl;
    
    // Se houver bytes locais de foto nova, faz o upload para o Storage primeiro
    if (pessoa.fotoBytes != null) {
      final url = await uploadFotoPerfil(pessoa.fotoBytes!, 'contato_${pessoa.id}.jpg');
      if (url != null) {
        fotoUrl = url;
      }
    }

    final data = <String, dynamic>{
      'criado_por_id': usuarioId,
      'nome': pessoa.nome,
      'tipo': pessoa.tipo,
      'situacao': pessoa.situacao,
    };
    if (pessoa.apelido != null && pessoa.apelido!.isNotEmpty) {
      data['sobrenome'] = pessoa.apelido;
    }
    if (pessoa.dataNascimento != null) {
      data['data_nascimento'] =
          '${pessoa.dataNascimento!.year}-${pessoa.dataNascimento!.month.toString().padLeft(2, '0')}-${pessoa.dataNascimento!.day.toString().padLeft(2, '0')}';
    }
    if (fotoUrl != null) {
      data['foto_perfil'] = fotoUrl;
    }
    if (pessoa.email != null) {
      data['email'] = pessoa.email;
    }
    if (pessoa.telefone != null) {
      data['telefone'] = pessoa.telefone;
    }

    try {
      if (isUpdate) {
        await _supabase
            .from('pessoas')
            .update(data)
            .eq('id', pessoa.id);
        return pessoa.id;
      } else {
        data['created_at'] = pessoa.createdAt.toIso8601String();
        final result = await _supabase
            .from('pessoas')
            .insert(data)
            .select('id')
            .single();
        return result['id'] as int?;
      }
    } catch (e) {
      print('[PessoaRepo] salvar() ERRO: $e');
      return null;
    }
  }

  static Future<void> remover(int pessoaId) async {
    if (!isConfigured) return;
    try {
      await _supabase.from('conteudo_permissoes').delete().eq('pessoa_id', pessoaId);
      await _supabase
          .from('pessoas')
          .update({'situacao': 'inativo'})
          .eq('id', pessoaId)
          .eq('criado_por_id', usuarioId);
    } catch (_) {
      rethrow;
    }
  }

  static Future<void> limparVinculosMemoria(int memoriaId) async {
    if (!isConfigured) return;
    try {
      await _supabase
          .from('conteudo_permissoes')
          .delete()
          .eq('conteudo_id', memoriaId)
          .eq('tipo_conteudo', 'memoria');
    } catch (_) {}
  }

  static Future<void> atualizarMemoria({
    required int memoriaId,
    required String titulo,
    required String contexto,
    required String categoria,
    DateTime? dataEvento,
    bool? isCompartilhada,
  }) async {
    if (!isConfigured) return;
    final data = <String, dynamic>{
      'titulo': titulo,
      'conteudo': contexto,
      'categoria': categoria,
    };
    if (dataEvento != null) {
      data['data_evento'] =
          '${dataEvento.year}-${dataEvento.month.toString().padLeft(2, '0')}-${dataEvento.day.toString().padLeft(2, '0')}';
    }
    if (isCompartilhada != null) {
      data['visibilidade'] = isCompartilhada ? 'contatos' : 'privado';
    }
    await _supabase.from('memorias').update(data).eq('id', memoriaId);
  }

  static Future<String?> uploadFotoMemoria({
    required int memoriaId,
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    if (!isConfigured) return null;

    final nomeSeguro = nomeArquivo.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]'), '_',
    );
    final caminho =
        'usuario_$usuarioId/app_mobile/${DateTime.now().millisecondsSinceEpoch}_$nomeSeguro';

    await _supabase.storage.from('fotos').uploadBinary(
          caminho,
          bytes,
          fileOptions: FileOptions(
            contentType: nomeArquivo.endsWith('.png') ? 'image/png' : 'image/jpeg',
            upsert: false,
          ),
        );

    final publicUrl =
        _supabase.storage.from('fotos').getPublicUrl(caminho);

    final foto = await _supabase.from('fotos').insert({
      'usuario_id': usuarioId,
      'titulo': 'Foto da memória',
      'caminho_arquivo': publicUrl,
    }).select('id').single();

    final fotoId = (foto['id'] as num).toInt();

    await _supabase.from('memoria_fotos').insert({
      'memoria_id': memoriaId,
      'foto_id': fotoId,
    });

    return publicUrl;
  }

  static Future<void> removerFotosDaMemoria(int memoriaId) async {
    if (!isConfigured) return;
    final vinculos = await _supabase
        .from('memoria_fotos')
        .select('foto_id')
        .eq('memoria_id', memoriaId);
    for (final v in vinculos) {
      final fotoId = (v['foto_id'] as num).toInt();
      await _supabase.from('memoria_fotos').delete().eq('foto_id', fotoId);
      await _supabase.from('fotos').delete().eq('id', fotoId);
    }
  }

  static Future<String?> uploadVideoMemoria({
    required int memoriaId,
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    if (!isConfigured) return null;

    final nomeSeguro = nomeArquivo.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]'), '_',
    );
    final caminho =
        'usuario_$usuarioId/app_mobile/${DateTime.now().millisecondsSinceEpoch}_$nomeSeguro';

    try {
      await _supabase.storage.from('fotos').uploadBinary(
            caminho,
            bytes,
            fileOptions: FileOptions(
              contentType: 'video/mp4',
              upsert: false,
            ),
          );

      final publicUrl =
          _supabase.storage.from('fotos').getPublicUrl(caminho);

      final video = await _supabase.from('videos').insert({
        'usuario_id': usuarioId,
        'titulo': 'Vídeo da memória',
        'caminho_arquivo': publicUrl,
      }).select('id').single();

      final videoId = (video['id'] as num).toInt();

      await _supabase.from('memoria_videos').insert({
        'memoria_id': memoriaId,
        'video_id': videoId,
      });

      return publicUrl;
    } catch (_) {
      return null;
    }
  }

  static Future<void> removerVideosDaMemoria(int memoriaId) async {
    if (!isConfigured) return;
    try {
      final vinculos = await _supabase
          .from('memoria_videos')
          .select('video_id')
          .eq('memoria_id', memoriaId);
      for (final v in vinculos) {
        final videoId = (v['video_id'] as num).toInt();
        await _supabase.from('memoria_videos').delete().eq('video_id', videoId);
        await _supabase.from('videos').delete().eq('id', videoId);
      }
    } catch (_) {}
  }

  // ── USUÁRIO (Supabase pessoas) ──

  static Future<Map<String, dynamic>?> obterUsuario() async {
    if (!isConfigured) return null;
    try {
      final rows = await _supabase
          .from('pessoas')
          .select('nome, sobrenome, email, telefone, data_nascimento, foto_perfil, tipo, auth_user_id')
          .eq('id', usuarioId);
      if (rows.isEmpty) return null;
      return rows.first as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> salvarUsuario(Map<String, dynamic> data) async {
    if (!isConfigured) return;
    try {
      await _supabase.from('pessoas').update(data).eq('id', usuarioId);
    } catch (_) {}
  }

  static Future<String?> uploadFotoPerfil(Uint8List bytes, String nomeArquivo) async {
    if (!isConfigured) return null;

    final nomeSeguro = nomeArquivo.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]'), '_',
    );
    final caminho =
        'usuario_$usuarioId/app_mobile/perfil_${DateTime.now().millisecondsSinceEpoch}_$nomeSeguro';

    try {
      await _supabase.storage.from('fotos').uploadBinary(
            caminho,
            bytes,
            fileOptions: FileOptions(
              contentType: nomeArquivo.endsWith('.png') ? 'image/png' : 'image/jpeg',
              upsert: false,
            ),
          );

      final publicUrl = _supabase.storage.from('fotos').getPublicUrl(caminho);
      await salvarUsuario({'foto_perfil': publicUrl});
      return publicUrl;
    } catch (_) {
      return null;
    }
  }

  static Future<void> excluirMemoriaCompleta(int memoriaId) async {
    if (!isConfigured) return;
    // 1. Remover fotos e mídias vinculadas
    await removerFotosDaMemoria(memoriaId);
    // 2. Remover vídeos vinculados
    await removerVideosDaMemoria(memoriaId);
    // 3. Limpar vínculos de pessoas e compartilhamento
    await limparVinculosMemoria(memoriaId);
    // 4. Deletar o registro da memória em si
    await _supabase.from('memorias').delete().eq('id', memoriaId);
  }

  static Future<void> recuperarSenha(String email) async {
    final emailLimpo = email.trim();
    if (emailLimpo.isEmpty) {
      throw Exception('Informe um e-mail para recuperar a senha.');
    }
    if (!isConfigured) {
      throw Exception('SUPABASE_ANON_KEY não configurada.');
    }
    await _supabase.auth.resetPasswordForEmail(
      emailLimpo.toLowerCase(),
      redirectTo: 'aeterna://login',
    );
  }

  static Future<String?> obterVideoDaMemoria(int? memoriaId) async {
    if (!isConfigured || memoriaId == null) return null;
    try {
      final rows = await _supabase
          .from('memoria_videos')
          .select('video_id')
          .eq('memoria_id', memoriaId);
      if (rows.isEmpty) return null;
      final videoId = (rows.first['video_id'] as num).toInt();
      final videoRows = await _supabase
          .from('videos')
          .select('caminho_arquivo')
          .eq('id', videoId);
      if (videoRows.isEmpty) return null;
      return videoRows.first['caminho_arquivo'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> atualizarVisibilidadeMemoria(
    int memoriaId,
    bool isCompartilhada,
  ) async {
    if (!isConfigured) return;
    await _supabase
        .from('memorias')
        .update({'visibilidade': isCompartilhada ? 'contatos' : 'privado'})
        .eq('id', memoriaId);
  }

  // ── VÍNCULOS (Supabase conteudo_permissoes) ──

  static Future<Map<int, List<int>>> listarVinculos() async {
    if (!isConfigured) return {};

    try {
      final rows = await _supabase
          .from('conteudo_permissoes')
          .select('conteudo_id, pessoa_id')
          .eq('tipo_conteudo', 'memoria');
      final map = <int, List<int>>{};
      for (final r in rows) {
        final memId = (r['conteudo_id'] as num).toInt();
        final pessoaId = (r['pessoa_id'] as num).toInt();
        map.putIfAbsent(memId, () => []).add(pessoaId);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  static Future<void> salvarVinculo(int memoriaId, List<int> pessoaIds) async {
    if (!isConfigured) return;
    await _supabase
        .from('conteudo_permissoes')
        .delete()
        .eq('conteudo_id', memoriaId)
        .eq('tipo_conteudo', 'memoria');
    for (final pessoaId in pessoaIds) {
      await _supabase.from('conteudo_permissoes').insert({
        'tipo_conteudo': 'memoria',
        'conteudo_id': memoriaId,
        'pessoa_id': pessoaId,
      });
    }
  }

  static Future<List<int>> obterPessoasDaMemoria(int? memoriaId) async {
    if (memoriaId == null) return [];
    final vinculos = await listarVinculos();
    return vinculos[memoriaId] ?? [];
  }

  // ── COMPARTILHAMENTO = VÍNCULOS (mesma tabela conteudo_permissoes) ──

  static Future<Map<int, List<int>>> listarCompartilhamentos() =>
      listarVinculos();

  static Future<void> salvarCompartilhamento(
    int memoriaId,
    List<int> familiaresIds,
  ) =>
      salvarVinculo(memoriaId, familiaresIds);

  static Future<List<int>> obterFamiliaresDaMemoria(int? memoriaId) =>
      obterPessoasDaMemoria(memoriaId);

  // ── MEMÓRIAS COMPARTILHADAS COM O USUÁRIO LOGADO (Bug 1) ──
  //
  // Fonte PRIMÁRIA (Sprint de Vínculos Familiares): `conteudo_colaboradores`,
  // que grava a permissão real diretamente contra a CONTA (`usuario_id`) de
  // quem recebeu — sem depender de cruzamento por e-mail. É preenchida ao
  // aceitar um convite (`aceitarConviteFamiliar`) ou pelo backfill SQL para
  // compartilhamentos antigos.
  //
  // Fonte LEGADA (fallback, mantida por compatibilidade): cruza
  // `pessoas.email` (de QUALQUER dono) com o e-mail de login do usuário
  // atual, e busca vínculos em `conteudo_permissoes`. Cobre o caso de um
  // ambiente onde o backfill SQL ainda não foi rodado.
  static Future<Map<int, Map<String, dynamic>>>
      listarMemoriasCompartilhadasComigo() async {
    if (!isConfigured) return {};

    final resultado = <int, Map<String, dynamic>>{};

    // 1) Fonte primária: conteudo_colaboradores (conta real).
    try {
      final colaboracoes = await _supabase
          .from('conteudo_colaboradores')
          .select('conteudo_id, papel, concedido_por')
          .eq('tipo_conteudo', 'memoria')
          .eq('usuario_id', usuarioId);

      if (colaboracoes.isNotEmpty) {
        final donoIds = colaboracoes
            .map<int>((r) => (r['concedido_por'] as num?)?.toInt() ?? 0)
            .where((id) => id > 0)
            .toSet()
            .toList();
        final nomesPorDono = await _mapaNomesPorId(donoIds);

        for (final r in colaboracoes) {
          final memId = (r['conteudo_id'] as num).toInt();
          final donoId = (r['concedido_por'] as num?)?.toInt();
          resultado[memId] = {
            'usuario_id': donoId,
            'nome': (donoId != null && (nomesPorDono[donoId]?.isNotEmpty ?? false))
                ? nomesPorDono[donoId]
                : 'Familiar',
          };
        }
      }
    } catch (e) {
      print('[PessoaRepo] listarMemoriasCompartilhadasComigo() (real) ERRO: $e');
    }

    // 2) Fonte legada: cruzamento por e-mail (pessoas x conteudo_permissoes).
    if (usuarioEmail != null && usuarioEmail!.trim().isNotEmpty) {
      try {
        final email = usuarioEmail!.trim();

        final pessoasRows = await _supabase
            .from('pessoas')
            .select('id, criado_por_id')
            .eq('email', email.trim().toLowerCase());

        final donoPorContato = <int, int>{};
        for (final r in pessoasRows) {
          final donoId = (r['criado_por_id'] as num?)?.toInt();
          final pessoaId = (r['id'] as num?)?.toInt();
          if (donoId != null && pessoaId != null && donoId != usuarioId) {
            donoPorContato[pessoaId] = donoId;
          }
        }

        if (donoPorContato.isNotEmpty) {
          final permissoes = await _supabase
              .from('conteudo_permissoes')
              .select('conteudo_id, pessoa_id')
              .eq('tipo_conteudo', 'memoria')
              .inFilter('pessoa_id', donoPorContato.keys.toList());

          final donoPorMemoria = <int, int>{};
          for (final p in permissoes) {
            final memId = (p['conteudo_id'] as num).toInt();
            final pessoaId = (p['pessoa_id'] as num).toInt();
            final donoId = donoPorContato[pessoaId];
            if (donoId != null) donoPorMemoria[memId] = donoId;
          }

          if (donoPorMemoria.isNotEmpty) {
            final donoIds = donoPorMemoria.values.toSet().toList();
            final nomesPorDono = await _mapaNomesPorId(donoIds);

            for (final entry in donoPorMemoria.entries) {
              // Não sobrescreve se já veio da fonte primária (real).
              resultado.putIfAbsent(entry.key, () => {
                    'usuario_id': entry.value,
                    'nome': (nomesPorDono[entry.value]?.isNotEmpty ?? false)
                        ? nomesPorDono[entry.value]
                        : 'Familiar',
                  });
            }
          }
        }
      } catch (e) {
        print('[PessoaRepo] listarMemoriasCompartilhadasComigo() (legado) ERRO: $e');
      }
    }

    return resultado;
  }

  static Future<Map<int, String>> _mapaNomesPorId(List<int> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _supabase
          .from('pessoas')
          .select('id, nome, sobrenome')
          .inFilter('id', ids);
      return {
        for (final u in rows)
          (u['id'] as num).toInt():
              '${u['nome'] ?? ''} ${u['sobrenome'] ?? ''}'.trim(),
      };
    } catch (_) {
      return {};
    }
  }

  // ── DATAS DE MEMÓRIA (Supabase memorias.data_evento) ──

  static Future<void> salvarDataMemoria(int memoriaId, DateTime data) async {
    if (!isConfigured) return;
    final dateStr =
        '${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';
    await _supabase
        .from('memorias')
        .update({'data_evento': dateStr})
        .eq('id', memoriaId);
  }

  static Future<Map<int, DateTime>> carregarDatasMemorias() async {
    if (!isConfigured) return {};
    try {
      final rows = await _supabase
          .from('memorias')
          .select('id, data_evento')
          .not('data_evento', 'is', null);
      final result = <int, DateTime>{};
      for (final r in rows) {
        final dt = DateTime.tryParse('${r['data_evento']}');
        if (dt != null) result[(r['id'] as num).toInt()] = dt;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<List<int>> obterPessoasDoMemorial(int memorialId) async {
    if (!isConfigured) return [];
    try {
      final rows = await _supabase
          .from('memorial_pessoas')
          .select('pessoa_id')
          .eq('memorial_id', memorialId);
      return rows.map<int>((r) => (r['pessoa_id'] as num).toInt()).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> atualizarPessoasDoMemorial(int memorialId, List<int> pessoaIds) async {
    if (!isConfigured) return;
    try {
      await _supabase
          .from('memorial_pessoas')
          .delete()
          .eq('memorial_id', memorialId);
      if (pessoaIds.isNotEmpty) {
        await _supabase.from('memorial_pessoas').insert(
          pessoaIds.map((pid) => {
            'memorial_id': memorialId,
            'pessoa_id': pid,
          }).toList(),
        );
      }
    } catch (e) {
      print('Erro ao atualizar pessoas do memorial: $e');
    }
  }

  // ── CONVITES FAMILIARES (vínculo bilateral real entre contas) ──
  //
  // Substitui o modelo frágil "contato por e-mail" (Bug 1): agora existe um
  // convite de verdade, com aceite explícito, que gera um vínculo bilateral
  // (`vinculos_familiares`) e, opcionalmente, já concede permissão de
  // colaboração num conteúdo específico (memória/memorial).

  /// Envia um convite para o e-mail informado. Se [tipoConteudoAlvo] e
  /// [conteudoIdAlvo] forem informados, ao aceitar o convite a pessoa já
  /// recebe automaticamente o [papelSugerido] (editor/colaborador/leitor)
  /// nesse conteúdo — ex.: convidar alguém direto para colaborar num
  /// memorial.
  static Future<void> enviarConviteFamiliar({
    required String email,
    int? pessoaId,
    String? tipoConteudoAlvo,
    int? conteudoIdAlvo,
    PapelColaborador? papelSugerido,
  }) async {
    if (!isConfigured) {
      throw Exception('SUPABASE_ANON_KEY não configurada.');
    }
    final emailLimpo = email.trim().toLowerCase();
    if (emailLimpo.isEmpty || !emailLimpo.contains('@')) {
      throw Exception('Informe um e-mail válido para o convite.');
    }
    if (emailLimpo == usuarioEmail?.trim().toLowerCase()) {
      throw Exception('Você não pode convidar a si mesmo.');
    }

    // Se a pessoa já tem conta, já resolvemos o usuario_destino_id na hora
    // (não depende de aceite para sabermos quem é, só para conceder acesso).
    final usuarioDestinoId = await obterUsuarioIdPorEmail(emailLimpo);

    await _supabase.from('convites_familiares').insert({
      'usuario_origem_id': usuarioId,
      if (pessoaId != null) 'pessoa_id': pessoaId,
      'email_destino': emailLimpo,
      if (usuarioDestinoId != null) 'usuario_destino_id': usuarioDestinoId,
      'status': 'pendente',
      if (papelSugerido != null) 'papel_sugerido': papelSugerido.valor,
      if (tipoConteudoAlvo != null) 'tipo_conteudo_alvo': tipoConteudoAlvo,
      if (conteudoIdAlvo != null) 'conteudo_id_alvo': conteudoIdAlvo,
    });
  }

  /// Convites PENDENTES endereçados ao e-mail do usuário logado.
  static Future<List<ConviteFamiliar>> listarConvitesRecebidos() async {
    if (!isConfigured || usuarioEmail == null || usuarioEmail!.isEmpty) {
      return [];
    }
    try {
      final rows = await _supabase
          .from('convites_familiares')
          .select('*')
          .ilike('email_destino', usuarioEmail!.trim())
          .eq('status', 'pendente')
          .order('criado_em', ascending: false);

      if (rows.isEmpty) return [];

      final origemIds = rows
          .map<int>((r) => (r['usuario_origem_id'] as num).toInt())
          .toSet()
          .toList();
      final pessoasRows = await _supabase
          .from('pessoas')
          .select('id, nome, sobrenome')
          .inFilter('id', origemIds);
      final nomesPorId = <int, String>{
        for (final p in pessoasRows)
          (p['id'] as num).toInt():
              '${p['nome'] ?? ''} ${p['sobrenome'] ?? ''}'.trim(),
      };

      return rows
          .map<ConviteFamiliar>((r) => ConviteFamiliar.fromMap(
                r,
                nomeOrigem: nomesPorId[(r['usuario_origem_id'] as num).toInt()],
              ))
          .toList();
    } catch (e) {
      print('[PessoaRepo] listarConvitesRecebidos() ERRO: $e');
      return [];
    }
  }

  /// Convites que o usuário logado enviou (para exibir status na tela de
  /// Pessoas: pendente/aceito/recusado).
  static Future<List<ConviteFamiliar>> listarConvitesEnviados() async {
    if (!isConfigured) return [];
    try {
      final rows = await _supabase
          .from('convites_familiares')
          .select('*')
          .eq('usuario_origem_id', usuarioId)
          .order('criado_em', ascending: false);
      return rows.map<ConviteFamiliar>((r) => ConviteFamiliar.fromMap(r)).toList();
    } catch (e) {
      print('[PessoaRepo] listarConvitesEnviados() ERRO: $e');
      return [];
    }
  }

  /// Aceita um convite: marca status='aceito', cria o vínculo familiar
  /// BILATERAL (duas linhas em `vinculos_familiares`) e, se o convite tinha
  /// um conteúdo-alvo, já concede a permissão correspondente.
  static Future<void> aceitarConviteFamiliar(ConviteFamiliar convite) async {
    if (!isConfigured || convite.id == null) return;

    await _supabase.from('convites_familiares').update({
      'status': 'aceito',
      'aceito_em': DateTime.now().toIso8601String(),
      'usuario_destino_id': usuarioId,
    }).eq('id', convite.id!);

    // Vínculo bilateral (ON CONFLICT tratado via try/catch — a constraint
    // UNIQUE de `vinculos_familiares` impede duplicidade).
    try {
      await _supabase.from('vinculos_familiares').insert({
        'usuario_id': convite.usuarioOrigemId,
        'vinculado_usuario_id': usuarioId,
        'origem_convite_id': convite.id,
      });
    } catch (_) {}
    try {
      await _supabase.from('vinculos_familiares').insert({
        'usuario_id': usuarioId,
        'vinculado_usuario_id': convite.usuarioOrigemId,
        'origem_convite_id': convite.id,
      });
    } catch (_) {}

    // Se o convite já tinha um conteúdo-alvo (ex.: convite direto para
    // colaborar num memorial), concede a permissão automaticamente.
    if (convite.tipoConteudoAlvo != null && convite.conteudoIdAlvo != null) {
      try {
        await concederPermissaoConteudo(
          tipoConteudo: convite.tipoConteudoAlvo!,
          conteudoId: convite.conteudoIdAlvo!,
          usuarioIdColaborador: usuarioId,
          papel: PapelColaborador.fromValor(convite.papelSugerido) ??
              PapelColaborador.colaborador,
          conviteId: convite.id,
          concedidoPor: convite.usuarioOrigemId,
        );
      } catch (_) {}
    }
  }

  static Future<void> recusarConviteFamiliar(int conviteId) async {
    if (!isConfigured) return;
    await _supabase
        .from('convites_familiares')
        .update({'status': 'recusado'}).eq('id', conviteId);
  }

  /// Familiares (contas reais) vinculados bilateralmente ao usuário logado.
  static Future<List<VinculoFamiliar>> listarVinculosFamiliares() async {
    if (!isConfigured) return [];
    try {
      final rows = await _supabase
          .from('vinculos_familiares')
          .select('vinculado_usuario_id')
          .eq('usuario_id', usuarioId);
      if (rows.isEmpty) return [];

      final ids = rows
          .map<int>((r) => (r['vinculado_usuario_id'] as num).toInt())
          .toList();
      final usuariosRows = await _supabase
          .from('pessoas')
          .select('id, nome, sobrenome, email, foto_perfil')
          .inFilter('id', ids);

      return usuariosRows
          .map<VinculoFamiliar>((u) => VinculoFamiliar(
                usuarioId: (u['id'] as num).toInt(),
                nome: '${u['nome'] ?? ''} ${u['sobrenome'] ?? ''}'.trim(),
                fotoUrl: u['foto_perfil'] as String?,
                email: u['email'] as String?,
              ))
          .toList();
    } catch (e) {
      print('[PessoaRepo] listarVinculosFamiliares() ERRO: $e');
      return [];
    }
  }

  // ── PERMISSÕES GRANULARES (conteudo_colaboradores) ──

  /// Concede (ou atualiza) o papel de um colaborador real sobre um conteúdo.
  static Future<void> concederPermissaoConteudo({
    required String tipoConteudo,
    required int conteudoId,
    required int usuarioIdColaborador,
    required PapelColaborador papel,
    int? conviteId,
    int? concedidoPor,
  }) async {
    if (!isConfigured) return;
    await _supabase.from('conteudo_colaboradores').upsert(
      {
        'tipo_conteudo': tipoConteudo,
        'conteudo_id': conteudoId,
        'usuario_id': usuarioIdColaborador,
        'papel': papel.valor,
        if (conviteId != null) 'convite_id': conviteId,
        'concedido_por': concedidoPor ?? usuarioId,
      },
      onConflict: 'tipo_conteudo,conteudo_id,usuario_id',
    );
  }

  /// Remove o acesso de um colaborador a um conteúdo.
  static Future<void> removerPermissaoConteudo({
    required String tipoConteudo,
    required int conteudoId,
    required int usuarioIdColaborador,
  }) async {
    if (!isConfigured) return;
    await _supabase
        .from('conteudo_colaboradores')
        .delete()
        .eq('tipo_conteudo', tipoConteudo)
        .eq('conteudo_id', conteudoId)
        .eq('usuario_id', usuarioIdColaborador);
  }

  /// Lista os colaboradores reais (com papel) de um conteúdo específico —
  /// usado pelo dono para gerenciar permissões.
  static Future<List<Colaborador>> listarColaboradoresDoConteudo(
    String tipoConteudo,
    int conteudoId,
  ) async {
    if (!isConfigured) return [];
    try {
      final rows = await _supabase
          .from('conteudo_colaboradores')
          .select('usuario_id, papel')
          .eq('tipo_conteudo', tipoConteudo)
          .eq('conteudo_id', conteudoId);
      if (rows.isEmpty) return [];

      final ids = rows.map<int>((r) => (r['usuario_id'] as num).toInt()).toList();
      final pessoasRows = await _supabase
          .from('pessoas')
          .select('id, nome, sobrenome')
          .inFilter('id', ids);
      final nomesPorId = <int, String>{
        for (final p in pessoasRows)
          (p['id'] as num).toInt():
              '${p['nome'] ?? ''} ${p['sobrenome'] ?? ''}'.trim(),
      };

      return rows.map<Colaborador>((r) {
        final uid = (r['usuario_id'] as num).toInt();
        return Colaborador(
          usuarioId: uid,
          nome: nomesPorId[uid] ?? 'Familiar',
          papel: PapelColaborador.fromValor(r['papel'] as String?) ??
              PapelColaborador.leitor,
        );
      }).toList();
    } catch (e) {
      print('[PessoaRepo] listarColaboradoresDoConteudo() ERRO: $e');
      return [];
    }
  }

  /// Papel do usuário logado sobre um conteúdo que NÃO é dele (retorna null
  /// se não houver permissão concedida — quem chama deve checar "dono"
  /// separadamente comparando `usuario_id` do conteúdo).
  static Future<PapelColaborador?> obterMeuPapelNoConteudo(
    String tipoConteudo,
    int conteudoId,
  ) async {
    if (!isConfigured) return null;
    try {
      final rows = await _supabase
          .from('conteudo_colaboradores')
          .select('papel')
          .eq('tipo_conteudo', tipoConteudo)
          .eq('conteudo_id', conteudoId)
          .eq('usuario_id', usuarioId);
      if (rows.isEmpty) return null;
      return PapelColaborador.fromValor(rows.first['papel'] as String?);
    } catch (_) {
      return null;
    }
  }
}

const parentescos = [
  'Pai',
  'Mãe',
  'Avô',
  'Avó',
  'Bisavô',
  'Bisavó',
  'Irmão',
  'Irmã',
  'Filho',
  'Filha',
  'Tio',
  'Tia',
  'Primo',
  'Prima',
  'Amigo',
  'Outro',
];
