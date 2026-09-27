import 'community.dart';
import 'content.dart';
import 'messages.dart';

/// Reads the Community API's JSON (backend src/community). The server uses
/// the app's enum names, so values map by name.
typedef Json = Map<String, dynamic>;

T? _byName<T extends Enum>(List<T> values, Object? name) => values.where((v) => v.name == name).firstOrNull;
List<String> _strings(Object? v) => [for (final x in (v as List<dynamic>? ?? const [])) x as String];
DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();

CommunityMember memberFromJson(Json j) => CommunityMember(
      id: j['id'] as String,
      name: j['name'] as String,
      city: j['city'] as String? ?? 'India',
      state: j['state'] as String?,
      headline: j['headline'] as String?,
      bio: j['bio'] as String?,
      playerId: j['playerId'] as String?,
      tags: _strings(j['tags']),
      languages: _strings(j['languages']),
      serviceArea: _strings(j['serviceArea']),
      availability: _byName(Availability.values, j['availability']),
      placeIds: _strings(j['placeIds']),
      groupIds: _strings(j['groupIds']),
      mutualConnections: j['mutualConnections'] as int? ?? 0,
      acceptsMessagesFrom: _byName(MessagePermission.values, j['acceptsMessagesFrom']) ?? MessagePermission.everyone,
      roles: [
        for (final r in (j['roles'] as List<dynamic>? ?? const []).cast<Json>())
          if (CommunityRole.byName(r['role'] as String?) case final role?)
            RoleRecord(
              role,
              verified: r['verified'] as bool? ?? false,
              since: r['since'] as int?,
              highlights: _strings(r['highlights']),
              metrics: [
                for (final m in (r['metrics'] as List<dynamic>? ?? const []).cast<Json>()) (m['label'] as String, m['value'] as String),
              ],
            ),
      ].let((roles) => roles.isEmpty ? const [RoleRecord(CommunityRole.player)] : roles),
    );

CommunityPlace placeFromJson(Json j) => CommunityPlace(
      id: j['id'] as String,
      kind: PlaceKind.byName(j['kind'] as String?) ?? PlaceKind.club,
      name: j['name'] as String,
      city: j['city'] as String,
      state: j['state'] as String?,
      area: j['area'] as String?,
      about: j['about'] as String? ?? '',
      verified: j['verified'] as bool? ?? false,
      venueId: j['venueId'] as String?,
      organizationId: j['organizationId'] as String?,
      courts: j['courts'] as int?,
      setting: _byName(PlaceSetting.values, j['setting']),
      surface: j['surface'] as String?,
      amenities: _strings(j['amenities']),
      hours: j['hours'] as String?,
      founded: j['founded'] as int?,
      programs: [
        for (final p in (j['programs'] as List<dynamic>? ?? const []).cast<Json>())
          Program(
            name: p['name'] as String,
            level: p['level'] as String,
            schedule: p['schedule'] as String,
            fee: p['fee'] as int?,
            juniors: p['juniors'] as bool? ?? false,
          ),
      ],
      staffIds: _strings(j['staffIds']),
      tournamentIds: _strings(j['tournamentIds']),
      members: j['members'] as int? ?? 0,
      followers: j['followers'] as int? ?? 0,
    );

CommunityGroup groupFromJson(Json j) => CommunityGroup(
      id: j['id'] as String,
      name: j['name'] as String,
      about: j['about'] as String? ?? '',
      access: _byName(GroupAccess.values, j['access']) ?? GroupAccess.public,
      members: j['members'] as int? ?? 0,
      activeThisWeek: j['activeThisWeek'] as int? ?? 0,
      city: j['city'] as String?,
      state: j['state'] as String?,
      focus: CommunityRole.byName(j['focus'] as String?),
      managedBy: j['managedBy'] as String?,
      rules: _strings(j['rules']),
    );

CommunityGraph graphFromJson(Json j) => CommunityGraph(
      connections: {
        for (final e in (j['connections'] as Json? ?? const {}).entries) e.key: ?_byName(ConnectionStatus.values, e.value),
      },
      following: {..._strings(j['following'])},
      groups: {
        for (final e in (j['groups'] as Json? ?? const {}).entries) e.key: ?_byName(GroupStatus.values, e.value),
      },
      adminOf: {..._strings(j['adminOf'])},
      blocked: {..._strings(j['blocked'])},
      saved: {
        for (final s in (j['saved'] as List<dynamic>? ?? const []).cast<Json>()) s['id'] as String: ?_byName(CommunityTarget.values, s['type']),
      },
    );

