
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

class MemoriesPage extends StatefulWidget {
  const MemoriesPage({super.key});

  @override
  _MemoriesPageState createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> with AutomaticKeepAliveClientMixin {
  DateTime _currentDisplayedMonth = DateTime.now();
  final List<String> _daysOfWeek = ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM'];
  Set<DateTime> _datesWithMemories = {};
  String _averageRatingMessage = '';
  bool _isIAActive = false;
  bool _isFirstLoad = true;
  bool _isLoading = false;

  // Theme colors
  Color _backgroundColor = Colors.black; // Default to black
  Color _textColor = Colors.white;       // Default to white
  Color _cardBackgroundColor = Colors.grey.shade900; // For dark mode cards
  Color _cardTextColor = Colors.white;              // For dark mode card text

  // Controller for smooth scrolling
  ScrollController _scrollController = ScrollController();

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
    _loadThemePreferences(); // Call this to load theme settings
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
    String monthKey = '${_currentDisplayedMonth.year}-${_currentDisplayedMonth.month}';
    if (_monthlyAverageRatings.containsKey(monthKey)) {
      setState(() {
        _averageRatingMessage = _monthlyAverageRatings[monthKey]!;
      });
    } else {
      _updateAverageRatingForMonth(_currentDisplayedMonth);
    }
  }

  // Renamed from _loadBackgroundColor to reflect broader theme loading
  Future<void> _loadThemePreferences() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      // On met 'system' par défaut si rien n'est sauvegardé
      String themeMode = prefs.getString('themeMode') ?? 'system';

      Brightness finalBrightness;

      if (themeMode == 'dark') {
        finalBrightness = Brightness.dark;
      } else if (themeMode == 'light') {
        finalBrightness = Brightness.light;
      } else { // Cas 'system'
        // On demande au système quel est le thème actuel
        finalBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      }

