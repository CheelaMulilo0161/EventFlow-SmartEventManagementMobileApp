import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../utils.dart';
import 'create_event_screen.dart';
import 'manage_event_screen.dart';

class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({super.key});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen> {
  List<OrganizerEvent> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _events.isEmpty;
      _error = null;
    });
    try {
      final events = await context.read<AuthState>().api.getOrganizerEvents();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateEventScreen()),
    );
    if (created == true && mounted) _load();
  }

  Future<void> _manage(OrganizerEvent event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ManageEventScreen(eventId: event.id)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final revenue = _events.fold<int>(0, (sum, event) => sum + event.revenueMinor);
    final sold = _events.fold<int>(0, (sum, event) => sum + event.soldCount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My events'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Try again')),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _HeaderStat(
                                label: 'Revenue',
                                value: formatMoney(revenue),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 38,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            Expanded(
                              child: _HeaderStat(
                                label: 'Tickets sold',
                                value: '$sold',
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 38,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            Expanded(
                              child: _HeaderStat(
                                label: 'Events',
                                value: '${_events.length}',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_events.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Column(
                            children: [
                              Icon(
                                Icons.event_note_outlined,
                                size: 56,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'You have not created an event yet.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _create,
                                icon: const Icon(Icons.add),
                                label: const Text('Create your first event'),
                              ),
                            ],
                          ),
                        )
                      else
                        ..._events.map(
                          (event) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _OrganizerEventCard(
                              event: event,
                              onTap: () => _manage(event),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _OrganizerEventCard extends StatelessWidget {
  const _OrganizerEventCard({required this.event, required this.onTap});

  final OrganizerEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = event.status == 'published'
        ? theme.colorScheme.primary
        : event.status == 'cancelled'
            ? theme.colorScheme.error
            : Colors.orange.shade800;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      prettyStatus(event.status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${formatEventDate(event.startsAt)} · ${event.venue}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MiniStat(label: 'Sold', value: '${event.soldCount}/${event.capacity}'),
                  const SizedBox(width: 18),
                  _MiniStat(label: 'Bookings', value: '${event.confirmedBookings}'),
                  const Spacer(),
                  Text(
                    formatMoney(event.revenueMinor),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
