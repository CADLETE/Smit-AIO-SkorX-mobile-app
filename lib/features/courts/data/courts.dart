import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/sample_latency.dart';
import '../../../core/sample_persona.dart';

class Venue {
  const Venue({
    required this.id,
    required this.name,
    required this.area,
    required this.city,
    required this.distanceKm,
    required this.rating,
    required this.reviews,
    required this.courts,
    required this.indoor,
    required this.pricePerHour,
    required this.peakPricePerHour,
    required this.openHour,
    required this.closeHour,
    this.surface = 'Acrylic hard court',
    this.facilities = const [],
    this.rules = const [],
    this.phone,
    this.address,
  });

  final String id;
  final String name;
  final String area;
  final String city;
  final double distanceKm;
  final double rating;
  final int reviews;
  final int courts;
  final bool indoor;
  final String surface;

  /// Off-peak and peak (6–10 PM) prices per court per hour, in rupees.
  final int pricePerHour;
  final int peakPricePerHour;
  final int openHour;
  final int closeHour;
  final List<String> facilities;
  final List<String> rules;
  final String? phone;
  final String? address;

  bool isPeak(int hour) => hour >= 18 && hour < 22;
  int priceAt(int hour) => isPeak(hour) ? peakPricePerHour : pricePerHour;
}

/// One hour on the venue's timetable, and which courts are free in it.
class Slot {
  const Slot({required this.start, required this.freeCourts, required this.price});

  final DateTime start;

  /// Court numbers, 1-based.
  final List<int> freeCourts;
  final int price;

  bool get available => freeCourts.isNotEmpty;
}

enum PartOfDay {
  any('Any time', 0, 24),
  morning('Morning', 5, 12),
  afternoon('Afternoon', 12, 17),
  evening('Evening', 17, 24);

  const PartOfDay(this.label, this.from, this.to);
  final String label;
  final int from;
  final int to;

  bool contains(DateTime t) => t.hour >= from && t.hour < to;
}

/// A venue in the search results, with its next free slots on the chosen day.
class VenueAvailability {
  const VenueAvailability(this.venue, this.freeSlots);

  final Venue venue;
  final List<Slot> freeSlots;
}

typedef VenueQuery = ({String city, DateTime date, PartOfDay part});

enum BookingStatus { confirmed, cancelled, completed }

class Booking {
  const Booking({
    required this.id,
    required this.code,
    required this.venue,
    required this.court,
    required this.start,
    required this.amount,
    this.duration = const Duration(hours: 1),
    this.status = BookingStatus.confirmed,
  });

  final String id;

  /// Shown at the venue desk, e.g. "SKX-7F3K2".
  final String code;
  final Venue venue;
  final int court;
  final DateTime start;
  final Duration duration;
  final int amount;
  final BookingStatus status;
}

/// Convenience fee added to every booking, in rupees.
const bookingFee = 20;

const bookingCities = ['Ahmedabad', 'Gandhinagar', 'Surat', 'Vadodara', 'Rajkot', 'Mumbai'];

/// Court booking. Method names mirror the endpoints they will call; the old
/// app's `/venue/*` and `/booking/*` move to the new API first.
abstract class CourtRepository {
  /// `GET /venues?city&date&from&to`
  Future<List<VenueAvailability>> search(VenueQuery query);

  /// `GET /venues/:id`
  Future<Venue> venue(String id);

  /// `GET /venues/:id/slots?date`
  Future<List<Slot>> slots(String venueId, DateTime date);

  /// `POST /bookings`, then payment.
  Future<Booking> book(String venueId, DateTime start, int court);

  /// `GET /me/bookings`
  Future<List<Booking>> myBookings();
}

final courtRepositoryProvider = Provider<CourtRepository>(
  (ref) => kDebugMode
      ? SampleCourtRepository(
          latency: ref.watch(sampleLatencyProvider),
          newcomer: ref.watch(samplePersonaProvider) == SamplePersona.newcomer,
        )
      : const EmptyCourtRepository(),
);

final venueSearchProvider = FutureProvider.family<List<VenueAvailability>, VenueQuery>(
  (ref, query) => ref.watch(courtRepositoryProvider).search(query),
);

final venueProvider = FutureProvider.family<Venue, String>((ref, id) => ref.watch(courtRepositoryProvider).venue(id));

final slotsProvider = FutureProvider.family<List<Slot>, (String, DateTime)>(
  (ref, args) => ref.watch(courtRepositoryProvider).slots(args.$1, args.$2),
);

