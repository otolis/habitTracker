import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await HabitRepository.create();
  runApp(HabitApp(repository: repo));
}

class HabitApp extends StatelessWidget {
  const HabitApp({super.key, required this.repository});
  final HabitRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Habit Tracker',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C63FF),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: HomeScreen(repository: repository),
    );
  }
}

// models

class Habit {
  Habit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    DateTime? createdAt,
    Set<String>? completedDays,
  })  : createdAt = createdAt ?? DateTime.now(),
        completedDays = completedDays ?? <String>{};

  final String id;
  String name;
  String emoji; 
  int colorValue; 
  final DateTime createdAt;
  final Set<String> completedDays; 

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'colorValue': colorValue,
        'createdAt': createdAt.toIso8601String(),
        'completedDays': completedDays.toList(),
      };

  static Habit fromJson(Map<String, dynamic> json) => Habit(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        colorValue: json['colorValue'] as int,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        completedDays: {
          for (final d in (json['completedDays'] as List? ?? const [])) d as String
        },
      );
}

// json file storage
class HabitRepository {
  HabitRepository._(this._file);
  final File _file;

  static const _filename = 'habits.json';

  static Future<HabitRepository> create() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_filename');
    if (!await file.exists()) {
      await file.writeAsString(jsonEncode({'habits': []}));
    }
    return HabitRepository._(file);
  }

  Future<List<Habit>> loadHabits() async {
    try {
      final text = await _file.readAsString();
      final map = jsonDecode(text) as Map<String, dynamic>;
      final list = (map['habits'] as List?) ?? const [];
      return list.map((e) => Habit.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHabits(List<Habit> habits) async {
    final map = {
      'habits': habits.map((h) => h.toJson()).toList(),
    };
    await _file.writeAsString(jsonEncode(map));
  }
}

// dates and streaks 
String dayKey(DateTime dt, {int startOfDayHour = 0}) {
  
  final local = dt.toLocal();
  final adjusted = local.hour < startOfDayHour
      ? local.subtract(const Duration(days: 1))
      : local;
  final y = adjusted.year.toString().padLeft(4, '0');
  final m = adjusted.month.toString().padLeft(2, '0');
  final d = adjusted.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

int computeCurrentStreak(Habit habit, {int startOfDayHour = 0}) {
  int streak = 0;
  var cursor = DateTime.now();
  while (true) {
    final key = dayKey(cursor, startOfDayHour: startOfDayHour);
    if (habit.completedDays.contains(key)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}

int computeBestStreak(Habit habit) {
  
  if (habit.completedDays.isEmpty) return 0;
  final dates = habit.completedDays
      .map((k) => DateTime.parse('${k}T12:00:00'))
      .toList()
    ..sort();
  int best = 1;
  int current = 1;
  for (int i = 1; i < dates.length; i++) {
    final prev = dates[i - 1];
    final cur = dates[i];
    if (cur.difference(prev).inDays == 1) {
      current += 1;
      if (current > best) best = current;
    } else if (cur.difference(prev).inDays > 1) {
      current = 1;
    }
  }
  return best;
}

List<String> lastNDaysKeys(int n, {int startOfDayHour = 0}) {
  final now = DateTime.now();
  return List.generate(n, (i) => dayKey(now.subtract(Duration(days: i)), startOfDayHour: startOfDayHour))
      .reversed
      .toList();
}

//home screen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});
  final HabitRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final int startOfDayHour = 4; 
  List<Habit> habits = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.repository.loadHabits();
    setState(() {
      habits = data;
      loading = false;
    });
  }

  Future<void> _save() async => widget.repository.saveHabits(habits);

  void _toggleToday(Habit h) {
    final key = dayKey(DateTime.now(), startOfDayHour: startOfDayHour);
    setState(() {
      if (h.completedDays.contains(key)) {
        h.completedDays.remove(key);
      } else {
        h.completedDays.add(key);
      }
    });
    _save();
  }

  Future<void> _addHabitDialog() async {
    final nameCtrl = TextEditingController();
    String emoji = '✅';
    Color color = Colors.indigo;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('New Habit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Habit name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Emoji:'),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 8,
                    children: ['✅', '📚', '🧘', '🏃', '💧', '🍎', '🛏️', '🧠']
                        .map((e) => ChoiceChip(
                              label: Text(e, style: const TextStyle(fontSize: 18)),
                              selected: emoji == e,
                              onSelected: (_) => setState(() => emoji = e),
                            ))
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Color:'),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 8,
                    children: _palette
                        .map((c) => _ColorDot(
                              color: c,
                              selected: color.value == c.value,
                              onTap: () => setState(() => color = c),
                            ))
                        .toList(),
                  )
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  setState(() {
                    habits.add(Habit(
                      id: UniqueKey().toString(),
                      name: name,
                      emoji: emoji,
                      colorValue: color.value,
                    ));
                  });
                  _save();
                  Navigator.pop(ctx);
                },
                child: const Text('Create'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _editHabitDialog(Habit h) async {
    final nameCtrl = TextEditingController(text: h.name);
    String emoji = h.emoji;
    Color color = h.color;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Edit Habit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Habit name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Emoji:'),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 8,
                    children: ['✅', '📚', '🧘', '🏃', '💧', '🍎', '🛏️', '🧠']
                        .map((e) => ChoiceChip(
                              label: Text(e, style: const TextStyle(fontSize: 18)),
                              selected: emoji == e,
                              onSelected: (_) => setState(() => emoji = e),
                            ))
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Color:'),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 8,
                    children: _palette
                        .map((c) => _ColorDot(
                              color: c,
                              selected: color.value == c.value,
                              onTap: () => setState(() => color = c),
                            ))
                        .toList(),
                  )
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    h.name = nameCtrl.text.trim().isEmpty ? h.name : nameCtrl.text.trim();
                    h.emoji = emoji;
                    h.colorValue = color.value;
                  });
                  _save();
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() => habits.removeWhere((x) => x.id == h.id));
                  _save();
                  Navigator.pop(ctx);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete habit'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habit Tracker'),
      ),
      body: habits.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: habits.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final h = habits[i];
                final todayKey = dayKey(DateTime.now(), startOfDayHour: startOfDayHour);
                final doneToday = h.completedDays.contains(todayKey);
                final currentStreak = computeCurrentStreak(h, startOfDayHour: startOfDayHour);
                final bestStreak = computeBestStreak(h);

                return GestureDetector(
                  onLongPress: () => _editHabitDialog(h),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: h.color.withOpacity(0.15),
                                child: Text(h.emoji, style: const TextStyle(fontSize: 18)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(h.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Streak: $currentStreak  •  Best: $bestStreak',
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: doneToday ? 'Mark as not done' : 'Mark as done',
                                onPressed: () => _toggleToday(h),
                                icon: Icon(
                                  doneToday ? Icons.check_circle : Icons.circle_outlined,
                                  color: doneToday ? h.color : Theme.of(context).colorScheme.outline,
                                  size: 28,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _WeeklyHeatmap(habit: h, weeks: 8, accent: h.color, startOfDayHour: startOfDayHour),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addHabitDialog,
        icon: const Icon(Icons.add),
        label: const Text('New habit'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Create your first habit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to add a habit. Long-press a habit to edit or delete it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// weekly hitmap
class _WeeklyHeatmap extends StatelessWidget {
  const _WeeklyHeatmap({
    required this.habit,
    this.weeks = 8,
    required this.accent,
    required this.startOfDayHour,
  });

  final Habit habit;
  final int weeks; 
  final Color accent;
  final int startOfDayHour;

  @override
  Widget build(BuildContext context) {
    final days = lastNDaysKeys(weeks * 7, startOfDayHour: startOfDayHour);
    final tiles = days.map((k) => habit.completedDays.contains(k)).toList();

    return SizedBox(
      height: 72,
      child: Row(
        children: List.generate(weeks, (w) {
          final start = w * 7;
          final end = start + 7;
          final slice = tiles.sublist(start, end);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final done = slice[i];
                return Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: done ? accent.withOpacity(0.9) : Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.onPrimaryContainer : Colors.white,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
      ),
    );
  }
}

final _palette = <Color>[
  const Color(0xFF6C63FF),
  const Color(0xFF00B894),
  const Color(0xFFFF7675),
  const Color(0xFFFFC312),
  const Color(0xFF0984E3),
  const Color(0xFFe84393),
  const Color(0xFF2ecc71),
  const Color(0xFFe17055),
];
