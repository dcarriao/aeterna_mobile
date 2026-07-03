import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'pending_memory_service.dart';
import '../models/pending_memory.dart';

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

  // Método de verificação em segundo plano
  Future<bool> verificarNovasMidiasEConvidar() async {
    try {
      // 1. Obter memórias pendentes
      final pendentes = await PendingMemoryService.instance.obterMemoriasPendentes();
      if (pendentes.isEmpty) {
        print('[CuratorInvitationService] Nenhuma mídia pendente de processamento encontrada.');
        return true;
      }

      final maisRecente = pendentes.first;

      // 2. Validar limites de frequência de convites
      final podeConvidar = await _validarLimitesFrequencia();
      if (!podeConvidar) {
        print('[CuratorInvitationService] Limite de frequência atingido. Convite ignorado.');
        return true;
      }

      // 3. Disparar o convite enriquecido por notificação
      await _dispararNotificacaoConvite(maisRecente);
      await _registrarEnvioConvite();

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
  Future<void> _dispararNotificacaoConvite(PendingMemory pending) async {
    final hasVideos = pending.quantidadeVideos > 0;
    
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
      pending.data.millisecondsSinceEpoch ~/ 1000, // ID único da notificação
      titulo,
      corpo,
      platformDetails,
      payload: pending.id,
    );
  }
}
