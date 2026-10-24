// Verificación de posición de banner - v1.0.0+40
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:http/http.dart' as http;
import 'services/firebase_service.dart';
import 'ad_helper.dart';
import 'firebase_options.dart';

// Color de la aplicación (el azul original siempre es el primero y el de por defecto)
const List<MaterialColor> coloresApp = [
  Colors.blue,
  Colors.indigo,
  Colors.deepPurple,
  Colors.purple,
  Colors.pink,
  Colors.red,
  Colors.deepOrange,
  Colors.orange,
  Colors.brown,
  Colors.green,
  Colors.teal,
  Colors.cyan,
  Colors.blueGrey,
];
final ValueNotifier<MaterialColor> colorApp = ValueNotifier(Colors.blue);
final ValueNotifier<bool> modoOscuro = ValueNotifier(false);

Future<void> cargarModoOscuro() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    modoOscuro.value = prefs.getBool('modo_oscuro') ?? false;
  } catch (_) {}
}

Future<void> cambiarModoOscuro() async {
  modoOscuro.value = !modoOscuro.value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('modo_oscuro', modoOscuro.value);
}

Future<void> cargarColorApp() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final i = prefs.getInt('color_app') ?? 0;
    colorApp.value =
        (i >= 0 && i < coloresApp.length) ? coloresApp[i] : Colors.blue;
  } catch (_) {}
}

