import 'package:eventflow/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money is formatted from integer minor units', () {
    expect(formatMoney(10000), 'ZMW 100.00');
    expect(formatMoney(750), 'ZMW 7.50');
    expect(formatMoney(0), 'ZMW 0.00');
  });

  test('event price label picks the cheapest ticket type', () {
    final event = Event.fromJson({
      'id': 'event-1',
      'title': 'Test event',
      'description': '',
      'venue': 'Lusaka',
      'starts_at': DateTime.now().toIso8601String(),
      'ends_at': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      'status': 'published',
      'organizer_name': 'Organizer',
      'ticket_types': [
        {
          'id': 'vip',
          'name': 'VIP',
          'price_minor': 25000,
          'currency': 'ZMW',
          'capacity': 10,
          'sold_count': 0,
          'remaining': 10,
        },
        {
          'id': 'general',
          'name': 'General',
          'price_minor': 10000,
          'currency': 'ZMW',
          'capacity': 100,
          'sold_count': 0,
          'remaining': 100,
        },
      ],
    });

    expect(event.priceLabel, 'From ZMW 100.00');
    expect(event.remaining, 110);
  });
}
