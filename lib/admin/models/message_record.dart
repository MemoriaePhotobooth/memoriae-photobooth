import 'package:cloud_firestore/cloud_firestore.dart';
import '../../shared/chat_media.dart';

/// A single chat message in an admin <-> customer conversation thread,
/// backed by a `messages/{id}` Firestore document — the same collection
/// the User and Staff apps read/write. From the customer's point of view
/// there's only one "business side" of the conversation, so this reads
/// the shared `fromStaff` field as [fromAdmin]: when an admin replies,
/// it's written back as `fromStaff: true` too, same as a staff reply
/// would be.
class MessageRecord {
  final String id;
  final String userId; // which customer this thread belongs to
  final String customerName;
  final String text;
  final bool fromAdmin;
  final DateTime sentAt;

  /// Id of the photo in `messageImages/{id}`, or '' for a text-only message.
  final String imageId;

  /// Booking or camera the customer shared from the User app (e.g. the
  /// camera they are asking about). Empty when there is no reference.
  final String refType;
  final String refId;
  final String refTitle;
  final String refSubtitle;

  const MessageRecord({
    required this.id,
    required this.userId,
    this.customerName = '',
    required this.text,
    required this.fromAdmin,
    required this.sentAt,
    this.imageId = '',
    this.refType = '',
    this.refId = '',
    this.refTitle = '',
    this.refSubtitle = '',
  });

  factory MessageRecord.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['sentAt'];
    return MessageRecord(
      id: doc.id,
      userId: (d['userId'] ?? '') as String,
      customerName: (d['customerName'] ?? '') as String,
      text: (d['text'] ?? '') as String,
      fromAdmin: d['fromStaff'] == true,
      // A just-sent message may still be a pending local write, so
      // `sentAt` briefly reads null until the server timestamp lands —
      // treat that as "now" rather than sorting it to the wrong end.
      sentAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      imageId: (d['imageId'] ?? '') as String,
      refType: (d['refType'] ?? '') as String,
      refId: (d['refId'] ?? '') as String,
      refTitle: (d['refTitle'] ?? '') as String,
      refSubtitle: (d['refSubtitle'] ?? '') as String,
    );
  }

  bool get hasImage => imageId.isNotEmpty;

  bool get hasRef => refType.isNotEmpty && refId.isNotEmpty;

  /// The text to show under a photo — empty when the message is just a
  /// photo (its stored text is only the "📷 Photo" label).
  String get caption => (hasImage && text == kPhotoMessageText) ? '' : text;
}

/// One row in the admin's Messages inbox list.
class ConversationSummary {
  final String userId;
  final String customerName;
  final String lastMessage;
  final DateTime lastMessageAt;
  final bool hasUnread;

  /// True when an admin closed the thread and the customer hasn't written
  /// since. A new customer message flips this back to false by itself.
  final bool isClosed;

  const ConversationSummary({
    required this.userId,
    required this.customerName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.hasUnread,
    this.isClosed = false,
  });
}
