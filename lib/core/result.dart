sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T value) ok,
    required R Function(String message, Object? error) err,
  }) {
    return switch (this) {
      Ok<T>(:final value) => ok(value),
      Err<T>(:final message, :final error) => err(message, error),
    };
  }

  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.message, [this.error]);
  final String message;
  final Object? error;
}