MyCommunityProfile profileFromJson(Json j) => MyCommunityProfile(
      roles: {for (final r in _strings(j['roles'])) ?CommunityRole.byName(r)},
      headline: j['headline'] as String?,
      availability: _byName(Availability.values, j['availability']),
      languages: _strings(j['languages']),
      serviceArea: _strings(j['serviceArea']),
      messagesFrom: _byName(MessagePermission.values, j['messagesFrom']) ?? MessagePermission.everyone,
      listed: j['listed'] as bool? ?? true,
      rolesChosen: j['rolesChosen'] as bool? ?? false,
    );

Json profileToJson(MyCommunityProfile p) => {
      'roles': [for (final r in p.roles) r.name],
      'headline': p.headline,
      'availability': p.availability?.name,
      'languages': p.languages,
      'serviceArea': p.serviceArea,
      'messagesFrom': p.messagesFrom.name,
      'listed': p.listed,
    };

Suggestion suggestionFromJson(Json j) => Suggestion(memberFromJson(j['member'] as Json), j['reason'] as String);

Conversation conversationFromJson(Json j) => Conversation(
      id: j['id'] as String,
      kind: _byName(ConversationKind.values, j['kind']) ?? ConversationKind.direct,
      targetId: j['targetId'] as String? ?? '',
      title: j['title'] as String,
      lastText: j['lastText'] as String?,
      lastAt: _date(j['lastAt']),
      unread: j['unread'] as int? ?? 0,
      request: j['request'] as bool? ?? false,
      awaitingReply: j['awaitingReply'] as bool? ?? false,
    );

/// The server marks my own messages with sender "me", like the app.
ChatMessage messageFromJson(Json j) => ChatMessage(
      id: j['id'] as String,
      conversationId: j['conversationId'] as String,
      senderId: j['senderId'] as String,
      senderName: j['senderName'] as String,
      text: j['text'] as String,
      at: _date(j['at']),
    );

CommunityEvent eventFromJson(Json j) => CommunityEvent(
      id: j['id'] as String,
      kind: EventKind.fromWire(j['kind'] as String?),
      title: j['title'] as String,
      about: j['about'] as String? ?? '',
      startsAt: _date(j['startsAt']),
      endsAt: _date(j['endsAt']),
      city: j['city'] as String,
      state: j['state'] as String?,
      address: j['address'] as String?,
      placeId: j['placeId'] as String?,
      placeName: j['placeName'] as String?,
      groupId: j['groupId'] as String?,
      tournamentId: j['tournamentId'] as String?,
      organizerId: (j['organizer'] as Json)['id'] as String,
      organizerName: (j['organizer'] as Json)['name'] as String,
      capacity: j['capacity'] as int?,
      feeInr: j['feeInr'] as int?,
      level: j['level'] as String?,
      going: j['going'] as int? ?? 0,
      interested: j['interested'] as int? ?? 0,
      myRsvp: _byName(RsvpStatus.values, j['myRsvp']),
      cancelled: j['cancelled'] as bool? ?? false,
      mine: j['mine'] as bool? ?? false,
    );

CommunityPost postFromJson(Json j) {
  final author = j['author'] as Json;
  final place = j['place'] as Json?;
  final group = j['group'] as Json?;
  final event = j['event'] as Json?;
  return CommunityPost(
    id: j['id'] as String,
    kind: PostKind.fromWire(j['kind'] as String?),
    body: j['body'] as String,
    link: j['link'] as String?,
    authorId: author['id'] as String,
    authorName: author['name'] as String,
    placeId: place?['id'] as String?,
    placeName: place?['name'] as String?,
    groupId: group?['id'] as String?,
    groupName: group?['name'] as String?,
    eventId: event?['id'] as String?,
    eventTitle: event?['title'] as String?,
    likes: j['likes'] as int? ?? 0,
    comments: j['comments'] as int? ?? 0,
    likedByMe: j['likedByMe'] as bool? ?? false,
    mine: j['mine'] as bool? ?? false,
    hidden: j['hidden'] as bool? ?? false,
    at: _date(j['at']),
  );
}

PostComment commentFromJson(Json j) => PostComment(
      id: j['id'] as String,
      postId: j['postId'] as String,
      authorId: (j['author'] as Json)['id'] as String,
      authorName: (j['author'] as Json)['name'] as String,
      body: j['body'] as String,
      at: _date(j['at']),
      mine: j['mine'] as bool? ?? false,
    );

VerificationRequest verificationFromJson(Json j) => VerificationRequest(
      id: j['id'] as String,
      role: CommunityRole.byName(j['role'] as String?),
      placeId: j['placeId'] as String?,
      status: _byName(VerificationStatus.values, j['status']) ?? VerificationStatus.pending,
      reviewNote: j['reviewNote'] as String?,
      createdAt: _date(j['createdAt']),
    );

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
