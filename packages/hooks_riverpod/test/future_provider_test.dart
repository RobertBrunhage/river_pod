import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('updates dependents with value', (tester) async {
    final future = FutureProvider((s) async => 42);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ProviderScope(
          child: HookBuilder(builder: (c) {
            return useProvider(future).when(
              data: (data) => Text(data.toString()),
              loading: () => const Text('loading'),
              error: (dynamic err, stack) => Text('$err'),
            );
          }),
        ),
      ),
    );

    expect(find.text('loading'), findsOneWidget);

    await tester.pump();

    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('updates dependents with error', (tester) async {
    final error = Error();
    final futureProvider = FutureProvider<int>((s) async => throw error);

    dynamic whenError;
    StackTrace whenStack;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ProviderScope(
          child: HookBuilder(builder: (c) {
            return useProvider(futureProvider).when(
              data: (data) => Text(data.toString()),
              loading: () => const Text('loading'),
              error: (dynamic err, stack) {
                whenError = err;
                whenStack = stack;
                return const Text('error');
              },
            );
          }),
        ),
      ),
    );

    expect(find.text('loading'), findsOneWidget);

    await tester.pump();

    expect(find.text('error'), findsOneWidget);
    expect(whenError, error);
    expect(whenStack, isNotNull);
  });

  testWidgets("future completes after unmount does't crash", (tester) async {
    final completer = Completer<int>();
    final futureProvider = FutureProvider((s) => completer.future);

    await tester.pumpWidget(
      ProviderScope(
        child: HookBuilder(builder: (c) {
          useProvider(futureProvider);
          return Container();
        }),
      ),
    );

    // unmount ProviderScope which disposes the provider
    await tester.pumpWidget(Container());

    completer.complete();

    // wait for then to tick
    await Future.value(null);
  });

  testWidgets("future fails after unmount does't crash", (tester) async {
    final completer = Completer<int>();
    final futureProvider = FutureProvider((s) => completer.future);

    await tester.pumpWidget(
      ProviderScope(
        child: HookBuilder(builder: (c) {
          useProvider(futureProvider);
          return Container();
        }),
      ),
    );

    // unmount ProviderScope which disposes the provider
    await tester.pumpWidget(Container());

    final error = Error();
    completer.completeError(error);

    // wait for onError to tick
    await Future.value(null);
  });

  testWidgets('FutureProvider can be overriden with Future', (tester) async {
    var callCount = 0;
    final futureProvider = FutureProvider((s) async {
      callCount++;
      return 42;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          futureProvider.overrideWithProvider(FutureProvider((_) async => 21)),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: HookBuilder(builder: (c) {
            return useProvider(futureProvider).maybeWhen(
              data: (data) => Text(data.toString()),
              orElse: () => const Text('else'),
            );
          }),
        ),
      ),
    );

    expect(callCount, 0);
    expect(find.text('else'), findsOneWidget);

    await tester.pump();

    expect(find.text('21'), findsOneWidget);
  });
  group('overrideWithValue', () {
    var callCount = 0;
    final futureProvider = FutureProvider((s) async {
      callCount++;
      return 42;
    });

    Future<int> future;
    var completed = false;
    final proxy = Provider<String>(
      (ref) {
        future = ref.watch(futureProvider.future)
          ..then(
            (value) => completed = true,
            onError: (dynamic _) => completed = true,
          );
        return '';
      },
    );

    setUp(() {
      callCount = 0;
      completed = false;
      future = null;
    });

    final child = Directionality(
      textDirection: TextDirection.ltr,
      child: HookBuilder(builder: (c) {
        useProvider(proxy);
        return useProvider(futureProvider).when(
          data: (data) => Text(data.toString()),
          loading: () => const Text('loading'),
          error: (dynamic err, stack) {
            return const Text('error');
          },
        );
      }),
    );

    testWidgets('no-op if completed and rebuild with same value',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureProvider.overrideWithValue(const AsyncValue.data(42)),
          ],
          child: child,
        ),
      );

      expect(completed, true);
      await expectLater(future, completion(42));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureProvider.overrideWithValue(const AsyncValue.data(42)),
          ],
          child: child,
        ),
      );
    });

    testWidgets(
        'FutureProviderDependency.future completes on rebuild with error',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureProvider.overrideWithValue(const AsyncValue.loading()),
          ],
          child: child,
        ),
      );

      // make sure the future doesn't just complete in one frame
      await Future.value(null);

      expect(completed, false);
      expect(future, isNotNull);

      final error = Error();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureProvider.overrideWithValue(AsyncValue.error(error)),
          ],
          child: child,
        ),
      );

      expect(completed, true);
      await expectLater(future, throwsA(error));
    });

    testWidgets('FutureProviderDependency.future loading to loading is no-op',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureProvider.overrideWithValue(const AsyncValue.loading()),
          ],
          child: child,
        ),
      );

      expect(completed, false);
      expect(future, isNotNull);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureProvider.overrideWithValue(const AsyncValue.loading()),
          ],
          child: child,
        ),
      );

      // make sure the future doesn't just complete in one frame
      await Future.value(null);

      expect(completed, false);
      expect(future, isNotNull);
    });

    testWidgets('Initial build as loading', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureProvider.overrideWithValue(const AsyncValue.loading()),
          ],
          child: child,
        ),
      );

      expect(callCount, 0);
      expect(find.text('loading'), findsOneWidget);

      expect(completed, false);
      expect(future, isNotNull);
    });

    testWidgets('Initial build as value', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureProvider.overrideWithValue(const AsyncValue.data(42)),
          ],
          child: child,
        ),
      );

      expect(callCount, 0);
      expect(find.text('42'), findsOneWidget);

      expect(completed, true);
      await expectLater(future, completion(42));
    });

    testWidgets('Initial build as error', (tester) async {
      final error = Error();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureProvider.overrideWithValue(AsyncValue.error(error)),
          ],
          child: child,
        ),
      );

      expect(callCount, 0);
      expect(find.text('error'), findsOneWidget);

      expect(completed, true);
      await expectLater(future, throwsA(error));
    });
  });
}
