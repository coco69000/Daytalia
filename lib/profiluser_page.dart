import 'dart:math';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shake/shake.dart';
import 'souvenir_model.dart';
import 'journee_model.dart';

// Modèles pour la clarté des pop-ups
class Souvenir {
  final String id;
  final String texte;
  final DateTime date;
  final List<String> photoUrls;
  final String shape;
  final String color;

  Souvenir({
    required this.id,
    required this.texte,
    required this.date,
    required this.photoUrls,
    this.shape = 'carrer',
    this.color = 'bleu',
  });

  factory Souvenir.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    final Timestamp? dateTimestamp = data['date'] as Timestamp?;

    return Souvenir(
      id: doc.id,
      texte: data['texte'] ?? 'Souvenir sans texte',
      date: dateTimestamp?.toDate() ?? DateTime.now(),
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
    );
  }
}

class PinnedItemState {
  final Map<String, dynamic> data;
  final int originalIndex;
  bool isFloating;

  PinnedItemState({
    required this.data,
    required this.originalIndex,
    this.isFloating = false,
  });
}

class ProfileUserPage extends StatefulWidget {
  final String userId;
  const ProfileUserPage({super.key, required this.userId});

  @override
  _ProfileUserPageState createState() => _ProfileUserPageState();
}

class _ProfileUserPageState extends State<ProfileUserPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  late Future<Map<String, dynamic>> _profileDataFuture;
  late ShakeDetector _shakeDetector;

  List<Souvenir> _allSouvenirs = [];
  List<Souvenir> _displayedSouvenirs = [];
  List<Souvenir> _hiddenSouvenirs = [];
  final int _maxFloatingSouvenirs = 100;
  Map<String, double> _souvenirZOrders = {};

  List<PinnedItemState> _pinnedJourneesState = [];
  List<PinnedItemState> _pinnedSouvenirsState = [];
  bool _arePinsFloating = false;

  bool _isFideliteActive = false;
  bool _isAutobiographieVisible = false;
  bool _isDarkMode = false;
  bool _profileCardBlurEnabled = false;

  // --- DÉBUT : NOUVELLES VARIABLES D'ÉTAT POUR LES LIKES ---
  final Random _random = Random();
  int _likeCount = 0;
  Offset _heartPosition = const Offset(50, 150);
  int _heartClickCount = 0;
  int _requiredHeartClicks = 1;
  int _spamWarningCount = 0;
  bool _likesBlocked = false;
  Color _heartColor = Colors.red;
  double _heartSize = 40.0;
  // --- FIN : NOUVELLES VARIABLES D'ÉTAT POUR LES LIKES ---

  // --- DÉBUT : NOUVELLES VARIABLES POUR LES AMIS ---
  int _friendCount = 0;
  int _mutualFriendsCount = 0;
  List<String> _currentUserFriends = [];
  // --- FIN : NOUVELLES VARIABLES POUR LES AMIS ---

  @override
  void initState() {
    super.initState();
    _loadThemeAndPreferences();
    _profileDataFuture = _loadProfileData();

    // Initialise le nombre de clics requis pour le premier cœur
    _requiredHeartClicks = _random.nextInt(10) + 1;

    _shakeDetector = ShakeDetector.autoStart(
      onPhoneShake: _togglePinnedItemsState,
      shakeThresholdGravity: 1.9,
    );
  }

  @override
  void dispose() {
    _shakeDetector.stopListening();
    super.dispose();
  }

  void _togglePinnedItemsState(ShakeEvent event) {
    if (!mounted) return;
    setState(() {
      _arePinsFloating = !_arePinsFloating;
      for (var item in _pinnedJourneesState) {
        if (item.data.isNotEmpty) item.isFloating = _arePinsFloating;
      }
      for (var item in _pinnedSouvenirsState) {
        if (item.data.isNotEmpty) item.isFloating = _arePinsFloating;
      }
    });
  }

  Future<void> _loadThemeAndPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeMode = prefs.getString('themeMode') ?? 'system';
      if (mounted) {
        setState(() {
          if (themeMode == 'dark') {
            _isDarkMode = true;
          } else if (themeMode == 'light') {
            _isDarkMode = false;
          } else {
            _isDarkMode =
                WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark;
          }
          _profileCardBlurEnabled =
              prefs.getBool('profileCardBlurEnabled') ?? false;
        });
      }
    } catch (e) {
      print("Erreur de chargement du thème: $e");
    }
  }

  Future<Map<String, dynamic>> _loadProfileData() async {
    try {
      final userDataDoc =
          await _firestore.collection('users').doc(widget.userId).get();
      if (!userDataDoc.exists) {
        throw Exception("L'utilisateur n'existe pas.");
      }
      final data = userDataDoc.data() as Map<String, dynamic>;

      // --- DÉBUT : CHARGEMENT DES DONNÉES D'AMIS ---
      final List<String> profileUserFriends = List<String>.from(
        data['friends'] ?? [],
      );
      if (currentUser != null && currentUser!.uid != widget.userId) {
        final currentUserDoc =
            await _firestore.collection('users').doc(currentUser!.uid).get();
        _currentUserFriends = List<String>.from(
          currentUserDoc.data()?['friends'] ?? [],
        );
      }
      final mutualFriends =
          profileUserFriends
              .where((friendId) => _currentUserFriends.contains(friendId))
              .toSet();
      // --- FIN : CHARGEMENT DES DONNÉES D'AMIS ---

      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final endOfToday = startOfToday.add(const Duration(days: 1));

      final todaysJourneeQuery =
          await _firestore
              .collection('journees')
              .where('userId', isEqualTo: widget.userId)
              .where('date', isGreaterThanOrEqualTo: startOfToday)
              .where('date', isLessThan: endOfToday)
              .limit(1)
              .get();

      final souvenirsQuery =
          await _firestore
              .collection('souvenirs')
              .where('userId', isEqualTo: widget.userId)
              .where('estPublic', isEqualTo: true)
              .get();

      List<Souvenir> allSouvenirs =
          souvenirsQuery.docs
              .map((doc) => Souvenir.fromFirestore(doc))
              .toList();

      if (mounted) {
        _allSouvenirs = allSouvenirs;
        _allSouvenirs.shuffle();

        final int pinCount = (data['isVip'] ?? false) ? 7 : 3;

        final List<dynamic> pinnedJourneesRaw = data['pinnedJournees'] ?? [];
        _pinnedJourneesState = List.generate(
          pinCount,
          (index) => PinnedItemState(
            data:
                index < pinnedJourneesRaw.length &&
                        pinnedJourneesRaw[index] != null
                    ? Map<String, dynamic>.from(pinnedJourneesRaw[index])
                    : {},
            originalIndex: index,
          ),
        );

        final List<dynamic> pinnedSouvenirsRaw = data['pinnedSouvenirs'] ?? [];
        _pinnedSouvenirsState = List.generate(
          pinCount,
          (index) => PinnedItemState(
            data:
                index < pinnedSouvenirsRaw.length &&
                        pinnedSouvenirsRaw[index] != null
                    ? Map<String, dynamic>.from(pinnedSouvenirsRaw[index])
                    : {},
            originalIndex: index,
          ),
        );

        final bool blurEnabledFromFirestore =
            data['profileCardBlurEnabled'] ?? false;

        setState(() {
          _likeCount = data['likeCount'] ?? 0;
          _friendCount = profileUserFriends.length;
          _mutualFriendsCount = mutualFriends.length;
          _displayedSouvenirs =
              _allSouvenirs.take(_maxFloatingSouvenirs).toList();
          _hiddenSouvenirs = _allSouvenirs.skip(_maxFloatingSouvenirs).toList();
          _souvenirZOrders.clear();
          for (var i = 0; i < _displayedSouvenirs.length; i++) {
            _souvenirZOrders[_displayedSouvenirs[i].id] = i.toDouble();
          }
          _isFideliteActive = data['isTruthAdjustmentActive'] ?? false;
          _profileCardBlurEnabled = blurEnabledFromFirestore;
        });
      }

      return {
        'userData': userDataDoc,
        'todaysJournee':
            todaysJourneeQuery.docs.isNotEmpty
                ? todaysJourneeQuery.docs.first
                : null,
      };
    } catch (e, stacktrace) {
      print("!!!!!! ERREUR FATALE DANS _loadProfileData !!!!!!");
      print(e);
      print(stacktrace);
      rethrow;
    }
  }

  // --- DÉBUT : NOUVELLES FONCTIONS POUR LES LIKES ---

  void _giveLike() {
    if (_likesBlocked || widget.userId == currentUser?.uid) return;

    final likerId = currentUser!.uid;
    final likerRef = _firestore
        .collection('users')
        .doc(widget.userId)
        .collection('likes')
        .doc(likerId);

    _firestore.runTransaction((transaction) async {
      final likerDoc = await transaction.get(likerRef);
      if (!likerDoc.exists) {
        transaction.set(likerRef, {
          'count': 1,
          'username': currentUser!.displayName ?? 'Utilisateur Anonyme',
        });
      } else {
        transaction.update(likerRef, {'count': FieldValue.increment(1)});
      }
      transaction.update(_firestore.collection('users').doc(widget.userId), {
        'likeCount': FieldValue.increment(1),
      });
    });

    setState(() {
      _heartClickCount++;
      _likeCount++;

      if (_heartClickCount >= _requiredHeartClicks) {
        _heartClickCount = 0;
        _requiredHeartClicks = _random.nextInt(10) + 1;
        final size = MediaQuery.of(context).size;
        final newX = _random.nextDouble() * (size.width - 50);
        final newY = _random.nextDouble() * (size.height - 150) + 100;
        _heartPosition = Offset(newX, newY);

        _heartSize = 30.0 + _random.nextDouble() * 30.0;
        const heartColors = [
          Colors.red,
          Colors.pink,
          Colors.purple,
          Colors.redAccent,
          Colors.deepPurpleAccent,
        ];
        _heartColor = heartColors[_random.nextInt(heartColors.length)];
      }
    });
  }

  void _handleSpamClick() {
    if (_likesBlocked) return;

    setState(() {
      _spamWarningCount++;
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (_spamWarningCount >= 3) {
      setState(() {
        _likesBlocked = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Likes bloqués en raison du spam.'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Avertissement de spam (${_spamWarningCount}/3). Veuillez cliquer sur le cœur.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _showLikesPopup() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final likersSnapshot =
          await _firestore
              .collection('users')
              .doc(widget.userId)
              .collection('likes')
              .orderBy('count', descending: true)
              .limit(100)
              .get();

      Navigator.of(context).pop();

      if (!mounted) return;

      final likers = await Future.wait(
        likersSnapshot.docs.map((doc) async {
          final userDoc =
              await _firestore.collection('users').doc(doc.id).get();
          final userData = userDoc.data() as Map<String, dynamic>?;
          final username = userData?['username'] ?? doc.data()['username'];

          return {
            'id': doc.id,
            'username': username ?? 'Utilisateur inconnu',
            'count': doc.data()['count'] ?? 0,
          };
        }),
      );

      showDialog(
        context: context,
        builder: (context) {
          final isDarkMode = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
            title: const Text('Personnes qui ont aimé ce profil'),
            content: SizedBox(
              width: double.maxFinite,
              child:
                  likers.isEmpty
                      ? const Center(
                        child: Text("Personne n'a encore aimé ce profil."),
                      )
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: likers.length,
                        itemBuilder: (context, index) {
                          final liker = likers[index];
                          final bool isFriend = _currentUserFriends.contains(
                            liker['id'],
                          );

                          return ListTile(
                            title: Text(liker['username'].toString()),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isFriend)
                                  const Icon(
                                    CupertinoIcons.person_2_fill,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.favorite,
                                  color: Colors.pink,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  liker['count'].toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
            ),
            actions: [
              TextButton(
                child: const Text('Fermer'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors du chargement des likes: $e")),
        );
      }
    }
  }
  // --- FIN : NOUVELLES FONCTIONS POUR LES LIKES ---

  void _sendSouvenirToBack(Souvenir souvenir) {
    if (_souvenirZOrders.isEmpty) return;
    final minZ = _souvenirZOrders.values.reduce((a, b) => a < b ? a : b);
    setState(() {
      _souvenirZOrders[souvenir.id] = minZ - 1;
    });
  }

  void _handleSouvenirReplacement(Souvenir oldSouvenir) {
    if (!mounted || _hiddenSouvenirs.isEmpty) return;
    setState(() {
      final oldIndex = _displayedSouvenirs.indexWhere(
        (s) => s.id == oldSouvenir.id,
      );
      if (oldIndex != -1) {
        final newSouvenir = _hiddenSouvenirs.removeAt(0);
        final oldZOrder = _souvenirZOrders[oldSouvenir.id] ?? 0.0;
        _souvenirZOrders.remove(oldSouvenir.id);
        _souvenirZOrders[newSouvenir.id] = oldZOrder;
        _displayedSouvenirs[oldIndex] = newSouvenir;
        _hiddenSouvenirs.add(oldSouvenir);
      }
    });
  }

  List<Souvenir> _getSortedSouvenirs() {
    final sortedList = List<Souvenir>.from(_displayedSouvenirs);
    sortedList.sort((a, b) {
      final zA = _souvenirZOrders[a.id] ?? 0.0;
      final zB = _souvenirZOrders[b.id] ?? 0.0;
      return zA.compareTo(zB);
    });
    return sortedList;
  }

  Future<void> _toggleFidelite(bool newValue) async {
    if (currentUser?.uid != widget.userId) return;

    setState(() {
      _isFideliteActive = newValue;
    });

    try {
      await _firestore.collection('users').doc(widget.userId).update({
        'isTruthAdjustmentActive': newValue,
      });
    } catch (e) {
      setState(() {
        _isFideliteActive = !newValue;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors de la mise à jour: $e")),
        );
      }
    }
  }

  // --- DEBUT DES FONCTIONS POUR LE POP-UP ---

  String _getImagePath(String design, String color) {
    return 'assets/${design}_${color}.png';
  }

  Color _getQualiteColor(String qualite) {
    switch (qualite) {
      case 'incroyable':
        return Colors.amber;
      case 'bonne':
        return Colors.green;
      case 'normale':
        return Colors.blue;
      case 'difficile':
        return Colors.orange;
      case 'horrible':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getQualiteLabel(String qualite) {
    if (qualite.isEmpty) return 'N/A';
    return qualite[0].toUpperCase() + qualite.substring(1);
  }

  void _showPopupCardSouvenir(
    BuildContext context,
    SouvenirModel souvenir,
    String design,
    String color,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        final bool isSpecialShape = [
          'coeur',
          'etoile',
          'rond',
        ].contains(design);
        final double paddingValue = isSpecialShape ? 50.0 : 40.0;
        final String qualiteAsString = souvenir.qualite.name;

        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Material(
            color: Colors.transparent,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Center(
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: GestureDetector(
                    onTap:
                        () {}, // Empêche la propagation du tap vers le parent
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.65,
                      height: MediaQuery.of(context).size.width * 0.65,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: Image.asset(
                              _getImagePath(design, color),
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (context, error, stackTrace) => Container(
                                    color: Colors.white,
                                    child: const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                    ),
                                  ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(paddingValue),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (souvenir.isRepost)
                                    Text(
                                      'Republié de ${souvenir.repostedFromUserName ?? 'un ami'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  Text(
                                    souvenir.texte,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: <Shadow>[
                                        Shadow(
                                          offset: Offset(1.5, 1.5),
                                          blurRadius: 3.0,
                                          color: Colors.black87,
                                        ),
                                        Shadow(
                                          offset: Offset(-1.5, -1.5),
                                          blurRadius: 3.0,
                                          color: Colors.black87,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (souvenir.photoUrls.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        souvenir.photoUrls.first,
                                        height: 100,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Chip(
                                    label: Text(
                                      'Qualité: ${_getQualiteLabel(qualiteAsString)}',
                                      style: TextStyle(
                                        color: _getQualiteColor(
                                          qualiteAsString,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    backgroundColor: _getQualiteColor(
                                      qualiteAsString,
                                    ).withOpacity(0.15),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Note: ${souvenir.noteQualite}/100',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
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

  void _showPopupCardJournee(
    BuildContext context,
    JourneeModel journee,
    String design,
    String color,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        final bool isSpecialShape = [
          'coeur',
          'etoile',
          'rond',
        ].contains(design);
        final double paddingValue = isSpecialShape ? 50.0 : 40.0;

        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Material(
            color: Colors.transparent,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Center(
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: GestureDetector(
                    onTap:
                        () {}, // Empêche la propagation du tap vers le parent
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.65,
                      height: MediaQuery.of(context).size.width * 0.65,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: Image.asset(
                              _getImagePath(design, color),
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (context, error, stackTrace) => Container(
                                    color: Colors.white,
                                    child: const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                    ),
                                  ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(paddingValue),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    journee.emoji ?? '🤔',
                                    style: const TextStyle(fontSize: 40),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    journee.texte1 ?? 'Aucun texte',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: <Shadow>[
                                        Shadow(
                                          offset: Offset(1.5, 1.5),
                                          blurRadius: 3.0,
                                          color: Colors.black87,
                                        ),
                                        Shadow(
                                          offset: Offset(-1.5, -1.5),
                                          blurRadius: 3.0,
                                          color: Colors.black87,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Chip(
                                    label: Text(
                                      'Qualité: ${_getQualiteLabel(journee.qualite)}',
                                      style: TextStyle(
                                        color: _getQualiteColor(
                                          journee.qualite,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    backgroundColor: _getQualiteColor(
                                      journee.qualite,
                                    ).withOpacity(0.15),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Note: ${journee.note}/100',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
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

  Future<void> _onPinTapped(
    Map<String, dynamic> pinData,
    String itemType,
  ) async {
    final String? docId = pinData['id'];
    if (docId == null || !mounted) return;

    final currentContext = context;
    showDialog(
      context: currentContext,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final DocumentSnapshot doc =
          await (itemType == 'souvenir'
              ? _firestore.collection('souvenirs').doc(docId).get()
              : _firestore.collection('journees').doc(docId).get());

      if (!mounted) return;
      Navigator.of(currentContext).pop(); // Ferme le loader

      if (!doc.exists) throw Exception("$itemType introuvable");

      final Map<String, dynamic> data =
          doc.data() as Map<String, dynamic>? ?? {};
      final String texte =
          (itemType == 'souvenir'
                  ? (data['texte'] ?? '')
                  : (data['texte1'] ?? data['texte'] ?? ''))
              as String;
      final String? emoji = data['emoji'] as String?;
      final List<dynamic> photos = data['photoUrls'] ?? [];

      showDialog(
        context: currentContext,
        builder: (ctx) {
          final bool isDarkMode = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDarkMode ? Colors.grey.shade900 : Colors.white,
            title: Text(
              itemType == 'souvenir' ? 'Souvenir' : 'Journée',
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (emoji != null)
                      Text(emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 8),
                    Text(
                      texte,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    if (photos.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: photos.length,
                          itemBuilder:
                              (_, i) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    photos[i].toString(),
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(currentContext).pop();
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text("Erreur: Impossible de charger les détails ($e)."),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = _isDarkMode ? Colors.black : Colors.white;
    final cardColor = _isDarkMode ? Colors.grey[900]! : Colors.white;
    final textColor = _isDarkMode ? Colors.white : Colors.black87;
    final hintColor = _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: true,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(
              child: Text("Impossible de charger le profil."),
            );
          }

          final DocumentSnapshot? userDataDoc = snapshot.data!['userData'];
          if (userDataDoc == null || !userDataDoc.exists) {
            return const Center(child: Text("Cet utilisateur n'existe pas."));
          }

          final userData = userDataDoc.data() as Map<String, dynamic>;
          final DocumentSnapshot? todaysJournee =
              snapshot.data!['todaysJournee'];

          return GestureDetector(
            onTap: _handleSpamClick,
            child: Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: Text(
                  userData['username'] ?? 'Profil',
                  style: TextStyle(color: textColor),
                ),
                backgroundColor: backgroundColor.withOpacity(0.5),
                elevation: 0,
                iconTheme: IconThemeData(color: textColor),
                flexibleSpace: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                actions: [_buildAppBarMenu(userData)],
              ),
              body: Stack(
                children: [
                  ..._getSortedSouvenirs().map((souvenir) {
                    return FloatingSouvenirCard(
                      key: ValueKey(souvenir.id),
                      souvenir: souvenir,
                      blurBackground: _profileCardBlurEnabled,
                      onNeedsReplacement:
                          () => _handleSouvenirReplacement(souvenir),
                      onSendToBack: () => _sendSouvenirToBack(souvenir),
                    );
                  }),
                  RefreshIndicator(
                    onRefresh: () async {
                      setState(() {
                        _profileDataFuture = _loadProfileData();
                      });
                    },
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.of(context).padding.top +
                            kToolbarHeight +
                            16,
                        16,
                        16,
                      ),
                      children: [
                        _buildHeader(userData, theme, textColor, hintColor),
                        const SizedBox(height: 24),
                        _buildAutobiographieContainer(
                          userData,
                          theme,
                          cardColor,
                          textColor,
                          hintColor,
                        ),
                        _buildPinnedSection(
                          title: 'Journées Épinglées',
                          pinnedItemsState: _pinnedJourneesState,
                          itemType: 'journee',
                          theme: theme,
                          textColor: textColor,
                        ),
                        _buildPinnedSection(
                          title: 'Souvenirs Épinglés',
                          pinnedItemsState: _pinnedSouvenirsState,
                          itemType: 'souvenir',
                          theme: theme,
                          textColor: textColor,
                        ),
                        _buildTodayJourneeSection(
                          todaysJournee,
                          theme,
                          textColor,
                          cardColor,
                          hintColor,
                        ),
                      ],
                    ),
                  ),
                  ..._pinnedJourneesState.where((item) => item.isFloating).map((
                    itemState,
                  ) {
                    return FloatingPinnedItemCard(
                      key: ValueKey('journee-float-${itemState.originalIndex}'),
                      itemData: itemState.data,
                    );
                  }),
                  ..._pinnedSouvenirsState.where((item) => item.isFloating).map(
                    (itemState) {
                      return FloatingPinnedItemCard(
                        key: ValueKey(
                          'souvenir-float-${itemState.originalIndex}',
                        ),
                        itemData: itemState.data,
                      );
                    },
                  ),

                  if (!_likesBlocked && widget.userId != currentUser?.uid)
                    Positioned(
                      left: _heartPosition.dx,
                      top: _heartPosition.dy,
                      child: GestureDetector(
                        onTap: _giveLike,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.favorite,
                            color: _heartColor,
                            size: _heartSize,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 15.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color textColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildStatsRow(ThemeData theme, Color textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatItem("Amis", _friendCount.toString(), textColor),
        if (widget.userId != currentUser?.uid && _mutualFriendsCount > 0)
          Container(height: 40, width: 1, color: Colors.grey.withOpacity(0.5)),
        if (widget.userId != currentUser?.uid && _mutualFriendsCount > 0)
          _buildStatItem(
            "En commun",
            _mutualFriendsCount.toString(),
            textColor,
          ),
      ],
    );
  }

  Widget _buildHeader(
    Map<String, dynamic> userData,
    ThemeData theme,
    Color textColor,
    Color hintColor,
  ) {
    final username = userData['username'] ?? 'Utilisateur';
    final firstName = userData['firstName'] ?? '';
    final lastName = userData['lastName'] ?? '';
    final profilePicUrl = userData['profileImageUrl'] ?? '';
    final qualiteDeVie = userData['qualiteDeVieActuelle'] ?? 50;
    final (color: qolColor, message: qolMessage) = _getQualiteDeVieInfo(
      qualiteDeVie,
    );
    final bool isOwnProfile = widget.userId == currentUser?.uid;

    return _SectionCard(
      cardColor: _isDarkMode ? Colors.grey[900]! : Colors.white,
      blur: _profileCardBlurEnabled,
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage:
                profilePicUrl.isNotEmpty ? NetworkImage(profilePicUrl) : null,
            backgroundColor: _isDarkMode ? Colors.grey[800] : Colors.grey[200],
            child:
                profilePicUrl.isEmpty
                    ? const Icon(Icons.person, size: 50)
                    : null,
          ),
          const SizedBox(height: 16),
          // ▼▼▼ MODIFICATION ICI ▼▼▼
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$firstName $lastName',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
              ),
              // On vérifie le statut VIP depuis les données de l'utilisateur
              if (userData['isVip'] ?? false)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(
                    Icons.star,
                    color: Colors.amber.shade700,
                    size: 24,
                  ),
                ),
            ],
          ),
          // ▲▲▲ FIN DE LA MODIFICATION ▲▲▲
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '@$username',
                style: theme.textTheme.titleMedium?.copyWith(color: hintColor),
              ),
              const SizedBox(width: 8),
              Icon(Icons.vibration, size: 16, color: hintColor),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildStatsRow(theme, textColor),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _showLikesPopup,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.pink.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite, color: Colors.pink, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '$_likeCount',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Column(
            children: [
              Text(
                'Niveau de Vie',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: qolColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: qualiteDeVie / 100.0,
                backgroundColor:
                    _isDarkMode ? Colors.grey[700] : Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(qolColor),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 8),
              Text(
                '$qualiteDeVie/100 - $qolMessage',
                style: theme.textTheme.bodySmall?.copyWith(color: qolColor),
              ),
            ],
          ),
          if (isOwnProfile) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Mode Fidélité',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color:
                        _isFideliteActive
                            ? theme.colorScheme.primary
                            : hintColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                Switch(
                  value: _isFideliteActive,
                  onChanged: _toggleFidelite,
                  activeColor: theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPinnedSection({
    required String title,
    required List<PinnedItemState> pinnedItemsState,
    required String itemType,
    required ThemeData theme,
    required Color textColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          // On ajoute un scroll horizontal ici
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(pinnedItemsState.length, (index) {
                final itemState = pinnedItemsState[index];

                if (_arePinsFloating || itemState.data.isEmpty) {
                  return _buildEmptyPinSlot(theme);
                } else {
                  return _buildPinnedItem(itemState.data, theme, itemType);
                }
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedItem(
    Map<String, dynamic> pinnedItemData,
    ThemeData theme,
    String itemType,
  ) {
    final String shape = pinnedItemData['pin_shape'] ?? 'carrer';
    final String color = pinnedItemData['pin_color'] ?? 'bleu';
    final String assetPath = 'assets/${shape}_${color}.png';
    final String text = pinnedItemData['texte'] ?? '';

    // Padding adapté selon la forme
    final double padding;
    switch (shape) {
      case 'coeur':
      case 'etoile':
        padding = 20.0;
        break;
      case 'rond':
        padding = 18.0;
        break;
      default:
        padding = 12.0;
    }

    return GestureDetector(
      onTap: () => _onPinTapped(pinnedItemData, itemType),
      child: Container(
        width: 150, // Taille fixe
        height: 160, // Taille fixe
        margin: const EdgeInsets.only(right: 12), // Espace entre les épingles
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              assetPath,
              fit: BoxFit.contain,
              errorBuilder:
                  (ctx, err, st) => Container(color: Colors.grey.shade200),
            ),
            Padding(
              padding: EdgeInsets.all(padding),
              child: Center(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      const Shadow(blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutobiographieContainer(
    Map<String, dynamic> userData,
    ThemeData theme,
    Color cardColor,
    Color textColor,
    Color hintColor,
  ) {
    final bool isPublic = userData['isAutobiographiePublic'] ?? false;
    final bool isOwnProfile = widget.userId == currentUser?.uid;

    if (!isPublic && !isOwnProfile) {
      return _SectionCard(
        cardColor: cardColor,
        blur: _profileCardBlurEnabled,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, color: hintColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                "L'autobiographie de cet utilisateur est privée.",
                style: TextStyle(color: hintColor),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        ElevatedButton.icon(
          icon: Icon(
            _isAutobiographieVisible ? Icons.visibility_off : Icons.visibility,
          ),
          label: Text(
            _isAutobiographieVisible
                ? "Masquer l'Autobiographie"
                : "Voir l'Autobiographie",
          ),
          onPressed: () {
            setState(() {
              _isAutobiographieVisible = !_isAutobiographieVisible;
            });
          },
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        if (_isAutobiographieVisible) ...[
          const SizedBox(height: 16),
          _buildAutobiographieContent(theme, cardColor, textColor),
        ],
      ],
    );
  }

  Widget _buildAutobiographieContent(
    ThemeData theme,
    Color cardColor,
    Color textColor,
  ) {
    return FutureBuilder<QuerySnapshot>(
      future:
          _firestore
              .collection('users')
              .doc(widget.userId)
              .collection('chapters')
              .orderBy('number')
              .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _SectionCard(
            blur: _profileCardBlurEnabled,
            cardColor: cardColor,
            child: Center(
              child: Text(
                "Cette autobiographie n'a pas encore de chapitres.",
                style: TextStyle(color: theme.hintColor),
              ),
            ),
          );
        }

        final chapters = snapshot.data!.docs;
        return Column(
          children:
              chapters.map((doc) {
                final chapterData = doc.data() as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _buildChapterCard(
                    chapterData,
                    theme,
                    cardColor,
                    textColor,
                  ),
                );
              }).toList(),
        );
      },
    );
  }

  Widget _buildChapterCard(
    Map<String, dynamic> chapterData,
    ThemeData theme,
    Color cardColor,
    Color textColor,
  ) {
    final int chapterNumber = chapterData['number'] ?? 0;
    final String chapterContent = chapterData['content'] ?? '';

    final RegExp imageMarkerRegex = RegExp(
      r'\[PHOTO_FOR_PARAGRAPH_HERE:(https?:\/\/[^\s\]]+)\]',
    );
    final List<Widget> contentWidgets = [];
    List<String> paragraphs = chapterContent.split(imageMarkerRegex);
    Iterable<Match> matches = imageMarkerRegex.allMatches(chapterContent);

    for (int i = 0; i < paragraphs.length; i++) {
      String paragraph = paragraphs[i];
      if (paragraph.trim().isNotEmpty) {
        contentWidgets.add(
          Text(
            paragraph.trim(),
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: textColor,
            ),
          ),
        );
        contentWidgets.add(const SizedBox(height: 10));
      }

      if (i < matches.length) {
        final Match match = matches.elementAt(i);
        final String imageUrl = match.group(1)!;
        if (imageUrl.isNotEmpty) {
          contentWidgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  loadingBuilder:
                      (context, child, progress) =>
                          progress == null
                              ? child
                              : Container(height: 200, color: Colors.grey[200]),
                  errorBuilder:
                      (context, error, stackTrace) => Container(
                        height: 200,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image),
                      ),
                ),
              ),
            ),
          );
          contentWidgets.add(const SizedBox(height: 10));
        }
      }
    }

    return _SectionCard(
      blur: _profileCardBlurEnabled,
      cardColor: cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chapitre $chapterNumber',
            style: theme.textTheme.headlineSmall?.copyWith(color: textColor),
          ),
          const SizedBox(height: 16),
          ...contentWidgets,
        ],
      ),
    );
  }

  Widget _buildEmptyPinSlot(ThemeData theme) {
    return Container(
      width: 150,
      height: 160,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: (_isDarkMode ? Colors.grey[800] : Colors.grey[200])?.withOpacity(
          0.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.push_pin_outlined, color: theme.hintColor, size: 30),
    );
  }

  Widget _buildTodayJourneeSection(
    DocumentSnapshot? journeeDoc,
    ThemeData theme,
    Color textColor,
    Color cardColor,
    Color hintColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Journée d'aujourd'hui",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            blur: _profileCardBlurEnabled,
            cardColor: cardColor,
            child:
                journeeDoc == null
                    ? Center(
                      child: Text(
                        'Aucune journée publiée aujourd\'hui.',
                        style: TextStyle(color: hintColor),
                      ),
                    )
                    : _buildJourneeCard(
                      journeeDoc.data() as Map<String, dynamic>,
                      theme,
                      textColor,
                      hintColor,
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildJourneeCard(
    Map<String, dynamic> journeeData,
    ThemeData theme,
    Color textColor,
    Color hintColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (journeeData['emoji'] != null)
          Text(journeeData['emoji'], style: const TextStyle(fontSize: 40)),
        SizedBox(height: journeeData['emoji'] != null ? 8 : 0),
        Text(
          journeeData['texte1'] ?? '',
          style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
        ),
        if (journeeData['commentaire'] != null &&
            journeeData['commentaire'].toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              journeeData['commentaire'],
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: hintColor,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAppBarMenu(Map<String, dynamic> userData) {
    if (widget.userId == currentUser?.uid) {
      return const SizedBox.shrink();
    }
    final username = userData['username'] ?? 'cet utilisateur';
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'remove_friend')
          _handleRemoveFriend(username);
        else if (value == 'block_user')
          _handleBlockUser(username);
      },
      itemBuilder:
          (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'remove_friend',
              child: Text(
                "Supprimer l'ami",
                style: TextStyle(color: Colors.orange),
              ),
            ),
            const PopupMenuItem<String>(
              value: 'block_user',
              child: Text('Bloquer', style: TextStyle(color: Colors.red)),
            ),
          ],
    );
  }

  Future<void> _handleBlockUser(String username) async {}
  Future<void> _handleRemoveFriend(String username) async {}

  ({Color color, String message}) _getQualiteDeVieInfo(int qualite) {
    if (qualite >= 85) return (color: Colors.green, message: "Excellente");
    if (qualite >= 65) return (color: Colors.lightGreen, message: "Bonne");
    if (qualite >= 45) return (color: Colors.blue, message: "Normale");
    if (qualite >= 25) return (color: Colors.orange, message: "Difficile");
    return (color: Colors.red, message: "Très difficile");
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final Color cardColor;
  final bool blur;

  const _SectionCard({
    required this.child,
    required this.cardColor,
    this.blur = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(blur ? 0.75 : 1.0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );

    if (blur) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: card,
        ),
      );
    }
    return card;
  }
}

class FloatingSouvenirCard extends StatefulWidget {
  final Souvenir souvenir;
  final VoidCallback onNeedsReplacement;
  final VoidCallback onSendToBack;
  final bool blurBackground;

  const FloatingSouvenirCard({
    required Key key,
    required this.souvenir,
    required this.onNeedsReplacement,
    required this.onSendToBack,
    this.blurBackground = false,
  }) : super(key: key);

  @override
  _FloatingSouvenirCardState createState() => _FloatingSouvenirCardState();
}

class _FloatingSouvenirCardState extends State<FloatingSouvenirCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();
  double _x = 0, _y = 0, _vx = 0, _vy = 0;
  int _bounceCount = 0;
  static const int _maxBounces = 3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updatePosition);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializePositionAndVelocity(context);
        _controller.repeat();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FloatingSouvenirCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.souvenir.id != oldWidget.souvenir.id) {
      _bounceCount = 0;
      _initializePositionAndVelocity(context);
    }
  }

  void _initializePositionAndVelocity(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const cardWidth = 180.0;
    const cardHeight = 120.0;
    setState(() {
      _x = _random.nextDouble() * (size.width - cardWidth);
      _y = _random.nextDouble() * (size.height - cardHeight);
      _vx = (_random.nextDouble() - 0.5) * 1.2;
      _vy = (_random.nextDouble() - 0.5) * 1.2;
    });
  }

  void _updatePosition() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    const cardWidth = 180.0;
    const cardHeight = 120.0;
    setState(() {
      _x += _vx;
      _y += _vy;
      bool bounced = false;
      if ((_x <= 0 && _vx < 0) || (_x >= size.width - cardWidth && _vx > 0)) {
        _vx *= -1;
        bounced = true;
      }
      if ((_y <= 0 && _vy < 0) || (_y >= size.height - cardHeight && _vy > 0)) {
        _vy *= -1;
        bounced = true;
      }
      if (bounced) {
        widget.onSendToBack();
        _bounceCount++;
        if (_bounceCount >= _maxBounces) widget.onNeedsReplacement();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final cardBackground = Container(
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850]! : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
    );

    Widget cardContent = Center(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Text(
          widget.souvenir.texte,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDarkMode ? Colors.white70 : Colors.black87,
          ),
          maxLines: 5,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    if (widget.blurBackground) {
      cardContent = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
          child: cardContent,
        ),
      );
    }

    return Positioned(
      left: _x,
      top: _y,
      child: SizedBox(
        width: 180,
        height: 120,
        child: Stack(children: [cardBackground, cardContent]),
      ),
    );
  }
}

class FloatingPinnedItemCard extends StatefulWidget {
  final Map<String, dynamic> itemData;

  const FloatingPinnedItemCard({Key? key, required this.itemData})
    : super(key: key);

  @override
  State<FloatingPinnedItemCard> createState() => _FloatingPinnedItemCardState();
}

class _FloatingPinnedItemCardState extends State<FloatingPinnedItemCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();
  double _x = 0, _y = 0, _vx = 0, _vy = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updatePosition);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializePositionAndVelocity(context);
        _controller.repeat();
      }
    });
  }

  void _initializePositionAndVelocity(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardWidth = 150.0;
    final cardHeight = 150.0 * (4 / 3);
    setState(() {
      _x = _random.nextDouble() * (size.width - cardWidth);
      _y = _random.nextDouble() * (size.height - cardHeight);
      _vx = (_random.nextDouble() - 0.5) * 1.5;
      _vy = (_random.nextDouble() - 0.5) * 1.5;
    });
  }

  void _updatePosition() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final cardWidth = 150.0;
    final cardHeight = 200.0;
    setState(() {
      _x += _vx;
      _y += _vy;
      if ((_x <= 0 && _vx < 0) || (_x >= size.width - cardWidth && _vx > 0)) {
        _vx *= -1;
      }
      if ((_y <= 0 && _vy < 0) || (_y >= size.height - cardHeight && _vy > 0)) {
        _vy *= -1;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String shape = widget.itemData['pin_shape'] ?? 'carrer';
    final String color = widget.itemData['pin_color'] ?? 'bleu';
    final String assetPath = 'assets/${shape}_${color}.png';
    final String text = widget.itemData['texte'] ?? '';

    final double padding;
    switch (shape) {
      case 'coeur':
      case 'etoile':
        padding = 32.0;
        break;
      case 'rond':
        padding = 28.0;
        break;
      default:
        padding = 18.0;
    }

    return Positioned(
      left: _x,
      top: _y,
      child: SizedBox(
        width: 150,
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(assetPath, fit: BoxFit.contain),
            Padding(
              // On met un padding égal de tous les côtés pour que le Center fasse son travail
              padding: EdgeInsets.all(padding),
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
