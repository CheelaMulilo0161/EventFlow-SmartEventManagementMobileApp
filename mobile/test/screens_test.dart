import 'package:eventflow/api_client.dart';
import 'package:eventflow/auth_state.dart';
import 'package:eventflow/models.dart';
import 'package:eventflow/screens/home_shell.dart';
import 'package:eventflow/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeApiClient extends ApiClient {
  FakeApiClient({this.events = const []}) : super(baseUrl: 'http://test.local:3000');

  final List<Event> events;

  @override
  Future<List<Event>> getEvents({String search = ''}) async => events;

  @override
  Future<List<Booking>> getBookings() async => const [];

  @override
  Future<List<OrganizerEvent>> getOrganizerEvents() async => const [];
}

Event buildEvent() {
  final now = DateTime.now();
  return Event.fromJson({
    'id': 'event-1',
    'title': 'Lusaka Live Concert',
    'description': 'Live music and food.',
    'venue': 'Mulungushi Conference Centre',
    'starts_at': now.add(const Duration(days: 14)).toIso8601String(),
    'ends_at': now.add(const Duration(days: 14, hours: 4)).toIso8601String(),
    'status': 'published',
    'organizer_name': 'Mwila Organizer',
    'ticket_types': [
      {
        'id': 'general',
        'name': 'General',
        'price_minor': 10000,
        'currency': 'ZMW',
        'capacity': 100,
        'sold_count': 5,
        'remaining': 95,
      },
    ],
  });
}

AuthState buildAuth({String role = 'attendee', List<Event> events = const []}) {
  final auth = AuthState(api: FakeApiClient(events: events))
    ..user = User(
      id: 'user-1',
      email: '$role@eventflow.zm',
      fullName: 'Demo ${role[0].toUpperCase()}${role.substring(1)}',
      phone: '+260971000001',
      role: role,
    );
  auth.api.token = 'test-token';
  return auth;
}

Widget wrap(AuthState auth, Widget child) {
  return ChangeNotifierProvider<AuthState>.value(
    value: auth,
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('login screen shows demo accounts and server address', (tester) async {
    await tester.pumpWidget(wrap(buildAuth(), const LoginScreen()));
    await tester.pump();

    expect(find.text('EventFlow'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Attendee'), findsOneWidget);
    expect(find.text('Organizer'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('http://test.local:3000'), findsOneWidget);
  });

  testWidgets('attendee navigation hides organizer destinations', (tester) async {
    await tester.pumpWidget(
      wrap(buildAuth(events: [buildEvent()]), const HomeShell()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Scan'), findsNothing);
    expect(find.text('My events'), findsNothing);
    expect(find.text('Lusaka Live Concert'), findsOneWidget);
    expect(find.text('From ZMW 100.00'), findsOneWidget);
  });

  testWidgets('attendee without events sees the empty state', (tester) async {
    await tester.pumpWidget(wrap(buildAuth(), const HomeShell()));
    await tester.pumpAndSettle();

    expect(find.text('No events match your search yet.'), findsOneWidget);
  });
}