Future<void> guardarColorApp(int i) async {
  colorApp.value = coloresApp[i];
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('color_app', i);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  print("DEBUG: Flutter initialized");
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("DEBUG: Firebase initialized");
  } catch (e) {
    print("DEBUG: Firebase Init Error: $e");
  }

  unawaited(MobileAds.instance.initialize());
  print("DEBUG: MobileAds initialized (unawaited)");

  try {
    await initializeDateFormatting('es_ES', null);
    print("DEBUG: Date formatting initialized");
  } catch (e) {
    print("DEBUG: Date Init Error: $e");
  }

  await cargarColorApp();
  await cargarModoOscuro();
  print("DEBUG: Running App");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: modoOscuro,
      builder: (context, oscuro, _) => ValueListenableBuilder<MaterialColor>(
      valueListenable: colorApp,
      builder: (context, color, _) => MaterialApp(
      title: 'CONTADOR-SERIES-LORENZITO-GIMNASIO',
      debugShowCheckedModeBanner: false,
      themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: color,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: color,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121417),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'CONTADOR-SERIES-LORENZITO-GIMNASIO'),
      ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  int _seriesCounter = 0;
  int _elapsedMs = 0;
  int _seriesMs = 0;
  int _lastSeriesMs = 0;
  bool _isRunning = false;
  bool _isSeriesInProgress = false;
  bool _isPaused = false;
  DateTime _currentTime = DateTime.now();
  DateTime? _startTime;
  List<Map<String, dynamic>> _savedSessions = [];
  List<int> _currentSessionSeriesTimes = [];
  List<int> _currentSessionSeriesMinBpm = [];
  List<int> _currentSessionSeriesMaxBpm = [];
  List<int> _currentSessionSeriesReps = [];
  int _upcomingReps = 0;
  String _selectedExerciseType = 'General';
  String _currentSeriesExerciseType = 'General';
  static const List<String> _defaultExerciseTypes = [
    'General',
    'Press de banca',
    'Sentadilla',
    'Peso muerto',
    'Remo',
    'Press militar',
    'Curl femoral',
    'Otro',
  ];
  List<String> _exerciseTypes = List<String>.from(_defaultExerciseTypes);
  List<String> _currentSessionSeriesExerciseTypes = [];
  int _cachedAverageMs = 0;
  Timer? _timer;
  DateTime _lastTick = DateTime.now();
  StateSetter? _dialogSetState;
  BannerAd? _bannerAd;
  final FirebaseService _firebaseService = FirebaseService();
  User? _user;
  bool _isSyncing = false;
  bool _isVip = false;
  StreamSubscription<bool>? _vipSubscription;

  // Heart Rate Monitor (HRM) states
  int _bpm = 0;
  int _maxBpm = 0;
  int _minBpm = 0;
  int _sumBpm = 0;
  int _countBpm = 0;
  int _avgBpm = 0;
  int _seriesMaxBpm = 0;
  int _seriesMinBpm = 0;
  bool _isHrmConnecting = false;
  String? _connectedDeviceId;
  bool get _isHrmConnected => _connectedDeviceId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    colorApp.addListener(_alCambiarColor);
    WakelockPlus.enable(); // <-- Prevenir que la pantalla se apague
    _loadSessions();
    _loadExerciseTypes();
    _lastTick = DateTime.now();
    _startTimer();
    _loadBannerAd();
    _initFirebase();
  }

  Future<void> _initFirebase() async {
    final user = await _firebaseService.signInAnonymously();
    if (user != null) {
      setState(() {
        _user = user.user;
      });
      _syncData();
      _listenToVipStatus();
    }
  }

  void _listenToVipStatus() {
    _vipSubscription?.cancel();
    _vipSubscription = _firebaseService.isUserVip().listen((status) {
      if (mounted) {
        setState(() {
          _isVip = status;
          if (_isVip) {
            _bannerAd?.dispose();
            _bannerAd = null;
          } else if (_bannerAd == null) {
            _loadBannerAd();
          }
        });
      }
    });
  }

  Future<void> _syncData() async {
    if (_user == null || _isSyncing) return;
    setState(() {
      _isSyncing = true;
    });
    // First download from cloud to get other devices' data
    await _firebaseService.syncCloudToLocal();
    // Then upload local data (which now includes any newly merged data)
    await _firebaseService.syncLocalToCloud();
    await _loadSessions(); // Reload sessions to reflect changes
    setState(() {
      _isSyncing = false;
    });
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdHelper.bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _bannerAd = ad as BannerAd;
          });
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('Failed to load a banner ad: ${err.message}');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    colorApp.removeListener(_alCambiarColor);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _bannerAd?.dispose();
    _vipSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Al volver, forzamos una actualización inmediata del tiempo para que no haya salto visual
      setState(() {
        _currentTime = DateTime.now();
      });
    }
  }

  void _alCambiarColor() {
    if (mounted) setState(() {});
  }

  void _mostrarSelectorColor() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Color de la aplicación',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                alignment: WrapAlignment.center,
                children: List.generate(coloresApp.length, (i) {
                  final c = coloresApp[i];
                  final elegido = c == colorApp.value;
                  return GestureDetector(
                    onTap: () {
                      guardarColorApp(i);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: elegido ? Theme.of(ctx).colorScheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: elegido
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  guardarColorApp(0);
                  Navigator.pop(ctx);
                },
                child: const Text('Volver al azul original'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? sessionsJson = prefs.getString('saved_sessions');
    if (sessionsJson != null) {
      setState(() {
        final decoded = json.decode(sessionsJson) as List;
        _savedSessions = decoded.map((item) {
          final map = Map<String, dynamic>.from(item);
          // Migración: Si la duración parece estar en segundos (ej: < 100000), convertir a ms
          if (map['duration'] != null && map['duration'] < 100000) {
            map['duration'] = map['duration'] * 1000;
          }
          return map;
        }).toList();
      });
    }
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_sessions', json.encode(_savedSessions));
  }

  Future<void> _loadExerciseTypes() async {
    final prefs = await SharedPreferences.getInstance();
    final storedExerciseTypes = prefs.getStringList('exercise_types');
    if (storedExerciseTypes != null && storedExerciseTypes.isNotEmpty) {
      setState(() {
        _exerciseTypes = storedExerciseTypes;
        if (!_exerciseTypes.contains(_selectedExerciseType)) {
          _selectedExerciseType = _exerciseTypes.first;
        }
        if (!_exerciseTypes.contains(_currentSeriesExerciseType)) {
          _currentSeriesExerciseType = _exerciseTypes.first;
        }
      });
    }
  }

  Future<void> _saveExerciseTypes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('exercise_types', _exerciseTypes);
  }

  Future<void> _showAddExerciseDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir ejercicio'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre del ejercicio',
            hintText: 'Por ejemplo: Press francés',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                Navigator.pop(context);
                return;
              }

              final alreadyExists = _exerciseTypes.any(
                (item) => item.toLowerCase() == name.toLowerCase(),
              );
              if (alreadyExists) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ese ejercicio ya existe')),
                );
                return;
              }

              setState(() {
                _exerciseTypes.add(name);
                _selectedExerciseType = name;
                _currentSeriesExerciseType = name;
              });
              await _saveExerciseTypes();
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeExerciseType(String exerciseType) async {
    if (exerciseType == 'General') return;

    setState(() {
      _exerciseTypes.remove(exerciseType);
      if (_selectedExerciseType == exerciseType) {
        _selectedExerciseType =
            _exerciseTypes.isNotEmpty ? _exerciseTypes.first : 'General';
      }
      if (_currentSeriesExerciseType == exerciseType) {
        _currentSeriesExerciseType =
            _exerciseTypes.isNotEmpty ? _exerciseTypes.first : 'General';
      }
    });
    await _saveExerciseTypes();
  }

  Future<void> _confirmRemoveExerciseType(
    String exerciseType, [
    void Function(void Function())? dialogSetState,
  ]) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar ejercicio'),
        content: Text('¿Deseas borrar "$exerciseType" de la lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeExerciseType(exerciseType);
      dialogSetState?.call(() {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ejercicio eliminado: $exerciseType')),
      );
    }
  }

  void _showExerciseTypeSelector() {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Selecciona el tipo de ejercicio'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _exerciseTypes.length,
                    itemBuilder: (context, index) {
                      final option = _exerciseTypes[index];
                      final canRemove = option != 'General';
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 2.0),
                        padding: const EdgeInsets.only(right: 4.0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                        ),
                        child: Row(
                          children: [
                            Radio<String>(
                              value: option,
                              groupValue: _selectedExerciseType,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedExerciseType = value;
                                  });
                                  Navigator.pop(dialogContext);
                                }
                              },
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedExerciseType = option;
                                  });
                                  Navigator.pop(dialogContext);
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text(option),
                                ),
                              ),
                            ),
                            if (canRemove)
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Eliminar ejercicio',
                                iconSize: 20,
                                padding: const EdgeInsets.all(8.0),
                                constraints: const BoxConstraints(),
                                onPressed: () async {
                                  await _confirmRemoveExerciseType(
                                    option,
                                    setDialogState,
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _showAddExerciseDialog();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir ejercicio'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSession(int index) async {
    setState(() {
      _savedSessions.removeAt(index);
    });
    await _saveSessions();
    _syncData();
  }

  Map<String, dynamic>? _parseCalendarEvent(Event event) {
    if (event.title == null || !event.title!.startsWith('GIMNASIO -')) {
      return null;
    }

    final start = event.start;
    final end = event.end;
    if (start == null) return null;

    final String sessionStartTime = start.toIso8601String();
    final String date = DateFormat('dd/MM/yyyy HH:mm').format(start);

    // Default duration is start-to-end difference. If end is null, we try to parse it.
    int duration = end != null ? end.difference(start).inMilliseconds : 0;

    String exerciseType = 'General';
    int series = 0;

    // Fallback: parse exerciseType and series from title.
    final titleParts = event.title!.split(' - ');
    if (titleParts.length >= 2) {
      exerciseType = titleParts[1].trim();
    }
    if (titleParts.length >= 3) {
      final seriesPart = titleParts[2]; // "3 SERIES (30 REPS)"
      final seriesMatch = RegExp(r'(\d+)\s+SERIES').firstMatch(seriesPart);
      if (seriesMatch != null) {
        series = int.tryParse(seriesMatch.group(1)!) ?? 0;
      }
    }

    // Now parse description (details)
    final details = event.description ?? '';
    final lines = details.split('\n');

    List<String> seriesExerciseTypes = [];
    List<int> seriesTimes = [];
    List<int> seriesMinBpm = [];
    List<int> seriesMaxBpm = [];
    List<int> seriesReps = [];
    int sessionMinBpm = 0;
    int sessionMaxBpm = 0;
    int sessionAvgBpm = 0;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.contains('Tipo de ejercicio:')) {
        final val = line.split(':').last.trim();
        if (val.isNotEmpty) exerciseType = val;
      } else if (line.contains('Series completadas:')) {
        final val = int.tryParse(line.split(':').last.trim()) ?? 0;
        if (val > 0) series = val;
      } else if (line.contains('Tiempo total:')) {
        final timeStr = line.replaceFirst('⏱️ Tiempo total:', '').trim();
        final parsedDur = _parseDurationString(timeStr);
        if (parsedDur > 0) duration = parsedDur;
      } else if (line.contains('Pulsaciones sesión:')) {
        final minMatch = RegExp(r'Min\s+(\d+)').firstMatch(line);
        final maxMatch = RegExp(r'Max\s+(\d+)').firstMatch(line);
        final medMatch = RegExp(r'Med\s+(\d+)').firstMatch(line);
        if (minMatch != null) sessionMinBpm = int.tryParse(minMatch.group(1)!) ?? 0;
        if (maxMatch != null) sessionMaxBpm = int.tryParse(maxMatch.group(1)!) ?? 0;
        if (medMatch != null) sessionAvgBpm = int.tryParse(medMatch.group(1)!) ?? 0;
      } else if (line.startsWith('Serie ') && line.contains('[')) {
        try {
          int startBracket = line.indexOf('[');
          int endBracket = line.indexOf(']');
          if (startBracket != -1 && endBracket != -1) {
            String sType = line.substring(startBracket + 1, endBracket).trim();
            seriesExerciseTypes.add(sType);

            int colonIndex = line.indexOf(':', endBracket);
            int repsParenthesisIndex = line.indexOf('(', colonIndex);
            if (colonIndex != -1 && repsParenthesisIndex != -1) {
              String durationStr = line.substring(colonIndex + 1, repsParenthesisIndex).trim();
              int sDur = _parseDurationString(durationStr);
              seriesTimes.add(sDur);

              int repsEndIndex = line.indexOf(')', repsParenthesisIndex);
              if (repsEndIndex != -1) {
                String repsStr = line.substring(repsParenthesisIndex + 1, repsEndIndex).replaceAll('reps', '').trim();
                int reps = int.tryParse(repsStr) ?? 10;
                seriesReps.add(reps);

                int bpmStartIndex = line.indexOf('(BPM:', repsEndIndex);
                int minB = 0;
                int maxB = 0;
                if (bpmStartIndex != -1) {
                  int bpmEndIndex = line.indexOf(')', bpmStartIndex);
                  if (bpmEndIndex != -1) {
                    String bpmStr = line.substring(bpmStartIndex + 5, bpmEndIndex).trim(); // "70 - 110"
                    final bpmParts = bpmStr.split('-');
                    minB = int.tryParse(bpmParts[0].trim()) ?? 0;
                    maxB = bpmParts.length > 1 ? (int.tryParse(bpmParts[1].trim()) ?? 0) : 0;
                  }
                }
                seriesMinBpm.add(minB);
                seriesMaxBpm.add(maxB);
              }
            }
          }
        } catch (e) {
          debugPrint("Error parsing series line: $line - $e");
        }
      }
    }

    return {
      'series': series,
      'duration': duration,
      'startTime': sessionStartTime,
      'exerciseType': exerciseType,
      'seriesExerciseTypes': seriesExerciseTypes,
      'date': date,
      'seriesTimes': seriesTimes,
      'seriesMinBpm': seriesMinBpm,
      'seriesMaxBpm': seriesMaxBpm,
      'seriesReps': seriesReps,
      'sessionMinBpm': sessionMinBpm,
      'sessionMaxBpm': sessionMaxBpm,
      'sessionAvgBpm': sessionAvgBpm,
    };
  }

  int _parseDurationString(String formatted) {
    final parts = formatted.split(':');
    if (parts.length < 3) return 0;
    int hours = int.tryParse(parts[0]) ?? 0;
    int minutes = int.tryParse(parts[1]) ?? 0;
    int seconds = int.tryParse(parts[2]) ?? 0;
    int hundredths = parts.length > 3 ? (int.tryParse(parts[3]) ?? 0) : 0;
    return (hours * 3600 + minutes * 60 + seconds) * 1000 + hundredths * 10;
  }

  Future<void> _importSessionsFromCalendar() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Recuperando entrenamientos del calendario...')),
          ],
        ),
      ),
    );

    try {
      final deviceCalendarPlugin = DeviceCalendarPlugin();
      var permissionsGranted = await deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && !permissionsGranted.data!) {
        permissionsGranted = await deviceCalendarPlugin.requestPermissions();
      }

      if (!permissionsGranted.isSuccess || !permissionsGranted.data!) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permiso denegado. No se puede acceder al calendario.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final calendarsResult = await deviceCalendarPlugin.retrieveCalendars();
      if (!mounted) return;
      if (!calendarsResult.isSuccess || calendarsResult.data == null) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudieron obtener los calendarios.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final List<Map<String, dynamic>> importedSessions = [];
      final calendars = calendarsResult.data!;
      final startDate = DateTime.now().subtract(const Duration(days: 365 * 3));
      final endDate = DateTime.now().add(const Duration(days: 7));

      for (var calendar in calendars) {
        if (calendar.id == null) continue;
        final eventsResult = await deviceCalendarPlugin.retrieveEvents(
          calendar.id,
          RetrieveEventsParams(
            startDate: startDate,
            endDate: endDate,
          ),
        );

        if (!mounted) return;
        if (eventsResult.isSuccess && eventsResult.data != null) {
          for (var event in eventsResult.data!) {
            final session = _parseCalendarEvent(event);
            if (session != null) {
              importedSessions.add(session);
            }
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (importedSessions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontraron entrenamientos de la app en el calendario.'),
            duration: Duration(seconds: 3),
          ),
        );
        _showHistory(); // Re-open history
        return;
      }

      int addedCount = 0;
      setState(() {
        for (var imported in importedSessions) {
          final exists = _savedSessions.any(
            (local) => local['startTime'] == imported['startTime'],
          );
          if (!exists) {
            _savedSessions.add(imported);
            addedCount++;
          }
        }

        if (addedCount > 0) {
          _savedSessions.sort((a, b) =>
              (b['startTime'] as String).compareTo(a['startTime'] as String));
        }
      });

      if (addedCount > 0) {
        await _saveSessions();
        if (!mounted) return;
        _syncData(); // Sync to cloud if available
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Éxito! Se han recuperado $addedCount nuevas sesiones del calendario.'),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todas las sesiones del calendario ya estaban en tu historial.'),
            duration: Duration(seconds: 3),
          ),
        );
      }

      if (!mounted) return;
      _showHistory(); // Re-open history to show changes
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if still open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ocurrió un error al importar: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
        _showHistory();
      }
    }
  }

  // ---- GOOGLE CALENDAR API IMPORT (Web) ----

  Map<String, dynamic>? _parseGoogleCalendarApiEvent(
      Map<String, dynamic> event) {
    final title = event['summary'] as String? ?? '';
    if (!title.startsWith('GIMNASIO -')) return null;

    // Dates from Google Calendar API come as ISO 8601
    final startStr =
        (event['start'] as Map?)?['dateTime'] as String? ??
        (event['start'] as Map?)?['date'] as String? ??
        '';
    final endStr =
        (event['end'] as Map?)?['dateTime'] as String? ??
        (event['end'] as Map?)?['date'] as String? ??
        '';
    if (startStr.isEmpty) return null;

    final DateTime start;
    try {
      start = DateTime.parse(startStr);
    } catch (_) {
      return null;
    }

    final end = endStr.isNotEmpty ? DateTime.tryParse(endStr) : null;
    int duration = end != null ? end.difference(start).inMilliseconds : 0;

    String exerciseType = 'General';
    int series = 0;

    // Parse title: "GIMNASIO - Press de banca - 3 SERIES (30 REPS)"
    final titleParts = title.split(' - ');
    if (titleParts.length >= 2) exerciseType = titleParts[1].trim();
    if (titleParts.length >= 3) {
      final seriesMatch = RegExp(r'(\d+)\s+SERIES').firstMatch(titleParts[2]);
      if (seriesMatch != null) {
        series = int.tryParse(seriesMatch.group(1)!) ?? 0;
      }
    }

    // Parse description (same format as the one the app generates)
    final description = event['description'] as String? ?? '';
    final lines = description.split('\n');

    List<String> seriesExerciseTypes = [];
    List<int> seriesTimes = [];
    List<int> seriesMinBpm = [];
    List<int> seriesMaxBpm = [];
    List<int> seriesReps = [];
    int sessionMinBpm = 0;
    int sessionMaxBpm = 0;
    int sessionAvgBpm = 0;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.contains('Tipo de ejercicio:')) {
        final val = line.split(':').last.trim();
        if (val.isNotEmpty) exerciseType = val;
      } else if (line.contains('Series completadas:')) {
        final val = int.tryParse(line.split(':').last.trim()) ?? 0;
        if (val > 0) series = val;
      } else if (line.contains('Tiempo total:')) {
        final timeStr =
            line.replaceFirst('⏱️ Tiempo total:', '').trim();
        final parsedDur = _parseDurationString(timeStr);
        if (parsedDur > 0) duration = parsedDur;
      } else if (line.contains('Pulsaciones sesión:')) {
        final minMatch = RegExp(r'Min\s+(\d+)').firstMatch(line);
        final maxMatch = RegExp(r'Max\s+(\d+)').firstMatch(line);
        final medMatch = RegExp(r'Med\s+(\d+)').firstMatch(line);
        if (minMatch != null)
          sessionMinBpm = int.tryParse(minMatch.group(1)!) ?? 0;
        if (maxMatch != null)
          sessionMaxBpm = int.tryParse(maxMatch.group(1)!) ?? 0;
        if (medMatch != null)
          sessionAvgBpm = int.tryParse(medMatch.group(1)!) ?? 0;
      } else if (line.startsWith('Serie ') && line.contains('[')) {
        try {
          final sb = line.indexOf('[');
          final eb = line.indexOf(']');
          if (sb != -1 && eb != -1) {
            seriesExerciseTypes.add(line.substring(sb + 1, eb).trim());
            final colonIdx = line.indexOf(':', eb);
            final parenIdx = line.indexOf('(', colonIdx);
            if (colonIdx != -1 && parenIdx != -1) {
              final durStr = line.substring(colonIdx + 1, parenIdx).trim();
              seriesTimes.add(_parseDurationString(durStr));
              final repsEnd = line.indexOf(')', parenIdx);
              if (repsEnd != -1) {
                final repsStr = line
                    .substring(parenIdx + 1, repsEnd)
                    .replaceAll('reps', '')
                    .trim();
                seriesReps.add(int.tryParse(repsStr) ?? 10);
                final bpmStart = line.indexOf('(BPM:', repsEnd);
                int minB = 0, maxB = 0;
                if (bpmStart != -1) {
                  final bpmEnd = line.indexOf(')', bpmStart);
                  if (bpmEnd != -1) {
                    final bpmStr =
                        line.substring(bpmStart + 5, bpmEnd).trim();
                    final bpmParts = bpmStr.split('-');
                    minB = int.tryParse(bpmParts[0].trim()) ?? 0;
                    maxB = bpmParts.length > 1
                        ? (int.tryParse(bpmParts[1].trim()) ?? 0)
                        : 0;
                  }
                }
                seriesMinBpm.add(minB);
                seriesMaxBpm.add(maxB);
              }
            }
          }
        } catch (e) {
          debugPrint('Error parsing series line: $line - $e');
        }
      }
    }

    return {
      'series': series,
      'duration': duration,
      'startTime': start.toIso8601String(),
      'exerciseType': exerciseType,
      'seriesExerciseTypes': seriesExerciseTypes,
      'date': DateFormat('dd/MM/yyyy HH:mm').format(start),
      'seriesTimes': seriesTimes,
      'seriesMinBpm': seriesMinBpm,
      'seriesMaxBpm': seriesMaxBpm,
      'seriesReps': seriesReps,
      'sessionMinBpm': sessionMinBpm,
      'sessionMaxBpm': sessionMaxBpm,
      'sessionAvgBpm': sessionAvgBpm,
    };
  }

  Future<void> _importFromGoogleCalendarApi() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(
                child: Text(
                    'Conectando con Google Calendar...\nSe abrirá una ventana para iniciar sesión.')),
          ],
        ),
      ),
    );

    try {
      // Use Google Sign-In via Firebase Auth popup.
      // We only request calendar read scope; we do NOT change the app's
      // anonymous Firebase auth session — we sign out the Google user
      // immediately after retrieving the access token.
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider
          .addScope('https://www.googleapis.com/auth/calendar.readonly');

      // Sign in with popup to get the access token
      final UserCredential credential =
          await FirebaseAuth.instance.signInWithPopup(googleProvider);

      final accessToken =
          (credential.credential as OAuthCredential?)?.accessToken;

      // Immediately sign back out of Google and restore anonymous session
      // so the rest of the app is not affected.
      await FirebaseAuth.instance.signOut();
      await _firebaseService.signInAnonymously().then((uc) {
        if (uc != null && mounted) {
          setState(() => _user = uc.user);
        }
      });

      if (accessToken == null) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No se pudo obtener acceso a Google Calendar.')),
        );
        _showHistory();
        return;
      }

      // Query Google Calendar API for events with "GIMNASIO" in the title
      final startTime =
          DateTime.now().subtract(const Duration(days: 365 * 3));
      final uri = Uri.https(
        'www.googleapis.com',
        '/calendar/v3/calendars/primary/events',
        {
          'q': 'GIMNASIO',
          'maxResults': '500',
          'singleEvents': 'true',
          'orderBy': 'startTime',
          'timeMin': startTime.toUtc().toIso8601String(),
        },
      );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Error al acceder a Google Calendar (${response.statusCode}). Comprueba que Google Sign-In está habilitado en Firebase.')),
        );
        _showHistory();
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final events = (data['items'] as List<dynamic>?) ?? [];

      Navigator.pop(context); // close loading dialog

      if (events.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'No se encontraron entrenamientos guardados en tu Google Calendar.')),
        );
        _showHistory();
        return;
      }

      int addedCount = 0;
      setState(() {
        for (var eventData in events) {
          final session = _parseGoogleCalendarApiEvent(
              eventData as Map<String, dynamic>);
          if (session == null) continue;
          final exists = _savedSessions
              .any((s) => s['startTime'] == session['startTime']);
          if (!exists) {
            _savedSessions.add(session);
            addedCount++;
          }
        }
        if (addedCount > 0) {
          _savedSessions.sort((a, b) =>
              (b['startTime'] as String).compareTo(a['startTime'] as String));
        }
      });

      if (addedCount > 0) {
        await _saveSessions();
        if (!mounted) return;
        _syncData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '¡Éxito! Se han recuperado $addedCount sesiones de tu Google Calendar.'),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Todas las sesiones ya estaban en tu historial.')),
        );
      }

      if (!mounted) return;
      _showHistory();
    } catch (e) {
      if (mounted) {
        // try to pop loading dialog if still open
        try { Navigator.pop(context); } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al conectar con Google Calendar: $e'),
              duration: const Duration(seconds: 5)),
        );
        _showHistory();
      }
      debugPrint('Error importing from Google Calendar API: $e');
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (mounted) {
        final now = DateTime.now();
        final deltaMs = now.difference(_lastTick).inMilliseconds;
        _lastTick = now;

        setState(() {
          _currentTime = now;
          if (_isRunning && !_isPaused) {
            _elapsedMs += deltaMs;
          }
          if (_isSeriesInProgress && !_isPaused) {
            _seriesMs += deltaMs;
          }
          if (_dialogSetState != null) {
            _dialogSetState!(() {});
          }
        });
      }
    });
  }

  String get _averageSeriesTime {
    if (_currentSessionSeriesTimes.isEmpty) return '00:00:00:00';
    return _formatHHMMSSCC(_cachedAverageMs);
  }

  void _recalculateCachedAverage() {
    if (_currentSessionSeriesTimes.isEmpty) {
      _cachedAverageMs = 0;
      return;
    }
    int totalMs = _currentSessionSeriesTimes.fold(0, (sum, item) => sum + item);
    _cachedAverageMs = totalMs ~/ _currentSessionSeriesTimes.length;
  }

  void _incrementCounter() {
    setState(() {
      final String completedSeriesExerciseType = _seriesCounter > 0
          ? _currentSeriesExerciseType
          : _selectedExerciseType;

      if (_seriesCounter > 0) {
        _lastSeriesMs = _seriesMs;
        _currentSessionSeriesTimes.add(_seriesMs);
        _currentSessionSeriesMinBpm.add(_seriesMinBpm);
        _currentSessionSeriesMaxBpm.add(_seriesMaxBpm);
        _currentSessionSeriesReps.add(_upcomingReps);
        _currentSessionSeriesExerciseTypes.add(completedSeriesExerciseType);
        _recalculateCachedAverage();
      }
      _seriesCounter++;
      if (!_isRunning) {
        _isRunning = true;
        _startTime = DateTime.now();
      }
      _isPaused = false;
      _isSeriesInProgress = true;
      _seriesMs = 0;
      // Resetear min/max de la serie
      _seriesMinBpm = 0;
      _seriesMaxBpm = 0;
      _currentSeriesExerciseType = _selectedExerciseType;
    });
    _saveToHistory(silent: true);
  }

  void _togglePause() {
    setState(() {
      if (_isRunning || _isSeriesInProgress) {
        _isPaused = !_isPaused;
      }
    });
  }

  void _saveToHistory({bool silent = false}) {
    if (_seriesCounter == 0) return;

    final String sessionStartTime =
        _startTime?.toIso8601String() ?? DateTime.now().toIso8601String();

    final session = {
      'series': _seriesCounter,
      'duration': _elapsedMs,
      'startTime': sessionStartTime,
      'exerciseType': _selectedExerciseType,
      'seriesExerciseTypes':
          List<String>.from(_currentSessionSeriesExerciseTypes),
      'date': DateFormat(
        'dd/MM/yyyy HH:mm',
      ).format(_startTime ?? DateTime.now()),
      'seriesTimes': List<int>.from(_currentSessionSeriesTimes),
      'seriesMinBpm': List<int>.from(_currentSessionSeriesMinBpm),
      'seriesMaxBpm': List<int>.from(_currentSessionSeriesMaxBpm),
      'seriesReps': List<int>.from(_currentSessionSeriesReps),
      'sessionMinBpm': _minBpm,
      'sessionMaxBpm': _maxBpm,
      'sessionAvgBpm': _avgBpm,
    };

    setState(() {
      int existingIndex = _savedSessions.indexWhere(
        (element) => element['startTime'] == sessionStartTime,
      );

      if (existingIndex != -1) {
        _savedSessions[existingIndex] = session;
      } else {
        _savedSessions.insert(0, session);
      }
    });
    _saveSessions();
    _syncData();

    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesión actualizada en el historial'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Historial de Entrenamientos'),
        content: SizedBox(
          width: double.maxFinite,
          child: _savedSessions.isEmpty
              ? const Text('No hay sesiones guardadas')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _savedSessions.length,
                  itemBuilder: (context, index) {
                    final session = _savedSessions[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          '${session['series']} series - ${_formatDuration(session['duration'])}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(session['date']),
                            Text(
                              'Tipo: ${session['exerciseType'] ?? 'General'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.deepPurple,
                              ),
                            ),
                            if (session['seriesReps'] != null)
                              Text(
                                'Repeticiones: ${(session['seriesReps'] as List).join(', ')}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            if (session['sessionMinBpm'] != null &&
                                session['sessionMinBpm'] > 0)
                              Text(
                                  'Pulsaciones: Min ${session['sessionMinBpm']} - Max ${session['sessionMaxBpm']} - Med ${session['sessionAvgBpm'] ?? 0}'),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            _confirmDelete(context, index);
                          },
                        ),
                        onTap: () {
                          _restoreSession(session);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              if (kIsWeb) {
                _importFromGoogleCalendarApi();
              } else {
                _importSessionsFromCalendar();
              }
            },
            icon: const Icon(Icons.calendar_month),
            label: const Text('Recuperar del Calendario'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext parentContext, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: const Text(
          '¿Estás seguro de que quieres eliminar esta sesión del historial?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              _deleteSession(index);
              Navigator.pop(context);
              Navigator.pop(parentContext);
              _showHistory();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _restoreSession(Map<String, dynamic> session) {
    setState(() {
      _seriesCounter = session['series'];
      _elapsedMs = session['duration'];
      _seriesMs = 0;
      _isRunning = false;
      _isSeriesInProgress = false;
      _startTime = DateTime.parse(session['startTime']);
      _selectedExerciseType = session['exerciseType'] ?? 'General';
      _currentSessionSeriesExerciseTypes =
          session['seriesExerciseTypes'] != null
              ? List<String>.from(session['seriesExerciseTypes'])
              : [];
      _currentSeriesExerciseType = _currentSessionSeriesExerciseTypes.isNotEmpty
          ? _currentSessionSeriesExerciseTypes.last
          : _selectedExerciseType;
      _currentSessionSeriesTimes = session['seriesTimes'] != null
          ? List<int>.from(session['seriesTimes'])
          : []; // Migración para sesiones viejas que no tenían seriesTimes
      _currentSessionSeriesMinBpm = session['seriesMinBpm'] != null
          ? List<int>.from(session['seriesMinBpm'])
          : [];
      _currentSessionSeriesMaxBpm = session['seriesMaxBpm'] != null
          ? List<int>.from(session['seriesMaxBpm'])
          : [];
      _currentSessionSeriesReps = session['seriesReps'] != null
          ? List<int>.from(session['seriesReps'])
          : List.filled(_seriesCounter, 10); // Default to 10 for old sessions
      // Restore overall session metrics if available
      _minBpm = session['sessionMinBpm'] ?? 0;
      _maxBpm = session['sessionMaxBpm'] ?? 0;
      _avgBpm = session['sessionAvgBpm'] ?? 0;
      if (_avgBpm > 0) {
        _countBpm = 1;
        _sumBpm = _avgBpm;
      }
      _recalculateCachedAverage();
    });
  }

  void _showSeriesDetails() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          _dialogSetState = setDialogState;
          return AlertDialog(
            title: const Text('Tiempos por Serie'),
            content: SizedBox(
              width: double.maxFinite,
              child: (_currentSessionSeriesTimes.isEmpty &&
                      !_isSeriesInProgress)
                  ? const Text('No hay series completadas aún')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _currentSessionSeriesTimes.length +
                          (_isSeriesInProgress ? 1 : 0),
                      itemBuilder: (context, index) {
                        bool isCurrent =
                            index == _currentSessionSeriesTimes.length;
                        int timeMs = isCurrent
                            ? _seriesMs
                            : _currentSessionSeriesTimes[index];

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                isCurrent ? Colors.orange : colorApp.value,
                            foregroundColor: Colors.white,
                            child: Text('${index + 1}'),
                          ),
                          title: Text(
                            _formatHHMMSSCC(timeMs),
                            style: TextStyle(
                              fontFamily: 'Courier',
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color:
                                  isCurrent ? Colors.orange[900] : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isCurrent)
                                const Text('En curso...',
                                    style:
                                        TextStyle(fontStyle: FontStyle.italic))
                              else if (index < _currentSessionSeriesReps.length)
                                Text(
                                  'Repeticiones: ${_currentSessionSeriesReps[index]}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueAccent),
                                ),
                              if (!isCurrent &&
                                  index <
                                      _currentSessionSeriesExerciseTypes.length)
                                Text(
                                  'Tipo: ${_currentSessionSeriesExerciseTypes[index]}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.deepPurple),
                                ),
                              if (isCurrent)
                                Text(
                                  'Tipo: $_currentSeriesExerciseType',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.deepPurple),
                                ),
                              if (!isCurrent &&
                                  index < _currentSessionSeriesMinBpm.length)
                                Text(
                                    'Pulsaciones: Min ${_currentSessionSeriesMinBpm[index]} - Max ${_currentSessionSeriesMaxBpm[index]}'),
                              if (isCurrent && _seriesMaxBpm > 0)
                                Text(
                                    'Pulsaciones: Min $_seriesMinBpm - Max $_seriesMaxBpm'),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    ).then((_) => _dialogSetState = null);
  }

  Future<void> _connectToHrm() async {
    if (_isHrmConnected) {
      await UniversalBle.disconnect(_connectedDeviceId!);
      setState(() {
        _connectedDeviceId = null;
        _bpm = 0;
      });
      return;
    }

    setState(() {
      _isHrmConnecting = true;
    });

    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Buscando dispositivos... (selecciona el tuyo)')),
      );

      UniversalBle.onScanResult = (device) async {
        await UniversalBle.stopScan();
        try {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Conectando a ${(device.name == null || device.name!.isEmpty) ? "Dispositivo desconocido" : device.name}...')),
          );

          await UniversalBle.connect(device.deviceId);

          // Dar tiempo para que se descubran los servicios
          await Future.delayed(const Duration(seconds: 1));

          // Verificar si el servicio de ritmo cardíaco existe
          final services = await UniversalBle.discoverServices(device.deviceId);
          final hasHrService =
              services.any((s) => s.uuid.toLowerCase().contains("180d"));

          if (!hasHrService) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    '⚠️ El dispositivo no tiene servicio de pulso. ¿Es el correcto?'),
                backgroundColor: Colors.orange,
              ),
            );
            await UniversalBle.disconnect(device.deviceId);
            setState(() => _isHrmConnecting = false);
            return;
          }

          _setupHrmSubscriptions(device.deviceId);

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Conectado correctamente'),
              backgroundColor: Colors.green,
            ),
          );

          setState(() {
            _connectedDeviceId = device.deviceId;
            _isHrmConnecting = false;
          });
        } catch (e) {
          debugPrint("Error connecting to Hrm: $e");
          setState(() => _isHrmConnecting = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al conectar: $e')),
          );
        }
      };

      await UniversalBle.startScan(
        scanFilter: ScanFilter(
          withServices: [], // Empty list to accept all devices on Web
        ),
        platformConfig: PlatformConfig(
          web: WebOptions(
            optionalServices: [
              "180d",
              "180a"
            ], // Required services despite not filtering
          ),
        ),
      );
    } catch (e) {
      debugPrint("Error starting Hrm scan: $e");
      setState(() => _isHrmConnecting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al buscar pulsómetro: $e')),
      );
    }
  }

  void _setupHrmSubscriptions(String deviceId) {
    // Escuchar cambios de valor
    UniversalBle.onValueChange = (deviceId, charId, value, timestamp) {
      if (charId.toLowerCase().contains("2a37")) {
        _decodeHeartRate(value);
      }
    };

    // Suscribirse a notificaciones
    UniversalBle.subscribeNotifications(
      deviceId,
      "180d",
      "2a37",
    );

    // Monitorizar desconexión
    UniversalBle.onConnectionChange = (id, isConnected, error) {
      if (id == deviceId && !isConnected) {
        if (!mounted) return;
        setState(() {
          _connectedDeviceId = null;
          _bpm = 0;
        });
      }
    };
  }

  void _decodeHeartRate(Uint8List data) {
    if (data.isEmpty) return;
    int flags = data[0];
    int hr;
    if ((flags & 0x01) == 0) {
      hr = data[1];
    } else {
      hr = (data[2] << 8) | data[1];
    }
    setState(() {
      _bpm = hr;
      if (_isRunning || _isSeriesInProgress) {
        if (_maxBpm == 0 || hr > _maxBpm) _maxBpm = hr;
        if (_minBpm == 0 || hr < _minBpm) _minBpm = hr;

        _sumBpm += hr;
        _countBpm++;
        _avgBpm = _sumBpm ~/ _countBpm;
      }
      if (_isSeriesInProgress) {
        if (_seriesMaxBpm == 0 || hr > _seriesMaxBpm) _seriesMaxBpm = hr;
        if (_seriesMinBpm == 0 || hr < _seriesMinBpm) _seriesMinBpm = hr;
      }
    });
  }

  void _openGoogleCalendar() async {
    if (_startTime == null) return;

    final start = _startTime!;
    final end = start.add(Duration(milliseconds: _elapsedMs));

    final startFormatted = DateFormat("yyyyMMdd'T'HHmmss").format(start);
    final endFormatted = DateFormat("yyyyMMdd'T'HHmmss").format(end);

    final totalReps =
        _currentSessionSeriesReps.fold(0, (sum, item) => sum + (item as int));

    // Detalle de series
    String details = '🏋️ Tipo de ejercicio: $_selectedExerciseType\n'
        '🏋️ Series completadas: $_seriesCounter\n'
        '🔢 Total repeticiones: $totalReps\n'
        '⏱️ Tiempo total: ${_formatHHMMSSCC(_elapsedMs)}\n'
        '📊 Tiempo medio: $_averageSeriesTime\n';

    if (_minBpm > 0 || _maxBpm > 0) {
      details +=
          '❤️ Pulsaciones sesión: Min $_minBpm - Max $_maxBpm - Med $_avgBpm\n';
    }

    details += '\n📝 Detalle de series:\n';

    for (int i = 0; i < _currentSessionSeriesTimes.length; i++) {
      int reps = i < _currentSessionSeriesReps.length
          ? _currentSessionSeriesReps[i]
          : 10;
      final String seriesType = i < _currentSessionSeriesExerciseTypes.length
          ? _currentSessionSeriesExerciseTypes[i]
          : _selectedExerciseType;
      details +=
          'Serie ${i + 1} [$seriesType]: ${_formatHHMMSSCC(_currentSessionSeriesTimes[i])} ($reps reps)';
      if (i < _currentSessionSeriesMinBpm.length &&
          _currentSessionSeriesMaxBpm[i] > 0) {
        details +=
            ' (BPM: ${_currentSessionSeriesMinBpm[i]} - ${_currentSessionSeriesMaxBpm[i]})';
      }
      details += '\n';
    }
    if (_isSeriesInProgress) {
      details +=
          'Serie ${_currentSessionSeriesTimes.length + 1} [$_currentSeriesExerciseType]: ${_formatHHMMSSCC(_seriesMs)} (Incompleta)';
      if (_seriesMaxBpm > 0) {
        details += ' (BPM: $_seriesMinBpm - $_seriesMaxBpm)';
      }
      details += '\n';
    }

    final titulo =
        'GIMNASIO - $_selectedExerciseType - $_seriesCounter SERIES ($totalReps REPS)';

    // En la web: se guarda directamente en Google Calendar en VERDE (colorId 10).
    // Si algo falla, se abre Google Calendar con el evento rellenado como antes.
    if (kIsWeb) {
      final ok = await _guardarEnCalendarioVerde(titulo, details, start, end);
      if (ok) return;
    }

    final url = Uri(
      scheme: 'https',
      host: 'calendar.google.com',
      path: '/calendar/render',
      queryParameters: {
        'action': 'TEMPLATE',
        'text': titulo,
        'dates': '$startFormatted/$endFormatted',
        'details': details,
        'sf': 'true',
        'output': 'xml',
      },
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  /// Crea el evento directamente en el calendario principal de Google con
  /// color verde (colorId "10" = Albahaca). Devuelve true si se ha guardado.
  Future<bool> _guardarEnCalendarioVerde(
      String titulo, String detalles, DateTime inicio, DateTime fin) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider
          .addScope('https://www.googleapis.com/auth/calendar.events');

      final UserCredential credential =
          await FirebaseAuth.instance.signInWithPopup(googleProvider);
      final accessToken =
          (credential.credential as OAuthCredential?)?.accessToken;

      // Volver a la sesión anónima de la app, como en la importación
      await FirebaseAuth.instance.signOut();
      await _firebaseService.signInAnonymously().then((uc) {
        if (uc != null && mounted) setState(() => _user = uc.user);
      });

      if (accessToken == null) return false;

      Map<String, dynamic> hora(DateTime d) =>
          {'dateTime': d.toUtc().toIso8601String()};

      final resp = await http.post(
        Uri.https('www.googleapis.com', '/calendar/v3/calendars/primary/events'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'summary': titulo,
          'description': detalles,
          'start': hora(inicio),
          'end': hora(fin),
          'colorId': '10', // verde
        }),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        messenger.showSnackBar(const SnackBar(
          content: Text('✅ Entrenamiento guardado en tu calendario (en verde)'),
          backgroundColor: Colors.green,
        ));
        return true;
      }
      messenger.showSnackBar(SnackBar(
          content: Text(
              'No se pudo guardar directamente (${resp.statusCode}). Se abre Google Calendar.')));
      return false;
    } catch (e) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No se pudo conectar con Google. Se abre Google Calendar.')));
      return false;
    }
  }

  String _formatHHMMSSCC(int milliseconds) {
    int hundredths = (milliseconds % 1000) ~/ 10;
    int seconds = (milliseconds ~/ 1000) % 60;
    int minutes = (milliseconds ~/ (1000 * 60)) % 60;
    int hours = (milliseconds ~/ (1000 * 60 * 60));

    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    final cc = hundredths.toString().padLeft(2, '0');

    return '$hh:$mm:$ss:$cc';
  }

  String _formatDuration(int milliseconds) {
    int totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: modoOscuro,
            builder: (context, oscuro, _) => Tooltip(
              message: oscuro ? 'Modo de día' : 'Modo oscuro',
              child: InkWell(
                onTap: cambiarModoOscuro,
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(
                    oscuro ? Icons.light_mode : Icons.dark_mode,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: InkWell(
              onTap: _mostrarSelectorColor,
              borderRadius: BorderRadius.circular(5),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: colorApp.value,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else if (_user != null) ...[
            if (_isVip)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Chip(
                    label: Text(
                      'VIP',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                    backgroundColor: Colors.orange,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.cloud_done),
              onPressed: _syncData,
              tooltip: 'Sincronizado',
            ),
          ],
        ],
      ),
      body: _cuerpo(
        <Widget>[
                Text(
                  DateFormat('EEEE, d MMMM yyyy', 'es_ES').format(_currentTime),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  DateFormat('HH:mm:ss').format(_currentTime),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FilledButton.icon(
                    onPressed: _showExerciseTypeSelector,
                    icon: const Icon(Icons.fitness_center, size: 18),
                    label: Text('Ejercicio: $_selectedExerciseType'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorApp.value,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 22,
                  child: _startTime != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorApp.value.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Inicio: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(_startTime!)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorApp.value,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Series completadas:',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.list_alt, size: 24),
                      color: colorApp.value,
                      onPressed: _showSeriesDetails,
                      tooltip: 'Ver detalles de series',
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        Icon(
                          Icons.favorite,
                          color: _isHrmConnected ? Colors.red : Colors.grey,
                          size: 24,
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _bpm > 0 ? '$_bpm' : '--',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color:
                                    _isHrmConnected ? Colors.red : Colors.grey,
                              ),
                            ),
                            if (_isHrmConnected && _avgBpm > 0) ...[
                              const SizedBox(width: 4),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  'MED $_avgBpm',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade400,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(
                          height: 24,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              if (_isHrmConnected && _minBpm > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'MIN $_minBpm',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorApp.value,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'MAX $_maxBpm',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              if (_isHrmConnected &&
                                  _isSeriesInProgress &&
                                  _seriesMinBpm > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'MIN SER $_seriesMinBpm',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: colorApp.value.shade300,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'MAX SER $_seriesMaxBpm',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade300,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 125,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text(
                              '$_seriesCounter',
                              style: TextStyle(
                                fontSize: 170,
                                fontWeight: FontWeight.bold,
                                color: Colors.brown[800],
                                height: 0.85,
                              ),
                            ),
                          ),
                        ),
                        if (_seriesCounter > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10, left: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'TOTAL',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                                Text(
                                  '${_currentSessionSeriesReps.fold(0, (sum, item) => sum + (item as int))}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: colorApp.value,
                                  ),
                                ),
                                const Text(
                                  'REPS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                const Text(
                  'Tiempo de la serie:',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(
                  height: 55,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Text(
                      _formatHHMMSSCC(_seriesMs),
                      style: TextStyle(
                        fontSize: 80,
                        fontWeight: FontWeight.bold,
                        color: Colors.brown[800],
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Última serie: ${_formatHHMMSSCC(_lastSeriesMs)}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tiempo medio: $_averageSeriesTime',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tiempo total: ${_formatHHMMSSCC(_elapsedMs)}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ],
        <Widget>[
                // Nueva sección de repeticiones
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: colorApp.value.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorApp.value.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'REPETICIONES DE LA SERIE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: colorApp.value,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () {
                              setState(() {
                                if (_upcomingReps > 0) _upcomingReps--;
                              });
                            },
                            icon: Icon(Icons.remove_circle_outline,
                                size: 18, color: colorApp.value),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$_upcomingReps',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: colorApp.value,
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _upcomingReps++;
                              });
                            },
                            icon: Icon(Icons.add_circle_outline,
                                size: 18, color: colorApp.value),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 350,
                    ),
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                      childAspectRatio: 3.2,
                      children: [
                        _buildGridButton(
                          label: '+',
                          icon: null,
                          onPressed: _incrementCounter,
                        ),
                        _buildGridButton(
                          label: _isPaused ? 'Continuar' : 'Pausa',
                          icon: _isPaused ? Icons.play_arrow : Icons.pause,
                          onPressed: _togglePause,
                        ),
                        _buildGridButton(
                          label: 'Guardar',
                          icon: Icons.save,
                          onPressed: _saveToHistory,
                        ),
                        _buildGridButton(
                          label: 'Historial',
                          icon: Icons.history,
                          onPressed: _showHistory,
                        ),
                        _buildGridButton(
                          label: 'Calendario',
                          icon: Icons.calendar_today,
                          onPressed: _openGoogleCalendar,
                        ),
                        _buildGridButton(
                          label: 'Terminar',
                          icon: Icons.stop_circle_outlined,
                          onPressed: _confirmReset,
                        ),
                        if (!_isVip)
                          _buildGridButton(
                            label: 'Quitar Publicidad',
                            icon: Icons.star,
                            onPressed: _showVipDialog,
                          ),
                        _buildGridButton(
                          label: _isHrmConnecting
                              ? 'Conectando...'
                              : (_isHrmConnected
                                  ? 'Desconectar 💓'
                                  : 'Conectar 💓'),
                          icon: _isHrmConnected
                              ? Icons.favorite
                              : Icons.favorite_border,
                          onPressed: _connectToHrm,
                          fontSize: 14,
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
      bottomNavigationBar: _bannerAd != null
          ? SafeArea(
              child: SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            )
          : null,
    );
  }

  // En el ordenador (ventana ancha) reparte la pantalla en dos columnas
  // para que se vean todos los botones sin tener que bajar.
  Widget _cuerpo(List<Widget> arriba, List<Widget> abajo) {
    return LayoutBuilder(
      builder: (context, c) {
        final ancho = c.maxWidth >= 700 && c.maxWidth > c.maxHeight;
        if (!ancho) {
          return SingleChildScrollView(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 15.0, bottom: 2.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    ...arriba,
                    const SizedBox(height: 15),
                    ...abajo,
                  ],
                ),
              ),
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: arriba,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: abajo,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGridButton({
    required String label,
    IconData? icon,
    String? emoji,
    required VoidCallback onPressed,
    double fontSize = 20,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colorApp.value,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (emoji != null) ...[
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4)
          ],
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize == 16 ? 13 : fontSize,
                fontWeight: label == '+' ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmReset() {
    if (_elapsedMs == 0) {
      _clearSession();
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Finalizar entrenamiento?'),
        content: const Text(
          '¿Deseas guardar el progreso actual en el historial o descartarlo antes de reiniciar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              _saveToHistory(silent: true);
              Navigator.pop(context); // Close the reset confirmation dialog
              _handleCalendarPostSave(); // Show the calendar prompt afterwards
            },
            child: const Text('Guardar y Reiniciar'),
          ),
          TextButton(
            onPressed: () {
              _clearSession();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Descartar y Reiniciar'),
          ),
        ],
      ),
    );
  }

  void _clearSession() {
    setState(() {
      _seriesCounter = 0;
      _elapsedMs = 0;
      _seriesMs = 0;
      _lastSeriesMs = 0;
      _isRunning = false;
      _isSeriesInProgress = false;
      _isPaused = false;
      _currentSessionSeriesMinBpm.clear();
      _currentSessionSeriesMaxBpm.clear();
      _startTime = null;
      _currentSessionSeriesTimes = [];
      _currentSessionSeriesReps = [];
      _currentSessionSeriesExerciseTypes = [];
      _currentSeriesExerciseType = _selectedExerciseType;
      _upcomingReps = 0;
      _maxBpm = 0;
      _minBpm = 0;
    });
  }

  void _handleCalendarPostSave() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('📅 Calendario'),
        content: const Text(
            '¿Quieres añadir este entrenamiento a tu Google Calendar?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearSession(); // Clear session ONLY after a choice is made
            },
            child: const Text('No por ahora'),
          ),
          ElevatedButton(
            onPressed: () {
              _openGoogleCalendar();
              Navigator.pop(context);
              _clearSession(); // Clear session after opening calendar
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            child:
                const Text('Sí, añadir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showVipDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🌟 ¡Hazte VIP!'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Disfruta de la mejor experiencia:'),
            SizedBox(height: 10),
            ListTile(
              leading: Icon(Icons.block, color: Colors.red),
              title: Text('Sin publicidad'),
            ),
            ListTile(
              leading: Icon(Icons.cloud_upload, color: Colors.blue),
              title: Text('Sincronización prioritaria'),
            ),
            ListTile(
              leading: Icon(Icons.star, color: Colors.orange),
              title: Text('Insignia VIP exclusiva'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Quizás luego'),
          ),
          ElevatedButton(
            onPressed: () {
              // Simulator: marking as VIP immediately
              _firebaseService.updateVipStatus(true);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('¡Ahora eres VIP! 🌟')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('¡Activar VIP!',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
