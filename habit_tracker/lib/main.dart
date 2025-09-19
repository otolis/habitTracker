import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// theme and dark mode
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await HabitRepository.create();
  final theme = ThemeController();
  await theme.load();
  runApp(HabitApp(repository: repo, theme: theme));
}

// app
class HabitApp extends StatelessWidget {
  const HabitApp({super.key, required this.repository, required this.theme});
  final HabitRepository repository;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: theme,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Habit Tracker',
          themeMode: theme.mode,
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF6C63FF),
            brightness: Brightness.light,
            useMaterial3: true,
            cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF6C63FF),
            brightness: Brightness.dark,
            useMaterial3: true,
            cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
          ),
          
          home: HomeScreen(
            key: ValueKey(theme.mode),
            repository: repository,
            theme: theme,
          ),
        );
      },
    );
  }
}

// theme controller
class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.light;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/settings.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      mode = (map['theme'] == 'dark') ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {}
  }

  Future<void> _save() async {
    final f = await _file();
    await f.writeAsString(jsonEncode({'theme': mode == ThemeMode.dark ? 'dark' : 'light'}));
  }

  Future<void> toggle() async {
    mode = (mode == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    await _save();
    notifyListeners();
  }
}

// models
enum HabitType { check, count }

class Habit {
  Habit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    this.type = HabitType.check,
    this.goalCount = 1,
    DateTime? createdAt,
    Set<String>? completedDays,
    Map<String, int>? dayCounts,
  })  : createdAt = createdAt ?? DateTime.now(),
        completedDays = completedDays ?? <String>{},
        dayCounts = dayCounts ?? <String, int>{};

  final String id;
  String name;
  String emoji;
  int colorValue;
  HabitType type;
  int? goalCount;
  final DateTime createdAt;
  final Set<String> completedDays;     // check type
  final Map<String, int> dayCounts;    // count type

  Color get color => Color(colorValue);

  bool isCompletedOn(String key) {
    if (type == HabitType.check) return completedDays.contains(key);
    final goal = (goalCount ?? 1).clamp(1, 1000000);
    return (dayCounts[key] ?? 0) >= goal;
  }

  Iterable<String> completedDayKeysForMetrics() sync* {
    if (type == HabitType.check) {
      yield* completedDays;
    } else {
      final goal = (goalCount ?? 1).clamp(1, 1000000);
      for (final e in dayCounts.entries) {
        if (e.value >= goal) yield e.key;
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'colorValue': colorValue,
        'type': type.name,
        'goalCount': goalCount,
        'createdAt': createdAt.toIso8601String(),
        'completedDays': completedDays.toList(),
        'dayCounts': dayCounts,
      };

  static Habit fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] as String?) ?? 'check';
    final parsedType =
        HabitType.values.firstWhere((t) => t.name == typeStr, orElse: () => HabitType.check);
    final rawCounts = (json['dayCounts'] as Map?) ?? {};
    return Habit(
      id: json['id'] as String,
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      colorValue: json['colorValue'] as int,
      type: parsedType,
      goalCount: (json['goalCount'] as int?) ?? 1,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      completedDays: {
        for (final d in (json['completedDays'] as List? ?? const [])) d as String
      },
      dayCounts: {
        for (final e in rawCounts.entries)
          e.key.toString(): int.tryParse(e.value.toString()) ?? 0
      },
    );
  }
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
    final map = {'habits': habits.map((h) => h.toJson()).toList()};
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
    if (habit.isCompletedOn(key)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}

