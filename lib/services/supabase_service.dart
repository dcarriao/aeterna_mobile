import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import '../models/memoria.dart';
import '../models/memorial.dart';
import '../models/contribuicao.dart';
import 'push_notification_service.dart';

class SupabaseService {
  SupabaseService._();

  static final instance = SupabaseService._();

  static const _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zfpvfljmnlgsqiqdxmka.supabase.co',
  );
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _bucketFotos = 'fotos';

  // ID de usuário dinâmico para isolamento de dados
  static int usuarioId = 2;

  bool get isConfigured => _anonKey.isNotEmpty;

  SupabaseClient? _supabaseClient;

  // BUG 2: evita o crash "Null check operator used on a null value" ao
  // usar métodos de auth (ex: resetPasswordForEmail) — ver pessoa.dart
  // para a explicação completa (fluxo PKCE exige asyncStorage que não é
  // fornecido a este cliente headless).
  static const _authOptions =
      AuthClientOptions(authFlowType: AuthFlowType.implicit);

  SupabaseClient get _client {
    if (!isConfigured) {
      throw const SupabaseConfigurationException();
    }
    return _supabaseClient ??=
        SupabaseClient(_url, _anonKey, authOptions: _authOptions);
  }

  static Future<void> initialize() async {
    final anonMasked = _anonKey.length > 8 ? '${_anonKey.substring(0, 8)}...' : '(vazio)';
    print('[Supabase] Inicializando SupabaseService...');
    print('[Supabase] URL: $_url');
    print('[Supabase] ANON_KEY: $anonMasked');
    if (!instance.isConfigured) {
      print('[Supabase] ALERTA: SUPABASE_ANON_KEY está vazia! O app funcionará em modo offline.');
    }
    if (!instance.isConfigured) return;
    instance._supabaseClient =
        SupabaseClient(_url, _anonKey, authOptions: _authOptions);
  }

  Future<List<Memoria>> listarMemorias() async {
    if (!isConfigured) return const [];

    final memoriaRows = await _client
        .from('memorias')
        .select('id, titulo, conteudo, categoria, data_criacao, data_evento')
        .eq('usuario_id', usuarioId)
        .order('data_criacao', ascending: false);

    if (memoriaRows.isEmpty) return const [];

    final memoriaIds = memoriaRows.map<int>((row) => row['id'] as int).toList();
    final vinculoRows = await _client
        .from('memoria_fotos')
        .select('memoria_id, foto_id')
        .inFilter('memoria_id', memoriaIds);

    final fotoPorMemoria = <int, String>{};
    if (vinculoRows.isNotEmpty) {
      final fotoIds = vinculoRows
          .map<int>((row) => row['foto_id'] as int)
          .toSet()
          .toList();
      final fotoRows = await _client
          .from('fotos')
          .select('id, caminho_arquivo')
          .inFilter('id', fotoIds);
      final urlsPorFoto = <int, String>{
        for (final row in fotoRows)
          if (row['caminho_arquivo'] != null)
            row['id'] as int: row['caminho_arquivo'] as String,
      };

      for (final vinculo in vinculoRows) {
        final url = urlsPorFoto[vinculo['foto_id'] as int];
        if (url != null) {
          fotoPorMemoria.putIfAbsent(vinculo['memoria_id'] as int, () => url);
        }
      }
    }

    // S.9.4b (Item 3) — vídeos em lote: cards/timeline sabem que a
    // memória tem vídeo sem N+1.
    final videoPorMemoria = <int, String>{};
    try {
      final vidVinculos = await _client
          .from('memoria_videos')
          .select('memoria_id, video_id')
          .inFilter('memoria_id', memoriaIds);
      if (vidVinculos.isNotEmpty) {
        final videoIds = vidVinculos
            .map<int>((r) => r['video_id'] as int)
            .toSet()
            .toList();
        final videoRows = await _client
            .from('videos')
            .select('id, caminho_arquivo')
            .inFilter('id', videoIds);
        final urlPorVideo = <int, String>{
          for (final r in videoRows)
            if (r['caminho_arquivo'] != null)
              r['id'] as int: r['caminho_arquivo'] as String,
        };
        for (final v in vidVinculos) {
          final url = urlPorVideo[v['video_id'] as int];
          if (url != null) {
            videoPorMemoria.putIfAbsent(v['memoria_id'] as int, () => url);
          }
        }
      }
      // S.9.4c — visibilidade: por que o bloco de vídeo não aparece no card
      // da home. Registra no painel de diagnóstico do Perfil.
      PushNotificationService.registrarDiagnostico(
          'videos lote: ${vidVinculos.length} vinculo(s), '
          '${videoPorMemoria.length} card(s) com vídeo');
    } catch (e) {
      print('[SupabaseService] videos em lote ERRO: $e');
      PushNotificationService.registrarDiagnostico('videos lote ERRO: $e');
    }

    return memoriaRows.map<Memoria>((row) {
      final id = row['id'] as int;
      return Memoria.fromMap(row,
          fotoUrl: fotoPorMemoria[id], videoUrl: videoPorMemoria[id]);
    }).toList();
  }

  /// Busca memórias que OUTRAS contas compartilharam com o usuário logado.
  ///
  /// [vinculos] é o mapa `memoriaId -> {usuario_id, nome}` retornado por
  /// `PessoaRepository.listarMemoriasCompartilhadasComigo()`. Essas
  /// memórias podem pertencer a qualquer `usuario_id`, por isso a busca
  /// NÃO filtra por `usuario_id == usuarioId` (Bug 1).
  Future<List<Memoria>> listarMemoriasRecebidas(
    Map<int, Map<String, dynamic>> vinculos,
  ) async {
    if (!isConfigured || vinculos.isEmpty) return const [];

    final ids = vinculos.keys.toList();
    final memoriaRows = await _client
        .from('memorias')
        .select('id, titulo, conteudo, categoria, data_criacao, data_evento')
        .inFilter('id', ids)
        .order('data_criacao', ascending: false);

    if (memoriaRows.isEmpty) return const [];

    final memoriaIds = memoriaRows.map<int>((row) => row['id'] as int).toList();
    final vinculoFotoRows = await _client
        .from('memoria_fotos')
        .select('memoria_id, foto_id')
        .inFilter('memoria_id', memoriaIds);

    final fotoPorMemoria = <int, String>{};
    if (vinculoFotoRows.isNotEmpty) {
      final fotoIds = vinculoFotoRows
          .map<int>((row) => row['foto_id'] as int)
          .toSet()
          .toList();
      final fotoRows = await _client
          .from('fotos')
          .select('id, caminho_arquivo')
          .inFilter('id', fotoIds);
      final urlsPorFoto = <int, String>{
        for (final row in fotoRows)
          if (row['caminho_arquivo'] != null)
            row['id'] as int: row['caminho_arquivo'] as String,
      };
      for (final vinculo in vinculoFotoRows) {
        final url = urlsPorFoto[vinculo['foto_id'] as int];
        if (url != null) {
          fotoPorMemoria.putIfAbsent(vinculo['memoria_id'] as int, () => url);
        }
      }
    }

    return memoriaRows.map<Memoria>((row) {
      final id = row['id'] as int;
      final info = vinculos[id];
      return Memoria.fromMap(
        row,
        fotoUrl: fotoPorMemoria[id],
        donoUsuarioId: info?['usuario_id'] as int?,
        compartilhadaPorNome: info?['nome'] as String?,
      );
    }).toList();
  }

  Future<Memoria> salvarMemoriaComFoto(MemoriaRascunho rascunho) async {
    if (!isConfigured) {
      return Memoria(
        titulo: rascunho.titulo,
        contexto: rascunho.contexto,
        categoria: rascunho.categoria,
        criadaEm: DateTime.now(),
        foto: rascunho.foto,
      );
    }

    final agora = DateTime.now();
    int? memoriaId;
    int? fotoId;
    String? caminhoStorage;

    try {
      final memoria = await _client
          .from('memorias')
          .insert({
            'usuario_id': usuarioId,
            'categoria': rascunho.categoria,
            'titulo': rascunho.titulo,
            'conteudo': rascunho.contexto,
            'origem': 'app_mobile',
            'data_criacao': agora.toIso8601String(),
          })
          .select('id')
          .single();
      memoriaId = memoria['id'] as int;

      String? publicUrl;
      if (rascunho.foto != null) {
        caminhoStorage = _criarCaminhoArquivo(
          agora,
          rascunho.nomeArquivo ?? 'foto.jpg',
        );
        await _uploadFoto(
          caminho: caminhoStorage,
          bytes: rascunho.foto!,
          nomeArquivo: rascunho.nomeArquivo,
        );
        publicUrl = _client.storage
            .from(_bucketFotos)
            .getPublicUrl(caminhoStorage);

        final foto = await _client
            .from('fotos')
            .insert({
              'usuario_id': usuarioId,
              'titulo': rascunho.titulo,
              'descricao': rascunho.contexto,
              'categoria': rascunho.categoria,
              'caminho_arquivo': publicUrl,
              'data_criacao': agora.toIso8601String(),
            })
            .select('id')
            .single();
        fotoId = foto['id'] as int;

        await _client.from('memoria_fotos').insert({
          'memoria_id': memoriaId,
          'foto_id': fotoId,
        });
      }

      return Memoria(
        id: memoriaId,
        titulo: rascunho.titulo,
        contexto: rascunho.contexto,
        categoria: rascunho.categoria,
        criadaEm: agora,
        foto: rascunho.foto,
        fotoUrl: publicUrl,
      );
    } catch (_) {
      await _rollback(
        memoriaId: memoriaId,
        fotoId: fotoId,
        caminhoStorage: caminhoStorage,
      );
      rethrow;
    }
  }

  Future<void> _uploadFoto({
    required String caminho,
    required Uint8List bytes,
    String? nomeArquivo,
  }) async {
    await _client.storage
        .from(_bucketFotos)
        .uploadBinary(
          caminho,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentType(nomeArquivo),
            upsert: false,
          ),
        );
  }

  String _criarCaminhoArquivo(DateTime data, String nomeOriginal) {
    final nomeSeguro = nomeOriginal.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]'),
      '_',
    );
    return 'usuario_$usuarioId/app_mobile/'
        '${data.microsecondsSinceEpoch}_$nomeSeguro';
  }

  String _contentType(String? nomeArquivo) {
    final nome = nomeArquivo?.toLowerCase() ?? '';
    if (nome.endsWith('.png')) return 'image/png';
    if (nome.endsWith('.webp')) return 'image/webp';
    if (nome.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _rollback({
    int? memoriaId,
    int? fotoId,
    String? caminhoStorage,
  }) async {
    try {
      if (memoriaId != null && fotoId != null) {
        await _client
            .from('memoria_fotos')
            .delete()
            .eq('memoria_id', memoriaId)
            .eq('foto_id', fotoId);
      }
      if (fotoId != null) {
        await _client.from('fotos').delete().eq('id', fotoId);
      }
      if (memoriaId != null) {
        await _client.from('memorias').delete().eq('id', memoriaId);
      }
      if (caminhoStorage != null) {
        await _client.storage.from(_bucketFotos).remove([caminhoStorage]);
      }
    } catch (_) {
      // Mantém o erro original; políticas RLS podem impedir a limpeza.
    }
  }

  // ── MEMORIAIS (Supabase) ──

  Future<List<Memorial>> listarMemoriais() async {
    if (!isConfigured) return const [];
    try {
      final rows = await _client
          .from('memoriais')
          .select('*')
          .eq('usuario_id', usuarioId)
          .order('criado_em', ascending: false);
      return rows.map<Memorial>((row) => Memorial.fromMap(row)).toList();
    } catch (e) {
      print('Erro ao listar memoriais: $e');
      return const [];
    }
  }

  /// S.9.3.2 — ids de memoriais vinculados a pets (para separar a lista).
  Future<Set<int>> listarMemorialIdsDePets() async {
    if (!isConfigured) return {};
    try {
      final pets =
          await _client.from('pessoas').select('id').eq('tipo', 'pet');
      final petIds = [for (final r in pets) (r['id'] as num).toInt()];
      if (petIds.isEmpty) return {};
      final rows = await _client
          .from('memorial_pessoas')
          .select('memorial_id')
          .inFilter('pessoa_id', petIds);
      return {
        for (final r in rows)
          if (r['memorial_id'] != null) (r['memorial_id'] as num).toInt(),
      };
    } catch (e) {
      print('Erro ao listar memoriais de pets: $e');
      return {};
    }
  }

  Future<Memorial> salvarMemorial(Memorial memorial) async {
    if (!isConfigured) return memorial;
    final agora = DateTime.now();
    String? publicUrl = memorial.fotoUrl;

    if (memorial.fotoBytes != null) {
      final caminhoStorage = _criarCaminhoArquivo(
        agora,
        'memorial_${agora.millisecondsSinceEpoch}.jpg',
      );
      await _uploadFoto(
        caminho: caminhoStorage,
        bytes: memorial.fotoBytes!,
        nomeArquivo: 'foto.jpg',
      );
      publicUrl = _client.storage
          .from(_bucketFotos)
          .getPublicUrl(caminhoStorage);
    }

    final data = memorial.toMap();
    if (publicUrl != null) {
      data['foto_perfil'] = publicUrl;
    }

    final row = await _client
        .from('memoriais')
        .insert(data)
        .select('id, nome, parentesco, data_nascimento, data_falecimento, biografia, foto_perfil, usuario_id, criado_em')
        .single();

    return Memorial.fromMap(row);
  }

  /// Permite que dono OU colaborador com papel `editor` altere a biografia
  /// (requisito 8 da sprint de colaboração — memorial não pode ser só
  /// leitura).
  Future<void> atualizarBiografiaMemorial(int id, String biografia) async {
    if (!isConfigured) return;
    await _client.from('memoriais').update({'biografia': biografia}).eq('id', id);
  }

  Future<void> excluirMemorial(int id) async {
    if (!isConfigured) return;
    try {
      await _client.from('memorial_pessoas').delete().eq('memorial_id', id);
    } catch (_) {}
    try {
      await _client.from('contribuicoes').delete().eq('memorial_id', id);
    } catch (_) {}
    try {
      await _client.from('conteudo_colaboradores')
          .delete()
          .eq('tipo_conteudo', 'memorial')
          .eq('conteudo_id', id);
    } catch (_) {}
    try {
      await _client.from('memoriais').delete().eq('id', id);
    } catch (_) {}
  }

  static const _colunasContribuicao =
      'id, memorial_id, tipo_conteudo, conteudo_id, usuario_dono_id, '
      'usuario_contribuidor_email, usuario_contribuidor_nome, '
      'tipo_contribuicao, texto, arquivo_url, audio_url, status, criado_em, '
      'avaliado_em, avaliado_por';

  /// Memoriais em que o usuário logado NÃO é dono, mas tem permissão de
  /// colaboração concedida via `conteudo_colaboradores` (tipo_conteudo =
  /// 'memorial'). Complementa `listarMemoriais()` (que só traz os próprios).
  Future<List<Memorial>> listarMemoriaisColaborativos() async {
    if (!isConfigured) return const [];
    try {
      final vinculos = await _client
          .from('conteudo_colaboradores')
          .select('conteudo_id')
          .eq('tipo_conteudo', 'memorial')
          .eq('usuario_id', usuarioId);
      if (vinculos.isEmpty) return const [];

      final ids = vinculos
          .map<int>((r) => (r['conteudo_id'] as num).toInt())
          .toSet()
          .toList();

      final rows = await _client
          .from('memoriais')
        .select('id, nome, parentesco, data_nascimento, data_falecimento, biografia, foto_perfil, usuario_id, criado_em')
          .inFilter('id', ids)
          .order('criado_em', ascending: false);
      return rows.map<Memorial>((row) => Memorial.fromMap(row)).toList();
    } catch (e) {
      print('Erro ao listar memoriais colaborativos: $e');
      return const [];
    }
  }

  // ── CONTRIBUIÇÕES (Supabase) ──

  Future<List<Contribuicao>> listarContribuicoes(
    int memorialId, {
    bool apenasAprovadas = false,
  }) async {
    if (!isConfigured) return const [];
    try {
      var query = _client
          .from('contribuicoes')
          .select(_colunasContribuicao)
          .eq('memorial_id', memorialId);

      if (apenasAprovadas) {
        query = query.eq('status', 'aprovado');
      }

      final rows = await query.order('criado_em', ascending: false);
      return rows.map<Contribuicao>((row) => Contribuicao.fromMap(row)).toList();
    } catch (e) {
      print('Erro ao listar contribuicoes: $e');
      return const [];
    }
  }

  /// Lista TODAS as contribuições de uma MEMÓRIA (Sprint G).
  /// Diferente de [listarContribuicoes], que filtra por `memorial_id`,
  /// esta consulta usa a FK polimórfica (`tipo_conteudo='memoria'` +
  /// `conteudo_id=memoriaId`) — o schema real já permite isso desde a
  /// sprint anterior; só não tinha UI que o usasse.
  Future<List<Contribuicao>> listarContribuicoesDaMemoria(
    int memoriaId, {
    bool apenasAprovadas = false,
  }) async {
    if (!isConfigured) return const [];
    try {
      var query = _client
          .from('contribuicoes')
          .select(_colunasContribuicao)
          .eq('tipo_conteudo', 'memoria')
          .eq('conteudo_id', memoriaId);

      if (apenasAprovadas) {
        query = query.eq('status', 'aprovado');
      }

      final rows = await query.order('criado_em', ascending: true);
      return rows.map<Contribuicao>((row) => Contribuicao.fromMap(row)).toList();
    } catch (e) {
      print('Erro ao listar contribuicoes da memoria: $e');
      return const [];
    }
  }

  /// Lê a flag `aprovacao_obrigatoria` de uma memória (Sprint G).
  /// Default: TRUE (preserva o comportamento conservador — se a coluna
  /// ainda não existe no banco, devolve true e o app mostra o caminho
  /// de aprovação obrigatória).
  Future<bool> memoriaExigeAprovacao(int memoriaId) async {
    if (!isConfigured) return true;
    try {
      final rows = await _client
          .from('memorias')
          .select('aprovacao_obrigatoria')
          .eq('id', memoriaId)
          .limit(1);
      if (rows.isEmpty) return true;
      final v = rows.first['aprovacao_obrigatoria'];
      return v is bool ? v : true;
    } catch (_) {
      return true;
    }
  }

  Future<Contribuicao> salvarContribuicao(Contribuicao contribuicao) async {
    if (!isConfigured) return contribuicao;
    final agora = DateTime.now();
    String? arquivoPublicUrl = contribuicao.arquivoUrl;
    String? audioPublicUrl = contribuicao.audioUrl;

    if (contribuicao.fotoBytes != null) {
      final caminhoStorage = _criarCaminhoArquivo(
        agora,
        'contrib_foto_${agora.millisecondsSinceEpoch}.jpg',
      );
      await _uploadFoto(
        caminho: caminhoStorage,
        bytes: contribuicao.fotoBytes!,
        nomeArquivo: 'foto.jpg',
      );
      arquivoPublicUrl = _client.storage
          .from(_bucketFotos)
          .getPublicUrl(caminhoStorage);
    } else if (contribuicao.videoBytes != null) {
      final caminhoStorage = _criarCaminhoArquivo(
        agora,
        'contrib_video_${agora.millisecondsSinceEpoch}.mp4',
      );
      await _client.storage.from(_bucketFotos).uploadBinary(
        caminhoStorage,
        contribuicao.videoBytes!,
        fileOptions: const FileOptions(contentType: 'video/mp4'),
      );
      arquivoPublicUrl = _client.storage
          .from(_bucketFotos)
          .getPublicUrl(caminhoStorage);
    } else if (contribuicao.audioBytes != null) {
      final caminhoStorage = _criarCaminhoArquivo(
        agora,
        'contrib_audio_${agora.millisecondsSinceEpoch}.m4a',
      );
      await _client.storage.from(_bucketFotos).uploadBinary(
        caminhoStorage,
        contribuicao.audioBytes!,
        fileOptions: const FileOptions(contentType: 'audio/m4a'),
      );
      audioPublicUrl = _client.storage
          .from(_bucketFotos)
          .getPublicUrl(caminhoStorage);
    }

    final data = contribuicao.toMap();
    if (arquivoPublicUrl != null) data['arquivo_url'] = arquivoPublicUrl;
    if (audioPublicUrl != null) data['audio_url'] = audioPublicUrl;

    final row = await _client
        .from('contribuicoes')
        .insert(data)
        .select(_colunasContribuicao)
        .single();

    return Contribuicao.fromMap(row);
  }

  /// Aprova ou rejeita uma contribuição. Diferente do comportamento antigo
  /// (que APAGAVA a contribuição ao rejeitar), agora usamos `status` para
  /// preservar o histórico (soft-reject), consistente com o schema real
  /// (`status` in ('pendente','aprovado','rejeitado')).
  Future<void> moderarContribuicao(
    int id,
    bool aprovado, {
    int? avaliadoPor,
  }) async {
    if (!isConfigured) return;
    try {
      await _client.from('contribuicoes').update({
        'status': aprovado ? 'aprovado' : 'rejeitado',
        'avaliado_em': DateTime.now().toIso8601String(),
        if (avaliadoPor != null) 'avaliado_por': avaliadoPor,
      }).eq('id', id);
    } catch (e) {
      print('Erro ao moderar contribuicao: $e');
    }
  }
}

class SupabaseConfigurationException implements Exception {
  const SupabaseConfigurationException();

  @override
  String toString() => 'SUPABASE_ANON_KEY não configurada.';
}