      // On met à jour les couleurs en fonction du thème final
      if (mounted) {
        setState(() {
          if (finalBrightness == Brightness.dark) {
            _backgroundColor = Colors.black;
            _textColor = Colors.white;
            _cardBackgroundColor = Colors.grey.shade800;
            _cardTextColor = Colors.white;
          } else { // Light mode
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
        await _updateAllMonthsAverageRatings();
      }
    }
  }

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
      final journeesSnapshot = await FirebaseFirestore.instance
          .collection('journees')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      final souvenirsSnapshot = await FirebaseFirestore.instance
          .collection('souvenirs')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      if (!mounted) return;

      Set<DateTime> datesWithMemories = {};

      for (var doc in journeesSnapshot.docs) {
        var data = doc.data();
        try {
          DateTime docDate = (data['date'] as Timestamp).toDate();
          datesWithMemories.add(DateTime(docDate.year, docDate.month, docDate.day));
        } catch (e) {
          print('Erreur lors de la conversion de la date de la journée : $e');
        }
      }

      for (var doc in souvenirsSnapshot.docs) {
        var data = doc.data();
        try {
          DateTime docDate = (data['date'] as Timestamp).toDate();
          datesWithMemories.add(DateTime(docDate.year, docDate.month, docDate.day));
        } catch (e) {
          print('Erreur lors de la conversion de la date du souvenir : $e');
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

    // Update the current display
    _updateAverageRatingDisplay();
  }

  Future<void> _updateAverageRatingForMonth(DateTime monthDate) async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final journeesSnapshot = await FirebaseFirestore.instance
          .collection('journees')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      final souvenirsSnapshot = await FirebaseFirestore.instance
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
        if (docDate.year == monthDate.year && docDate.month == monthDate.month) {
          if (data['note'] != null) {
            int noteValue = parseNote(data['note']);
            if (noteValue > 0) notes.add(noteValue);
          }
        }
      }

      for (var doc in souvenirsSnapshot.docs) {
        var data = doc.data();
        DateTime docDate = (data['date'] as Timestamp).toDate();
        if (docDate.year == monthDate.year && docDate.month == monthDate.month) {
          // Assuming 'qualite' field stores a numerical quality score for souvenirs
          // If not, you might need to adjust or create a 'noteQualite' field in SouvenirModel
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
          String qualification = average <= 30 ? "Pas super" :
          average <= 60 ? "Bien" : "Très bien";
          message = "Moyenne des notes pour ${DateFormat('MMMM yyyy', 'fr').format(monthDate)} : ${average.toStringAsFixed(2)} - $qualification";
        } else {
          message = "Aucune note trouvée pour ${DateFormat('MMMM yyyy', 'fr').format(monthDate)}.";
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

  // Replace with your actual Anthropic API key
  static const String ANTHROPIC_API_KEY = 'YOUR_ANTHROPIC_API_KEY_HERE';

  Future<void> _analyzeMonthWithIA() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    if (ANTHROPIC_API_KEY.contains('YOUR_ANTHROPIC_API_KEY_HERE')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clé API Anthropic non configurée.')),
      );
      setState(() {
        _isIAActive = false; // Turn off IA if API key is not configured
        _updateAverageRatingDisplay(); // Show normal message
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Analyse IA en cours...', style: TextStyle(color: _textColor))),
    );

    try {
      final analysisRequest = await _prepareAnalysisRequest();
      if (analysisRequest.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune donnée à analyser pour ce mois.')),
        );
        setState(() {
          _isIAActive = false;
          _updateAverageRatingDisplay();
        });
        return;
      }

      const url = 'https://api.anthropic.com/v1/messages';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': ANTHROPIC_API_KEY,
          'Anthropic-Version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 500,
          'messages': [
            {
              'role': 'user',
              'content': "Analyse les journées et souvenirs suivants pour le mois de ${DateFormat('MMMM yyyy', 'fr').format(_currentDisplayedMonth)}. Fournis un résumé des tendances émotionnelles, des points forts, des défis, et une perspective générale sur la qualité de vie du mois. Termine par une petite phrase encourageante. Voici les données:\n$analysisRequest"
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        String analysis = responseData['content'][0]['text'];

        setState(() {
          _averageRatingMessage = analysis; // Remplacer le texte par l'analyse
        });
      } else {
        print('Erreur lors de l\'appel à l\'API Claude : ${response.statusCode} - ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur API Claude: ${response.statusCode}')),
        );
        setState(() {
          _isIAActive = false;
          _updateAverageRatingDisplay();
        });
      }
    } catch (e) {
      print('Erreur lors de l\'analyse avec l\'IA : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'analyse : $e')),
      );
      setState(() {
        _isIAActive = false;
        _updateAverageRatingDisplay();
      });
    }
  }

  Future<String> _prepareAnalysisRequest() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return '';

    final startOfMonth = DateTime(_currentDisplayedMonth.year, _currentDisplayedMonth.month, 1);
    final endOfMonth = DateTime(_currentDisplayedMonth.year, _currentDisplayedMonth.month + 1, 0, 23, 59, 59, 999);

    final journeesSnapshot = await FirebaseFirestore.instance
        .collection('journees')
        .where('userId', isEqualTo: currentUser.uid)
        .where('date', isGreaterThanOrEqualTo: startOfMonth)
        .where('date', isLessThanOrEqualTo: endOfMonth)
        .orderBy('date')
        .get();

    final souvenirsSnapshot = await FirebaseFirestore.instance
        .collection('souvenirs')
        .where('userId', isEqualTo: currentUser.uid)
        .where('date', isGreaterThanOrEqualTo: startOfMonth)
        .where('date', isLessThanOrEqualTo: endOfMonth)
        .orderBy('date')
        .get();

    final List<String> entries = [];
    for (var doc in journeesSnapshot.docs) {
      final data = doc.data();
      final date = DateFormat('dd/MM').format((data['date'] as Timestamp).toDate());
      final note = data['note'] ?? 'N/A';
      final text = data['texte1'] ?? data['commentaire'] ?? 'Aucun texte';
      entries.add("Journée du $date (Note: $note): $text");
    }

    for (var doc in souvenirsSnapshot.docs) {
      final data = doc.data();
      final date = DateFormat('dd/MM').format((data['date'] as Timestamp).toDate());
      final qualite = data['qualite'] ?? 'N/A'; // Assuming 'qualite' is a string or an enum label
      final noteQualite = data['noteQualite'] ?? 'N/A'; // Assuming numerical quality
      final text = data['texte'] ?? 'Aucun texte';
      entries.add("Souvenir du $date (Qualité: $qualite, Note: $noteQualite): $text");
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
        body: SafeArea( // <--- AJOUTEZ LE WIDGET SAFEAEREA ICI
        child: _isLoading
        ? _buildLoadingIndicator()
        : Column(
    children: <Widget>[
          // Fixed header with month name, average rating and days of week
          Container(
            color: _backgroundColor,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('MMMM yyyy', 'fr').format(_currentDisplayedMonth),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _textColor,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isIAActive ? Icons.analytics : Icons.analytics_outlined,
                        color: _isIAActive ? Colors.blue : _textColor,
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
                    ),
                  ),
                _buildDaysOfWeek(),
              ],
            ),
          ),

          // Scrollable calendar area
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _monthsToDisplay.length,
              itemBuilder: (context, index) {
                return _buildMonthCalendar(_monthsToDisplay[index]);
              },
              // Smooth scrolling physics
              physics: const BouncingScrollPhysics(),
            ),
          ),
        ],
      ),
        )
    );
  }

  Widget _buildMonthCalendar(DateTime monthDate) {
    int daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    int firstDayOfMonth = DateTime(monthDate.year, monthDate.month, 1).weekday;

    // Adjust firstDayOfMonth for Monday being 1
    int firstDayAdjusted = (firstDayOfMonth == 7) ? 0 : firstDayOfMonth; // 0 for Sunday, 1 for Monday, etc.

    // Calculate number of weeks needed for this month
    int totalDays = firstDayAdjusted + daysInMonth;
    int numberOfWeeks = (totalDays / 7).ceil();

    List<Widget> weekRows = [];

    for (int week = 0; week < numberOfWeeks; week++) {
      List<Widget> dayWidgets = [];

      for (int weekday = 0; weekday < 7; weekday++) {
        int dayNumber = week * 7 + weekday - firstDayAdjusted + 1;

        if (dayNumber <= 0 || dayNumber > daysInMonth) {
          // --- CORRECTION 1 : Envelopper l'espace vide dans Expanded ---
          dayWidgets.add(Expanded(child: const SizedBox(height: 48.0)));
          continue;
        }

        DateTime currentDay = DateTime(monthDate.year, monthDate.month, dayNumber);
        bool isToday = currentDay.year == DateTime.now().year &&
            currentDay.month == DateTime.now().month &&
            currentDay.day == DateTime.now().day;
        bool hasMemories = _datesWithMemories.contains(currentDay);

        dayWidgets.add(
          Expanded( // <--- AJOUTEZ CECI
            child: GestureDetector(
            onTap: () {
              if (hasMemories) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DayDetailsPage(selectedDay: currentDay),
                  ),
                );
              }
            },
              child: Container(
                margin: const EdgeInsets.all(4.0),
                // Vous pouvez maintenant retirer la largeur fixe, car Expanded s'en occupe
                // width: 48.0,  <--- SUPPRIMEZ OU COMENTEZ CETTE LIGNE
                height: 48.0,
                decoration: BoxDecoration(
                color: hasMemories
                    ? (Theme.of(context).brightness == Brightness.dark ? Colors.blue.shade700 : const Color.fromARGB(255, 0, 195, 255))
                    : (isToday ? (Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade700 : Colors.white) : Colors.transparent),
                borderRadius: BorderRadius.circular(isToday ? 24.0 : 8.0),
                border: isToday && !hasMemories
                    ? Border.all(color: (Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade400 : Colors.blue.shade700), width: 2)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '$dayNumber',
                style: TextStyle(
                  fontSize: 18,
                  color: hasMemories ? Colors.white :
                  isToday ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black) : _textColor,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            )
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
            _updateAverageRatingDisplay();
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          children: [
            // Month name for each calendar
            Text(
              DateFormat('MMMM yyyy', 'fr').format(monthDate),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textColor,
              ),
            ),
            // Week rows
            ...weekRows,
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: CircularProgressIndicator(
        color: _textColor,
      ),
    );
  }

  Widget _buildDaysOfWeek() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _daysOfWeek.map((day) {
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

class DayDetailsPage extends StatefulWidget {
  final DateTime selectedDay;

  const DayDetailsPage({super.key, required this.selectedDay});

  @override
  _DayDetailsPageState createState() => _DayDetailsPageState();
}

class _DayDetailsPageState extends State<DayDetailsPage> {
  List<Map<String, dynamic>> _dayMemories = [];
  bool isIAAnalysisActive = false; // État pour l'activation de l'IA
  Color _backgroundColor = Colors.black;
  Color _textColor = Colors.white;
  Color _cardBackgroundColor = Colors.grey.shade900;
  Color _cardTextColor = Colors.white;

  // Clé API utilisée pour la similarité
  static const String DEEPSEEK_API_KEY = 'sk-2891f44dd4e344908dda525bf5852649';


  @override
  void initState() {
    super.initState();
    _loadThemePreferences();
    _loadDayMemories();
  }

  Future<void> _loadThemePreferences() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      // On met 'system' par défaut si rien n'est sauvegardé
      String themeMode = prefs.getString('themeMode') ?? 'system';

      Brightness finalBrightness;

      if (themeMode == 'dark') {
        finalBrightness = Brightness.dark;
      } else if (themeMode == 'light') {
        finalBrightness = Brightness.light;
      } else { // Cas 'system'
        // On demande au système quel est le thème actuel
        finalBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      }

      // On met à jour les couleurs en fonction du thème final
      if (mounted) {
        setState(() {
          if (finalBrightness == Brightness.dark) {
            _backgroundColor = Colors.black;
            _textColor = Colors.white;
            _cardBackgroundColor = Colors.grey.shade800;
            _cardTextColor = Colors.white;
          } else { // Light mode
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
    User? currentUser  = FirebaseAuth.instance.currentUser ;
    if (currentUser  == null) return;

    try {
      // Récupérer les journées
      QuerySnapshot journeesSnapshot = await FirebaseFirestore.instance
          .collection('journees')
          .where('userId', isEqualTo: currentUser .uid)
          .get();

      // Récupérer les souvenirs
      QuerySnapshot souvenirsSnapshot = await FirebaseFirestore.instance
          .collection('souvenirs')
          .where('userId', isEqualTo: currentUser .uid)
          .get();

      // Transformer les documents en liste de mémoires
      List<Map<String, dynamic>> memories = [];

      // Filtrer les journées par date côté Dart
      memories.addAll(journeesSnapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        DateTime docDate = (data['date'] as Timestamp).toDate();

        // Vérifier si la date correspond au jour sélectionné
        if (docDate.year == widget.selectedDay.year &&
            docDate.month == widget.selectedDay.month &&
            docDate.day == widget.selectedDay.day) {
          return {
            'type': 'journee',
            'id': doc.id,
            'texte': data['texte1'] ?? data['texte'],
            'date': docDate,
            'estPublic': data['estPublic'] ?? false,
            'emoji': data['emoji'],
            'note': data['note'],
            'motsCles': data['motsCles'] ?? [],
          };
        }
        return null;
      }).whereType<Map<String, dynamic>>());

      // Faire de même pour les souvenirs
      memories.addAll(souvenirsSnapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        DateTime docDate = (data['date'] as Timestamp).toDate();

        // Vérifier si la date correspond au jour sélectionné
        if (docDate.year == widget.selectedDay.year &&
            docDate.month == widget.selectedDay.month &&
            docDate.day == widget.selectedDay.day) {
          return {
            'type': 'souvenir',
            'id': doc.id,
            'texte': data['texte'],
            'date': docDate,
            'estPublic': data['estPublic'] ?? false,
            'qualite': data['qualite'],
            'noteQualite': data['noteQualite'],
            'photoUrls': data['photoUrls'] ?? [],
            'isRepost': data['isRepost'] ?? false,
            'repostedFromUserId': data['repostedFromUserId'],
            'repostedFromUserName': data['repostedFromUserName'],
          };
        }
        return null;
      }).whereType<Map<String, dynamic>>());

      // Trier les mémoires par date
      memories.sort((a, b) => b['date'].compareTo(a['date']));

      setState(() {
        _dayMemories = memories;
      });
    } catch (e) {
      print('Erreur détaillée lors du chargement des mémoires : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de chargement : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor, // Apply background color
      appBar: AppBar(
        title: Text(
          'Souvenirs du ${DateFormat('dd/MM/yyyy').format(widget.selectedDay)}',
          style: TextStyle(color: _textColor), // Apply text color
        ),
        centerTitle: true,
        backgroundColor: _backgroundColor, // Apply app bar background color
        iconTheme: IconThemeData(color: _textColor), // Apply icon color
      ),
      body: _dayMemories.isEmpty ? _buildEmptyState() : ListView.builder(
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
          Icon(
            Icons.memory,
            size: 100,
            color: _textColor.withOpacity(0.5), // Use textColor with opacity
          ),
          const SizedBox(height: 20),
          Text(
            'Aucun souvenir pour cette date',
            style: TextStyle(
              color: _textColor.withOpacity(0.7), // Use textColor with opacity
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(Map<String, dynamic> memory) {
    // --- NOUVEAU : GESTUREDETECTOR ---
    return GestureDetector(
      onLongPress: memory['type'] == 'journee'
          ? () {
        // Reconstruire un objet JourneeModel pour le passer au pop-up
        final journee = JourneeModel(
          id: memory['id'],
          texte1: memory['texte'],
          date: memory['date'],
          estPublic: memory['estPublic'],
          emoji: memory['emoji'],
          note: memory['note'],
          motsCles: List<String>.from(memory['motsCles'] ?? []),
          userId: FirebaseAuth.instance.currentUser?.uid,
        );
        _showPopupCard(context, journee); // Appeler le nouveau pop-up
      }
          : null, // Pas d'action pour les souvenirs
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 4,
        color: _cardBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
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
                      color: _textColor,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: _textColor),
                    onSelected: (action) => _handleMemoryAction(memory, action),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                      const PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                memory['texte'],
                style: TextStyle(fontSize: 15, color: _cardTextColor),
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('dd MMMM yyyy HH:mm', 'fr').format(memory['date']),
                style: TextStyle(fontSize: 12, color: _cardTextColor.withOpacity(0.7)),
              ),
              const SizedBox(height: 8),

              if (memory['type'] == 'journee' && memory['note'] != null)
                Row(
                  children: [
                    Icon(Icons.star, size: 16, color: _getNoteColor(memory['note'])),
                    const SizedBox(width: 5),
                    Text(
                      'Note: ${memory['note']}',
                      style: TextStyle(color: _getNoteColor(memory['note'])),
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
              else if (memory['type'] == 'souvenir' && memory['qualite'] != null)
                Row(
                  children: [
                    _getQualiteChip(memory['qualite']),
                    const SizedBox(width: 10),
                    Text(
                      'Note: ${memory['noteQualite'] ?? 'N/A'}',
                      style: TextStyle(color: _cardTextColor),
                    ),
                  ],
                ),

              const Divider(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        memory['estPublic'] ? Icons.public : Icons.lock_outline,
                        size: 16,
                        color: memory['estPublic'] ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        memory['estPublic'] ? 'Public' : 'Privé',
                        style: TextStyle(
                          color: memory['estPublic'] ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  // --- SUPPRESSION : Le bouton "Similaires" a été retiré ---
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- NOUVEAU : Copié et adapté depuis MovingJourneeCard ---
  void _showPopupCard(BuildContext context, JourneeModel journee) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: ScaleTransition(
              scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.7,
                margin: const EdgeInsets.all(16),
                child: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [ Colors.blue.shade100, Colors.white, ],
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                            child: StatefulBuilder(
                              builder: (BuildContext context, StateSetter setDialogState) {
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
                                  final lastSearchTimestamp = data?['lastSimilaritySearchDate'] as Timestamp?;

                                  if (lastSearchTimestamp != null) {
                                    lastSearchDate = lastSearchTimestamp.toDate();
                                  }

                                  if (cache != null && cache.isNotEmpty) {
                                    hasResultsInCache = true;
                                    final futures = cache.entries.map((entry) async {
                                      final journeeDoc = await FirebaseFirestore.instance
                                          .collection('journees')
                                          .doc(entry.key)
                                          .get();
                                      if (journeeDoc.exists) {
                                        return MapEntry(
                                          JourneeModel.fromFirestore(journeeDoc),
                                          (entry.value as num).toDouble(),
                                        );
                                      }
                                      return null;
                                    }).toList();

                                    final results = (await Future.wait(futures)).whereType<MapEntry<JourneeModel, double>>().toList();
                                    results.sort((a,b) => b.value.compareTo(a.value));
                                    displayedSimilarities = results;
                                  }
                                }

                                Future<void> handleSearch() async {
                                  setDialogState(() {
                                    isSearching = true;
                                    searchError = null;
                                  });

                                  try {
                                    final results = await _findSimilarJournees(journee, searchAfter: lastSearchDate);

                                    await FirebaseFirestore.instance.collection('journees').doc(journee.id).set({
                                      'similarJourneesCache': results.map((key, value) => MapEntry(key.id!, value)),
                                      'lastSimilaritySearchDate': FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));

                                    setDialogState(() {
                                      displayedSimilarities = results.entries.toList();
                                      hasResultsInCache = results.isNotEmpty;
                                      lastSearchDate = DateTime.now();
                                    });

                                  } catch (e) {
                                    setDialogState(() { searchError = "Erreur: ${e.toString()}"; });
                                  } finally {
                                    setDialogState(() { isSearching = false; });
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
                                          Text(
                                              DateFormat('EEEE d MMMM yyyy').format(journee.date),
                                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)
                                          ),
                                          const SizedBox(height: 12),
                                          Text(journee.texte1 ?? 'Aucune description', style: const TextStyle(fontSize: 16, color: Colors.black87, height: 1.4)),
                                          const SizedBox(height: 16),
                                          const Divider(height: 32),
                                          if (searchError != null)
                                            Center(child: Text(searchError!, style: const TextStyle(color: Colors.red)))
                                          else if (displayedSimilarities != null && displayedSimilarities!.isNotEmpty)
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Journées similaires', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                                                const SizedBox(height: 8),
                                                ...displayedSimilarities!.map((entry) {
                                                  return Card(
                                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                                    child: ListTile(
                                                      title: Text(DateFormat('d MMMM yyyy').format(entry.key.date)),
                                                      subtitle: Text(entry.key.texte1 ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                                                      trailing: Text('${entry.value.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                                                    ),
                                                  );
                                                }).toList(),
                                              ],
                                            )
                                          else if (lastSearchDate != null && !hasResultsInCache)
                                              const Center(
                                                child: Padding(
                                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                                  child: Text(
                                                    "Aucune journée similaire n'a été trouvée.",
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                                                  ),
                                                ),
                                              ),
                                          const SizedBox(height: 20),
                                          Center(
                                            child: isSearching
                                                ? const CircularProgressIndicator()
                                                : ElevatedButton.icon(
                                              icon: Icon(hasResultsInCache ? Icons.sync : Icons.search),
                                              label: Text(hasResultsInCache ? 'Mettre à jour' : 'Rechercher'),
                                              onPressed: handleSearch,
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                        ],
                                      );
                                    }
                                );
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Fermer'),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  // --- NOUVEAU : Copié et adapté depuis MovingJourneeCard ---
  Future<Map<JourneeModel, double>> _findSimilarJournees(
      JourneeModel selectedJournee, {DateTime? searchAfter}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    final selectedText = selectedJournee.texte1 ?? selectedJournee.commentaire ?? '';
    if (selectedText.trim().isEmpty) return {};

    Query journeesQuery = FirebaseFirestore.instance
        .collection('journees')
        .where('userId', isEqualTo: user.uid)
        .where('id', isNotEqualTo: selectedJournee.id);

    if (searchAfter != null) {
      journeesQuery = journeesQuery.where('date', isGreaterThan: Timestamp.fromDate(searchAfter));
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
          }));
    }

    final results = await Future.wait(similarJourneesFutures);
    final similarJournees = <JourneeModel, double>{};
    for (var result in results) {
      if (result != null) {
        similarJournees[result.key] = result.value;
      }
    }

    final sortedEntries = similarJournees.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Map.fromEntries(sortedEntries.take(5));
  }

  // --- NOUVEAU : Copié et adapté depuis MovingJourneeCard ---
  Future<double> _calculateSimilarity(String text1, String text2) async {
    if (text1.isEmpty || text2.isEmpty) {
      return 0.0;
    }
    const url = 'https://api.deepseek.com/v1/chat/completions';
    try {
      final response = await http.post(Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $DEEPSEEK_API_KEY'
          },
          body: jsonEncode({
            'model': 'deepseek-chat',
            'messages': [
              {
                'role': 'user',
                'content':
                '''Compare sémantiquement les deux textes suivants. Donne un pourcentage de similarité basé sur le contenu, le ton et les thèmes.
                  Réponds UNIQUEMENT avec un nombre entier entre 0 et 100 suivi de "/100". Exemple : "75/100".

                  Texte 1: "$text1"
                  Texte 2: "$text2"'''
              }
            ],
            'max_tokens': 10,
            'temperature': 0.1,
          }));

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
        print('DeepSeek API error for similarity: ${response.statusCode} - ${response.body}');
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
        builder: (context) => JourneePage(
          journeeToEdit: journee,
        ),
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
    final String collection = memory['type'] == 'journee' ? 'journees' : 'souvenirs';
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
          );
          wasModified = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (context) => JourneePage(journeeToEdit: journee)),
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
            MaterialPageRoute(builder: (context) => SouvenirPage(souvenirToEdit: souvenir)),
          );
        }

        if (wasModified == true) {
          await FirebaseFirestore.instance.collection(collection).doc(docId).set({
            'dateDerniereModif': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          _loadDayMemories();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vous avez déjà modifié cet élément aujourd\'hui.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (action == 'supprimer') {
      try {
        await FirebaseFirestore.instance.collection(collection).doc(docId).delete();
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
  Color _getNoteColor(String note) {
    try {
      int noteValue;
      if (note.contains('/')) {
        noteValue = int.parse(note.split('/').first);
      } else {
        noteValue = int.parse(note);
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
        style: TextStyle(
          color: chipColor,
          fontSize: 12,
        ),
      ),
    );
  }
}