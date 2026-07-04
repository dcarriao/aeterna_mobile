import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/detected_moment.dart';
import 'curator_decision_log_service.dart';
import 'curator_invitation_scoring_service.dart';
import 'moment_detection_service.dart';

// Função global obrigatória para o Workmanager (headless isolate)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('[Workmanager] Executando tarefa em background: $task');
    try {
      final success = await CuratorInvitationService.instance.verificarNovasMidiasEConvidar();
      return success;
    } catch (e) {
      print('[Workmanager] Erro na execução da tarefa: $e');
      return false;
    }
  });
}

/// SPRINT F — Sensibilidade dos Convites do Curador.
///
/// ANTES desta sprint, este serviço decidia notificar com base apenas em
/// "existe alguma mídia não usada" + limite de frequência (1/dia, 2/semana),
/// usando `PendingMemoryService` (agrupamento por DIA CIVIL). Isso divergia
/// da fonte usada pela Home (`MomentDetectionService`, agrupamento por
/// PROXIMIDADE de 90 min), fazendo a notificação e o banner da Home falarem
/// de "momentos" potencialmente diferentes — achado da auditoria desta
/// sprint.
///
/// A partir de agora, notificação e Home usam a MESMA fonte
/// (`MomentDetectionService`) e o MESMO sistema de pontuação
/// (`CuratorInvitationScoringService`), garantindo que só um momento que
/// já seria mostrado como convite principal na Home possa também virar
/// notificação.
class CuratorInvitationService {
  CuratorInvitationService._();

  static final instance = CuratorInvitationService._();

  static const _lastInviteDateKey = 'last_curator_invitation_date';
  static const _weeklyInvitesKey = 'weekly_curator_invitations_dates';

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // Inicializar Notificações e Workmanager
  Future<void> inicializar() async {
    // 1. Inicializar Notificações Locais
    const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        print('[Notifications] Usuário clicou na notificação: ${details.payload}');
      },
    );

    // Solicita permissão de notificação em runtime (Android 13+ exige
    // POST_NOTIFICATIONS explícito; sem isso, `_notificationsPlugin.show`
    // silenciosamente não exibe nada em muitos dispositivos).
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // 2. Inicializar Workmanager
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    // Registrar tarefa periódica (a cada 12 horas para monitorar galeria)
    await Workmanager().registerPeriodicTask(
      'curator_gallery_monitor',
      'verificarNovasMidiasEConvidar',
      frequency: const Duration(hours: 12),
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: true,
      ),
    );

    print('[CuratorInvitationService] Infraestrutura de background e notificações inicializada.');
  }

  /// Método de verificação em segundo plano. Regra central: só notifica se
  /// (1) o momento pontuar >= limite mínimo E (2) os limites explícitos de
  /// frequência/recusas também permitirem.
  Future<bool> verificarNovasMidiasEConvidar() async {
    try {
      final momentos = await MomentDetectionService.instance.obterMomentosDetectados();
      if (momentos.isEmpty) {
        print('[CuratorInvitationService] Nenhum momento detectado.');
        return true;
      }

      final maisRecente = momentos.first;
      final score = await CuratorInvitationScoringService.instance.calcularScore(maisRecente);

      if (!score.atingiuLimite) {
        print('[CuratorInvitationService] Score insuficiente. ${score.motivoResumido}');
        await CuratorDecisionLogService.instance.registrarDecisao(
          momento: maisRecente,
          score: score,
          conviteCriado: false,
        );
        return true;
      }

      final dentroDaFrequencia = await _validarLimitesFrequencia();
      final recusouMuito =
          await CuratorInvitationScoringService.instance.usuarioRecusouMuitasVezesRecentemente();

      if (!dentroDaFrequencia || recusouMuito) {
        print('[CuratorInvitationService] Bloqueado por frequência/recusas recentes.');
        await CuratorDecisionLogService.instance.registrarDecisao(
          momento: maisRecente,
          score: score,
          conviteCriado: false,
        );
        return true;
      }

      await _dispararNotificacaoConvite(maisRecente);
      await _registrarEnvioConvite();
      await CuratorDecisionLogService.instance.registrarDecisao(
        momento: maisRecente,
        score: score,
        conviteCriado: true,
      );

      return true;
    } catch (e) {
      print('[CuratorInvitationService] Erro ao verificar novas mídias: $e');
      return false;
    }
  }

  // Verificar regras de frequência (Máximo: 1 por dia, 2 por semana)
  Future<bool> _validarLimitesFrequencia() async {
    final prefs = await SharedPreferences.getInstance();
    final agora = DateTime.now();

    // Regra 1: Máximo 1 por dia
    final ultimaDataStr = prefs.getString(_lastInviteDateKey);
    if (ultimaDataStr != null) {
      final ultimaData = DateTime.tryParse(ultimaDataStr);
      if (ultimaData != null &&
          ultimaData.year == agora.year &&
          ultimaData.month == agora.month &&
          ultimaData.day == agora.day) {
        return false; // Já enviou hoje
      }
    }

    // Regra 2: Máximo 2 por semana
    final enviosSemana = prefs.getStringList(_weeklyInvitesKey) ?? <String>[];
    final seteDiasAtras = agora.subtract(const Duration(days: 7));

    // Filtrar e limpar envios mais velhos de 7 dias
    final enviosValidos = enviosSemana
        .map((s) => DateTime.tryParse(s))
        .where((d) => d != null && d.isAfter(seteDiasAtras))
        .map((d) => d!.toIso8601String())
        .toList();

    await prefs.setStringList(_weeklyInvitesKey, enviosValidos);

    if (enviosValidos.length >= 2) {
      return false; // Limite de 2 por semana atingido
    }

    return true;
  }

  // Registrar a data e atualizar contadores de envio
  Future<void> _registrarEnvioConvite() async {
    final prefs = await SharedPreferences.getInstance();
    final agora = DateTime.now();

    await prefs.setString(_lastInviteDateKey, agora.toIso8601String());

    final enviosSemana = prefs.getStringList(_weeklyInvitesKey) ?? <String>[];
    enviosSemana.add(agora.toIso8601String());
    await prefs.setStringList(_weeklyInvitesKey, enviosSemana);
  }

  // Entregar a notificação na bandeja do sistema
  Future<void> _dispararNotificacaoConvite(DetectedMoment momento) async {
    final hasVideos = momento.quantidadeVideos > 0;

    final titulo = hasVideos ? 'Você gravou um vídeo hoje. 📹' : 'Você registrou um momento hoje. 📷';
    const corpo = 'Vamos preservar a história por trás dele antes que os detalhes se percam?';

    const androidDetails = AndroidNotificationDetails(
      'curator_invitations',
      'Convites do Curador',
      channelDescription: 'Sugestões proativas do curador de memórias',
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
      momento.inicio.millisecondsSinceEpoch ~/ 1000, // ID único da notificação
      titulo,
      corpo,
      platformDetails,
      payload: momento.id,
    );
  }
}
