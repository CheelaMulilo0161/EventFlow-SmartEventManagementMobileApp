import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../auth_state.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _venueController = TextEditingController();
  final List<_TypeDraft> _types = [_TypeDraft.first()];

  late DateTime _start;
  int _durationHours = 4;
  bool _publish = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().add(const Duration(days: 7));
    _start = DateTime(now.year, now.month, now.day, 18, 0);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    for (final type in _types) {
      type.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute);
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(_start.year, _start.month, _start.day, picked.hour, picked.minute);
    });
  }

  void _addType() {
    setState(() => _types.add(_TypeDraft()));
  }

  void _removeType(int index) {
    if (_types.length == 1) return;
    setState(() {
      _types.removeAt(index).dispose();
    });
  }

  int _priceToMinor(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    final amount = double.tryParse(cleaned) ?? 0;
    return (amount * 100).round();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final ticketTypes = _types
        .map(
          (type) => {
            'name': type.name.text.trim(),
            'price_minor': _priceToMinor(type.price.text),
            'capacity': int.tryParse(type.capacity.text.trim()) ?? 0,
          },
        )
        .toList();

    final api = context.read<AuthState>().api;
    try {
      final event = await api.createEvent({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'venue': _venueController.text.trim(),
        'starts_at': _start.toUtc().toIso8601String(),
        'ends_at': _start.add(Duration(hours: _durationHours)).toUtc().toIso8601String(),
        'ticket_types': ticketTypes,
      });

      if (_publish) {
        await api.publishEvent(event.id);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create event')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            Text(
              'Event basics',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Event title',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (value) =>
                  value == null || value.trim().length < 3 ? 'Enter an event title' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _venueController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Venue',
                prefixIcon: Icon(Icons.place_outlined),
              ),
              validator: (value) =>
                  value == null || value.trim().length < 2 ? 'Enter the venue' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      '${_start.day.toString().padLeft(2, '0')}/'
                      '${_start.month.toString().padLeft(2, '0')}/${_start.year}',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      '${_start.hour.toString().padLeft(2, '0')}:'
                      '${_start.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _durationHours,
              decoration: const InputDecoration(
                labelText: 'Duration',
                prefixIcon: Icon(Icons.timelapse),
              ),
              items: const [2, 3, 4, 5, 6, 8, 10]
                  .map(
                    (hours) => DropdownMenuItem(
                      value: hours,
                      child: Text('$hours hours'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _durationHours = value);
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Ticket types',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addType,
                  icon: const Icon(Icons.add),
                  label: const Text('Add type'),
                ),
              ],
            ),
            ..._types.asMap().entries.map((entry) {
              final index = entry.key;
              final type = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            'Ticket ${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          if (_types.length > 1)
                            IconButton(
                              onPressed: () => _removeType(index),
                              icon: const Icon(Icons.delete_outline),
                              color: theme.colorScheme.error,
                            ),
                        ],
                      ),
                      TextFormField(
                        controller: type.name,
                        decoration: const InputDecoration(labelText: 'Name (e.g. VIP)'),
                        validator: (value) => value == null || value.trim().length < 2
                            ? 'Enter a ticket name'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: type.price,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Price (ZMW)',
                                prefixIcon: Icon(Icons.payments_outlined),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter 0 for free';
                                }
                                final parsed = double.tryParse(
                                  value.replaceAll(',', '').trim(),
                                );
                                if (parsed == null || parsed < 0) return 'Invalid price';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: type.capacity,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Capacity',
                                prefixIcon: Icon(Icons.groups_outlined),
                              ),
                              validator: (value) {
                                final parsed = int.tryParse(value?.trim() ?? '');
                                if (parsed == null || parsed <= 0) {
                                  return 'Must be > 0';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _publish,
              onChanged: (value) => setState(() => _publish = value),
              title: const Text('Publish immediately'),
              subtitle: const Text('Attendees can book as soon as the event is saved'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save event'),
          ),
        ),
      ),
    );
  }
}

class _TypeDraft {
  _TypeDraft({
    String? name,
    String? price,
    String? capacity,
  })  : name = TextEditingController(text: name),
        price = TextEditingController(text: price),
        capacity = TextEditingController(text: capacity);

  factory _TypeDraft.first() {
    return _TypeDraft(name: 'General', price: '100', capacity: '100');
  }

  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController capacity;

  void dispose() {
    name.dispose();
    price.dispose();
    capacity.dispose();
  }
}
