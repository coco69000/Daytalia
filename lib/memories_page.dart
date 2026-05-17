import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'journee_page.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'journee_model.dart';
import 'souvenir_model.dart';
import 'souvenir_page.dart';
import 'dart:ui'; // Ajout nécessaire pour le filtre de flou
import 'ai_model_selector.dart';

class MemoriesPage extends StatefulWidget {
  // MODIFIÉ: Propriété pour savoir si on est en mode sélection.
  final bool isPinningMode;
  // MODIFIÉ: Nouveau paramètre pour savoir QUEL type d'élément on épingle.
  final String? pinItemType;

  const MemoriesPage({super.key, this.isPinningMode = false, this.pinItemType});

  @override
  _MemoriesPageState createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage>
    with AutomaticKeepAliveClientMixin {
  DateTime _currentDisplayedMonth = DateTime.now();
  final List<String> _daysOfWeek = [
    'LUN',
    'MAR',
    'MER',
    'JEU',
    'VEN',
    'SAM',
    'DIM',
  ];
  Set<DateTime> _datesWithMemories = {};
  String _averageRatingMessage = '';
  bool _isIAActive = false;
  bool _isFirstLoad = true;
  bool _isLoading = false;

  // Theme colors
  Color _backgroundColor = Colors.black;
  Color _textColor = Colors.white;
  Color _cardBackgroundColor = Colors.grey.shade900;
  Color _cardTextColor = Colors.white;

  // Controller for smooth scrolling
  final ScrollController _scrollController = ScrollController();

  // Map to store average ratings for different months
  Map<String, String> _monthlyAverageRatings = {};

  // List of months to display
  List<DateTime> _monthsToDisplay = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeMonthsList();
    _loadThemePreferences();
    _initializeData();
  }

