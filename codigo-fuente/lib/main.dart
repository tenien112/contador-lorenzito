import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('Firebase initialization skipped: $error');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CONTADOR-LORENZITO-1',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 200, // Bigger text
            fontWeight: FontWeight.bold,
            color: Color(0xFF3E2723), // Dark Brown
          ),
          displayMedium: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          headlineMedium: TextStyle(fontSize: 24, color: Colors.black54),
        ),
      ),
      home: const GymTrackerScreen(),
    );
  }
}

class GymTrackerScreen extends StatefulWidget {
  const GymTrackerScreen({super.key});

  @override
  State<GymTrackerScreen> createState() => _GymTrackerScreenState();
}

class _GymTrackerScreenState extends State<GymTrackerScreen>
    with WidgetsBindingObserver {
  int _currentSet = 0;
  DateTime? _startTime;
  DateTime? _setStartTime;
  Duration _totalDuration = Duration.zero;
  Duration _setDuration = Duration.zero;
  Timer? _timer;
  bool _isActive = false;
  bool _isPaused = false;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _startClock();
    _tryRecoverCurrentSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _startClock() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
        if (_isActive && !_isPaused) {
          if (_startTime != null) {
            _totalDuration = DateTime.now().difference(_startTime!);
          }
          if (_setStartTime != null) {
            _setDuration = DateTime.now().difference(_setStartTime!);
          }
        }
      });
    });
  }

  Future<void> _saveCurrentState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('currentSet', _currentSet);
    await prefs.setString('startTime', _startTime?.toIso8601String() ?? '');
    await prefs.setString(
      'setStartTime',
      _setStartTime?.toIso8601String() ?? '',
    );
    await prefs.setBool('isActive', _isActive);
    await prefs.setBool('isPaused', _isPaused);
    await prefs.setInt('savedTotalSeconds', _totalDuration.inSeconds);
  }

  Future<void> _tryRecoverCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('currentSet')) return;

    if (prefs.getBool('isActive') == true) {
      setState(() {
        _currentSet = prefs.getInt('currentSet') ?? 0;
        final startStr = prefs.getString('startTime');
        _startTime = startStr != null && startStr.isNotEmpty
            ? DateTime.tryParse(startStr)
            : null;

        final setStartStr = prefs.getString('setStartTime');
        _setStartTime = setStartStr != null && setStartStr.isNotEmpty
            ? DateTime.tryParse(setStartStr)
            : null;

        _isActive = true;
        _isPaused = prefs.getBool('isPaused') ?? true;

        if (_isPaused) {
          _totalDuration = Duration(
            seconds: prefs.getInt('savedTotalSeconds') ?? 0,
          );
        }
      });
    }
  }

  Future<void> _saveToHistory() async {
    if (_currentSet == 0 && !_isActive) return;

    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('history') ?? [];

    final session = {
      'date': DateTime.now().toIso8601String(),
      'sets': _currentSet,
      'duration': _totalDuration.inSeconds,
    };

    historyJson.add(jsonEncode(session));
    await prefs.setStringList('history', historyJson);

    try {
      await FirebaseFirestore.instance.collection('sessions').add(session);
    } catch (_) {
      // Firestore is optional; local storage still works.
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sesión guardada en el historial')),
    );
  }

  void _showHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('history') ?? [];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Historial Lorenzito'),
        content: SizedBox(
          width: double.maxFinite,
          child: historyJson.isEmpty
              ? const Text('No hay sesiones guardadas.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: historyJson.length,
                  itemBuilder: (context, index) {
                    final itemStr = historyJson[historyJson.length - 1 - index];
                    final item = jsonDecode(itemStr);
                    final date = DateTime.parse(item['date']);
                    return ListTile(
                      leading: const Icon(Icons.fitness_center),
                      title: Text(
                        DateFormat('d MMM yyyy - HH:mm').format(date),
                      ),
                      subtitle: Text(
                        '${item['sets']} Series - ${_formatDuration(Duration(seconds: item['duration']))}',
                      ),
                      onTap: () {
                        _loadSessionFromHistory(item);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CERRAR'),
          ),
        ],
      ),
    );
  }

  void _loadSessionFromHistory(Map<String, dynamic> item) {
    setState(() {
      _currentSet = item['sets'];
      _totalDuration = Duration(seconds: item['duration']);
      _setDuration = Duration.zero;
      _isActive = true;
      _isPaused = true;
      _startTime = DateTime.now().subtract(_totalDuration);
    });
    _saveCurrentState();
  }

  void _addSet() {
    setState(() {
      if (!_isActive) {
        _isActive = true;
        _isPaused = false;
        _currentSet = 1;
        _startTime = DateTime.now();
        _setStartTime = DateTime.now();
        _totalDuration = Duration.zero;
        _setDuration = Duration.zero;
      } else {
        _currentSet++;
        _setStartTime = DateTime.now();
        _setDuration = Duration.zero;
      }
    });
    _saveCurrentState();
  }

  void _togglePause() {
    if (!_isActive) return;
    setState(() {
      _isPaused = !_isPaused;
      if (!_isPaused && _startTime != null) {
        _startTime = DateTime.now().subtract(_totalDuration);
        if (_setStartTime != null) {
          _setStartTime = DateTime.now().subtract(_setDuration);
        }
      }
    });
    _saveCurrentState();
  }

  void _resetApp() {
    setState(() {
      _isActive = false;
      _isPaused = false;
      _currentSet = 0;
      _totalDuration = Duration.zero;
      _setDuration = Duration.zero;
      _startTime = null;
      _setStartTime = null;
    });
    _saveCurrentState();
  }

  Future<void> _sendToCalendar() async {
    if (_startTime == null && _totalDuration.inSeconds == 0) return;

    final start = _startTime ?? DateTime.now().subtract(_totalDuration);
    final end = DateTime.now();

    final title = 'Lorenzito Gym: $_currentSet Series';
    final description =
        'Entrenamiento completado.\n'
        'Series: $_currentSet\n'
        'Tiempo: ${_formatDuration(_totalDuration)}';

    final url = Uri.parse(
      'https://calendar.google.com/calendar/render?action=TEMPLATE'
      '&text=${Uri.encodeComponent(title)}'
      '&dates=${DateFormat("yyyyMMdd'T'HHmmss").format(start)}/${DateFormat("yyyyMMdd'T'HHmmss").format(end)}'
      '&details=${Uri.encodeComponent(description)}'
      '&add=tenien112@gmail.com',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CONTADOR-LORENZITO-1'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showHistory,
            tooltip: 'Historial',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveToHistory,
            tooltip: 'Guardar Sesión',
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('EEE, d MMM').format(_now),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(
                              DateFormat('HH:mm:ss').format(_now),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                      if (_startTime != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10.0),
                          child: Text(
                            'INICIO: ${DateFormat('HH:mm - d MMM').format(_startTime!)}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),

                      const Text(
                        'SERIES',
                        style: TextStyle(fontSize: 24, color: Colors.grey),
                      ),
                      Text(
                        '$_currentSet',
                        style: Theme.of(context).textTheme.displayLarge,
                      ),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _TimerBox(
                            label: 'SERIE ACTUAL',
                            time: _formatDuration(_setDuration),
                            color: Colors.black87,
                          ),
                          _TimerBox(
                            label: 'TOTAL',
                            time: _formatDuration(_totalDuration),
                            color: Colors.black87,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _ActionButton(
                                    icon: _isPaused || !_isActive
                                        ? Icons.play_arrow
                                        : Icons.pause,
                                    color: Colors.blue,
                                    onPressed: _togglePause,
                                    label: _isActive
                                        ? (_isPaused ? 'REANUDAR' : 'PAUSA')
                                        : 'PAUSA',
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: _ActionButton(
                                    icon: Icons.add,
                                    color: Colors.blue,
                                    onPressed: _addSet,
                                    label: _isActive ? '+ SERIE' : 'INICIAR (+)',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: _ActionButton(
                                    icon: Icons.refresh,
                                    color: Colors.blue,
                                    onPressed: _resetApp,
                                    label: 'SALIR',
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: _ActionButton(
                                    icon: Icons.calendar_today,
                                    color: Colors.blue,
                                    onPressed: _sendToCalendar,
                                    label: 'CALENDARIO',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: _ActionButton(
                                    icon: Icons.save,
                                    color: Colors.blue,
                                    onPressed: _saveToHistory,
                                    label: 'GUARDAR',
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: _ActionButton(
                                    icon: Icons.history,
                                    color: Colors.blue,
                                    onPressed: _showHistory,
                                    label: 'HISTORIAL',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TimerBox extends StatelessWidget {
  final String label;
  final String time;
  final Color color;

  const _TimerBox({
    required this.label,
    required this.time,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 16)),
        Text(
          time,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final String label;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 28),
      label: Text(label, style: const TextStyle(fontSize: 16)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
