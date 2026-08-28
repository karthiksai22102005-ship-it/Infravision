import 'package:flutter/foundation.dart';

import '../engines/notification_engine.dart';

/// In-app notification store. The citizen portal listens to this
/// ChangeNotifier so important status changes surface automatically without
/// the citizen having to keep checking the app.
class NotificationService extends ChangeNotifier {
  NotificationService();

  final List<NotificationItem> _items = [];
  int _unseen = 0;

  List<NotificationItem> get items => List.unmodifiable(_items);
  int get unseen => _unseen;

  void add(NotificationItem item) {
    _items.insert(0, item);
    _unseen++;
    notifyListeners();
  }

  void markAllSeen() {
    if (_unseen == 0) return;
    _unseen = 0;
    notifyListeners();
  }
}