  void _initializeMonthsList() {
    DateTime now = DateTime.now();
    _monthsToDisplay = List.generate(24, (index) {
      return DateTime(now.year, now.month - index, 1);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateAverageRatingDisplay() {
    String monthKey =
        '${_currentDisplayedMonth.year}-${_currentDisplayedMonth.month}';
    if (_monthlyAverageRatings.containsKey(monthKey)) {
      setState(() {
        _averageRatingMessage = _monthlyAverageRatings[monthKey]!;
      });
    } else {
      _updateAverageRatingForMonth(_currentDisplayedMonth);
    }
  }

  Future<void> _loadThemePreferences() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String themeMode = prefs.getString('themeMode') ?? 'system';

      Brightness finalBrightness;

      if (themeMode == 'dark') {
        finalBrightness = Brightness.dark;
      } else if (themeMode == 'light') {
        finalBrightness = Brightness.light;
      } else {
        finalBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
      }

      if (mounted) {
        setState(() {
          if (finalBrightness == Brightness.dark) {
            _backgroundColor = Colors.black;
            _textColor = Colors.white;
            _cardBackgroundColor = Colors.grey.shade800;
            _cardTextColor = Colors.white;
          } else {
            // Light mode
            _backgroundColor = Colors.white;
            _textColor = Colors.black;
            _cardBackgroundColor = Colors.white;
            _cardTextColor = Colors.black;
          }
        });
      }
    } catch (e) {
      print('Erreur de chargement des préférences de thème : $e');
    }
  }

  Future<void> _initializeData() async {
    if (_isFirstLoad) {
      _isFirstLoad = false;
      await initializeDateFormatting('fr', null);
      if (mounted) {
        await _loadAllMemories();
        if (!widget.isPinningMode) {
          await _updateAllMonthsAverageRatings();
        }
      }
    }
  }

  // MODIFIÉ: La méthode charge maintenant les données en fonction du mode (épinglage de journée ou de souvenir).
  Future<void> _loadAllMemories() async {
    if (_isLoading || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      Set<DateTime> datesWithMemories = {};

      // Charger les journées si on n'est pas en mode épinglage, ou si on épingle une journée.
      if (!widget.isPinningMode || widget.pinItemType == 'journee') {
        final journeesSnapshot =
            await FirebaseFirestore.instance
                .collection('journees')
                .where('userId', isEqualTo: currentUser.uid)
                .get();
        for (var doc in journeesSnapshot.docs) {
          var data = doc.data();
          try {
            DateTime docDate = (data['date'] as Timestamp).toDate();
            datesWithMemories.add(
              DateTime(docDate.year, docDate.month, docDate.day),
            );
          } catch (e) {
            print('Erreur lors de la conversion de la date de la journée : $e');
          }
        }
      }

      // Charger les souvenirs si on n'est pas en mode épinglage, ou si on épingle un souvenir.
      if (!widget.isPinningMode || widget.pinItemType == 'souvenir') {
        final souvenirsSnapshot =
            await FirebaseFirestore.instance
                .collection('souvenirs')
                .where('userId', isEqualTo: currentUser.uid)
                .get();
        for (var doc in souvenirsSnapshot.docs) {
          var data = doc.data();
          try {
            DateTime docDate = (data['date'] as Timestamp).toDate();
            datesWithMemories.add(
              DateTime(docDate.year, docDate.month, docDate.day),
            );
          } catch (e) {
            print('Erreur lors de la conversion de la date du souvenir : $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          _datesWithMemories = datesWithMemories;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Erreur lors du chargement des dates avec mémoires : $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateAllMonthsAverageRatings() async {
    // Calculate for all months in our list
    for (DateTime monthDate in _monthsToDisplay) {
      await _updateAverageRatingForMonth(monthDate);
    }
    _updateAverageRatingDisplay();
  }

  Future<void> _updateAverageRatingForMonth(DateTime monthDate) async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final journeesSnapshot =
          await FirebaseFirestore.instance
              .collection('journees')
              .where('userId', isEqualTo: currentUser.uid)
              .get();

      final souvenirsSnapshot =
          await FirebaseFirestore.instance
              .collection('souvenirs')
              .where('userId', isEqualTo: currentUser.uid)
              .get();

      if (!mounted) return;

      List<int> notes = [];

      int parseNote(dynamic note) {
        if (note == null) return 0;
        if (note is int) return note;
        if (note is String) {
          if (note.contains('/')) {
            try {
              return int.parse(note.split('/').first);
            } catch (e) {
              return 0;
            }
          }
          try {
            return int.parse(note);
          } catch (e) {
            return 0;
          }
        }
        return 0;
      }

      for (var doc in journeesSnapshot.docs) {
        var data = doc.data();
        DateTime docDate = (data['date'] as Timestamp).toDate();
        if (docDate.year == monthDate.year &&
            docDate.month == monthDate.month) {
          if (data['note'] != null) {
            int noteValue = parseNote(data['note']);
            if (noteValue > 0) notes.add(noteValue);
          }
        }
      }

      for (var doc in souvenirsSnapshot.docs) {
        var data = doc.data();
        DateTime docDate = (data['date'] as Timestamp).toDate();
        if (docDate.year == monthDate.year &&
            docDate.month == monthDate.month) {
          if (data['noteQualite'] != null) {
            int qualiteValue = parseNote(data['noteQualite']);
            if (qualiteValue > 0) notes.add(qualiteValue);
          }
        }
      }

      if (mounted) {
        String monthKey = '${monthDate.year}-${monthDate.month}';
        String message;

        if (notes.isNotEmpty) {
          double average = notes.reduce((a, b) => a + b) / notes.length;
          String qualification =
              average <= 30
                  ? "Pas super"
                  : average <= 60
                  ? "Bien"
                  : "Très bien";
          message =
              "Moyenne des notes pour ${DateFormat('MMMM yyyy', 'fr').format(monthDate)} : ${average.toStringAsFixed(2)} - $qualification";
        } else {
          message =
              "Aucune note trouvée pour ${DateFormat('MMMM yyyy', 'fr').format(monthDate)}.";
        }

        setState(() {
          _monthlyAverageRatings[monthKey] = message;
          if (monthDate.year == _currentDisplayedMonth.year &&
              monthDate.month == _currentDisplayedMonth.month) {
            _averageRatingMessage = message;
          }
        });
      }
    } catch (e) {
      print('Erreur lors du calcul de la moyenne : $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du calcul de la moyenne : $e')),
        );
      }
    }
  }

  static const String ANTHROPIC_API_KEY = 'YOUR_ANTHROPIC_API_KEY_HERE';

  Future<void> _analyzeMonthWithIA() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    setState(() => _isIAActive = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Analyse IA en cours...',
          style: TextStyle(color: _textColor),
        ),
      ),
    );

    try {
      final analysisRequest = await _prepareAnalysisRequest();
      if (analysisRequest.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucune donnée à analyser pour ce mois.'),
          ),
        );
        setState(() => _isIAActive = false);
        return;
      }

      // Récupérer le statut VIP pour choisir le bon modèle
      bool isVip = false;
      try {
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .get();
        isVip = userDoc.data()?['isVip'] ?? false;
      } catch (e) {
        print('Erreur lors de la récupération du statut VIP: $e');
      }
      final aiModel = await resolveAiModel(isVip: isVip);

      const url = 'https://api.deepinfra.com/v1/openai/chat/completions';

      // Utilisez votre clé DeepSeek/DeepInfra
      const String apiKey = 'HA2RvSG1u7aE7u78yXd1UqnBuMY6VV70';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': aiModel,
          'max_tokens': 500,
          'messages': [
            {
              'role': 'system',
              'content':
                  'Tu es un psychologue bienveillant. Fais un résumé court et chaleureux.',
            },
            {
              'role': 'user',
              'content':
                  "Analyse les journées et souvenirs suivants pour le mois de ${DateFormat('MMMM yyyy', 'fr').format(_currentDisplayedMonth)}. Fournis un résumé des tendances émotionnelles et une perspective générale sur la qualité de vie du mois. Termine par une petite phrase encourageante. Voici les données:\n$analysisRequest",
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        String analysis = responseData['choices'][0]['message']['content'];

        setState(() {
          _averageRatingMessage = analysis;
        });
      } else {
        print('Erreur API: ${response.statusCode} - ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'analyse IA')),
        );
        setState(() => _isIAActive = false);
      }
    } catch (e) {
      print('Erreur : $e');
      setState(() => _isIAActive = false);
    }
  }

  Future<String> _prepareAnalysisRequest() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return '';

    final startOfMonth = DateTime(
      _currentDisplayedMonth.year,
      _currentDisplayedMonth.month,
      1,
    );
    final endOfMonth = DateTime(
      _currentDisplayedMonth.year,
      _currentDisplayedMonth.month + 1,
      0,
      23,
      59,
      59,
      999,
    );

    final journeesSnapshot =
        await FirebaseFirestore.instance
            .collection('journees')
            .where('userId', isEqualTo: currentUser.uid)
            .where('date', isGreaterThanOrEqualTo: startOfMonth)
            .where('date', isLessThanOrEqualTo: endOfMonth)
            .orderBy('date')
            .get();

    final souvenirsSnapshot =
        await FirebaseFirestore.instance
            .collection('souvenirs')
            .where('userId', isEqualTo: currentUser.uid)
            .where('date', isGreaterThanOrEqualTo: startOfMonth)
            .where('date', isLessThanOrEqualTo: endOfMonth)
            .orderBy('date')
            .get();

    final List<String> entries = [];
    for (var doc in journeesSnapshot.docs) {
      final data = doc.data();
      final date = DateFormat(
        'dd/MM',
      ).format((data['date'] as Timestamp).toDate());
      final note = data['note'] ?? 'N/A';
      final text = data['texte1'] ?? data['commentaire'] ?? 'Aucun texte';
      entries.add("Journée du $date (Note: $note): $text");
    }

    for (var doc in souvenirsSnapshot.docs) {
      final data = doc.data();
      final date = DateFormat(
        'dd/MM',
      ).format((data['date'] as Timestamp).toDate());
      final qualite = data['qualite'] ?? 'N/A';
      final noteQualite = data['noteQualite'] ?? 'N/A';
      final text = data['texte'] ?? 'Aucun texte';
      entries.add(
        "Souvenir du $date (Qualité: $qualite, Note: $noteQualite): $text",
      );
    }

    if (entries.isEmpty) {
      return '';
    }
    return entries.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar:
          widget.isPinningMode
              ? AppBar(
                title: Text(
                  'Choisir un(e) ${widget.pinItemType} à épingler',
                  style: TextStyle(color: _textColor),
                ),
                backgroundColor: _backgroundColor,
                elevation: 0,
                iconTheme: IconThemeData(color: _textColor),
              )
              : null,
      body: SafeArea(
        child:
            _isLoading
                ? _buildLoadingIndicator()
                : Column(
                  children: <Widget>[
                    if (!widget.isPinningMode)
                      Container(
                        color: _backgroundColor,
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat(
                                    'MMMM yyyy',
                                    'fr',
                                  ).format(_currentDisplayedMonth),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: _textColor,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    _isIAActive
                                        ? Icons.analytics
                                        : Icons.analytics_outlined,
                                    color:
                                        _isIAActive ? Colors.blue : _textColor,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isIAActive = !_isIAActive;
                                      if (_isIAActive) {
                                        _analyzeMonthWithIA();
                                      } else {
                                        _updateAverageRatingDisplay();
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (_averageRatingMessage.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  _averageRatingMessage,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _textColor,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            _buildDaysOfWeek(),
                          ],
                        ),
                      ),

                    if (widget.isPinningMode) _buildDaysOfWeek(),

                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: _monthsToDisplay.length,
                        itemBuilder: (context, index) {
                          return _buildMonthCalendar(_monthsToDisplay[index]);
                        },
                        physics: const BouncingScrollPhysics(),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _buildMonthCalendar(DateTime monthDate) {
    int daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    int firstDayOfMonth = DateTime(monthDate.year, monthDate.month, 1).weekday;
    int firstDayAdjusted = (firstDayOfMonth == 1) ? 0 : firstDayOfMonth - 1;

    int totalDays = firstDayAdjusted + daysInMonth;
    int numberOfWeeks = (totalDays / 7).ceil();

    List<Widget> weekRows = [];

    for (int week = 0; week < numberOfWeeks; week++) {
      List<Widget> dayWidgets = [];
      for (int weekday = 0; weekday < 7; weekday++) {
        int dayNumber = week * 7 + weekday - firstDayAdjusted + 1;

        if (dayNumber <= 0 || dayNumber > daysInMonth) {
          dayWidgets.add(Expanded(child: const SizedBox(height: 48.0)));
          continue;
        }

        DateTime currentDay = DateTime(
          monthDate.year,
          monthDate.month,
          dayNumber,
        );
        bool isToday =
            currentDay.year == DateTime.now().year &&
            currentDay.month == DateTime.now().month &&
            currentDay.day == DateTime.now().day;
        bool hasMemories = _datesWithMemories.contains(currentDay);

        dayWidgets.add(
          Expanded(
            child: GestureDetector(
              // MODIFIÉ: La logique de clic a été mise à jour pour le mode épinglage.
              onTap: () async {
                if (!hasMemories) {
                  if (widget.isPinningMode) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Il n'y a rien à épingler pour cette date.",
                        ),
                      ),
                    );
                  }
                  return;
                }

                if (widget.isPinningMode) {
                  // Ouvre la page de détails pour choisir un élément spécifique et attend un retour.
                  final selectedItem =
                      await Navigator.push<Map<String, dynamic>>(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => DayDetailsPage(
                                selectedDay: currentDay,
                                isPinningMode: true,
                                pinItemType: widget.pinItemType!,
                              ),
                        ),
                      );

                  // Si un élément a été sélectionné sur la page de détails, on le renvoie à la page de profil.
                  if (selectedItem != null && mounted) {
                    Navigator.of(context).pop(selectedItem);
                  }
                } else {
                  // Comportement normal : ouvrir la page de détails.
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => DayDetailsPage(selectedDay: currentDay),
                    ),
                  );
                }
              },
              child: Container(
                margin: const EdgeInsets.all(4.0),
                height: 48.0,
                decoration: BoxDecoration(
                  color:
                      hasMemories
                          ? (Theme.of(context).brightness == Brightness.dark
                              ? Colors.blue.shade700
                              : const Color.fromARGB(255, 0, 195, 255))
                          : (isToday
                              ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey.shade700
                                  : Colors.white)
                              : Colors.transparent),
                  borderRadius: BorderRadius.circular(isToday ? 24.0 : 8.0),
                  border:
                      isToday && !hasMemories
                          ? Border.all(
                            color:
                                (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey.shade400
                                    : Colors.blue.shade700),
                            width: 2,
                          )
                          : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$dayNumber',
                  style: TextStyle(
                    fontSize: 18,
                    color:
                        hasMemories
                            ? Colors.white
                            : isToday
                            ? (Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black)
                            : _textColor,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      weekRows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: dayWidgets,
        ),
      );
    }

    return VisibilityDetector(
      key: Key('month-${monthDate.year}-${monthDate.month}'),
      onVisibilityChanged: (visibilityInfo) {
        if (visibilityInfo.visibleFraction > 0.8 && mounted) {
          setState(() {
            _currentDisplayedMonth = monthDate;
            if (!widget.isPinningMode) {
              _updateAverageRatingDisplay();
            }
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          children: [
            if (!widget.isPinningMode)
              Text(
                DateFormat('MMMM yyyy', 'fr').format(monthDate),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                ),
              ),
            ...weekRows,
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(child: CircularProgressIndicator(color: _textColor));
  }

  Widget _buildDaysOfWeek() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children:
            _daysOfWeek.map((day) {
              return Text(
                day,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                  fontSize: 12,
                ),
              );
            }).toList(),
      ),
    );
  }
}

