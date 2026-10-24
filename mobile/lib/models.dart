import 'package:intl/intl.dart';

String formatMoney(int minor, [String currency = 'ZMW']) {
  return '$currency ${(minor / 100).toStringAsFixed(2)}';
}

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String formatEventDate(DateTime? date) {
  if (date == null) return 'Date to be announced';
  return DateFormat('EEE d MMM, HH:mm').format(date);
}

String formatShortDate(DateTime? date) {
  if (date == null) return '';
  return DateFormat('d MMM yyyy').format(date);
}

class User {
  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.role,
  });

  final String id;
  final String email;
  final String fullName;
  final String phone;
  final String role;

  bool get isOrganizer =>
      role == 'organizer' || role == 'admin' || role == 'super_admin';
  bool get isAdmin => role == 'admin' || role == 'super_admin';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? 'attendee',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'phone': phone,
        'role': role,
      };
}

class TicketType {
  const TicketType({
    required this.id,
    required this.name,
    required this.priceMinor,
    required this.currency,
    required this.capacity,
    required this.soldCount,
    required this.remaining,
  });

  final String id;
  final String name;
  final int priceMinor;
  final String currency;
  final int capacity;
  final int soldCount;
  final int remaining;

  bool get isSoldOut => remaining <= 0;

  factory TicketType.fromJson(Map<String, dynamic> json) {
    return TicketType(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Ticket',
      priceMinor: (json['price_minor'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String? ?? 'ZMW').trim(),
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      soldCount: (json['sold_count'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
    );
  }
}

class Event {
  const Event({
    required this.id,
    required this.title,
    required this.description,
    required this.venue,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.organizerName,
    required this.ticketTypes,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String description;
  final String venue;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String status;
  final String organizerName;
  final List<TicketType> ticketTypes;
  final String? imageUrl;

  int get capacity => ticketTypes.fold(0, (sum, type) => sum + type.capacity);
  int get remaining => ticketTypes.fold(0, (sum, type) => sum + type.remaining);
  int? get minPriceMinor {
    if (ticketTypes.isEmpty) return null;
    return ticketTypes.map((type) => type.priceMinor).reduce((a, b) => a < b ? a : b);
  }

  String get priceLabel {
    final price = minPriceMinor;
    if (price == null) return 'Tickets soon';
    if (price == 0) return 'Free';
    return 'From ${formatMoney(price)}';
  }

  factory Event.fromJson(Map<String, dynamic> json) {
    final rawTypes = json['ticket_types'] as List<dynamic>? ?? const [];
    return Event(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      venue: json['venue'] as String? ?? '',
      startsAt: parseDate(json['starts_at']),
      endsAt: parseDate(json['ends_at']),
      status: json['status'] as String? ?? 'published',
      organizerName: json['organizer_name'] as String? ?? 'EventFlow organizer',
      imageUrl: json['image_url'] as String?,
      ticketTypes: rawTypes
          .map((item) => TicketType.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BookingEvent {
  const BookingEvent({
    required this.id,
    required this.title,
    required this.venue,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.organizerName,
  });

  final String id;
  final String title;
  final String venue;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String status;
  final String organizerName;

  factory BookingEvent.fromJson(Map<String, dynamic> json) {
    return BookingEvent(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      venue: json['venue'] as String? ?? '',
      startsAt: parseDate(json['starts_at']),
      endsAt: parseDate(json['ends_at']),
      status: json['status'] as String? ?? '',
      organizerName: json['organizer_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'venue': venue,
        'starts_at': startsAt?.toIso8601String(),
        'ends_at': endsAt?.toIso8601String(),
        'status': status,
        'organizer_name': organizerName,
      };
}

class BookingItem {
  const BookingItem({
    required this.ticketTypeId,
    required this.ticketTypeName,
    required this.quantity,
    required this.unitPriceMinor,
  });

  final String ticketTypeId;
  final String ticketTypeName;
  final int quantity;
  final int unitPriceMinor;

  factory BookingItem.fromJson(Map<String, dynamic> json) {
    return BookingItem(
      ticketTypeId: json['ticket_type_id'] as String? ?? '',
      ticketTypeName: json['ticket_type_name'] as String? ?? 'Ticket',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPriceMinor: (json['unit_price_minor'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'ticket_type_id': ticketTypeId,
        'ticket_type_name': ticketTypeName,
        'quantity': quantity,
        'unit_price_minor': unitPriceMinor,
      };
}

class Ticket {
  const Ticket({
    required this.id,
    required this.token,
    required this.shortCode,
    required this.status,
    required this.attendeeName,
    required this.ticketTypeName,
    this.usedAt,
  });

  final String id;
  final String token;
  final String shortCode;
  final String status;
  final String? attendeeName;
  final String ticketTypeName;
  final DateTime? usedAt;

  bool get isUsed => status == 'used';

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: json['id'] as String,
      token: json['token'] as String? ?? '',
      shortCode: json['short_code'] as String? ?? '',
      status: json['status'] as String? ?? 'valid',
      attendeeName: json['attendee_name'] as String?,
      ticketTypeName: json['ticket_type_name'] as String? ?? 'Ticket',
      usedAt: parseDate(json['used_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'token': token,
        'short_code': shortCode,
        'status': status,
        'attendee_name': attendeeName,
        'ticket_type_name': ticketTypeName,
        'used_at': usedAt?.toIso8601String(),
      };
}

class Payment {
  const Payment({
    required this.id,
    required this.providerReference,
    required this.status,
    required this.amountMinor,
    required this.currency,
  });

  final String id;
  final String providerReference;
  final String status;
  final int amountMinor;
  final String currency;

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String? ?? '',
      providerReference: json['provider_reference'] as String? ?? '',
      status: json['status'] as String? ?? '',
      amountMinor: (json['amount_minor'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String? ?? 'ZMW').trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider_reference': providerReference,
        'status': status,
        'amount_minor': amountMinor,
        'currency': currency,
      };
}

class Booking {
  const Booking({
    required this.id,
    required this.status,
    required this.totalMinor,
    required this.currency,
    required this.createdAt,
    required this.event,
    required this.items,
    required this.tickets,
    this.expiresAt,
    this.payment,
  });

  final String id;
  final String status;
  final int totalMinor;
  final String currency;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final BookingEvent event;
  final List<BookingItem> items;
  final List<Ticket> tickets;
  final Payment? payment;

  bool get isConfirmed => status == 'confirmed';
  bool get isPending => status == 'pending';
  bool get isCancelled => status == 'cancelled' || status == 'expired';

  String get statusLabel {
    switch (status) {
      case 'confirmed':
        return 'Confirmed';
      case 'pending':
        return 'Awaiting payment';
      case 'cancelled':
        return 'Cancelled';
      case 'expired':
        return 'Expired';
      default:
        return status;
    }
  }

  factory Booking.fromJson(Map<String, dynamic> json) {
    final items = json['items'] as List<dynamic>? ?? const [];
    final tickets = json['tickets'] as List<dynamic>? ?? const [];
    final paymentJson = json['payment'];
    return Booking(
      id: json['id'] as String,
      status: json['status'] as String? ?? '',
      totalMinor: (json['total_minor'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String? ?? 'ZMW').trim(),
      createdAt: parseDate(json['created_at']),
      expiresAt: parseDate(json['expires_at']),
      event: BookingEvent.fromJson(json['event'] as Map<String, dynamic>),
      items: items
          .map((item) => BookingItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      tickets:
          tickets.map((item) => Ticket.fromJson(item as Map<String, dynamic>)).toList(),
      payment: paymentJson is Map<String, dynamic> ? Payment.fromJson(paymentJson) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'total_minor': totalMinor,
        'currency': currency,
        'created_at': createdAt?.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'event': event.toJson(),
        'items': items.map((item) => item.toJson()).toList(),
        'tickets': tickets.map((ticket) => ticket.toJson()).toList(),
        'payment': payment?.toJson(),
      };
}

class OrganizerEvent {
  const OrganizerEvent({
    required this.id,
    required this.title,
    required this.venue,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.revenueMinor,
    required this.confirmedBookings,
    required this.capacity,
    required this.soldCount,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String venue;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String status;
  final int revenueMinor;
  final int confirmedBookings;
  final int capacity;
  final int soldCount;
  final String? imageUrl;

  factory OrganizerEvent.fromJson(Map<String, dynamic> json) {
    return OrganizerEvent(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      venue: json['venue'] as String? ?? '',
      startsAt: parseDate(json['starts_at']),
      endsAt: parseDate(json['ends_at']),
      status: json['status'] as String? ?? 'draft',
      revenueMinor: (json['revenue_minor'] as num?)?.toInt() ?? 0,
      confirmedBookings: (json['confirmed_bookings'] as num?)?.toInt() ?? 0,
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      soldCount: (json['sold_count'] as num?)?.toInt() ?? 0,
      imageUrl: json['image_url'] as String?,
    );
  }
}

class ScanOutcome {
  const ScanOutcome({
    required this.status,
    required this.message,
    this.shortCode,
    this.attendeeName,
    this.ticketTypeName,
    this.usedAt,
  });

  final String status;
  final String message;
  final String? shortCode;
  final String? attendeeName;
  final String? ticketTypeName;
  final DateTime? usedAt;

  bool get isValid => status == 'valid';
  bool get isAlreadyUsed => status == 'already_used';

  factory ScanOutcome.fromJson(Map<String, dynamic> json) {
    final ticket = json['ticket'] as Map<String, dynamic>?;
    return ScanOutcome(
      status: json['status'] as String? ?? 'invalid',
      message: json['message'] as String? ?? 'Invalid ticket',
      shortCode: ticket?['short_code'] as String?,
      attendeeName: ticket?['attendee_name'] as String?,
      ticketTypeName: ticket?['ticket_type_name'] as String?,
      usedAt: parseDate(ticket?['used_at']),
    );
  }
}

class SalesSnapshot {
  const SalesSnapshot({
    required this.ticketTypes,
    required this.revenueMinor,
    required this.confirmedBookings,
    required this.pendingBookings,
    required this.checkedIn,
    required this.validTickets,
  });

  final List<Map<String, dynamic>> ticketTypes;
  final int revenueMinor;
  final int confirmedBookings;
  final int pendingBookings;
  final int checkedIn;
  final int validTickets;

  factory SalesSnapshot.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>? ?? const {};
    final checkins = json['checkins'] as Map<String, dynamic>? ?? const {};
    return SalesSnapshot(
      ticketTypes: (json['ticket_types'] as List<dynamic>? ?? const [])
          .map((item) => item as Map<String, dynamic>)
          .toList(),
      revenueMinor: (totals['revenue_minor'] as num?)?.toInt() ?? 0,
      confirmedBookings: (totals['confirmed_bookings'] as num?)?.toInt() ?? 0,
      pendingBookings: (totals['pending_bookings'] as num?)?.toInt() ?? 0,
      checkedIn: (checkins['checked_in'] as num?)?.toInt() ?? 0,
      validTickets: (checkins['valid'] as num?)?.toInt() ?? 0,
    );
  }
}
