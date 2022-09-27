part of '../isolate_pool.dart';

typedef Compute<T, M> = FutureOr<T> Function(M message, Updater updater);

class _Runnable<T, M> {
  _Runnable(this.compute, this.message);

  final Compute<T, M> compute;
  final M message;

  late Updater updater;

  FutureOr<T> call() {
    return compute(message, updater);
  }
}
