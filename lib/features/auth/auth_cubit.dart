import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/errors/app_exception.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/sync/sync_engine.dart';
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
  AuthCubit(this._auth, this._sync) : super(const AuthState());
  final AuthService _auth;
  final SyncEngine _sync;

  Future<void> restore() async {
    emit(state.copyWith(loading: true));
    final session = await _auth.restore();
    emit(AuthState(session: session));
    if (session != null) {
      unawaited(_recordSession(session));
    }
  }

  Future<void> login(String username, String password) async {
    emit(state.copyWith(loading: true, error: null));
    try {
      final session = await _auth.login(username, password);
      emit(AuthState(session: session));
      unawaited(_recordSession(session));
    } on AppException catch (e) {
      emit(state.copyWith(loading: false, error: e.messageAr));
    } catch (_) {
      emit(state.copyWith(loading: false, error: S.loginFailed));
    }
  }

  Future<void> _recordSession(AppSession session) {
    return _sync.recordAuthenticatedSession(
      userId: session.userId,
      username: session.username,
      displayName: session.displayName,
      roleId: session.roleName,
    );
  }

  Future<void> logout() async {
    await _auth.logout();
    emit(const AuthState());
  }
}