final myBookingsProvider = FutureProvider<List<Booking>>((ref) => ref.watch(courtRepositoryProvider).myBookings());

/// The city and day the player is searching, kept while the app is open.
final courtSearchProvider = NotifierProvider<CourtSearchController, VenueQuery>(CourtSearchController.new);

class CourtSearchController extends Notifier<VenueQuery> {
  @override
  VenueQuery build() {
    final now = DateTime.now();
    return (city: 'Ahmedabad', date: DateTime(now.year, now.month, now.day), part: PartOfDay.any);
  }

  void setCity(String city) => state = (city: city, date: state.date, part: state.part);
  void setDate(DateTime date) => state = (city: state.city, date: date, part: state.part);
  void setPart(PartOfDay part) => state = (city: state.city, date: state.date, part: part);
}

class EmptyCourtRepository implements CourtRepository {
  const EmptyCourtRepository();

  @override
  Future<List<VenueAvailability>> search(VenueQuery query) async => const [];

  @override
  Future<Venue> venue(String id) async => throw const ApiException('NOT_FOUND', 'This venue is not on SkorX yet.');

  @override
  Future<List<Slot>> slots(String venueId, DateTime date) async => const [];

  @override
  Future<Booking> book(String venueId, DateTime start, int court) async =>
      throw const ApiException('NOT_AVAILABLE', 'Court booking opens in the next update.');

  @override
  Future<List<Booking>> myBookings() async => const [];
}

/// Debug builds: sample venues with a timetable that is the same every time
/// for a given venue and day. Bookings last until the app restarts.
class SampleCourtRepository implements CourtRepository {
  SampleCourtRepository({this.latency = const Duration(milliseconds: 350), bool newcomer = false}) {
    final now = DateTime.now();
    final blitz = _venues.first;
    if (!newcomer) {
      _bookings.addAll([
      Booking(
        id: 'b-1',
        code: 'SKX-4Q7M2',
        venue: blitz,
        court: 2,
        start: DateTime(now.year, now.month, now.day + 4, 7),
        amount: blitz.priceAt(7) + bookingFee,
      ),
      Booking(
        id: 'b-0',
        code: 'SKX-9D2LA',
        venue: _venues[1],
        court: 4,
        start: DateTime(now.year, now.month, now.day - 6, 19),
        amount: _venues[1].priceAt(19) + bookingFee,
        status: BookingStatus.completed,
      ),
    ]);
    }
  }

  final Duration latency;
  final List<Booking> _bookings = [];

  static const _rules = [
    'Arrive 10 minutes before your slot.',
    'Non-marking shoes only.',
    'Free cancellation up to 6 hours before.',
    'Paddles and balls available at the desk.',
  ];

  static const _venues = [
    Venue(
      id: 'v-blitz',
      name: 'Pickle Blitz Arena',
      area: 'Prahlad Nagar',
      city: 'Ahmedabad',
      address: 'Behind Corporate Road, Prahlad Nagar, Ahmedabad',
      distanceKm: 2.4,
      rating: 4.7,
      reviews: 312,
      courts: 6,
      indoor: true,
      pricePerHour: 600,
      peakPricePerHour: 800,
      openHour: 6,
      closeHour: 23,
      facilities: ['Parking', 'Changing rooms', 'Paddle rental', 'Café', 'Floodlights', 'AC'],
      rules: _rules,
      phone: '+91 79 4000 1234',
    ),
    Venue(
      id: 'v-smash',
      name: 'Smash Arena',
      area: 'SG Highway',
      city: 'Ahmedabad',
      address: 'Near Iscon Cross Road, SG Highway, Ahmedabad',
      distanceKm: 4.2,
      rating: 4.5,
      reviews: 208,
      courts: 8,
      indoor: true,
      pricePerHour: 700,
      peakPricePerHour: 900,
      openHour: 6,
      closeHour: 23,
      facilities: ['Parking', 'Changing rooms', 'Showers', 'Pro shop', 'Coaching'],
      rules: _rules,
      phone: '+91 79 4000 5678',
    ),
    Venue(
      id: 'v-riverside',
      name: 'Riverside Courts',
      area: 'Riverfront',
      city: 'Ahmedabad',
      address: 'Sabarmati Riverfront West, Ahmedabad',
      distanceKm: 5.1,
      rating: 4.3,
      reviews: 96,
      courts: 4,
      indoor: false,
      surface: 'Outdoor hard court',
      pricePerHour: 400,
      peakPricePerHour: 550,
      openHour: 5,
      closeHour: 22,
      facilities: ['Parking', 'Floodlights', 'Drinking water'],
      rules: _rules,
    ),
    Venue(
      id: 'v-cadlete',
      name: 'CADLETE Club',
      area: 'Bodakdev',
      city: 'Ahmedabad',
      address: 'Judges Bungalow Road, Bodakdev, Ahmedabad',
      distanceKm: 6.8,
      rating: 4.8,
      reviews: 441,
      courts: 5,
      indoor: true,
      pricePerHour: 750,
      peakPricePerHour: 950,
      openHour: 6,
      closeHour: 22,
      facilities: ['Parking', 'Changing rooms', 'Showers', 'Coaching', 'Café', 'AC'],
      rules: _rules,
    ),
    Venue(
      id: 'v-diamond',
      name: 'Diamond Sports Hub',
      area: 'Vesu',
      city: 'Surat',
      distanceKm: 3.0,
      rating: 4.4,
      reviews: 150,
      courts: 6,
      indoor: true,
      pricePerHour: 550,
      peakPricePerHour: 700,
      openHour: 6,
      closeHour: 23,
      facilities: ['Parking', 'Changing rooms', 'AC'],
      rules: _rules,
    ),
  ];

