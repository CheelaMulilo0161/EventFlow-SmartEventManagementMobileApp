import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../utils.dart';
import 'scan_screen.dart';

class ManageEventScreen extends StatefulWidget {
  const ManageEventScreen({super.key, required this.eventId});

  final String eventId;

  @override
  State<ManageEventScreen> createState() => _ManageEventScreenState();
}

class _ManageEventScreenState extends State<ManageEventScreen> {
  Event? _event;
  SalesSnapshot? _sales;
  bool _loading = true;
  bool _actionBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AuthState>().api;
      final results = await Future.wait([
        api.getOrganizerEvent(widget.eventId),
        api.getSales(widget.eventId),
      ]);
      if (!mounted) return;
      setState(() {
        _event = results[0] as Event;
        _sales = results[1] as SalesSnapshot;
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

  Future<void> _publish() async {
    setState(() => _actionBusy = true);
    try {
      await context.read<AuthState>().api.publishEvent(widget.eventId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event published and on sale.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this event?'),
        content: const Text(
          'All active bookings will be cancelled and ticket codes will stop working. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep event'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel event'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await context.read<AuthState>().api.cancelEvent(widget.eventId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event cancelled.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _scan() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanScreen(initialEventId: widget.eventId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = _event;
    final sales = _sales;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage event'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : event == null || sales == null
                  ? const Center(child: Text('Event not found'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          event.title,
                                          style: theme.textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          prettyStatus(event.status),
                                          style: TextStyle(
                                            color: theme.colorScheme.onPrimaryContainer,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${formatEventDate(event.startsAt)} · ${event.venue}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _Metric(
                                          label: 'Revenue',
                                          value: formatMoney(sales.revenueMinor),
                                        ),
                                      ),
                                      Expanded(
                                        child: _Metric(
                                          label: 'Bookings',
                                          value: '${sales.confirmedBookings}',
                                        ),
                                      ),
                                      Expanded(
                                        child: _Metric(
                                          label: 'Checked in',
                                          value: '${sales.checkedIn}',
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (event.status == 'draft' || event.status == 'published') ...[
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        if (event.status == 'draft')
                                          Expanded(
                                            child: FilledButton.icon(
                                              onPressed: _actionBusy ? null : _publish,
                                              icon: const Icon(Icons.publish),
                                              label: const Text('Publish'),
                                            ),
                                          ),
                                        if (event.status == 'draft')
                                          const SizedBox(width: 10),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _actionBusy ||
                                                    event.status != 'published'
                                                ? null
                                                : _scan,
                                            icon: const Icon(Icons.qr_code_scanner),
                                            label: const Text('Scan'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Ticket types',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...event.ticketTypes.map((type) {
                            final sold = type.soldCount;
                            final percent = type.capacity == 0
                                ? 0.0
                                : (sold / type.capacity).clamp(0.0, 1.0);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              type.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          Text(formatMoney(type.priceMinor)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: percent,
                                        minHeight: 8,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        '$sold sold · ${type.remaining} remaining · '
                                        '${type.capacity} capacity',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Icon(Icons.qr_code_2, size: 30),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'At the gate, scan QR codes or enter a ticket short code. '
                                      'The server marks each ticket as used exactly once.',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: event.status == 'published' ? _scan : null,
                                    icon: const Icon(Icons.arrow_forward),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (event.status == 'published') ...[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _actionBusy ? null : _cancel,
                              icon: Icon(Icons.cancel_outlined, color: theme.colorScheme.error),
                              label: Text(
                                'Cancel event',
                                style: TextStyle(color: theme.colorScheme.error),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
