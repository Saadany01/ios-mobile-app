import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { incoming, outgoing, missed }

enum CallSessionStatus { ringing, accepted, declined, canceled, ended }

extension CallSessionStatusX on CallSessionStatus {
  String get value {
    switch (this) {
      case CallSessionStatus.ringing:
        return 'ringing';
      case CallSessionStatus.accepted:
        return 'accepted';
      case CallSessionStatus.declined:
        return 'declined';
      case CallSessionStatus.canceled:
        return 'canceled';
      case CallSessionStatus.ended:
        return 'ended';
    }
  }

  bool get isTerminal {
    switch (this) {
      case CallSessionStatus.ringing:
      case CallSessionStatus.accepted:
        return false;
      case CallSessionStatus.declined:
      case CallSessionStatus.canceled:
      case CallSessionStatus.ended:
        return true;
    }
  }

  static CallSessionStatus fromValue(String value) {
    switch (value) {
      case 'accepted':
        return CallSessionStatus.accepted;
      case 'declined':
        return CallSessionStatus.declined;
      case 'canceled':
        return CallSessionStatus.canceled;
      case 'ended':
        return CallSessionStatus.ended;
      case 'ringing':
      default:
        return CallSessionStatus.ringing;
    }
  }
}

class CallRecord {
  final String id;
  final String contactName;
  final String? contactUserId;
  final String? contactPhone;
  final String? contactAvatar;
  final CallType type;
  final DateTime timestamp;
  final int duration; // in seconds

  CallRecord({
    required this.id,
    required this.contactName,
    this.contactUserId,
    this.contactPhone,
    this.contactAvatar,
    required this.type,
    required this.timestamp,
    this.duration = 0,
  });

  factory CallRecord.fromFirestore(Map<String, dynamic> data, String id) {
    final typeIndex = (data['type'] as num?)?.toInt() ?? 0;
    final safeTypeIndex = typeIndex
        .clamp(0, CallType.values.length - 1)
        .toInt();
    final rawTimestamp = data['timestamp'];

    return CallRecord(
      id: id,
      contactName: data['contactName'] ?? 'Unknown',
      contactUserId: data['contactUserId'],
      contactPhone: data['contactPhone'],
      contactAvatar: data['contactAvatar'],
      type: CallType.values[safeTypeIndex],
      timestamp: rawTimestamp is Timestamp
          ? rawTimestamp.toDate()
          : DateTime.now(),
      duration: data['duration'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'contactName': contactName,
      'contactUserId': contactUserId,
      'contactPhone': contactPhone,
      'contactAvatar': contactAvatar,
      'type': type.index,
      'timestamp': Timestamp.fromDate(timestamp),
      'duration': duration,
    };
  }

  String get formattedDuration {
    if (duration == 0) return 'Not connected';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes}m ${seconds}s';
  }
}

class ActiveCallSession {
  ActiveCallSession({
    required this.id,
    required this.callerId,
    required this.callerName,
    this.callerPhotoUrl,
    required this.calleeId,
    required this.calleeName,
    this.calleePhotoUrl,
    required this.status,
    required this.createdAt,
    required this.mediaType,
    this.startedAt,
    this.endedAt,
    this.endedBy,
    this.offer,
    this.answer,
    this.historyWritten = false,
  });

  final String id;
  final String callerId;
  final String callerName;
  final String? callerPhotoUrl;
  final String calleeId;
  final String calleeName;
  final String? calleePhotoUrl;
  final CallSessionStatus status;
  final DateTime createdAt;
  final String mediaType;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? endedBy;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final bool historyWritten;

  bool get isVideoCall => mediaType == 'video';

  bool get isTerminal => status.isTerminal;

  bool get wasConnected =>
      status == CallSessionStatus.ended && startedAt != null;

  factory ActiveCallSession.fromFirestore(
    Map<String, dynamic> data,
    String id,
  ) {
    DateTime readCreatedAt() {
      final value = data['createdAt'];
      if (value is Timestamp) {
        return value.toDate();
      }

      final clientValue = data['clientCreatedAt'];
      if (clientValue is Timestamp) {
        return clientValue.toDate();
      }

      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    DateTime? readNullableTimestamp(String key) {
      final value = data[key];
      return value is Timestamp ? value.toDate() : null;
    }

    return ActiveCallSession(
      id: id,
      callerId: (data['callerId'] ?? '').toString(),
      callerName: (data['callerName'] ?? 'Unknown').toString(),
      callerPhotoUrl: (data['callerPhotoUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (data['callerPhotoUrl']).toString(),
      calleeId: (data['calleeId'] ?? '').toString(),
      calleeName: (data['calleeName'] ?? 'Unknown').toString(),
      calleePhotoUrl: (data['calleePhotoUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (data['calleePhotoUrl']).toString(),
      mediaType: (data['mediaType'] ?? 'audio').toString(),
      status: CallSessionStatusX.fromValue(
        (data['status'] ?? 'ringing').toString(),
      ),
      createdAt: readCreatedAt(),
      startedAt: readNullableTimestamp('startedAt'),
      endedAt: readNullableTimestamp('endedAt'),
      endedBy: (data['endedBy'] ?? '').toString().trim().isEmpty
          ? null
          : (data['endedBy']).toString(),
      offer: data['offer'] is Map<String, dynamic>
          ? data['offer'] as Map<String, dynamic>
          : null,
      answer: data['answer'] is Map<String, dynamic>
          ? data['answer'] as Map<String, dynamic>
          : null,
      historyWritten: data['historyWritten'] == true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'callerId': callerId,
      'callerName': callerName,
      'callerPhotoUrl': callerPhotoUrl,
      'calleeId': calleeId,
      'calleeName': calleeName,
      'calleePhotoUrl': calleePhotoUrl,
      'status': status.value,
      'mediaType': mediaType,
      'createdAt': Timestamp.fromDate(createdAt),
      'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
      'endedAt': endedAt == null ? null : Timestamp.fromDate(endedAt!),
      'endedBy': endedBy,
      'offer': offer,
      'answer': answer,
      'historyWritten': historyWritten,
    };
  }
}