  @override
  Future<List<VenueAvailability>> search(VenueQuery query) async {
    await simulateLatency(latency);
    final now = DateTime.now();
    return [
      for (final v in _venues.where((v) => v.city == query.city))
        VenueAvailability(
          v,
          _timetable(v, query.date)
              .where((s) => s.available && s.start.isAfter(now) && query.part.contains(s.start))
              .toList(),
        ),
    ]..sort((a, b) => a.venue.distanceKm.compareTo(b.venue.distanceKm));
  }

  @override
  Future<Venue> venue(String id) async {
    await simulateLatency(latency);
    return _venues.firstWhere(
      (v) => v.id == id,
      orElse: () => throw const ApiException('NOT_FOUND', 'This venue is not on SkorX yet.'),
    );
  }

  @override
  Future<List<Slot>> slots(String venueId, DateTime date) async {
    await simulateLatency(latency);
    final v = _venues.firstWhere((v) => v.id == venueId);
    final now = DateTime.now();
    return [
      for (final s in _timetable(v, date))
        if (s.start.isAfter(now)) s,
    ];
  }

  @override
  Future<Booking> book(String venueId, DateTime start, int court) async {
    await simulateLatency(latency * 2);
    final v = _venues.firstWhere((v) => v.id == venueId);
    final slot = _timetable(v, start).where((s) => s.start == start).firstOrNull;
    if (slot == null || !slot.freeCourts.contains(court)) {
      throw const ApiException('SLOT_TAKEN', 'Someone just booked that court. Pick another court or time.');
    }
    final n = _bookings.length + 1;
    final booking = Booking(
      id: 'b-$n',
      code: 'SKX-${(start.millisecondsSinceEpoch ~/ 60000 + court * 7 + n).toRadixString(36).toUpperCase().substring(0, 5)}',
      venue: v,
      court: court,
      start: start,
      amount: slot.price + bookingFee,
    );
    _bookings.add(booking);
    return booking;
  }

  @override
  Future<List<Booking>> myBookings() async {
    await simulateLatency(latency);
    return [..._bookings]..sort((a, b) => b.start.compareTo(a.start));
  }

  /// A timetable that looks lived-in: evenings busier than mornings, stable
  /// for the same venue and day, minus what this phone has booked.
  List<Slot> _timetable(Venue v, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final seed = v.id.codeUnits.fold<int>(day.day * 31 + day.month, (a, b) => a * 7 + b);
    return [
      for (var hour = v.openHour; hour < v.closeHour; hour++)
        Slot(
          start: DateTime(day.year, day.month, day.day, hour),
          price: v.priceAt(hour),
          freeCourts: [
            for (var c = 1; c <= v.courts; c++)
              if ((seed + hour * 13 + c * 17) % (v.isPeak(hour) ? 3 : 5) != 0 &&
                  !_bookings.any((b) =>
                      b.venue.id == v.id && b.court == c && b.start == DateTime(day.year, day.month, day.day, hour)))
                c,
          ],
        ),
    ];
  }
}
