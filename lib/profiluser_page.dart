import 'dart:math';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// NOUVEAU: Importation nécessaire pour lire les préférences de thème
import 'package:shared_preferences/shared_preferences.dart';

// --- Models (pour la clarté) ---

class Souvenir {
  final String id;
  final String texte;
  final DateTime date;
  final List<String> photoUrls;

  Souvenir({
    required this.id,
    required this.texte,
    required this.date,
    required this.photoUrls,
  });

  factory Souvenir.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Souvenir(
      id: doc.id,
      texte: data['texte'] ?? 'Souvenir sans texte',
      date: (data['date'] as Timestamp).toDate(),
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
    );
  }
}

class Journee {
  final String id;
  final String texte;
  final String? emoji;
  final String? commentaire;
  final List<String> photoUrls;

  Journee({
    required this.id,
    required this.texte,
    this.emoji,
    this.commentaire,
    required this.photoUrls,
  });

  factory Journee.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Journee(
      id: doc.id,
      texte: data['texte1'] ?? 'Journée sans description',
      emoji: data['emoji'],
      commentaire: data['commentaire'],
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
    );
  }
}

// --- Widget Principal de la Page ---

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

  // State pour les souvenirs flottants
  List<Souvenir> _allSouvenirs = [];
  List<Souvenir> _displayedSouvenirs = [];
  List<Souvenir> _hiddenSouvenirs = [];
  final int _maxFloatingSouvenirs = 100;
  Map<String, double> _souvenirZOrders = {};

  // États locaux pour le switch et la visibilité de l'autobiographie
  bool _isFideliteActive = false;
  bool _isAutobiographieVisible = false;

  // NOUVEAU: État pour gérer le mode sombre
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    // NOUVEAU: Charger le thème en plus des données du profil
    _loadTheme();
    _profileDataFuture = _loadProfileData();
  }

  // NOUVEAU: Méthode pour charger la préférence de thème
  Future<void> _loadTheme() async {
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
            // S'adapte au système si aucune préférence n'est définie
            _isDarkMode =
                WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                    Brightness.dark;
          }
        });
      }
    } catch (e) {
      print("Erreur de chargement du thème: $e");
    }
  }

  Future<Map<String, dynamic>> _loadProfileData() async {
    final userDataDoc =
    await _firestore.collection('users').doc(widget.userId).get();

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    final todaysJourneeQuery = await _firestore
        .collection('journees')
        .where('userId', isEqualTo: widget.userId)
        .where('date', isGreaterThanOrEqualTo: startOfToday)
        .where('date', isLessThan: endOfToday)
        .limit(1)
        .get();

    final souvenirsQuery = await _firestore
        .collection('souvenirs')
        .where('userId', isEqualTo: widget.userId)
        .where('estPublic', isEqualTo: true)
        .get();

    if (mounted) {
      _allSouvenirs =
          souvenirsQuery.docs.map((doc) => Souvenir.fromFirestore(doc)).toList();
      _allSouvenirs.shuffle();

      setState(() {
        _displayedSouvenirs = _allSouvenirs.take(_maxFloatingSouvenirs).toList();
        _hiddenSouvenirs = _allSouvenirs.skip(_maxFloatingSouvenirs).toList();

        _souvenirZOrders.clear();
        for (var i = 0; i < _displayedSouvenirs.length; i++) {
          _souvenirZOrders[_displayedSouvenirs[i].id] = i.toDouble();
        }

        if (userDataDoc.exists) {
          final data = userDataDoc.data() as Map<String, dynamic>;
          _isFideliteActive = data['isTruthAdjustmentActive'] ?? false;
        }
      });
    }

    return {
      'userData': userDataDoc,
      'todaysJournee':
      todaysJourneeQuery.docs.isNotEmpty ? todaysJourneeQuery.docs.first : null,
    };
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
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors de la mise à jour: $e")),
        );
      }
    }
  }

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
      final oldIndex =
      _displayedSouvenirs.indexWhere((s) => s.id == oldSouvenir.id);
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

  @override
  Widget build(BuildContext context) {
    // MODIFIÉ: On utilise notre variable _isDarkMode pour définir les couleurs
    final theme = Theme.of(context);
    final backgroundColor = _isDarkMode ? Colors.black : Colors.white;
    final cardColor = _isDarkMode ? Colors.grey[900]! : Colors.white;
    final textColor = _isDarkMode ? Colors.white : Colors.black87;
    final hintColor = _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;

    return Scaffold(
      // MODIFIÉ: Utilisation de la couleur de fond manuelle
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
                child: Text("Impossible de charger le profil."));
          }

          final DocumentSnapshot? userDataDoc = snapshot.data!['userData'];
          if (userDataDoc == null || !userDataDoc.exists) {
            return const Center(child: Text("Cet utilisateur n'existe pas."));
          }

          final userData = userDataDoc.data() as Map<String, dynamic>;
          final DocumentSnapshot? todaysJournee =
          snapshot.data!['todaysJournee'];

          // ======================= CORRECTION : DÉPLACER LA LOGIQUE ICI =======================
          // On prépare les listes d'IDs AVANT de construire l'interface utilisateur.

          // 1. Préparation pour les journées
          final List<dynamic> pinnedJourneesData = userData['pinnedJournees'] ?? [];
          final List<String> pinnedJourneeIds = pinnedJourneesData
              .map((item) {
            if (item is Map<String, dynamic> && item['id'] != null) {
              return item['id'].toString();
            }
            return null;
          })
              .whereType<String>()
              .toList();

          // 2. Préparation pour les souvenirs
          final List<dynamic> pinnedSouvenirsData = userData['pinnedSouvenirs'] ?? [];
          final List<String> pinnedSouvenirIds = pinnedSouvenirsData
              .map((item) {
            if (item is Map<String, dynamic> && item['id'] != null) {
              return item['id'].toString();
            }
            return null;
          })
              .whereType<String>()
              .toList();
          // ===================================================================================

          return Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: backgroundColor,
            appBar: AppBar(
              title: Text(userData['username'] ?? 'Profil',
                  style: TextStyle(color: textColor)),
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
                    onNeedsReplacement: () =>
                        _handleSouvenirReplacement(souvenir),
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
                        16),
                    children: [
                      _buildHeader(userData, theme, textColor, hintColor),
                      const SizedBox(height: 24),
                      _buildAutobiographieContainer(
                          userData, theme, cardColor, textColor, hintColor),

                      // ======================= CORRECTION : UTILISER LES VARIABLES ICI =======================
                      // Maintenant, on peut simplement appeler les widgets avec les variables déjà prêtes.
                      _buildPinnedSection(
                        title: 'Journées Épinglées',
                        pinnedIds: pinnedJourneeIds,
                        collectionName: 'journees',
                        theme: theme,
                        textColor: textColor,
                      ),
                      _buildPinnedSection(
                        title: 'Souvenirs Épinglés',
                        pinnedIds: pinnedSouvenirIds,
                        collectionName: 'souvenirs',
                        theme: theme,
                        textColor: textColor,
                      ),
                      // =======================================================================================

                      _buildTodayJourneeSection(
                          todaysJournee, theme, textColor, cardColor, hintColor),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Méthodes de construction de l'UI ---

  Widget _buildHeader(Map<String, dynamic> userData, ThemeData theme, Color textColor, Color hintColor) {
    final username = userData['username'] ?? 'Utilisateur';
    final firstName = userData['firstName'] ?? '';
    final lastName = userData['lastName'] ?? '';
    final profilePicUrl = userData['profilePicUrl'] ?? '';
    final qualiteDeVie = userData['qualiteDeVieActuelle'] ?? 50;
    final (color: qolColor, message: qolMessage) =
    _getQualiteDeVieInfo(qualiteDeVie);

    final bool isOwnProfile = widget.userId == currentUser?.uid;

    return _SectionCard(
      cardColor: _isDarkMode ? Colors.grey[900]! : Colors.white,
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage:
            profilePicUrl.isNotEmpty ? NetworkImage(profilePicUrl) : null,
            backgroundColor: _isDarkMode ? Colors.grey[800] : Colors.grey[200],
            child:
            profilePicUrl.isEmpty ? const Icon(Icons.person, size: 50) : null,
          ),
          const SizedBox(height: 16),
          Text('$firstName $lastName',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: textColor),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('@$username',
              style: theme.textTheme.titleMedium?.copyWith(color: hintColor)),
          const SizedBox(height: 20),
          Column(
            children: [
              Text('Niveau de Vie',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: qolColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: qualiteDeVie / 100,
                backgroundColor: _isDarkMode ? Colors.grey[700] : Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(qolColor),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 8),
              Text('$qualiteDeVie/100 - $qolMessage',
                  style: theme.textTheme.bodySmall?.copyWith(color: qolColor)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Mode Fidélité',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: _isFideliteActive
                      ? theme.colorScheme.primary
                      : hintColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Switch(
                value: _isFideliteActive,
                onChanged:
                isOwnProfile ? _toggleFidelite : null, // Seul le propriétaire peut changer
                activeColor: theme.colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutobiographieContainer(Map<String, dynamic> userData, ThemeData theme, Color cardColor, Color textColor, Color hintColor) {
    final bool isPublic = userData['isAutobiographiePublic'] ?? false;

    if (!isPublic) {
      return _SectionCard(
        cardColor: cardColor,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, color: hintColor),
            const SizedBox(width: 8),
            Text("L'autobiographie de cet utilisateur est privée.",
                style: TextStyle(color: hintColor)),
          ],
        ),
      );
    }

    return Column(
      children: [
        ElevatedButton.icon(
          icon: Icon(
              _isAutobiographieVisible ? Icons.visibility_off : Icons.visibility),
          label: Text(_isAutobiographieVisible
              ? "Masquer l'Autobiographie"
              : "Voir l'Autobiographie"),
          onPressed: () {
            setState(() {
              _isAutobiographieVisible = !_isAutobiographieVisible;
            });
          },
          style: ElevatedButton.styleFrom(
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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

  Widget _buildAutobiographieContent(ThemeData theme, Color cardColor, Color textColor) {
    return FutureBuilder<QuerySnapshot>(
      future: _firestore
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
              cardColor: cardColor,
              child: Center(
                  child: Text(
                      "Cette autobiographie n'a pas encore de chapitres.",
                      style: TextStyle(color: theme.hintColor))));
        }

        final chapters = snapshot.data!.docs;
        return Column(
          children: chapters.map((doc) {
            final chapterData = doc.data() as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _buildChapterCard(chapterData, theme, cardColor, textColor),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildChapterCard(Map<String, dynamic> chapterData, ThemeData theme, Color cardColor, Color textColor) {
    final int chapterNumber = chapterData['number'] ?? 0;
    final String chapterContent = chapterData['content'] ?? '';

    final RegExp imageMarkerRegex =
    RegExp(r'\[PHOTO_FOR_PARAGRAPH_HERE:(https?:\/\/[^\s\]]+)\]');
    final List<Widget> contentWidgets = [];
    List<String> paragraphs = chapterContent.split(imageMarkerRegex);
    Iterable<Match> matches = imageMarkerRegex.allMatches(chapterContent);

    for (int i = 0; i < paragraphs.length; i++) {
      String paragraph = paragraphs[i];
      if (paragraph.trim().isNotEmpty) {
        contentWidgets.add(
          Text(
            paragraph.trim(),
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6, color: textColor),
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
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : Container(height: 200, color: Colors.grey[200]),
                  errorBuilder: (context, error, stackTrace) => Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image)),
                ),
              ),
            ),
          );
          contentWidgets.add(const SizedBox(height: 10));
        }
      }
    }

    return _SectionCard(
      cardColor: cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chapitre $chapterNumber', style: theme.textTheme.headlineSmall?.copyWith(color: textColor)),
          const SizedBox(height: 16),
          ...contentWidgets,
        ],
      ),
    );
  }

  Widget _buildPinnedSection({
    required String title,
    required List<String> pinnedIds,
    required String collectionName,
    required ThemeData theme,
    required Color textColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 12),
          Row(
            children: List.generate(3, (index) {
              if (index < pinnedIds.length && pinnedIds[index].isNotEmpty) {
                return _buildPinnedItem(pinnedIds[index], collectionName, theme);
              } else {
                return _buildEmptyPinSlot(theme);
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedItem(String docId, String collection, ThemeData theme) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: FutureBuilder<DocumentSnapshot>(
            future: _firestore.collection(collection).doc(docId).get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(color: _isDarkMode ? Colors.grey[800] : Colors.grey[200]),
                );
              }
              final data = snapshot.data!.data() as Map<String, dynamic>;
              final photoUrls = List<String>.from(data['photoUrls'] ?? []);
              final text = data['texte1'] ?? data['texte'] ?? '';

              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: _isDarkMode ? Colors.grey[800] : Colors.grey[200],
                  child: photoUrls.isNotEmpty
                      ? Image.network(
                    photoUrls.first,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) =>
                    progress == null
                        ? child
                        : const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2)),
                    errorBuilder: (context, error, stack) =>
                    const Icon(Icons.broken_image),
                  )
                      : Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 4,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPinSlot(ThemeData theme) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: (_isDarkMode ? Colors.grey[800] : Colors.grey[200])?.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.add, color: theme.hintColor, size: 30),
          ),
        ),
      ),
    );
  }

  Widget _buildTodayJourneeSection(DocumentSnapshot? journeeDoc, ThemeData theme, Color textColor, Color cardColor, Color hintColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Journée d'aujourd'hui",
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 12),
          _SectionCard(
            cardColor: cardColor,
            child: journeeDoc == null
                ? Center(
                child: Text('Aucune journée publiée aujourd\'hui.',
                    style: TextStyle(color: hintColor)))
                : _buildJourneeCard(journeeDoc.data() as Map<String, dynamic>, theme, textColor, hintColor),
          ),
        ],
      ),
    );
  }

  Widget _buildJourneeCard(Map<String, dynamic> journeeData, ThemeData theme, Color textColor, Color hintColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (journeeData['emoji'] != null)
          Text(journeeData['emoji'], style: const TextStyle(fontSize: 40)),
        SizedBox(height: journeeData['emoji'] != null ? 8 : 0),
        Text(journeeData['texte1'] ?? '', style: theme.textTheme.bodyLarge?.copyWith(color: textColor)),
        if (journeeData['commentaire'] != null &&
            journeeData['commentaire'].toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              journeeData['commentaire'],
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontStyle: FontStyle.italic, color: hintColor),
            ),
          ),
      ],
    );
  }

  // --- Méthodes d'Aide & Widgets ---

  Widget _buildAppBarMenu(Map<String, dynamic> userData) {
    if (widget.userId == currentUser?.uid) {
      return const SizedBox.shrink();
    }

    final username = userData['username'] ?? 'cet utilisateur';

    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'remove_friend') {
          _handleRemoveFriend(username);
        } else if (value == 'block_user') {
          _handleBlockUser(username);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'remove_friend',
          child: Text("Supprimer l'ami", style: TextStyle(color: Colors.orange)),
        ),
        const PopupMenuItem<String>(
          value: 'block_user',
          child: Text('Bloquer', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Future<void> _handleBlockUser(String username) async {
    final currentUserId = currentUser?.uid;
    if (currentUserId == null) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
            Text("Vous devez être connecté pour bloquer un utilisateur.")),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bloquer $username?'),
        content: const Text(
            'Voulez-vous vraiment bloquer cet utilisateur? Vous ne verrez plus son contenu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              await _firestore.collection('users').doc(currentUserId).update({
                'blockedUsers': FieldValue.arrayUnion([widget.userId])
              });
              if (mounted) {
                Navigator.pop(context);
                Navigator.pop(context);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRemoveFriend(String username) async {
    final currentUserId = currentUser?.uid;
    if (currentUserId == null) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Vous devez être connecté pour supprimer un ami.")),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer $username?'),
        content: const Text('Voulez-vous vraiment supprimer cet ami?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              QuerySnapshot friendDocs = await _firestore
                  .collection('friends')
                  .where('users', whereIn: [
                [currentUserId, widget.userId],
                [widget.userId, currentUserId]
              ]).get();

              for (var doc in friendDocs.docs) {
                await doc.reference.delete();
              }

              if (mounted) {
                Navigator.pop(context);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  ({Color color, String message}) _getQualiteDeVieInfo(int qualite) {
    if (qualite < 20) return (color: Colors.red, message: "Très faible");
    if (qualite < 40) return (color: Colors.orange, message: "Faible");
    if (qualite < 60) return (color: Colors.amber.shade700, message: "Moyenne");
    if (qualite < 80) return (color: Colors.lightGreen, message: "Bonne");
    return (color: Colors.green, message: "Excellente");
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// MODIFIÉ: Helper widget pour un style de carte floutée consistent, acceptant une couleur
class _SectionCard extends StatelessWidget {
  final Widget child;
  final Color cardColor;

  const _SectionCard({required this.child, required this.cardColor});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        ),
      ),
    );
  }
}

// --- Widget pour les Souvenirs Flottants ---

class FloatingSouvenirCard extends StatefulWidget {
  final Souvenir souvenir;
  final VoidCallback onNeedsReplacement;
  final VoidCallback onSendToBack;

  const FloatingSouvenirCard({
    required Key key,
    required this.souvenir,
    required this.onNeedsReplacement,
    required this.onSendToBack,
  }) : super(key: key);

  @override
  _FloatingSouvenirCardState createState() => _FloatingSouvenirCardState();
}

class _FloatingSouvenirCardState extends State<FloatingSouvenirCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();

  double _x = 0, _y = 0;
  double _vx = 0, _vy = 0;
  int _bounceCount = 0;
  static const int _maxBounces = 3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 16))
      ..addListener(_updatePosition);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializePositionAndVelocity(context);
        _controller.repeat();
      }
    });
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
      if (_x <= 0 && _vx < 0) {
        _vx *= -1;
        _x = 0;
        bounced = true;
      }
      if (_x >= size.width - cardWidth && _vx > 0) {
        _vx *= -1;
        _x = size.width - cardWidth;
        bounced = true;
      }

      if (_y <= 0 && _vy < 0) {
        _vy *= -1;
        _y = 0;
        bounced = true;
      }
      if (_y >= size.height - cardHeight && _vy > 0) {
        _vy *= -1;
        _y = size.height - cardHeight;
        bounced = true;
      }

      if (bounced) {
        widget.onSendToBack();
        _bounceCount++;
        if (_bounceCount >= _maxBounces) {
          widget.onNeedsReplacement();
        }
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
    final theme = Theme.of(context);
    final hasImage = widget.souvenir.photoUrls.isNotEmpty;

    return Positioned(
      left: _x,
      top: _y,
      child: Container(
        width: 180,
        height: 120,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                Image.network(
                  widget.souvenir.photoUrls.first,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(color: theme.colorScheme.surfaceVariant),
                ),
              if (!hasImage) Container(color: theme.colorScheme.surfaceVariant),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                      Colors.black.withOpacity(0.7)
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  widget.souvenir.texte,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontSize: 13,
                    shadows: [
                      const Shadow(blurRadius: 2, color: Colors.black87)
                    ],
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}