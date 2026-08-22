import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/errors/app_exception.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/services/auth_service.dart';
import '../../domain/session.dart';

class AuthState extends Equatable {
  final bool loading;
  final AppSession? session;
  final String? error;

  const AuthState({this.loading = false, this.session, this.error});

  bool get isAuthenticated => session != null;

  AuthState copyWith({
    bool? loading,
    AppSession? session,
    String? error,
    bool clearSession = false,
  }) {
    return AuthState(
      loading: loading ?? this.loading,
      session: clearSession ? null : (session ?? this.session),
      error: error,
    );
  }

  @override
  List<Object?> get props => [loading, session, error];
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._auth) : super(const AuthState());
  final AuthService _auth;

  Future<void> restore() async {
    emit(state.copyWith(loading: true));
    final session = await _auth.restore();
    emit(AuthState(session: session));
  }

  Future<void> login(String username, String password) async {
    emit(state.copyWith(loading: true, error: null));
    try {
      final session = await _auth.login(username, password);
      emit(AuthState(session: session));
    } on AppException catch (e) {
      emit(state.copyWith(loading: false, error: e.messageAr));
    } catch (_) {
      emit(state.copyWith(loading: false, error: S.loginFailed));
    }
  }

  Future<void> logout() async {
    await _auth.logout();
    emit(const AuthState());
  }
}
