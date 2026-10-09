/// Explicit success/failure results used across the Observation Portal.
///
/// Services never throw raw exceptions to the UI (§84): they return an [Err]
/// carrying a user-safe message plus a technical code for diagnostics.
library;

class Failure {
  const Failure(this.code, this.message, {this.technical});

  /// Stable machine code (safe to show in diagnostics).
  final String code;

  /// Short, user-safe explanation (no stack traces, §84).
  final String message;

  /// Optional technical detail for the diagnostics ring buffer only.
  final String? technical;

  @override
  String toString() => 'Failure($code: $message)';
}

sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;
  Failure? get failureOrNull => this is Err<T> ? (this as Err<T>).failure : null;
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}

/// Accessors for call sites that have already branched on the variant
/// (`if (result is Err<T>) return ...;`). They never silently return `null`:
/// reading the wrong variant fails loudly during development.
extension ResultAccess<T> on Result<T> {
  /// The success payload; throws a [StateError] when this is an [Err].
  T get value => switch (this) {
    Ok<T>(:final T value) => value,
    Err<T>(:final Failure failure) =>
      throw StateError('Result is an error: $failure'),
  };

  /// The failure; throws a [StateError] when this is an [Ok].
  Failure get failure => switch (this) {
    Err<T>(:final Failure failure) => failure,
    Ok<T>() => throw StateError('Result is a success'),
  };
}
