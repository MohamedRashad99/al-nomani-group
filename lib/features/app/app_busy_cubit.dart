import 'package:flutter_bloc/flutter_bloc.dart';

/// Prevents PWA/app reload while a business transaction is in progress.
class AppBusyCubit extends Cubit<int> {
  AppBusyCubit() : super(0);

  bool get isBusy => state > 0;

  Future<T> guard<T>(Future<T> Function() action) async {
    emit(state + 1);
    try {
      return await action();
    } finally {
      emit(state - 1);
    }
  }
}
