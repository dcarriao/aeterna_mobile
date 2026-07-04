import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/memoria_pode_crescer.dart';
import '../models/pessoa.dart';
import 'memory_growth_scoring_service.dart';
import 'workmanager_fanout.dart';

/// SPRINT I — Orquestrador dos convites do Curador para memórias
/// contínuas.
///
/// Responsabilidades:
///   1. Buscar memórias candidatas via RPC `memorias_que_podem_crescer`
///      (SQL da sprint).
///   2. Calcular score via [MemoryGrowthScoringService].
///   3. Filtrar dispensadas e bloqueadas.
///   4. Expor [listarParaHome] (top 3) e [listarParaMemoriaDetalhe] (1).
///   5. Notificar via push (Sprint F já tem a infra `flutter_local_notifications`
///      + Workmanager; aqui reusa com um novo canal `memory_growth`).
class MemoryGrowthInvitationService {
  MemoryGrowthInvitationService._();
  static final instance = MemoryGrowthInvitationService._();

  // ── SharedPreferences (reusa as chaves da Sprint F para o gate de
  // frequência diário/semanal — não há motivo para duplicar).
  static const _lastInviteDateKey = 'last_curator_invitation_date';
  static const _weeklyInvitesKey = 'weekly_curator_invitations_dates';

  static const _androidChannelId = 'memory_growth';
  static const _androidChannelName = 'Curador de Memórias Contínuas';
  static const _androidChannelDesc =
      'Convite para enriquecer memórias que podem crescer.';
  static const _wmTaskName = 'memory_growth_check';

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // ── QUEM SOU EU? ──
  // O canal `memory_growth` é separado do `curator_invitations` (Sprint F)
  // para que o usuário possa futuramente configurar cada tipo
  // independentemente. Esta sprint não cria tela de configuração;
  // só prepara a infra.