int computeBestStreak(Habit habit) {
  final days = habit.completedDayKeysForMetrics().toList();
  if (days.isEmpty) return 0;
  final dates = days.map((k) => DateTime.parse('${k}T12:00:00')).toList()..sort();
  int best = 1, current = 1;
  for (int i = 1; i < dates.length; i++) {
    final gap = dates[i].difference(dates[i - 1]).inDays;
    if (gap == 1) {
      current++;
      if (current > best) best = current;
    } else if (gap > 1) {
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

// home screen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, required this.theme});
  final HabitRepository repository;
  final ThemeController theme;

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
    if (h.type == HabitType.count) {
      _incrementToday(h);
      return;
    }
    setState(() {
      if (h.completedDays.contains(key)) {
        h.completedDays.remove(key);
      } else {
        h.completedDays.add(key);
      }
    });
    _save();
  }

  void _incrementToday(Habit h) {
    final k = dayKey(DateTime.now(), startOfDayHour: startOfDayHour);
    setState(() => h.dayCounts[k] = (h.dayCounts[k] ?? 0) + 1);
    _save();
  }

  void _decrementToday(Habit h) {
    final k = dayKey(DateTime.now(), startOfDayHour: startOfDayHour);
    setState(() => h.dayCounts[k] = ((h.dayCounts[k] ?? 0) - 1).clamp(0, 1000000));
    _save();
  }

  Future<void> _addHabitDialog() async {
    final nameCtrl = TextEditingController();
    final goalCtrl = TextEditingController(text: '8');
    String emoji = '✅';
    Color color = Colors.indigo;
    HabitType type = HabitType.check;

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
                  const Text('Type:'),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('check'),
                    selected: type == HabitType.check,
                    onSelected: (_) => setState(() => type = HabitType.check),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('count'),
                    selected: type == HabitType.count,
                    onSelected: (_) => setState(() => type = HabitType.count),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (type == HabitType.count)
                TextField(
                  controller: goalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'daily goal (e.g. 8)',
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
                              selected: color.toARGB32() == c.toARGB32(),
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
                  int? goal;
                  if (type == HabitType.count) {
                    goal = int.tryParse(goalCtrl.text.trim());
                    goal = (goal == null || goal <= 0) ? 8 : goal;
                  }
                  setState(() {
                    habits.add(Habit(
                      id: UniqueKey().toString(),
                      name: name,
                      emoji: emoji,
                      colorValue: color.toARGB32(),
                      type: type,
                      goalCount: type == HabitType.count ? goal : 1,
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
    final goalCtrl = TextEditingController(text: (h.goalCount ?? 1).toString());
    String emoji = h.emoji;
    Color color = h.color;
    HabitType type = h.type;

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
                  const Text('Type:'),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('check'),
                    selected: type == HabitType.check,
                    onSelected: (_) => setState(() => type = HabitType.check),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('count'),
                    selected: type == HabitType.count,
                    onSelected: (_) => setState(() => type = HabitType.count),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (type == HabitType.count)
                TextField(
                  controller: goalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'daily goal',
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
                              selected: color.toARGB32() == c.toARGB32(),
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
                    final newName = nameCtrl.text.trim();
                    if (newName.isNotEmpty) h.name = newName;
                    h.type = type;
                    if (type == HabitType.count) {
                      final g = int.tryParse(goalCtrl.text.trim());
                      h.goalCount = (g == null || g <= 0) ? 8 : g;
                    } else {
                      h.goalCount = 1;
                    }
                    h.emoji = emoji;
                    // ignore: deprecated_member_use
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

  Future<void> _confirmDelete(Habit h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete habit?'),
        content: Text('This will remove "${h.name}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => habits.removeWhere((x) => x.id == h.id));
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = widget.theme.mode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habit Tracker'),
        actions: [
          IconButton(
            tooltip: isDark ? 'light mode' : 'dark mode',
            onPressed: () => widget.theme.toggle(),
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
          ),
        ],
      ),
      body: habits.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: habits.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final h = habits[i];
                final today = dayKey(DateTime.now(), startOfDayHour: startOfDayHour);
                final doneToday = h.isCompletedOn(today);
                final currentStreak = computeCurrentStreak(h, startOfDayHour: startOfDayHour);
                final bestStreak = computeBestStreak(h);

                final goal = (h.goalCount ?? 1).clamp(1, 1000000);
                final countToday = h.dayCounts[today] ?? (h.type == HabitType.check && doneToday ? 1 : 0);
                final progress =
                    (h.type == HabitType.count) ? (countToday / goal).clamp(0.0, 1.0) : (doneToday ? 1.0 : 0.0);

                return GestureDetector(
                  onLongPress: () => _editHabitDialog(h),
                  child: Card(
                     
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 42,
                                height: 42,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0, end: progress),
                                      duration: const Duration(milliseconds: 350),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, value, _) {
                                        return CircularProgressIndicator(
                                          value: value,
                                          strokeWidth: 4,
                                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                          valueColor: AlwaysStoppedAnimation<Color>(h.color),
                                        );
                                      },
                                    ),
                                    Text(h.emoji, style: const TextStyle(fontSize: 18)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(h.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 250),
                                      transitionBuilder: (child, anim) =>
                                          FadeTransition(opacity: anim, child: child),
                                      child: Text(
                                        h.type == HabitType.count
                                            ? 'Today: $countToday / $goal  •  Streak: $currentStreak  •  Best: $bestStreak'
                                            : 'Streak: $currentStreak  •  Best: $bestStreak',
                                        key: ValueKey('${h.id}-$countToday-$currentStreak-$bestStreak-${h.type.name}'),
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'edit',
                                onPressed: () => _editHabitDialog(h),
                                icon: const Icon(Icons.edit),
                              ),
                              IconButton(
                                tooltip: 'delete',
                                onPressed: () => _confirmDelete(h),
                                icon: const Icon(Icons.delete_outline),
                                color: Colors.red,
                              ),
                              if (h.type == HabitType.count) ...[
                                IconButton(
                                  tooltip: 'minus',
                                  onPressed: () => _decrementToday(h),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                IconButton(
                                  tooltip: 'plus',
                                  onPressed: () => _incrementToday(h),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ] else ...[
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(scale: anim, child: child),
                                  child: IconButton(
                                    key: ValueKey(doneToday),
                                    tooltip: doneToday ? 'mark as not done' : 'mark as done',
                                    onPressed: () => _toggleToday(h),
                                    icon: Icon(
                                      doneToday ? Icons.check_circle : Icons.circle_outlined,
                                      color: doneToday
                                          ? h.color
                                          : Theme.of(context).colorScheme.outline,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          _WeeklyHeatmap(
                            habit: h,
                            weeks: 8,
                            accent: h.color,
                            startOfDayHour: startOfDayHour,
                          ),
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

// empty state
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

// weekly heatmap
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
    final completedSet = habit.completedDayKeysForMetrics().toSet();
    final tiles = days.map((k) => completedSet.contains(k)).toList();

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
                    color: done ? accent.withValues(alpha: 0.9) : Theme.of(context).colorScheme.surfaceContainerHighest,
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

// color dot
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).dividerColor;
         
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
      ),
    );
  }
}

// palette
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
