/// Who a conversation is with.
enum ConversationKind { direct, place, group, event }

/// One thread in the SkorX inbox. Phone numbers are never shared: people
/// reach each other here first.
class Conversation {
  const Conversation({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.title,
    required this.lastAt,
    this.lastText,
    this.unread = 0,
    this.request = false,
    this.awaitingReply = false,
  });

  final String id;
  final ConversationKind kind;

  /// The member, place or group it is with.
  final String targetId;
  final String title;
  final String? lastText;
  final DateTime lastAt;
  final int unread;

  /// Someone who is not a connection wrote first. It sits under Requests
  /// until accepted; they are not told if it is declined.
  final bool request;

  /// I wrote first to someone who is not a connection. One message goes
  /// through; more once they reply (spam protection, docs/COMMUNITY.md §5).
  final bool awaitingReply;

  Conversation copyWith({String? lastText, DateTime? lastAt, int? unread, bool? request, bool? awaitingReply}) =>
      Conversation(
        id: id,
        kind: kind,
        targetId: targetId,
        title: title,
        lastText: lastText ?? this.lastText,
        lastAt: lastAt ?? this.lastAt,
        unread: unread ?? this.unread,
        request: request ?? this.request,
        awaitingReply: awaitingReply ?? this.awaitingReply,
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.at,
  });

  final String id;
  final String conversationId;

  /// [meId] for the signed-in member.
  final String senderId;
  final String senderName;
  final String text;
  final DateTime at;

  bool get mine => senderId == meId;
}

/// The signed-in member, wherever a sender or member id is expected.
const meId = 'me';

/// Longest message the server accepts.
const maxMessageLength = 2000;
