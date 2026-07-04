/// Sprint I — Ponte global para o entry-point do Workmanager.
///
/// O pacote `workmanager` só permite UM `callbackDispatcher` por
/// processo. Como já temos o da Sprint F
/// (`curator_invitation_service.dart::callbackDispatcher`), esta
/// classe expõe uma maneira de a Sprint I injetar sua função de
/// verificação sem precisar de um segundo dispatcher.
///
/// Uso:
///   - `curator_invitation_service.dart` faz fan-out lendo
///     `WorkmanagerFanOut.sprintIBridge` quando o task name
///     corresponde.
///   - `memory_growth_invitation_service.dart` injeta a bridge em
///     `registrarVerificacaoPeriodica` antes de registrar o job.
class WorkmanagerFanOut {
  static const String sprintITaskName = 'verificarMemoriasQuePodemCrescer';

  /// Callback a ser executado quando a tarefa `sprintITaskName` for
  /// invocada pelo Workmanager. Injetado pelo
  /// `MemoryGrowthInvitationService.registrarVerificacaoPeriodica`.
  /// Pode ser `null` se a Sprint I nunca foi inicializada no app
  /// (ex.: app não foi atualizado) — nesse caso o fan-out simplesmente
  /// não faz nada.
  static void Function()? sprintIBridge;
}
