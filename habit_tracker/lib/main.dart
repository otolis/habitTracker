import 'dart:convert';
import 'dart:io';


import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';


void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await HabitRepository.create();
  runApp(HabitApp(repository: repo));
}
//root widget for home screen
class HabitApp extends StatelessWidget{
  const HabitApp({super.key,required this.repository});
  final HabitRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Habit Tracker",
      theme: ThemeData(
        colorSchemeSeed:const Color(0xFF6C63FF),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
    home: HomeScreen(repository:repository),
    );
  }
}
// habit entity
class Habit {
  Habit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    DateTime? createdAt,
    Set<String>? completedDays, 
}) : createdAt = createdAt ?? DateTime.now(), 
completedDays = completedDays ?? <String>{}; 
  final String id;
  String name;
  String emoji;
  int colorValue;
  final DateTime createdAt;
  final Set<String> completedDays;
  Color get color => Color(colorValue);
  
//json map
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

// habit loading and saving
class HabitRepository {
  HabitRepository._(this._file);
  final File _file;

  static const _filename = "habits.json";
  

  static Future<HabitRepository> create() async {
 final dir = await getApplicationDocumentsDirectory(); 
 final file = File('${dir.path}/$_filename'); 
 if (!await file.exists()) { 
 await file.writeAsString(jsonEncode({'habits': []})); 
 }
 return HabitRepository._(file);
 }
 // read habits from localstorage
 Future<List<Habit>> localHabits() async{
  try {
    final text=await _file.readAsString();
    final map = jsonDecode(text) as Map<String,dynamic>;
    final list = (map["habits"] as List?) ?? const [];
    return list
       .map((e) => Habit.fromJson(e as Map<String, dynamic>)) 
       .toList(); 
  } catch(_){
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


// best streak
int computeBestStreak(Habit habit) {
if (habit.completedDays.isEmpty) return 0; 
final dates = habit.completedDays
.map((k) => DateTime.parse('$kT12:00:00')) 
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
return List.generate(
n,
(i) => dayKey(now.subtract(Duration(days: i)), startOfDayHour: startOfDayHour), 
).reversed.toList(); 
}

//home screen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key,required this.repository});
  final HabitRepository repository;
  
  @override
  State<HomeScreen> createState() => _HomeScreenState();
  
}

class _HomeScreenState extends State<HomeScreen> {
  final int startOfDayHour = 12;
  List<Habit> habits = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }


  Future<void> _load() async {
  final data = await widget.repository.loadHabits(); // Read from disk
  setState(() {
    habits = data; // Set state
    loading = false; // Done loading
  });
  }
}  