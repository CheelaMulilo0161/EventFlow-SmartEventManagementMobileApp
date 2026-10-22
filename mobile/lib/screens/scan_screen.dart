import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.initialEventId});

  final String? initialEventId;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _codeController = TextEditingController();
  late final MobileScannerController _scannerController;
  List<OrganizerEvent> _events = [];
  String? _selectedEventId;
  bool _loadingEvents = true;
  bool _processing = false;
  ScanOutcome? _outcome;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEvents());
  }

  @override
  void dispose() {
    _codeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    try {
      final events = await context.read<AuthState>().api.getOrganizerEvents();
      final published = events.where((event) => event.status == 'published').toList();
      if (!mounted) return;
      setState(() {
        _events = published;
        _loadingEvents = false;
        _selectedEventId = widget.initialEventId != null &&
                published.any((event) => event.id == widget.initialEventId)
            ? widget.initialEventId
            : (published.isEmpty ? null : published.first.id);
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingEvents = false;
        _error = error.message;
      });
    }
  }

  Future<void> _handleToken(String token) async {
    if (_processing || _selectedEventId == null) return;
    setState(() {
      _processing = true;
      _outcome = null;
    });
    final api = context.read<AuthState>().api;
    await _scannerController.stop();

    try {
      final result = await api.scanTicket(token, eventId: _selectedEventId);
      if (!mounted) return;
      setState(() {
        _outcome = result;
        _processing = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = error.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _handleCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 6 || _processing || _selectedEventId == null) return;
    setState(() {
      _processing = true;
      _outcome = null;
    });
    final api = context.read<AuthState>().api;
    await _scannerController.stop();

    try {
      final result = await api.scanShortCode(code, eventId: _selectedEventId);
      if (!mounted) return;
      setState(() {
        _outcome = result;
        _processing = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = error.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _scanNext() async {
    setState(() {
      _outcome = null;
      _error = null;
      _codeController.clear();
    });
    try {
      await _scannerController.start();
    } catch (_) {
      // The manual code form remains available when the camera cannot start.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan tickets'),
        actions: [
          IconButton(
            tooltip: 'Torch',
            onPressed: () => _scannerController.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
        ],
      ),
      body: _loadingEvents
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_error != null && _events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                if (_events.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 46,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Publish an event before scanning tickets.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedEventId,
                    decoration: const InputDecoration(
                      labelText: 'Scanning for event',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    items: _events
                        .map(
                          (event) => DropdownMenuItem(
                            value: event.id,
                            child: Text(
                              event.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedEventId = value;
                        _outcome = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      height: 300,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: _scannerController,
                            onDetect: (capture) {
                              final code = capture.barcodes
                                  .map((barcode) => barcode.rawValue)
                                  .whereType<String>()
                                  .firstOrNull;
                              if (code != null && code.isNotEmpty) {
                                _handleToken(code);
                              }
                            },
                            errorBuilder: (context, error) {
                              return Container(
                                color: Colors.black87,
                                padding: const EdgeInsets.all(24),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.no_photography_outlined,
                                      color: Colors.white70,
                                      size: 42,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Camera unavailable.\nUse the short code form below.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          IgnorePointer(
                            child: Center(
                              child: Container(
                                width: 210,
                                height: 210,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_processing)
                            Container(
                              color: Colors.black54,
                              child: const Center(
                                child: CircularProgressIndicator(color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Point the camera at the attendee’s QR code.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_outcome != null) ...[
                    _ScanResultCard(outcome: _outcome!),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _processing ? null : _scanNext,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan next ticket'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.keyboard_outlined),
                              SizedBox(width: 8),
                              Text(
                                'Manual check-in',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Use the 8-character code printed under the QR.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _codeController,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 8,
                            decoration: const InputDecoration(
                              labelText: 'Short code',
                              prefixIcon: Icon(Icons.confirmation_number_outlined),
                              counterText: '',
                            ),
                            onSubmitted: (_) => _handleCode(),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.tonal(
                            onPressed: _processing ? null : _handleCode,
                            child: const Text('Check in with code'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ScanResultCard extends StatelessWidget {
  const _ScanResultCard({required this.outcome});

  final ScanOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = outcome.isValid;
    final used = outcome.isAlreadyUsed;
    final color = valid
        ? const Color(0xFF137A3D)
        : used
            ? const Color(0xFFB26A00)
            : theme.colorScheme.error;
    final icon = valid
        ? Icons.check_circle
        : used
            ? Icons.history
            : Icons.cancel;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 46),
          const SizedBox(height: 8),
          Text(
            outcome.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (outcome.attendeeName != null ||
              outcome.ticketTypeName != null ||
              outcome.shortCode != null) ...[
            const SizedBox(height: 12),
            if (outcome.attendeeName != null)
              Text(
                outcome.attendeeName!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            if (outcome.ticketTypeName != null)
              Text(
                outcome.ticketTypeName!,
                style: theme.textTheme.bodySmall,
              ),
            if (outcome.shortCode != null)
              Text(
                'Code ${outcome.shortCode}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.5,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