// MODIFIÉ: DayDetailsPage a été mis à jour pour gérer le mode épinglage.
class DayDetailsPage extends StatefulWidget {
  final DateTime selectedDay;
  final bool isPinningMode;
  final String? pinItemType;

  const DayDetailsPage({
    super.key,
    required this.selectedDay,
    this.isPinningMode = false,
    this.pinItemType,
  });

  @override
  _DayDetailsPageState createState() => _DayDetailsPageState();
}

class _DayDetailsPageState extends State<DayDetailsPage> {
  List<Map<String, dynamic>> _dayMemories = [];
  bool isIAAnalysisActive = false;
  Color _backgroundColor = Colors.black;
  Color _textColor = Colors.white;
  Color _cardBackgroundColor = Colors.grey.shade900;
  Color _cardTextColor = Colors.white;

  static const String DEEPSEEK_API_KEY = 'HA2RvSG1u7aE7u78yXd1UqnBuMY6VV70';

  @override
  void initState() {
    super.initState();
    _loadThemePreferences();
    _loadDayMemories();
  }

  Future<void> _loadThemePreferences() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String themeMode = prefs.getString('themeMode') ?? 'system';
      Brightness finalBrightness;

      if (themeMode == 'dark') {
        finalBrightness = Brightness.dark;
      } else if (themeMode == 'light') {
        finalBrightness = Brightness.light;
      } else {
        finalBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
      }