  bool _initialized = false;
  Future<void> inicializar() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        // Ao tocar na notificação, abrimos a MemoriaDetalheScreen.
        // O payload carrega o id da memória.
      },
    );
    // Android 13+: pedir permissão de notificação explicitamente.
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  /// Registra o job periódico do Workmanager (12h) que verifica
  /// memórias candidatas e dispara notificação push quando relevante.
  /// Idempotente — pode ser chamado várias vezes.
  Future<void> registrarVerificacaoPeriodica() async {
    // Liga o fan-out do Workmanager (Sprint I) ao callback do
    // `CuratorInvitationService` (Sprint F) — reusa o MESMO entry-point
    // para não conflitar com o limite de 1 dispatcher por processo.
    WorkmanagerFanOut.sprintIBridge = () {
      // fire-and-forget: o callbackDispatcher é sincrono e não pode
      // ser await; a logica real do background já trata o que precisa.
      MemoryGrowthInvitationService.instance.verificarEConvidarBackground();
    };
    await Workmanager().registerPeriodicTask(
      _wmTaskName,
      WorkmanagerFanOut.sprintITaskName,
      frequency: const Duration(hours: 12),
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: true,
      ),
    );
  }

  // ── QUERY ──
  /// Carrega as memórias candidatas (SQL) e retorna o TOP N com score
  /// acima do limite, já filtrando as dispensadas e pendentes.
  Future<List<MemoriaComScore>> listarParaHome({int limite = 3}) async {
    final candidatas = await _carregarCandidatas();
    final qualificadas = <MemoriaComScore>[];
    for (final m in candidatas) {
      if (m.totalContribuicoesPendentes > 0) continue;
      if (await MemoryGrowthScoringService.instance.foiDispensadaRecentemente(m.memoriaId)) {
        continue;
      }
      final score = await MemoryGrowthScoringService.instance.calcularScore(m);
      if (score.atingiuLimite) {
        qualificadas.add(MemoriaComScore(memoria: m, score: score));
      }
      if (qualificadas.length >= limite) break;
    }
    return qualificadas;
  }

  /// Versão para a MemoriaDetalheScreen: retorna até 1 sugestão para
  /// a memória específica, ou null se não atinge o limite.
  Future<MemoriaComScore?> obterParaMemoria(int memoriaId) async {
    final todas = await listarParaHome(limite: 50);
    for (final m in todas) {
      if (m.memoria.memoriaId == memoriaId) return m;
    }
    return null;
  }

  /// Chama a RPC e desserializa.
  Future<List<MemoriaPodeCrescer>> _carregarCandidatas() async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient
          .rpc('memorias_que_podem_crescer', params: {
        'usuario': PessoaRepository.usuarioId,
        'limite': 20, // Top 20 da SQL, depois o app filtra mais
      })
          .select('*');
      return rows
          .cast<Map<String, dynamic>>()
          .map(MemoriaPodeCrescer.fromMap)
          .toList();
    } catch (e) {
      print('[MemoryGrowth] _carregarCandidatas ERRO: $e');
      return const [];
    }
  }

  // ── FREQUÊNCIA / GATE (reaproveitando lógica da Sprint F) ──
  Future<bool> _validarLimitesFrequencia() async {
    final prefs = await SharedPreferences.getInstance();
    final agora = DateTime.now();

    final ultima = prefs.getString(_lastInviteDateKey);
    if (ultima != null) {
      final d = DateTime.tryParse(ultima);
      if (d != null &&
          d.year == agora.year &&
          d.month == agora.month &&
          d.day == agora.day) {
        return false; // já enviou hoje
      }
    }

    final envios = prefs.getStringList(_weeklyInvitesKey) ?? <String>[];
    final seteDiasAtras = agora.subtract(const Duration(days: 7));
    final enviosValidos = envios
        .map((s) => DateTime.tryParse(s))
        .where((d) => d != null && d.isAfter(seteDiasAtras))
        .map((d) => d!.toIso8601String())
        .toList();
    await prefs.setStringList(_weeklyInvitesKey, enviosValidos);
    if (enviosValidos.length >= 2) return false; // máx 2/semana
    return true;
  }

  Future<void> _registrarEnvioConvite() async {
    final prefs = await SharedPreferences.getInstance();
    final agora = DateTime.now().toIso8601String();
    await prefs.setString(_lastInviteDateKey, agora);
    final envios = prefs.getStringList(_weeklyInvitesKey) ?? <String>[];
    envios.add(agora);
    await prefs.setStringList(_weeklyInvitesKey, envios);
  }

  // ── WORKMANAGER (chamado pelo headless isolate) ──
  // O callback real vive em `curator_invitation_service.dart`
  // (callbackDispatcher) que faz fan-out para esta Sprint I via
  // `WorkmanagerFanOut.sprintIBridge` — Workmanager só permite 1
  // dispatcher por processo.
  Future<void> verificarEConvidarBackground() async {
    await inicializar();
    if (!PessoaRepository.isConfigured) return;
    if (!await _validarLimitesFrequencia()) return;

    final candidatas = await listarParaHome(limite: 1);
    if (candidatas.isEmpty) return;
    final top = candidatas.first;

    await _dispararNotificacao(top);
    await _registrarEnvioConvite();
  }

  // ── NOTIFICAÇÃO ──
  /// Dispara notificação push com mensagem adaptativa segundo o caso
  /// (heurística: "tem colaborador não-contribuiu" → Caso 1;
  /// "tem contribuições pendentes" → Caso 2; "autor único" → Caso 3).
  Future<void> _dispararNotificacao(MemoriaComScore top) async {
    final m = top.memoria;
    final criterios = top.score.criterios;

    final temColaboradorNaoContribuiu = criterios
        .any((c) => c.nome == 'Colaborador que ainda não contribuiu');
    final temAutorUnico = criterios
        .any((c) => c.nome == 'Memória com autor único');

    String titulo;
    String corpo;
    if (temColaboradorNaoContribuiu) {
      titulo = 'Sua família pode enriquecer "${m.titulo}"';
      corpo =
          'Vemos colaboradores cadastrados para essa história que ainda não contribuíram. Que tal convidá-los a participar?';
    } else if (temAutorUnico) {
      titulo = '"${m.titulo}" está esperando a versão de outras pessoas';
      corpo =
          'Essa história foi escrita só por você. Que tal convidar alguém que viveu esse momento para contar a versão dele?';
    } else {
      titulo = '"${m.titulo}" pode crescer ainda mais';
      corpo =
          'Encontramos novas possibilidades para enriquecer essa história com novas fotos, vídeos ou detalhes.';
    }

    const androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      m.memoriaId,
      titulo,
      corpo,
      platformDetails,
      payload: 'memoria:${m.memoriaId}',
    );
  }
}

/// Tupla (memória, score) para o retorno da Home / MemoriaDetalhe.
class MemoriaComScore {
  const MemoriaComScore({required this.memoria, required this.score});
  final MemoriaPodeCrescer memoria;
  final MemoryGrowthScore score;
}
