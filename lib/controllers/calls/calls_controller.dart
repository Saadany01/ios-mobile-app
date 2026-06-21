import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/call_model.dart';
import '../../services/calls_service.dart';

class CallsController {
  CallsController({required CallsService callsService})
    : _callsService = callsService;

  final CallsService _callsService;

  Stream<List<CallRecord>> callsStream(String userId) {
    return _callsService.watchCalls(userId);
  }

  IconData iconForType(CallType type) {
    switch (type) {
      case CallType.incoming:
        return Icons.call_received;
      case CallType.outgoing:
        return Icons.call_made;
      case CallType.missed:
        return Icons.call_missed;
    }
  }

  Color colorForType(CallType type) {
    switch (type) {
      case CallType.incoming:
        return Colors.green;
      case CallType.outgoing:
        return Colors.blue;
      case CallType.missed:
        return Colors.red;
    }
  }

  String formatTimeLabel(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return DateFormat('HH:mm').format(timestamp);
    }
    if (difference.inDays == 1) {
      return 'Yesterday';
    }
    if (difference.inDays < 7) {
      return DateFormat('EEEE').format(timestamp);
    }
    return DateFormat('MMM d').format(timestamp);
  }
}
