import 'package:cloud_firestore/cloud_firestore.dart';
import '../../shared/chat_media.dart';

/// A single chat message in a customer <-> staff conversation thread,
/// backed by a `messages/{id}` Firestore document. Same collection the
/// Staff app's inbox reads from, so a message sent here shows up there
/// (and vice versa) without any extra syncing.
class MessageRecord {
  final String id;
  final String userId; // which customer this thread belongs to
  final String customerName;
  final String text;
  final bool fromStaff;
  final DateTime sentAt;

  /// Id of the photo in `messageImages/{id}`, or '' for a text-only message.
  final String imageId;

  /// Optional shared item: 'camera' or 'booking', with its id and a
  /// snapshot of its title/subtitle at the time it was sent. Empty = none.
  final String refType;
  final String refId;
  final String refTitle;
  final String refSubtitle;

  const MessageRecord({
    required this.id,
    required this.userId,
    this.customerName = '',
    required this.text,
    required this.fromStaff,
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
      fromStaff: d['fromStaff'] == true,
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
