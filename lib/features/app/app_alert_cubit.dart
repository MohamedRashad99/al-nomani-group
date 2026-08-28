import 'package:flutter_bloc/flutter_bloc.dart';

enum AppAlertKind { success, error, warning, info }

class AppAlert {
  const AppAlert({required this.message, required this.kind});

  final String message;
  final AppAlertKind kind;
}

class AppAlertCubit extends Cubit<AppAlert?> {
  AppAlertCubit() : super(null);

  void show(String message, {AppAlertKind kind = AppAlertKind.info}) {
    emit(AppAlert(message: message, kind: kind));
  }

  void success(String message) => show(message, kind: AppAlertKind.success);
  void error(String message) => show(message, kind: AppAlertKind.error);
  void warning(String message) => show(message, kind: AppAlertKind.warning);
  void info(String message) => show(message, kind: AppAlertKind.info);
  void clear() => emit(null);
}
