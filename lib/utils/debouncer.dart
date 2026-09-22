import 'dart:async';

/// Collapses a burst of rapid calls (e.g. every keystroke in a search box)
/// into one call [delay] after the last one. None of this app's search
/// fields debounced their `onChanged` before this - each keystroke re-ran a
/// full client-side filter (or, for a couple of screens, a network call)
/// over whatever list was loaded, which is wasted work for a fast typer and
/// gets worse the larger that list is (a large company's full voucher/item
/// history).
///
/// Usage: keep one `Debouncer` per search field as a widget field, call
/// `_debouncer.run(() => notifier.search(query))` from `onChanged`, and
/// `_debouncer.dispose()` from the widget's own `dispose()`.
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 350)});

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
