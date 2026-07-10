// lib/services/push_notification_service.dart
// Sprint S.9.2 — Push Notifications Transacionais
//
// Mudanças em relação ao Sprint R.4:
//   - RPC corrigida: upsert_device_token(p_usuario_id) → upsert_push_dispositivo(p_pessoa_id)
//     (a FK era para usuarios.id; agora aponta para pessoas.id — correto desde Sprint S.3)
//   - desativarDispositivoAtual(): chamado no logout para marcar ativo=false
//   - Foreground: exibe notificação local via flutter_local_notifications
//   - Toque na notificação: navega para a rota correta via callback (_navigationCallback)
//   - Logs: [PUSH_TOKEN] e [PUSH_OPEN] para rastreamento

import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import '../models/pessoa.dart';

/// Callback invocado quando o usuário toca numa notificação push.
/// Recebe o [data] do payload FCM (campo `data`, nunca `notification`).
typedef PushNavigationCallback = void Function(Map<String, dynamic> data);

/// Canal Android para notificações transacionais do aEterna.
const _androidChannel = AndroidNotificationChannel(
  'aeterna_transacional',
  'Notificações aEterna',
  description: 'Convites, compartilhamentos e atualizações de memórias.',
  importance: Importance.high,
  playSound: true,
);

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  bool _inicializado = false;
  String? _currentToken;
  PushNavigationCallback? _navigationCallback;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  bool get isInitialized => _inicializado;
  String? get currentToken => _currentToken;

  /// Registra o callback de navegação.
  /// Deve ser chamado por main.dart logo após initialize().
  void setNavigationCallback(PushNavigationCallback callback) {
    _navigationCallback = callback;
  }

  /// Inicializa Firebase, flutter_local_notifications e listeners de FCM.
  /// Deve ser chamado o mais cedo possível em main() — antes de runApp().
  Future<void> initialize() async {
    if (_inicializado) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final messaging = FirebaseMessaging.instance;

      // iOS: exibe alertas e sons em foreground (padrão FCM suprime no iOS)
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Solicita permissão (iOS pede dialog; Android 13+ já declarado no manifest)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('[PUSH_TOKEN] Permissão: ${settings.authorizationStatus}');

      // Inicializa flutter_local_notifications (necessário para foreground Android
      // e para roteamento ao tocar em notificação recebida em foreground)
      await _inicializarLocalNotifications();

      // Captura o token atual
      _currentToken = await messaging.getToken();
      if (_currentToken != null) {
        print('[PUSH_TOKEN] Token FCM obtido: ...${_currentToken!.substring(_currentToken!.length - 8)}');
        await _salvarTokenSeLogado();
      }

      // Escuta renovação de token
      messaging.onTokenRefresh.listen((token) async {
        print('[PUSH_TOKEN] Token FCM renovado: ...${token.substring(token.length - 8)}');
        _currentToken = token;
        await _salvarTokenSeLogado();
      });

      // Mensagem recebida com app em FOREGROUND
      FirebaseMessaging.onMessage.listen(_onMessage);

      // App aberto ao tocar em notificação (app estava em BACKGROUND)
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      // Notificação que abriu o app a partir do estado TERMINADO
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        print('[PUSH_OPEN] App iniciado via notificação: tipo=${initialMessage.data['tipo']}');
        _invocarCallback(initialMessage.data);
      }

      _inic