      if (mounted) {
        setState(() {
          if (finalBrightness == Brightness.dark) {
            _backgroundColor = Colors.black;
            _textColor = Colors.white;
            _cardBackgroundColor = Colors.grey.shade800;
            _cardTextColor = Colors.white;
          } else {
            _backgroundColor = Colors.white;
            _textColor = Colors.black;
            _cardBackgroundColor = Colors.white;
            _cardTextColor = Colors.black;
          }
        });
      }
    } catch (e) {
      print('Erreur de chargement des préférences de thème : $e');
    }
  }

  Future _loadDayMemories() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      DateTime startOfDay = DateTime(
        widget.selectedDay.year,
        widget.selectedDay.month,
        widget.selectedDay.day,
      );
      DateTime endOfDay = startOfDay.add(const Duration(days: 1));
      List<Map<String, dynamic>> memories = [];

      // MODIFIÉ: Ne charge les journées que si nécessaire.
      if (!widget.isPinningMode || widget.pinItemType == 'journee') {
        QuerySnapshot journeesSnapshot =
            await FirebaseFirestore.instance
                .collection('journees')
                .where('userId', isEqualTo: currentUser.uid)
                .where('date', isGreaterThanOrEqualTo: startOfDay)
                .where('date', isLessThan: endOfDay)
                .get();
        memories.addAll(
          journeesSnapshot.docs.map((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return {
              'type': 'journee',
              'id': doc.id,
              'texte': data['texte1'] ?? data['texte'],
              'date': (data['date'] as Timestamp).toDate(),
              'estPublic': data['estPublic'] ?? false,
              'emoji': data['emoji'],
              'note': data['note'],
              'motsCles': data['motsCles'] ?? [],
              'qualite':
                  data['qualite'] ?? 'normale', // <-- AJOUTEZ CETTE LIGNE
            };
          }).whereType<Map<String, dynamic>>(),
        );
      }

      // MODIFIÉ: Ne charge les souvenirs que si nécessaire.
      if (!widget.isPinningMode || widget.pinItemType == 'souvenir') {
        QuerySnapshot souvenirsSnapshot =
            await FirebaseFirestore.instance
                .collection('souvenirs')
                .where('userId', isEqualTo: currentUser.uid)
                .where('date', isGreaterThanOrEqualTo: startOfDay)
                .where('date', isLessThan: endOfDay)
                .get();
        memories.addAll(
          souvenirsSnapshot.docs.map((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return {
              'type': 'souvenir',
              'id': doc.id,
              'texte': data['texte'],
              'date': (data['date'] as Timestamp).toDate(),
              'estPublic': data['estPublic'] ?? false,
              'qualite': data['qualite'],
              'noteQualite': data['noteQualite'],
              'photoUrls': data['photoUrls'] ?? [],
              'isRepost': data['isRepost'] ?? false,
              'repostedFromUserId': data['repostedFromUserId'],
              'repostedFromUserName': data['repostedFromUserName'],
            };
          }).whereType<Map<String, dynamic>>(),
        );
      }

      memories.sort(
        (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime),
      );

      setState(() {
        _dayMemories = memories;
      });
    } catch (e) {
      print('Erreur détaillée lors du chargement des mémoires : $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur de chargement : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(
          // MODIFIÉ: Le titre de l'AppBar s'adapte au mode épinglage.
          widget.isPinningMode
              ? 'Sélectionnez un élément'
              : 'Souvenirs du ${DateFormat('dd/MM/yyyy', 'fr').format(widget.selectedDay)}',
          style: TextStyle(color: _textColor),
        ),
        centerTitle: true,
        backgroundColor: _backgroundColor,
        iconTheme: IconThemeData(color: _textColor),
      ),
      // MODIFIÉ: Le FAB a été supprimé pour simplifier l'interface en mode épinglage.
      body:
          _dayMemories.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                itemCount: _dayMemories.length,
                itemBuilder: (context, index) {
                  return _buildMemoryCard(_dayMemories[index]);
                },
              ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.memory, size: 100, color: _textColor.withOpacity(0.5)),
          const SizedBox(height: 20),
          Text(
            'Aucun souvenir pour cette date',
            style: TextStyle(color: _textColor.withOpacity(0.7), fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(Map<String, dynamic> memory) {
    return FutureBuilder<Map<String, String>>(
      future: _getCardColors(memory['type']),
      builder: (context, snapshot) {
        final colors = snapshot.data ?? {};
        final String colorPref = colors['color'] ?? 'bleu';
        final bool isDark = _backgroundColor == Colors.black;

        Color cardColor;
        switch (colorPref) {
          case 'noir':
            cardColor = isDark ? Colors.grey.shade900 : Colors.black87;
            break;
          case 'rouge':
            cardColor = isDark ? Colors.red.shade900 : Colors.red.shade400;
            break;
          case 'vert':
            cardColor = isDark ? Colors.green.shade900 : Colors.green.shade400;
            break;
          case 'orange':
            cardColor =
                isDark ? Colors.orange.shade900 : Colors.orange.shade400;
            break;
          case 'jaune':
            cardColor =
                isDark ? Colors.yellow.shade900 : Colors.yellow.shade600;
            break;
          case 'violet':
            cardColor =
                isDark ? Colors.purple.shade900 : Colors.purple.shade300;
            break;
          case 'rose':
            cardColor = isDark ? Colors.pink.shade900 : Colors.pink.shade300;
            break;
          case 'blanc':
            cardColor = isDark ? Colors.grey.shade300 : Colors.white;
            break;
          case 'bleu':
          default:
            cardColor = isDark ? Colors.blue.shade900 : Colors.blue.shade300;
            break;
        }

        final Color cardEnd = isDark ? Colors.grey.shade900 : Colors.white;
        final Color textCol =
            cardColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

        return GestureDetector(
          onTap: () {
            if (widget.isPinningMode) {
              Navigator.of(context).pop(memory);
            } else if (memory['type'] == 'journee') {
              final journee = JourneeModel(
                id: memory['id'],
                texte1: memory['texte'],
                date: memory['date'],
                estPublic: memory['estPublic'],
                emoji: memory['emoji'],
                note: memory['note'],
                motsCles: List<String>.from(memory['motsCles'] ?? []),
                userId: FirebaseAuth.instance.currentUser?.uid,
                qualite: memory['qualite'],
              );
              _showPopupCard(context, journee);
            }
          },
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side:
                  widget.isPinningMode
                      ? BorderSide(color: Colors.blue.shade300, width: 2)
                      : BorderSide.none,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cardColor, cardEnd],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          memory['type'] == 'journee' ? 'Journée' : 'Souvenir',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textCol,
                          ),
                        ),
                        if (!widget.isPinningMode)
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, color: textCol),
                            onSelected:
                                (action) => _handleMemoryAction(memory, action),
                            itemBuilder:
                                (context) => [
                                  const PopupMenuItem(
                                    value: 'modifier',
                                    child: Text('Modifier'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'supprimer',
                                    child: Text('Supprimer'),
                                  ),
                                ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      memory['texte'],
                      style: TextStyle(fontSize: 15, color: textCol),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat(
                        'dd MMMM yyyy HH:mm',
                        'fr',
                      ).format(memory['date']),
                      style: TextStyle(
                        fontSize: 12,
                        color: textCol.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (memory['type'] == 'journee' && memory['note'] != null)
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 16,
                            color: _getNoteColor(memory['note']),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Note: ${memory['note']}',
                            style: TextStyle(
                              color: _getNoteColor(memory['note']),
                            ),
                          ),
                          if (memory['emoji'] != null) ...[
                            const SizedBox(width: 10),
                            Text(
                              memory['emoji'],
                              style: const TextStyle(fontSize: 20),
                            ),
                          ],
                        ],
                      )
                    else if (memory['type'] == 'souvenir' &&
                        memory['qualite'] != null)
                      Row(children: [_getQualiteChip(memory['qualite'])]),

                    const Divider(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              memory['estPublic']
                                  ? Icons.public
                                  : Icons.lock_outline,
                              size: 16,
                              color:
                                  memory['estPublic']
                                      ? Colors.green
                                      : Colors.red,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              memory['estPublic'] ? 'Public' : 'Privé',
                              style: TextStyle(
                                color:
                                    memory['estPublic']
                                        ? Colors.green
                                        : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPopupCard(BuildContext context, JourneeModel journee) {
  final isDark = _backgroundColor == Colors.black;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.90, end: 1.0).animate(
            CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, anim1, anim2) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14.0, sigmaY: 14.0),
        child: Material(
          color: Colors.black.withOpacity(0.55),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                    maxWidth: MediaQuery.of(context).size.width,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade900 : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 24, spreadRadius: 2),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat('dd/MM/yyyy').format(journee.date),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close,
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                onPressed: () => Navigator.of(ctx).pop(),
                              ),
                            ],
                          ),
                        ),
                        // Content + Similarités
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                            child: StatefulBuilder(
                              builder: (context, setStateDialog) {
                                bool isSearching = false;
                                String? searchError;
                                List<MapEntry<JourneeModel, double>>? displayedSimilarities;
                                DateTime? lastSearchDate;
                                bool hasResultsInCache = false;

                                Future<void> loadCache() async {
                                  if (journee.id == null) return;
                                  final doc = await FirebaseFirestore.instance
                                      .collection('journees')
                                      .doc(journee.id)
                                      .get();
                                  if (!doc.exists) return;
                                  final data = doc.data();
                                  final cache = data?['similarJourneesCache'] as Map<String, dynamic>?;
                                  final ts = data?['lastSimilaritySearchDate'] as Timestamp?;
                                  if (ts != null) lastSearchDate = ts.toDate();
                                  if (cache != null && cache.isNotEmpty) {
                                    hasResultsInCache = true;
                                    final futures = cache.entries.map((entry) async {
                                      final d = await FirebaseFirestore.instance
                                          .collection('journees').doc(entry.key).get();
                                      if (d.exists) {
                                        return MapEntry(
                                          JourneeModel.fromFirestore(d),
                                          (entry.value as num).toDouble(),
                                        );
                                      }
                                      return null;
                                    }).toList();
                                    final results = (await Future.wait(futures))
                                        .whereType<MapEntry<JourneeModel, double>>()
                                        .toList();
                                    results.sort((a, b) => b.value.compareTo(a.value));
                                    displayedSimilarities = results;
                                  }
                                }

                                Future<void> handleSearch() async {
                                  setStateDialog(() { isSearching = true; searchError = null; });
                                  try {
                                    final results = await _findSimilarJournees(journee, searchAfter: lastSearchDate);
                                    await FirebaseFirestore.instance
                                        .collection('journees').doc(journee.id)
                                        .set({
                                          'similarJourneesCache': results.map((k, v) => MapEntry(k.id!, v)),
                                          'lastSimilaritySearchDate': FieldValue.serverTimestamp(),
                                        }, SetOptions(merge: true));
                                    setStateDialog(() {
                                      displayedSimilarities = results.entries.toList();
                                      hasResultsInCache = results.isNotEmpty;
                                      lastSearchDate = DateTime.now();
                                    });
                                  } catch (e) {
                                    setStateDialog(() { searchError = "Erreur: ${e.toString()}"; });
                                  } finally {
                                    setStateDialog(() { isSearching = false; });
                                  }
                                }

                                return FutureBuilder(
                                  future: loadCache(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const Center(child: CircularProgressIndicator());
                                    }
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (journee.emoji != null) ...[
                                          Text(journee.emoji!, style: const TextStyle(fontSize: 36)),
                                          const SizedBox(height: 8),
                                        ],
                                        Text(
                                          journee.texte1 ?? '',
                                          style: TextStyle(
                                            fontSize: 15, height: 1.65,
                                            color: isDark ? Colors.grey.shade100 : Colors.black87,
                                          ),
                                        ),
                                        if (journee.note != null) ...[
                                          const SizedBox(height: 14),
                                          Row(children: [
                                            const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                            const SizedBox(width: 6),
                                            Text('Note : ${journee.note}',
                                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)),
                                          ]),
                                        ],
                                        if (searchError != null) ...[
                                          const SizedBox(height: 12),
                                          Text(searchError!, style: const TextStyle(color: Colors.red)),
                                        ] else if (displayedSimilarities != null && displayedSimilarities!.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          Text('Journées similaires',
                                              style: TextStyle(
                                                fontSize: 16, fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.blue.shade300 : Colors.blue,
                                              )),
                                          const SizedBox(height: 8),
                                          ...displayedSimilarities!.map((entry) => Card(
                                            margin: const EdgeInsets.symmetric(vertical: 4),
                                            child: ListTile(
                                              title: Text(DateFormat('d MMMM yyyy', 'fr').format(entry.key.date)),
                                              subtitle: Text(entry.key.texte1 ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                                              trailing: Text('${entry.value.toStringAsFixed(0)}%',
                                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                                            ),
                                          )),
                                        ] else if (lastSearchDate != null && !hasResultsInCache) ...[
                                          const SizedBox(height: 12),
                                          Text('Aucune journée similaire trouvée.',
                                              style: TextStyle(fontStyle: FontStyle.italic,
                                                  color: isDark ? Colors.white54 : Colors.grey)),
                                        ],
                                        const SizedBox(height: 20),
                                        Center(
                                          child: isSearching
                                              ? const CircularProgressIndicator()
                                              : ElevatedButton.icon(
                                                  icon: Icon(hasResultsInCache ? Icons.sync : Icons.search),
                                                  label: Text(hasResultsInCache ? 'Mettre à jour' : 'Rechercher des journées similaires'),
                                                  onPressed: handleSearch,
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.blue.shade700,
                                                    foregroundColor: Colors.white,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

  Future<Map<JourneeModel, double>> _findSimilarJournees(
    JourneeModel selectedJournee, {
    DateTime? searchAfter,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    final selectedText =
        selectedJournee.texte1 ?? selectedJournee.commentaire ?? '';
    if (selectedText.trim().isEmpty) return {};

    Query journeesQuery = FirebaseFirestore.instance
        .collection('journees')
        .where('userId', isEqualTo: user.uid)
        .where('id', isNotEqualTo: selectedJournee.id);

    if (searchAfter != null) {
      journeesQuery = journeesQuery.where(
        'date',
        isGreaterThan: Timestamp.fromDate(searchAfter),
      );
    }

    final allJourneesSnapshot = await journeesQuery.get();
    final similarJourneesFutures = <Future<MapEntry<JourneeModel, double>?>>[];

    for (var doc in allJourneesSnapshot.docs) {
      final journee = JourneeModel.fromFirestore(doc);
      final journeeText = journee.texte1 ?? journee.commentaire ?? '';
      if (journeeText.isEmpty) continue;

      similarJourneesFutures.add(
        _calculateSimilarity(selectedText, journeeText).then((similarity) {
          if (similarity > 30) {
            return MapEntry(journee, similarity);
          }
          return null;
        }),
      );
    }

    final results = await Future.wait(similarJourneesFutures);
    final similarJournees = <JourneeModel, double>{};
    for (var result in results) {
      if (result != null) {
        similarJournees[result.key] = result.value;
      }
    }

    final sortedEntries =
        similarJournees.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return Map.fromEntries(sortedEntries.take(5));
  }

  Future<double> _calculateSimilarity(String text1, String text2) async {
    if (text1.isEmpty ||
        text2.isEmpty ||
        DEEPSEEK_API_KEY.contains('YOUR_DEEPSEEK_API_KEY_HERE')) {
      return 0.0;
    }
    const url = 'https://api.deepinfra.com/v1/openai/chat/completions';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': await resolveAiModel(),
          'messages': [
            {
              'role': 'user',
              'content':
                  '''Compare sémantiquement les deux textes suivants. Donne un pourcentage de similarité basé sur le contenu, le ton et les thèmes.
                  Réponds UNIQUEMENT avec un nombre entier entre 0 et 100 suivi de "/100". Exemple : "75/100".

                  Texte 1: "$text1"
                  Texte 2: "$text2"''',
            },
          ],
          'max_tokens': 10,
          'temperature': 0.1,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content =
            data['choices']?[0]['message']['content']?.toString() ?? '';
        final match = RegExp(r'(\d+)').firstMatch(content);
        if (match != null) {
          return double.tryParse(match.group(1)!) ?? 0.0;
        }
        return 0.0;
      } else {
        print(
          'DeepSeek API error for similarity: ${response.statusCode} - ${response.body}',
        );
        return 0.0;
      }
    } catch (e) {
      print('Exception during similarity calculation: $e');
      return 0.0;
    }
  }

  void _modifierJournee(JourneeModel journee) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JourneePage(journeeToEdit: journee),
      ),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Future<bool> _canModify(String collection, String? docId) async {
    if (docId == null) return false;

    final docRef = FirebaseFirestore.instance.collection(collection).doc(docId);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) return true;

    final data = docSnapshot.data();
    final lastModifiedTimestamp = data?['dateDerniereModif'] as Timestamp?;

    if (lastModifiedTimestamp == null) {
      return true; // Jamais modifié
    }

    final lastModifiedDate = lastModifiedTimestamp.toDate();
    final now = DateTime.now();

    return !_isSameDay(lastModifiedDate, now);
  }

  void _handleMemoryAction(Map<String, dynamic> memory, String action) async {
    final String docId = memory['id'];
    final String collection =
        memory['type'] == 'journee' ? 'journees' : 'souvenirs';
    final currentUser = FirebaseAuth.instance.currentUser;

    if (action == 'modifier') {
      bool canModify = await _canModify(collection, docId);
      if (!mounted) return;

      if (canModify) {
        bool? wasModified;

        if (memory['type'] == 'journee') {
          JourneeModel journee = JourneeModel(
            id: docId,
            texte1: memory['texte'],
            estPublic: memory['estPublic'],
            date: memory['date'],
            emoji: memory['emoji'],
            note: memory['note'],
            userId: currentUser?.uid,
            qualite: memory['qualite'], // <-- AJOUTEZ CETTE LIGNE
          );
          wasModified = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => JourneePage(journeeToEdit: journee),
            ),
          );
        } else if (memory['type'] == 'souvenir') {
          SouvenirQualite qualiteEnum = SouvenirQualite.values.firstWhere(
            (e) => e.name == (memory['qualite'] as String?),
            orElse: () => SouvenirQualite.nostalgie,
          );

          SouvenirModel souvenir = SouvenirModel(
            id: docId,
            userId: currentUser!.uid,
            texte: memory['texte'] ?? '',
            date: memory['date'] as DateTime,
            estPublic: memory['estPublic'] ?? false,
            qualite: qualiteEnum,
            noteQualite: memory['noteQualite'] ?? 0,
            photoUrls: List<String>.from(memory['photoUrls'] ?? []),
            isRepost: memory['isRepost'] ?? false,
            repostedFromUserId: memory['repostedFromUserId'],
            repostedFromUserName: memory['repostedFromUserName'],
          );

          wasModified = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => SouvenirPage(souvenirToEdit: souvenir),
            ),
          );
        }

        if (wasModified == true) {
          await FirebaseFirestore.instance
              .collection(collection)
              .doc(docId)
              .set({
                'dateDerniereModif': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
          _loadDayMemories();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vous avez déjà modifié cet élément aujourd\'hui.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (action == 'supprimer') {
      try {
        await FirebaseFirestore.instance
            .collection(collection)
            .doc(docId)
            .delete();
        _loadDayMemories();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mémoire supprimée avec succès')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression : $e')),
        );
      }
    }
  }

  Color _getNoteColor(dynamic note) {
    try {
      int noteValue;
      if (note is String) {
        if (note.contains('/')) {
          noteValue = int.parse(note.split('/').first);
        } else {
          noteValue = int.parse(note);
        }
      } else if (note is int) {
        noteValue = note;
      } else {
        return Colors.grey;
      }

      if (noteValue <= 20) return Colors.red.shade700;
      if (noteValue <= 40) return Colors.orange.shade700;
      if (noteValue <= 60) return Colors.amber.shade700;
      if (noteValue <= 80) return Colors.green.shade500;
      return Colors.green.shade700;
    } catch (e) {
      return Colors.grey;
    }
  }

  Future<Map<String, String>> _getCardColors(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final color =
        type == 'journee'
            ? (prefs.getString('journeeCardColor') ?? 'bleu')
            : (prefs.getString('cardColor') ?? 'bleu');
    return {'color': color};
  }

  Widget _getQualiteChip(String qualite) {
    Color chipColor;
    String qualiteLabel;
    switch (qualite) {
      case 'nostalgie':
        chipColor = Colors.purple;
        qualiteLabel = 'Nostalgie';
        break;
      case 'jamaisOublie':
        chipColor = Colors.blue;
        qualiteLabel = 'Jamais Oublié';
        break;
      case 'bonheur':
        chipColor = Colors.green;
        qualiteLabel = 'Bonheur';
        break;
      default:
        chipColor = Colors.grey;
        qualiteLabel = 'Inconnu';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        qualiteLabel,
        style: TextStyle(color: chipColor, fontSize: 12),
      ),
    );
  }
}
