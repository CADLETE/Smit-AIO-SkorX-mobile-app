import 'package:flutter/material.dart';

import 'community.dart';


/// Clinics, open play, meetups and socials. Tournaments stay in the TMS.
enum EventKind {
  clinic('Clinic', Icons.school_rounded),
  openPlay('Open play', Icons.sports_tennis_rounded),
  meetup('Meetup', Icons.groups_rounded),
  camp('Camp', Icons.cabin_rounded),
  workshop('Workshop', Icons.build_circle_outlined),
  social('Social', Icons.celebration_rounded),
  clubEvent('Club event', Icons.flag_rounded);

  const EventKind(this.label, this.icon);
  final String label;
  final IconData icon;

  /// The server's id: open_play, club_event…
  String get wire => switch (this) {
        EventKind.openPlay => 'open_play',
        EventKind.clubEvent => 'club_event',
        _ => name,
      };

  static EventKind fromWire(String? s) => values.where((k) => k.wire == s).firstOrNull ?? EventKind.meetup;
}

enum RsvpStatus { going, interested }

class CommunityEvent {
  const CommunityEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.about,
    required this.startsAt,
    required this.endsAt,
    required this.city,
    required this.organizerId,
    required this.organizerName,
    this.state,
    this.address,
    this.placeId,
    this.placeName,
    this.groupId,
    this.tournamentId,
    this.capacity,
    this.feeInr,
    this.level,
    this.going = 0,
    this.interested = 0,
    this.myRsvp,
    this.cancelled = false,
    this.mine = false,
  });

  final String id;
  final EventKind kind;
  final String title;
  final String about;
  final DateTime startsAt;
  final DateTime endsAt;
  final String city;
  final String? state;
  final String? address;
  final String? placeId;
  final String? placeName;
  final String? groupId;

  /// The TMS tournament it belongs to, when it does.
  final String? tournamentId;
  final String organizerId;
  final String organizerName;
  final int? capacity;
  final int? feeInr;
  final String? level;
  final int going;
  final int interested;
  final RsvpStatus? myRsvp;
  final bool cancelled;
  final bool mine;

  bool get full => capacity != null && going >= capacity! && myRsvp != RsvpStatus.going;
  int? get spotsLeft => capacity == null ? null : (capacity! - going).clamp(0, capacity!);

  CommunityEvent copyWith({int? going, int? interested, RsvpStatus? Function()? myRsvp, bool? cancelled}) => CommunityEvent(
        id: id,
        kind: kind,
        title: title,
        about: about,
        startsAt: startsAt,
        endsAt: endsAt,
        city: city,
        state: state,
        address: address,
        placeId: placeId,
        placeName: placeName,
        groupId: groupId,
        tournamentId: tournamentId,
        organizerId: organizerId,
        organizerName: organizerName,
        capacity: capacity,
        feeInr: feeInr,
        level: level,
        going: going ?? this.going,
        interested: interested ?? this.interested,
        myRsvp: myRsvp == null ? this.myRsvp : myRsvp(),
        cancelled: cancelled ?? this.cancelled,
        mine: mine,
      );
}

/// What a new event needs; `POST /community/events`.
class EventDraft {
  const EventDraft({
    required this.kind,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.city,
    this.about = '',
    this.address,
    this.placeId,
    this.groupId,
    this.capacity,
    this.feeInr,
    this.level,
  });

  final EventKind kind;
  final String title;
  final String about;
  final DateTime startsAt;
  final DateTime endsAt;
  final String city;
  final String? address;
  final String? placeId;
  final String? groupId;
  final int? capacity;
  final int? feeInr;
  final String? level;

  Map<String, dynamic> toJson() => {
        'kind': kind.wire,
        'title': title,
        'about': about,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt.toUtc().toIso8601String(),
        'city': city,
        'address': ?address,
        'placeId': ?placeId,
        'groupId': ?groupId,
        'capacity': ?capacity,
        'feeInr': ?feeInr,
        'level': ?level,
      };
}

/// Pickleball-focused posts only: no generic photo feed.
enum PostKind {
  announcement('Announcement', Icons.campaign_rounded),
  achievement('Achievement', Icons.emoji_events_rounded),
  tip('Tip', Icons.lightbulb_outline_rounded),
  event('Event', Icons.event_rounded),
  news('News', Icons.newspaper_rounded);

  const PostKind(this.label, this.icon);
  final String label;
  final IconData icon;

  static PostKind fromWire(String? s) => values.where((k) => k.name == s).firstOrNull ?? PostKind.announcement;
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.kind,
    required this.body,
    required this.authorId,
    required this.authorName,
    required this.at,
    this.link,
    this.placeId,
    this.placeName,
    this.groupId,
    this.groupName,
    this.eventId,
    this.eventTitle,
    this.likes = 0,
    this.comments = 0,
    this.likedByMe = false,
    this.mine = false,
    this.hidden = false,
  });

  final String id;
  final PostKind kind;
  final String body;

  /// An app route it points at, e.g. /player/tournament/t-open.
  final String? link;
  final String authorId;
  final String authorName;
  final String? placeId;
  final String? placeName;
  final String? groupId;
  final String? groupName;
  final String? eventId;
  final String? eventTitle;
  final int likes;
  final int comments;
  final bool likedByMe;
  final bool mine;

  /// Hidden after reports, shown only to its author until reviewed.
  final bool hidden;
  final DateTime at;

  CommunityPost copyWith({int? likes, bool? likedByMe, int? comments}) => CommunityPost(
        id: id,
        kind: kind,
        body: body,
        link: link,
        authorId: authorId,
        authorName: authorName,
        placeId: placeId,
        placeName: placeName,
        groupId: groupId,
        groupName: groupName,
        eventId: eventId,
        eventTitle: eventTitle,
        likes: likes ?? this.likes,
        comments: comments ?? this.comments,
        likedByMe: likedByMe ?? this.likedByMe,
        mine: mine,
        hidden: hidden,
        at: at,
      );
}

class PostComment {
  const PostComment({required this.id, required this.postId, required this.authorId, required this.authorName, required this.body, required this.at, this.mine = false});

  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime at;
  final bool mine;
}

class PostPage {
  const PostPage(this.posts, this.nextCursor);

  final List<CommunityPost> posts;
  final String? nextCursor;
}

/// Where a feed reads from.
class FeedScope {
  const FeedScope({this.groupId, this.placeId, this.authorId});

  static const network = FeedScope();

  final String? groupId;
  final String? placeId;
  final String? authorId;

  Map<String, String> toParams() => {'groupId': ?groupId, 'placeId': ?placeId, 'authorId': ?authorId};

  @override
  bool operator ==(Object other) => other is FeedScope && other.groupId == groupId && other.placeId == placeId && other.authorId == authorId;

  @override
  int get hashCode => Object.hash(groupId, placeId, authorId);
}

enum VerificationStatus { pending, approved, rejected }

class VerificationRequest {
  const VerificationRequest({required this.id, required this.status, required this.createdAt, this.role, this.placeId, this.reviewNote});

  final String id;
  final CommunityRole? role;
  final String? placeId;
  final VerificationStatus status;
  final String? reviewNote;
  final DateTime createdAt;
}

/// Roles an organiser can leave feedback on (backend FEEDBACK_ROLES).
const feedbackRoles = {
  CommunityRole.referee,
  CommunityRole.scorekeeper,
  CommunityRole.official,
  CommunityRole.commentator,
  CommunityRole.streamer,
  CommunityRole.photographer,
  CommunityRole.coach,
};
