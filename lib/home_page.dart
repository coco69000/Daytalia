
import 'dart:math' as math;
import 'dart:math' as Math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http; // NÉCESSAIRE POUR LES NOTIFICATIONS
import 'dart:convert'; // NÉCESSAIRE POUR LES NOTIFICATIONS
import 'journee_page.dart';
import 'souvenir_page.dart';
import 'addamis_page.dart';
import 'dart:ui';
import 'dart:ui' as ui;
import 'profil_page.dart';
import 'dart:math';
import 'profiluser_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'JourneeEnDirectPage_page.dart';
import 'journee_model.dart';
import 'dart:async';
import 'souvenir_model.dart';
import 'souvenir_model.dart' as sm;
const String DEEPSEEK_API_KEY = 'VOTRE_CLÉ_API_DEEPSEEK';

// --- AMÉLIORATION : CONFIGURATION ONESIGNAL (À METTRE À JOUR) ---
const String ONE_SIGNAL_APP_ID = "83c44506-2022-4432-a8fe-004e4406416e";
// ATTENTION : NE JAMAIS LAISSER CETTE CLÉ DANS LE CODE CLIENT EN PRODUCTION !
const String ONE_SIGNAL_REST_API_KEY = "os_v2_app_qpcekbraejcdfkh6abheibsbny3tigrupigu4vf3vtds3wnadgmdiwe7bi35yw4lcugsvh2shc5tnrnxmoru4aj3w66k6ewldrlguka";

// --- AMÉLIORATION : Service de notification ---
class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> sendNotification({
    required List<String> playerIds,
    required String title,
    required String message,
  }) async {
    if (ONE_SIGNAL_REST_API_KEY == "VOTRE_REST_API_KEY_ONESIGNAL") {
      print("--- ERREUR NOTIFICATION: Clé REST API OneSignal non configurée.");
      return;
    }

    final validPlayerIds = playerIds.where((id) => id.isNotEmpty).toList();
    if (validPlayerIds.isEmpty) {
      print("--- INFO NOTIFICATION: Aucun Player ID valide à notifier.");
      return;
    }

    try {
      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Basic $ONE_SIGNAL_REST_API_KEY',
        },
        body: jsonEncode(<String, dynamic>{
          "app_id": ONE_SIGNAL_APP_ID,
          "include_player_ids": validPlayerIds,
          "headings": {"en": title},
          "contents": {"en": message},
        }),
      );
      print("--- INFO NOTIFICATION: Notification envoyée à ${validPlayerIds.join(', ')}");
    } catch (e) {
      print("--- ERREUR NOTIFICATION: Échec de l'envoi de la notification: $e");
    }
  }

  static Future<void> notifyFriendsOfNewPost(String authorName) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final friendsSnapshot = await _firestore.collection('friends').where('users', arrayContains: currentUser.uid).get();
    final friendIds = friendsSnapshot.docs.expand((doc) => List<String>.from(doc['users'])).toSet()..remove(currentUser.uid);

    if (friendIds.isEmpty) return;

    final List<String> playerIds = [];
    for (String friendId in friendIds) {
      final userDoc = await _firestore.collection('users').doc(friendId).get();
      if (userDoc.exists && userDoc.data()!.containsKey('oneSignalPlayerId')) {
        playerIds.add(userDoc['oneSignalPlayerId']);
      }
    }

    sendNotification(
      playerIds: playerIds,
      title: "Nouvelle journée !",
      message: "$authorName a partagé sa journée.",
    );
  }

  static Future<void> notifyOwnerOnInteraction({
    required String journeeId,
    required String interactorName,
    required String action, // "commenté" ou "réagi à"
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final journeeDoc = await _firestore.collection('journees').doc(journeeId).get();
    if (!journeeDoc.exists) return;

    final ownerId = journeeDoc['userId'];
    if (ownerId == currentUser.uid) return; // Ne pas se notifier soi-même

    final ownerDoc = await _firestore.collection('users').doc(ownerId).get();
    if (ownerDoc.exists && ownerDoc.data()!.containsKey('oneSignalPlayerId')) {
      final playerId = ownerDoc['oneSignalPlayerId'];
      sendNotification(
        playerIds: [playerId],
        title: "Nouvelle interaction !",
        message: "$interactorName a $action votre journée.",
      );
    }
  }
}


// --- VIP --- : Helper pour récupérer les données utilisateur (VIP, timestamps)
Future<Map<String, dynamic>> getUserSubscriptionData() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return {'isVip': false, 'lastIaUpdate': null, 'lastAutobioUpdate': null, 'autobioPrompt': ''};
  }
  try {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      return {
        'isVip': userDoc.data()?['isVip'] ?? false,
        'lastIaAnalysisUpdate': userDoc.data()?['lastIaAnalysisUpdate'] as Timestamp?,
        'lastAutobiographyUpdate': userDoc.data()?['lastAutobiographyUpdate'] as Timestamp?,
        'autobiographyGeneralPrompt': userDoc.data()?['autobiographyGeneralPrompt'] ?? '',
      };
    }
  } catch (e) {
    print("Erreur de récupération des données d'abonnement: $e");
  }
  return {'isVip': false, 'lastIaUpdate': null, 'lastAutobioUpdate': null, 'autobioPrompt': ''};
}

// --- VIP --- : Popup pour encourager l'abonnement
void showVipPromotionPopup(BuildContext context, String featureName) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.star, color: Colors.amber),
          SizedBox(width: 8),
          Text("Fonctionnalité Premium"),
        ],
      ),
      content: Text("La fonctionnalité '$featureName' est réservée aux membres VIP. Passez à la version premium pour en profiter !"),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Plus tard"),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Redirection vers la page d'abonnement...")),
            );
          },
          child: const Text("Devenir VIP"),
        ),
      ],
    ),
  );
}
class AutobiographieDialog extends StatefulWidget {
  const AutobiographieDialog({Key? key}) : super(key: key);

  @override
  State<AutobiographieDialog> createState() => _AutobiographieDialogState();
}

class _AutobiographieDialogState extends State<AutobiographieDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  Map<int, Map<String, dynamic>> _chaptersData = {};
  List<Map<String, dynamic>> _availableCategories = [];
  Map<String, String> _categoryNames = {};
  Map<String, bool> _themeHasUpdates = {};
  bool _isLoadingUpdates = true;

  bool _isLoadingChapters = true;
  bool _isLoadingCategories = true;
  int? _generatingChapterNumber;
  bool _isAutobiographiePublic = true;
  bool _isLoadingVisibility = true;

  bool _isVip = false;
  DateTime? _lastAutobioUpdate;
  bool _canUpdateAutobio = false;
  final TextEditingController _promptController = TextEditingController();


  @override
  void initState() {
    super.initState();
    if (_currentUser != null) {
      _loadInitialData();
      _loadVisibility();
      _loadVipData();
    } else {
      setState(() {
        _isLoadingChapters = false;
        _isLoadingCategories = false;
        _isLoadingUpdates = false;
        _isLoadingVisibility = false;
      });
    }
  }

  Future<void> _loadVipData() async {
    final data = await getUserSubscriptionData();
    if (mounted) {
      setState(() {
        _isVip = data['isVip'];
        final lastUpdateTimestamp = data['lastAutobioUpdate'] as Timestamp?;
        _lastAutobioUpdate = lastUpdateTimestamp?.toDate();
        _promptController.text = data['autobioPrompt'] ?? '';
        _checkIfCanUpdate();
      });
    }
  }

  void _checkIfCanUpdate() {
    if (_isVip) {
      _canUpdateAutobio = true;
      return;
    }
    if (_lastAutobioUpdate == null) {
      _canUpdateAutobio = true;
    } else {
      _canUpdateAutobio = DateTime.now().difference(_lastAutobioUpdate!).inDays >= 7;
    }
  }

  Future<void> _saveGeneralPrompt() async {
    if (_currentUser == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .set({'autobiographyGeneralPrompt': _promptController.text}, SetOptions(merge: true));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prompt général sauvegardé !'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadVisibility() async {
    if (_currentUser == null) return;
    try {
      final userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists && userDoc.data()!.containsKey('isAutobiographiePublic')) {
        if (mounted) {
          setState(() {
            _isAutobiographiePublic = userDoc.data()!['isAutobiographiePublic'];
          });
        }
      }
    } catch (e) {
      print("Erreur lors du chargement de la visibilité: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingVisibility = false);
      }
    }
  }

  Future<void> _toggleVisibility(bool isPublic) async {
    if (_currentUser == null) return;
    setState(() {
      _isAutobiographiePublic = isPublic;
    });
    try {
      await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .set({'isAutobiographiePublic': isPublic}, SetOptions(merge: true));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Visibilité de l\'autobiographie mise à jour.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la mise à jour: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadInitialData() async {
    await _loadCategories();
    await Future.wait([
      _loadChapters(),
      _checkThemesForUpdates(),
    ]);
  }

  Future<void> _loadCategories() async {
    if (_currentUser == null) return;
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('categories_elements')
          .get();

      final loadedCategories = snapshot.docs.map((doc) {
        final data = doc.data();
        _categoryNames[doc.id] = data['nom'] as String;
        return {'id': doc.id, 'nom': data['nom']};
      }).toList();

      if (mounted) {
        setState(() {
          _availableCategories = loadedCategories;
          _isLoadingCategories = false;
        });
      }
    } catch (e, stackTrace) {
      print('Erreur lors du chargement des catégories: $e\n$stackTrace');
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }
  Future<void> _checkThemesForUpdates() async {
    if (_currentUser == null || _availableCategories.isEmpty) {
      if (mounted) setState(() => _isLoadingUpdates = false);
      return;
    }

    final updates = <String, bool>{};
    for (var category in _availableCategories) {
      final categoryId = category['id'] as String;
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('categories_elements')
            .doc(categoryId)
            .collection('elements')
            .where('lastAnalyzedAutobiographie', isEqualTo: null)
            .limit(1)
            .get();
        updates[categoryId] = snapshot.docs.isNotEmpty;
      } catch (e) {
        print("Erreur de vérification des MaJ pour le thème $categoryId: $e");
        updates[categoryId] = false;
      }
    }

    if (mounted) {
      setState(() {
        _themeHasUpdates = updates;
        _isLoadingUpdates = false;
      });
    }
  }

  Future<void> _loadChapters() async {
    if (_currentUser == null) return;
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('chapters')
          .get();

      final loadedChapters = <int, Map<String, dynamic>>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data.containsKey('number')) {
          loadedChapters[data['number']] = data;
        }
      }

      if (mounted) {
        setState(() {
          _chaptersData = loadedChapters;
          _isLoadingChapters = false;
        });
      }
    } catch (e, stackTrace) {
      print('Erreur lors du chargement des chapitres: $e\n$stackTrace');
      if (mounted) setState(() => _isLoadingChapters = false);
    }
  }

  void _promptForThemeSelection(int chapterNumber) {
    final messenger = ScaffoldMessenger.of(context);

    List<Map<String, dynamic>> dialogCategories =
    _availableCategories.map((c) => Map<String, dynamic>.from(c)).toList();
    for (var cat in dialogCategories) {
      cat['selected'] = false;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Thèmes du Chapitre $chapterNumber', style: const TextStyle(color: Colors.blue)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Choisissez les thèmes à inclure.'),
                    const SizedBox(height: 16),
                    ListTile(
                      title: const Text('Tous les thèmes (recréer)'),
                      leading: const Icon(Icons.all_inclusive, color: Colors.blue),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _generateAndSaveChapter(chapterNumber, selectedThemeIds: null, isUpdate: false);
                      },
                    ),
                    const Divider(),
                    ...dialogCategories.map((category) {
                      final bool hasUpdates = _themeHasUpdates[category['id']] ?? false;
                      return CheckboxListTile(
                        title: Row(
                          children: [
                            Expanded(child: Text(category['nom'])),
                            if (hasUpdates)
                              Chip(
                                label: const Text('Nouveau', style: TextStyle(fontSize: 10)),
                                backgroundColor: Colors.green.shade100,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              ),
                          ],
                        ),
                        value: category['selected'],
                        onChanged: (bool? value) {
                          setDialogState(() {
                            category['selected'] = value ?? false;
                          });
                        },
                        activeColor: Colors.blue,
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Annuler', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final selectedIds = dialogCategories
                        .where((cat) => cat['selected'] == true)
                        .map((cat) => cat['id'] as String)
                        .toList();
                    if (selectedIds.isEmpty) {
                      messenger.showSnackBar(const SnackBar(content: Text('Veuillez sélectionner au moins un thème.')));
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    _generateAndSaveChapter(chapterNumber, selectedThemeIds: selectedIds, isUpdate: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Mettre à jour'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final selectedIds = dialogCategories
                        .where((cat) => cat['selected'] == true)
                        .map((cat) => cat['id'] as String)
                        .toList();
                    if (selectedIds.isEmpty) {
                      messenger.showSnackBar(const SnackBar(content: Text('Veuillez sélectionner au moins un thème.')));
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    _generateAndSaveChapter(chapterNumber, selectedThemeIds: selectedIds, isUpdate: false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Recréer'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  Future<void> _generateAndSaveChapter(
      int chapterNumber, {
        required List<String>? selectedThemeIds,
        required bool isUpdate,
      }) async {
    if (_currentUser == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _generatingChapterNumber = chapterNumber);

    try {
      final fetchResult = await _fetchChapterElements(selectedThemeIds, isUpdate: isUpdate);
      final List<Map<String, dynamic>> elementsWithImages = fetchResult['data'];
      final List<DocumentReference> elementRefs = fetchResult['refs'];

      if (!mounted) return;

      if (elementsWithImages.isEmpty) {
        messenger.showSnackBar(SnackBar(
            content: Text(isUpdate ? 'Aucun nouvel élément à ajouter.' : 'Aucun élément trouvé pour les thèmes sélectionnés.')));
        setState(() => _generatingChapterNumber = null);
        return;
      }

      final previousChapterContent = _chaptersData[chapterNumber - 1]?['content'] ?? '';
      final existingContent = _chaptersData[chapterNumber]?['content'];

      final newContent = await _generateChapterContent(
        chapterNumber: chapterNumber,
        elements: elementsWithImages,
        previousChapterContent: previousChapterContent,
        existingContent: isUpdate ? existingContent : null,
        generalPrompt: _isVip ? _promptController.text : null,
      );

      if (!mounted) return;

      final chapterData = {
        'number': chapterNumber,
        'content': newContent,
        'themesUsed': selectedThemeIds ?? ['all'],
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('chapters')
          .doc('chapter_$chapterNumber')
          .set(chapterData, SetOptions(merge: true));
      WriteBatch batch = _firestore.batch();
      for (final ref in elementRefs) {
        batch.update(ref, {'lastAnalyzedAutobiographie': Timestamp.now()});
      }
      await batch.commit();
      if (!_isVip) {
        await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .set({'lastAutobiographyUpdate': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        _loadVipData();
      }
      if (mounted) {
        setState(() {
          _chaptersData[chapterNumber] = {...chapterData, 'lastUpdated': Timestamp.now()};
          _checkThemesForUpdates();
        });
        messenger.showSnackBar(SnackBar(
          content: Text('Chapitre $chapterNumber ${isUpdate ? "mis à jour" : "généré"} avec succès !'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e, stackTrace) {
      print("--- Erreur dans la génération: $e\n$stackTrace ---");
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Une erreur est survenue lors de la génération: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _generatingChapterNumber = null);
      }
    }
  }
  Future<Map<String, dynamic>> _fetchChapterElements(
      List<String>? themeIds, {
        required bool isUpdate,
      }) async {
    if (_currentUser == null) return {'data': [], 'refs': []};

    List<Map<String, dynamic>> elements = [];
    List<DocumentReference> elementRefs = [];
    final categoriesRef = _firestore
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('categories_elements');

    List<DocumentSnapshot> categoryDocs;
    if (themeIds == null) {
      categoryDocs = (await categoriesRef.get()).docs;
    } else {
      final futures = themeIds.map((id) => categoriesRef.doc(id).get()).toList();
      categoryDocs = (await Future.wait(futures)).where((doc) => doc.exists).toList();
    }

    for (var categoryDoc in categoryDocs) {
      Query elementsQuery = categoryDoc.reference.collection('elements');
      if (isUpdate) {
        elementsQuery = elementsQuery.where('lastAnalyzedAutobiographie', isEqualTo: null);
      }
      final elementsSnapshot = await elementsQuery.get();

      for (var elementDoc in elementsSnapshot.docs) {
        final elementData = elementDoc.data();
        if (elementData is Map<String, dynamic>) {
          String sourceInfo = '';
          if (elementData['isRepost'] == true && elementData['repostedFromUserName'] != null) {
            sourceInfo = " (Cet élément a été republié par l'utilisateur à partir d'un contenu de ${elementData['repostedFromUserName']}).";
          }
          elements.add({
            'texte': elementData['texte'] ?? '',
            'explication': (elementData['explication'] ?? '') + sourceInfo,
            'date': (elementData['date'] as Timestamp).toDate(),
            'photoUrls': await _getPhotoUrlsForElement(elementData),
          });
          elementRefs.add(elementDoc.reference);
        }
      }
    }
    return {'data': elements, 'refs': elementRefs};
  }

  Future<List<String>> _getPhotoUrlsForElement(Map<String, dynamic> elementData) async {
    if (elementData['date'] is Timestamp) {
      final elementDate = (elementData['date'] as Timestamp).toDate();
      final dayStart = DateTime(elementDate.year, elementDate.month, elementDate.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final querySnapshot = await _firestore
          .collection('journees')
          .where('userId', isEqualTo: _currentUser!.uid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('date', isLessThan: Timestamp.fromDate(dayEnd))
          .get();

      final List<String> photoUrls = [];
      for (var doc in querySnapshot.docs) {
        final journeeData = doc.data();
        if (journeeData.containsKey('photoUrls') && journeeData['photoUrls'] is List) {
          photoUrls.addAll(List<String>.from(journeeData['photoUrls']));
        }
      }
      return photoUrls.toSet().toList();
    }
    return [];
  }

  Future<String> _generateChapterContent({
    required int chapterNumber,
    required List<Map<String, dynamic>> elements,
    required String previousChapterContent,
    String? existingContent,
    String? generalPrompt,
  }) async {
    const apiUrl = 'https://api.deepseek.com/v1/chat/completions';

    final formattedElements = elements.map((e) {
      String imageInfo = '';
      if (e['photoUrls'] != null && (e['photoUrls'] as List).isNotEmpty) {
        imageInfo = " (Images associées à cet événement: ${e['photoUrls'].map((url) => '[IMAGE_URL:$url]').join(', ')})";
      }
      return "- ${e['texte']}: ${e['explication']}$imageInfo";
    }).join('\n');

    final bool isUpdate = existingContent != null && existingContent.isNotEmpty;

    final generalPromptSection = (generalPrompt != null && generalPrompt.isNotEmpty)
        ? """
    4.  **Instruction générale de l'utilisateur (à suivre pour l'ensemble du récit) :**
        $generalPrompt
    """
        : "";

    final prompt = """
    Tu es un écrivain et biographe talentueux. Ta mission est de rédiger un chapitre d'une autobiographie de manière engageante, fluide et émotive, à la première personne ("je").

    Voici les informations à ta disposition :

    1.  **Éléments de vie à intégrer :**
        $formattedElements

    2.  **Contexte du chapitre précédent (Chapitre ${chapterNumber - 1}) :**
        ${previousChapterContent.isEmpty ? "C'est le premier chapitre. Commence par une introduction appropriée." : previousChapterContent}

    ${isUpdate ? """
    3.  **Version actuelle du chapitre $chapterNumber à améliorer :**
        $existingContent
    """ : ""}
    
    $generalPromptSection 

    **Instructions :**
    - **Tâche :** ${isUpdate ? "Mets à jour et enrichis ce chapitre en intégrant les NOUVEAUX éléments de vie fournis." : "Écris"} le **Chapitre $chapterNumber**.
    - **Style :** Narratif, personnel, à la première personne ("je").
    - **Intégration :** Tisse les "Éléments de vie" (et les descriptions d'images s'il y en a) de manière naturelle. Place le marqueur `[PHOTO_FOR_PARAGRAPH_HERE:URL_DE_LA_PHOTO]` à la fin du paragraphe pertinent.
    - **Format :** Produis uniquement le texte du chapitre, sans titre ni introduction superflue.
    """;

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $DEEPSEEK_API_KEY',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'max_tokens': 4000,
        'messages': [{'role': 'user', 'content': prompt}],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['choices'][0]['message']['content'] as String;
    } else {
      throw Exception(
          'Erreur de l\'API DeepSeek: ${response.statusCode} - ${response.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: Column(
          children: [
            _buildDialogHeader(),
            const Divider(height: 24, thickness: 1, color: Colors.blueAccent),
            if (_isVip) _buildGeneralPromptField(),
            Expanded(
              child: (_isLoadingChapters || _isLoadingCategories)
                  ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)))
                  : _buildChaptersList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralPromptField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: _promptController,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: "Instruction générale pour l'IA (VIP)",
          hintText: "Ex: 'Je veux que tu parles de mes passions dans les chapitres 1 et 2...'",
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.save, color: Colors.green),
            onPressed: _saveGeneralPrompt,
            tooltip: "Sauvegarder l'instruction",
          ),
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.auto_stories, color: Colors.blue[700], size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Mon Autobiographie',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.redAccent),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _isLoadingVisibility
            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Privé', style: TextStyle(color: _isAutobiographiePublic ? Colors.grey : Colors.red, fontWeight: FontWeight.bold)),
            Switch(
              value: _isAutobiographiePublic,
              onChanged: _toggleVisibility,
              activeColor: Colors.green,
              inactiveThumbColor: Colors.red,
            ),
            Text('Public', style: TextStyle(color: _isAutobiographiePublic ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildChaptersList() {
    final chapterCount = _chaptersData.keys.isNotEmpty
        ? (_chaptersData.keys.reduce((a, b) => a > b ? a : b)) + 1
        : 1;

    return ListView.builder(
      itemCount: chapterCount,
      itemBuilder: (context, index) {
        final chapterNumber = index + 1;
        final chapterData = _chaptersData[chapterNumber];
        return _buildChapterCard(
          chapterNumber: chapterNumber,
          chapterData: chapterData,
        );
      },
    );
  }

  Widget _buildChapterCard({
    required int chapterNumber,
    Map<String, dynamic>? chapterData,
  }) {
    final bool chapterExists = chapterData != null;
    final bool isGenerating = _generatingChapterNumber == chapterNumber;
    final themesUsed = chapterData?['themesUsed'] as List<dynamic>?;
    final chapterContent = chapterExists ? (chapterData['content'] as String) : '';

    final RegExp imageMarkerRegex = RegExp(r'\[PHOTO_FOR_PARAGRAPH_HERE:(https?:\/\/[^\s\]]+)\]');

    final List<Widget> contentWidgets = [];
    if (chapterExists) {
      List<String> paragraphs = chapterContent.split(imageMarkerRegex);
      Iterable<Match> matches = imageMarkerRegex.allMatches(chapterContent);

      for (int i = 0; i < paragraphs.length; i++) {
        String paragraph = paragraphs[i];
        if (paragraph.trim().isNotEmpty) {
          contentWidgets.add(
            Text(
              paragraph.trim(),
              style: TextStyle(height: 1.6, fontSize: 15, color: Colors.grey[800]),
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
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 200,
                        color: Colors.grey[200],
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                : null,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 200,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                      );
                    },
                  ),
                ),
              ),
            );
            contentWidgets.add(const SizedBox(height: 10));
          }
        }
      }
    }

    String buttonTooltip = '';
    if (!_canUpdateAutobio) {
      final remainingDays = 7 - DateTime.now().difference(_lastAutobioUpdate!).inDays;
      buttonTooltip = 'Attendez encore $remainingDays jour(s)';
    }


    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chapitre $chapterNumber',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 12),

            if (themesUsed != null && themesUsed.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: (themesUsed.contains('all')
                    ? [Chip(label: const Text('Tous les thèmes'), backgroundColor: Colors.lightBlue.shade100)]
                    : themesUsed
                    .map((id) =>
                    Chip(label: Text(_categoryNames[id] ?? 'Thème Inconnu'), backgroundColor: Colors.lightBlue.shade100))
                    .toList()),
              ),
            if (themesUsed != null && themesUsed.isNotEmpty) const SizedBox(height: 12),

            if (isGenerating)
              const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)),
                  ))
            else if (chapterExists)
              ...contentWidgets
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Center(
                  child: Text(
                    'Ce chapitre n\'a pas encore été généré.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: buttonTooltip,
                child: ElevatedButton.icon(
                  icon: Icon(chapterExists ? Icons.edit_note : Icons.auto_fix_high),
                  label: Text(chapterExists ? 'Éditer les thèmes' : 'Générer'),
                  onPressed: (isGenerating || !_canUpdateAutobio)
                      ? null
                      : () => _promptForThemeSelection(chapterNumber),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25)),
                    padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    elevation: 5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MovingSouvenirCard extends StatefulWidget {
  final SouvenirModel souvenir;
  final String design;
  final String size;
  final VoidCallback onSendToBack;
  final VoidCallback onReplaceRequest;
  final BoxConstraints parentConstraints;

  const MovingSouvenirCard({
    super.key,
    required this.souvenir,
    required this.design,
    required this.size,
    required this.onSendToBack,
    required this.onReplaceRequest,
    required this.parentConstraints,
  });

  @override
  _MovingSouvenirCardState createState() => _MovingSouvenirCardState();
}

class _MovingSouvenirCardState extends State<MovingSouvenirCard>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  double _positionX = 0.0;
  double _positionY = 0.0;
  double _velocityX = 0.0;
  double _velocityY = 0.0;
  double _rotation = 0.0;
  bool _isAnimating = true;
  int _collisionCount = 0;

  double _randomOffsetX = 0.0;
  double _randomOffsetY = 0.0;
  double _randomFrequencyX = 1.0;
  double _randomFrequencyY = 1.0;
  double _randomAmplitudeX = 1.0;
  double _randomAmplitudeY = 1.0;

  static const double maxSpeed = 4.0;
  final Random random = Random();

  String _animationStyle = 'default';
  String _animationSpeed = 'normal';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeState();
  }

// --- CORRECTION : Taille unifiée pour la carte (carré) ---
  double get cardSize {
    // Taille de base unifiée pour souvenirs et journées
    double baseSize = 250.0;
    switch (widget.size) {
      case 'tres_petit':
        return baseSize * 0.7;
      case 'petit':
        return baseSize * 0.85;
      case 'normal':
        return baseSize;
      case 'gros':
        return baseSize * 1.1;
      default:
        return baseSize;
    }
  }

// Les getters pour la largeur et la hauteur utilisent maintenant la même taille
  double get cardWidth => cardSize;
  double get cardHeight => cardSize;


  void _initializeState() {
    _controller = AnimationController(vsync: this);
    _initializeRandomFloatingParams();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _setRandomInitialPosition();
        _loadAnimationSettings();
      }
    });
    _velocityX = (random.nextDouble() - 0.5) * maxSpeed;
    _velocityY = (random.nextDouble() - 0.5) * maxSpeed;
  }

  void _initializeRandomFloatingParams() {
    _randomOffsetX = random.nextDouble() * 2 * pi;
    _randomOffsetY = random.nextDouble() * 2 * pi;
    _randomFrequencyX = random.nextDouble() * 0.4 + 0.8;
    _randomFrequencyY = random.nextDouble() * 0.4 + 0.8;
    _randomAmplitudeX = random.nextDouble() * 0.5 + 0.5;
    _randomAmplitudeY = random.nextDouble() * 0.5 + 0.5;
  }
  Future<void> _loadAnimationSettings() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _animationStyle = prefs.getString('cardAnimation') ?? 'default';
        _animationSpeed = prefs.getString('animationSpeed') ?? 'normal';
      });
      _initializeAnimation();
    } catch (e) {
      print('Erreur de chargement du style d\'animation : $e');
      _animationStyle = 'default';
      _initializeAnimation();
    }
  }

  void _setRandomInitialPosition() {
    final parentWidth = widget.parentConstraints.maxWidth;
    final parentHeight = widget.parentConstraints.maxHeight;

    if (parentWidth > cardWidth && parentHeight > cardHeight) {
      final shapePath = _getCardShape(widget.design).getOuterPath(Rect.fromLTWH(0, 0, cardWidth, cardHeight));
      final bounds = shapePath.getBounds();

      final double minX = 0 - bounds.left;
      final double maxX = parentWidth - bounds.right;
      final double minY = 0 - bounds.top;
      final double maxY = parentHeight - bounds.bottom;

      if (maxX > minX && maxY > minY) {
        setState(() {
          _positionX = minX + random.nextDouble() * (maxX - minX);
          _positionY = minY + random.nextDouble() * (maxY - minY);
        });
      } else {
        setState(() {
          _positionX = (parentWidth - cardWidth) / 2;
          _positionY = (parentHeight - cardHeight) / 2;
        });
      }
    }
  }
  Duration _getAnimationDuration() {
    switch (_animationSpeed) {
      case 'lent':
        return const Duration(milliseconds: 80);
      case 'normal':
        return const Duration(milliseconds: 50);
      case 'rapide':
        return const Duration(milliseconds: 30);
      default:
        return const Duration(milliseconds: 50);
    }
  }
  double _getVelocityFactor() {
    switch (_animationSpeed) {
      case 'lent':
        return 0.7;
      case 'normal':
        return 1.0;
      case 'rapide':
        return 1.5;
      default:
        return 1.0;
    }
  }
  void _initializeAnimation() {
    _controller.stop();
    _rotation = 0.0;

    switch (_animationStyle) {
      case 'changer':
        _startFadeAnimation();
        break;
      case 'rotation':
        _startRotationAnimation();
        break;
      case 'flottant':
        _startFloatingAnimation();
        break;
      case 'pulsation':
        _startPulsingAnimation();
        break;
      default:
        _startMovingAnimation();
        break;
    }
  }

  void _startAnimation(void Function() listener) {
    _controller.dispose();
    _controller =
    AnimationController(vsync: this, duration: _getAnimationDuration())
      ..addListener(listener);
    _controller.repeat();
  }

  void _startMovingAnimation() => _startAnimation(_updateMovingPosition);
  void _startRotationAnimation() => _startAnimation(_updateRotationPosition);
  void _startFloatingAnimation() => _startAnimation(_updateFloatingPosition);

  void _startPulsingAnimation() {
    _controller.dispose();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.addListener(_updateMovingPosition);
    _controller.repeat(reverse: true);
  }

  void _startFadeAnimation() {
    _controller.dispose();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (!_isAnimating || !mounted) return;
        _setRandomInitialPosition();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_isAnimating && mounted) _controller.reverse();
        });
      } else if (status == AnimationStatus.dismissed) {
        if (!_isAnimating || !mounted) return;
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (_isAnimating && mounted) _controller.forward();
        });
      }
    });
    _controller.forward();
  }
  void _handleCollisionEvent() {
    widget.onSendToBack();
    _collisionCount++;
    if (_collisionCount >= 3) {
      widget.onReplaceRequest();
      _collisionCount = 0;
    }
  }

  void _updateMovingPosition() {
    if (!mounted) return;

    final parentWidth = widget.parentConstraints.maxWidth;
    final parentHeight = widget.parentConstraints.maxHeight;
    final factor = _getVelocityFactor();

    // Calcule la prochaine position potentielle
    final double nextX = _positionX + (_velocityX * factor);
    final double nextY = _positionY + (_velocityY * factor);

    bool hasCollided = false;

    // --- LOGIQUE DE COLLISION CORRIGÉE ---

    // Vérifie les collisions sur l'axe horizontal (murs gauche et droit)
    if (nextX <= 0 && _velocityX < 0) {
      _velocityX = -_velocityX;
      _positionX = 0; // Correction : On repositionne le widget pile sur le bord
      hasCollided = true;
    } else if (nextX + cardWidth >= parentWidth && _velocityX > 0) {
      _velocityX = -_velocityX;
      _positionX = parentWidth - cardWidth; // Correction : On repositionne sur le bord droit
      hasCollided = true;
    }

    // Vérifie les collisions sur l'axe vertical (murs haut et bas)
    if (nextY <= 0 && _velocityY < 0) {
      _velocityY = -_velocityY;
      _positionY = 0; // Correction : On repositionne sur le bord haut
      hasCollided = true;
    } else if (nextY + cardHeight >= parentHeight && _velocityY > 0) {
      _velocityY = -_velocityY;
      _positionY = parentHeight - cardHeight; // Correction : On repositionne sur le bord bas
      hasCollided = true;
    }

    // Si aucune collision n'a été détectée, on met à jour la position normalement.
    // Sinon, la position a déjà été corrigée et on déclenche l'événement.
    if (!hasCollided) {
      _positionX = nextX;
      _positionY = nextY;
    } else {
      _handleCollisionEvent();
      // Ajoute une petite variation aléatoire à la vitesse pour éviter les boucles
      _velocityX *= (0.95 + random.nextDouble() * 0.1);
      _velocityY *= (0.95 + random.nextDouble() * 0.1);
    }

    // S'assure que la vitesse ne devient pas trop grande ou trop petite
    _velocityX = _velocityX.clamp(-maxSpeed, maxSpeed);
    _velocityY = _velocityY.clamp(-maxSpeed, maxSpeed);
    if (_velocityX.abs() < 0.5) _velocityX = 0.5 * _velocityX.sign;
    if (_velocityY.abs() < 0.5) _velocityY = 0.5 * _velocityY.sign;

    // Demande à Flutter de redessiner le widget à sa nouvelle position
    if (mounted) {
      setState(() {});
    }
  }

  void _updateRotationPosition() {
    _rotation += 0.02 * _getVelocityFactor();
    _updateMovingPosition();
  }

  void _updateFloatingPosition() {
    if (!mounted) return;

    final baseFactor = _getVelocityFactor() * 0.5;
    final time = _controller.value * 2 * pi;

    final driftX = sin(time * _randomFrequencyX + _randomOffsetX) * _randomAmplitudeX;
    final driftY = cos(time * _randomFrequencyY + _randomOffsetY) * _randomAmplitudeY;

    _positionX += _velocityX.sign * driftX * baseFactor;
    _positionY += _velocityY.sign * driftY * baseFactor;

    _handleCollisionsAfterMove();

    setState(() {});
  }

  void _handleCollisionsAfterMove() {
    final shapePath = _getCardShape(widget.design).getOuterPath(Rect.fromLTWH(0, 0, cardWidth, cardHeight));
    final localBounds = shapePath.getBounds();
    final currentPath = shapePath.shift(Offset(_positionX, _positionY));
    final currentBounds = currentPath.getBounds();
    final parentWidth = widget.parentConstraints.maxWidth;
    final parentHeight = widget.parentConstraints.maxHeight;
    bool collided = false;

    if (currentBounds.left <= 0) { _velocityX = _velocityX.abs(); _positionX = 0 - localBounds.left; collided = true; }
    if (currentBounds.right >= parentWidth) { _velocityX = -_velocityX.abs(); _positionX = parentWidth - localBounds.right; collided = true; }
    if (currentBounds.top <= 0) { _velocityY = _velocityY.abs(); _positionY = 0 - localBounds.top; collided = true; }
    if (currentBounds.bottom >= parentHeight) { _velocityY = -_velocityY.abs(); _positionY = parentHeight - localBounds.bottom; collided = true; }

    if (collided) {
      _handleCollisionEvent();
    }
  }


  String _getQualiteLabel(sm.SouvenirQualite qualite) {
    switch (qualite) {
      case sm.SouvenirQualite.nostalgie: return "Nostalgie";
      case sm.SouvenirQualite.jamaisOublie: return "Jamais Oublié";
      case sm.SouvenirQualite.bonheur: return "Bonheur";
    }
  }

  Color _getQualiteColor(sm.SouvenirQualite qualite) {
    switch (qualite) {
      case sm.SouvenirQualite.nostalgie: return Colors.purple;
      case sm.SouvenirQualite.jamaisOublie: return Colors.blue;
      case sm.SouvenirQualite.bonheur: return Colors.green;
    }
  }
  ShapeBorder _getCardShape(String design) {
    switch (design) {
      case 'rond':
        return const RoundShapeBorder();
      case 'coeur':
        return const HeartShapeBorder();
      case 'etoile':
        return const StarShapeBorder();
      case 'minimaliste':
        return const SouvenirMinimalistShapeBorder();
      case 'default':
      default:
        return const SouvenirMinimalistShapeBorder();
    }
  }
  Future<Color> _loadCardColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorKey = prefs.getString('cardColor') ?? 'default';
    switch (colorKey) {
      case 'noir': return Colors.black;
      case 'bleu': return Colors.blue.shade300;
      case 'rouge': return Colors.red.shade300;
      case 'vert': return Colors.green.shade300;
      default: return Colors.blue.shade100;
    }
  }

// --- AMÉLIORATION : Restauration du popup au long-press ---
  void _showPopupCard(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true, // Le popup peut être fermé en touchant en dehors
      barrierLabel:
      MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54, // Fond sombre semi-transparent
      transitionDuration: const Duration(milliseconds: 300), // Durée de l'animation d'apparition
      pageBuilder: (context, animation, secondaryAnimation) {
        // Le contenu du dialogue
        return Center(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), // Effet de flou en arrière-plan
            child: ScaleTransition( // Animation d'échelle pour l'apparition du popup
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
              ),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9, // Largeur du popup
                height: MediaQuery.of(context).size.height * 0.6, // Hauteur du popup
                child: Card( // Utilisation de Card pour l'élévation et les coins arrondis
                  elevation: 10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient( // Dégradé pour le fond du popup
                        colors: [
                          Colors.blue.shade100,
                          Colors.white,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.2),
                          spreadRadius: 3,
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(25),
                    child: SingleChildScrollView( // Permet de faire défiler le contenu si trop long
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Affichage des informations spécifiques au souvenir
                          if (widget.souvenir.isRepost)
                            Text(
                              'Republié de ${widget.souvenir.repostedFromUserName ?? 'un ami'}',
                              style: const TextStyle(
                                  fontSize: 14, color: Colors.grey),
                            ),
                          Text(
                            widget.souvenir.texte,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          if (widget.souvenir.photoUrls.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                widget.souvenir.photoUrls.first,
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            )
                          ],
                          const SizedBox(height: 16),
                          Text(
                            DateFormat('yyyy-MM-dd')
                                .format(widget.souvenir.date),
                            style: const TextStyle(
                                fontSize: 15, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.star,
                                  color: _getQualiteColor( // Affiche la couleur de qualité
                                      widget.souvenir.qualite),
                                  size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Qualité: ${_getQualiteLabel(widget.souvenir.qualite)}', // Affiche le label de qualité
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _getQualiteColor(
                                      widget.souvenir.qualite),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Note: ${widget.souvenir.noteQualite}/100', // Affiche la note de qualité
                            style: const TextStyle(
                                fontSize: 16, color: Colors.black87),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                widget.souvenir.estPublic
                                    ? Icons.public
                                    : Icons.lock,
                                color: widget.souvenir.estPublic
                                    ? Colors.green
                                    : Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.souvenir.estPublic
                                    ? 'Visibilité: Public'
                                    : 'Visibilité: Privé',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: widget.souvenir.estPublic
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bool isSpecialShape = widget.design == 'coeur' || widget.design == 'etoile' || widget.design == 'rond';

    return FutureBuilder<Color>(
      future: _loadCardColor(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final cardColor = snapshot.data!;

        return Positioned(
            left: _positionX,
            top: _positionY,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                double currentScale = 1.0;
                double currentOpacity = 1.0;

                if (_animationStyle == 'changer') {
                  currentOpacity = _fadeAnimation.value;
                } else if (_animationStyle == 'pulsation' && _controller.isAnimating) {
                  currentScale = _pulseAnimation.value;
                }

                return Opacity(
                  opacity: currentOpacity,
                  child: Transform.rotate(
                    angle: _rotation,
                    child: Transform.scale(
                      scale: currentScale,
                      child: child,
                    ),
                  ),
                );
              },
              // --- CORRECTION : SizedBox est maintenant un carré ---
              child: GestureDetector(
                onLongPress: () => _showPopupCard(context),
                child: SizedBox(
                  width: cardWidth, // Utilise cardWidth (qui est égal à cardHeight)
                  height: cardHeight, // Utilise cardHeight (qui est égal à cardWidth)
                  child: Container(
                    decoration: BoxDecoration(
                      // La bordure verte est appliquée au conteneur carré
                      border: Border.all(color: Colors.green, width: 2.0),
                    ),
                    child: Card(
                      margin: EdgeInsets.zero,
                      elevation: 8,
                      clipBehavior: Clip.antiAlias,
                      shape: _getCardShape(widget.design),
                      child: Container(
                        padding: widget.design == 'minimaliste' ? const EdgeInsets.all(10.0) : const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [cardColor, Colors.white],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: _buildRectangularContent(
                          isMinimaliste: widget.design == 'minimaliste',
                          titleFontSize: widget.design == 'minimaliste' ? 13 : 16,
                          titleMaxLines: widget.design == 'minimaliste' ? 2 : null,
                          isSpecialShape: isSpecialShape,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
        );
      },
    );
  }

// --- AMÉLIORATION : Contenu conditionnel pour les formes spéciales
  Widget _buildRectangularContent({
    required bool isMinimaliste,
    double? titleFontSize,
    int? titleMaxLines,
    bool isSpecialShape = false,
  }) {
    final finalTitleFontSize = titleFontSize ?? 16;

    if (isSpecialShape) {
      // Pour les formes spéciales (cœur, étoile, rond), le 'padding' est déjà
      // géré par le conteneur parent. On retire le 'Padding' redondant ici
      // pour que le texte occupe l'espace disponible à l'intérieur de la forme.
      return Center(
        child: Text(
          widget.souvenir.texte,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: finalTitleFontSize,
              height: 1.4,
              color: Colors.black87,
              fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
          maxLines: 5,
        ),
      );
    }

    // Le reste de la logique pour les cartes "standard" et "minimaliste" reste inchangé.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Contenu du haut
        if (widget.souvenir.isRepost)
          Text(
            'De ${widget.souvenir.repostedFromUserName ?? 'un ami'}',
            style: TextStyle(fontSize: isMinimaliste ? 10 : 11, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
        Text(
          widget.souvenir.texte,
          style: TextStyle(
              fontSize: finalTitleFontSize,
              height: 1.4,
              color: Colors.black87,
              fontWeight: FontWeight.w500),
          maxLines: titleMaxLines,
          overflow: TextOverflow.ellipsis,
        ),
        if (widget.souvenir.photoUrls.isNotEmpty) ...[
          SizedBox(height: isMinimaliste ? 4 : 8),
          SizedBox(
            height: isMinimaliste ? 30 : 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.souvenir.photoUrls.length,
              itemBuilder: (context, index) => Padding(
                padding: EdgeInsets.only(right: isMinimaliste ? 4.0 : 6.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isMinimaliste ? 4.0 : 8.0),
                  child: Image.network(
                    widget.souvenir.photoUrls[index],
                    width: isMinimaliste ? 30 : 60,
                    height: isMinimaliste ? 30 : 60,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
        // Contenu du bas
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              DateFormat('yyyy-MM-dd').format(widget.souvenir.date),
              style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                  fontSize: isMinimaliste ? 10 : 12),
            ),
            if (isMinimaliste)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: _getQualiteColor(widget.souvenir.qualite).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _getQualiteLabel(widget.souvenir.qualite),
                  style: TextStyle(
                      color: _getQualiteColor(widget.souvenir.qualite),
                      fontSize: 9,
                      fontWeight: FontWeight.bold),
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stars_outlined,
                      size: 14,
                      color: _getQualiteColor(widget.souvenir.qualite)),
                  const SizedBox(width: 4),
                  Text(
                    _getQualiteLabel(widget.souvenir.qualite),
                    style: TextStyle(
                        fontSize: 12,
                        color: _getQualiteColor(widget.souvenir.qualite),
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
          ],
        ),
        if (!isMinimaliste) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Note: ${widget.souvenir.noteQualite}/100',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ]
      ],
    );
  }


  @override
  void dispose() {
    _isAnimating = false;
    _controller.dispose();
    super.dispose();
  }
}


class MovingJourneeCard extends StatefulWidget {
  final JourneeModel journee;
  final String design;
  final String size;
  final VoidCallback onSendToBack;
  final VoidCallback onReplaceRequest;
  final BoxConstraints parentConstraints;

  const MovingJourneeCard({
    super.key,
    required this.journee,
    required this.design,
    required this.size,
    required this.onSendToBack,
    required this.onReplaceRequest,
    required this.parentConstraints,
  });

  @override
  _MovingJourneeCardState createState() => _MovingJourneeCardState();
}

class _MovingJourneeCardState extends State<MovingJourneeCard>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  double _positionX = 0.0;
  double _positionY = 0.0;
  double _velocityX = 0.0;
  double _velocityY = 0.0;
  double _rotation = 0.0;
  bool _isAnimating = true;
  int _collisionCount = 0;

  double _randomOffsetX = 0.0;
  double _randomOffsetY = 0.0;
  double _randomFrequencyX = 1.0;
  double _randomFrequencyY = 1.0;
  double _randomAmplitudeX = 1.0;
  double _randomAmplitudeY = 1.0;

  static const double maxSpeed = 3.0;
  final Random random = Random();

  String _animationStyle = 'default';
  String _animationSpeed = 'normal';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeState();
  }

  // --- CORRECTION : Taille unifiée pour la carte (carré) ---
  double get cardSize {
    // Taille de base unifiée pour souvenirs et journées
    double baseSize = 250.0;
    switch (widget.size) {
      case 'tres_petit':
        return baseSize * 0.7;
      case 'petit':
        return baseSize * 0.85;
      case 'normal':
        return baseSize;
      case 'gros':
        return baseSize * 1.1;
      default:
        return baseSize;
    }
  }

  // Les getters pour la largeur et la hauteur utilisent maintenant la même taille
  double get cardWidth => cardSize;
  double get cardHeight => cardSize;


  void _initializeState() {
    _controller = AnimationController(vsync: this);
    _initializeRandomFloatingParams();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _setRandomInitialPosition();
        _loadAnimationSettings();
      }
    });

    _velocityX = (random.nextDouble() - 0.5) * maxSpeed;
    _velocityY = (random.nextDouble() - 0.5) * maxSpeed;
  }

  void _initializeRandomFloatingParams() {
    _randomOffsetX = random.nextDouble() * 2 * pi;
    _randomOffsetY = random.nextDouble() * 2 * pi;
    _randomFrequencyX = random.nextDouble() * 0.4 + 0.8;
    _randomFrequencyY = random.nextDouble() * 0.4 + 0.8;
    _randomAmplitudeX = random.nextDouble() * 0.5 + 0.5;
    _randomAmplitudeY = random.nextDouble() * 0.5 + 0.5;
  }

  Future<void> _loadAnimationSettings() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _animationStyle =
            prefs.getString('journeeAnimation') ?? 'default';
        _animationSpeed = prefs.getString('animationSpeed') ?? 'normal';
      });
      _initializeAnimation();
    } catch (e) {
      print('Erreur de chargement du style d\'animation : $e');
      _animationStyle = 'default';
      _initializeAnimation();
    }
  }

  void _setRandomInitialPosition() {
    final parentWidth = widget.parentConstraints.maxWidth;
    final parentHeight = widget.parentConstraints.maxHeight;

    if (parentWidth > cardWidth && parentHeight > cardHeight) {
      final shapePath = _getCardShape(widget.design).getOuterPath(
          Rect.fromLTWH(0, 0, cardWidth, cardHeight));
      final bounds = shapePath.getBounds();

      final double minX = 0 - bounds.left;
      final double maxX = parentWidth - bounds.right;
      final double minY = 0 - bounds.top;
      final double maxY = parentHeight - bounds.bottom;

      if (maxX > minX && maxY > minY) {
        setState(() {
          _positionX = minX + random.nextDouble() * (maxX - minX);
          _positionY = minY + random.nextDouble() * (maxY - minY);
        });
      } else {
        setState(() {
          _positionX = (parentWidth - cardWidth) / 2;
          _positionY = (parentHeight - cardHeight) / 2;
        });
      }
    }
  }

  Duration _getAnimationDuration() {
    switch (_animationSpeed) {
      case 'lent':
        return const Duration(milliseconds: 80);
      case 'normal':
        return const Duration(milliseconds: 50);
      case 'rapide':
        return const Duration(milliseconds: 30);
      default:
        return const Duration(milliseconds: 50);
    }
  }

  double _getVelocityFactor() {
    switch (_animationSpeed) {
      case 'lent':
        return 0.7;
      case 'normal':
        return 1.0;
      case 'rapide':
        return 1.5;
      default:
        return 1.0;
    }
  }

  void _initializeAnimation() {
    _controller.stop();
    _rotation = 0.0;

    switch (_animationStyle) {
      case 'changer':
        _startFadeAnimation();
        break;
      case 'rotation':
        _startRotationAnimation();
        break;
      case 'flottant':
        _startFloatingAnimation();
        break;
      case 'pulsation':
        _startPulsingAnimation();
        break;
      default:
        _startMovingAnimation();
        break;
    }
  }

  void _startAnimation(void Function() listener) {
    _controller.dispose();
    _controller =
    AnimationController(vsync: this, duration: _getAnimationDuration())
      ..addListener(listener);
    _controller.repeat();
  }

  void _startMovingAnimation() => _startAnimation(_updateMovingPosition);

  void _startRotationAnimation() => _startAnimation(_updateRotationPosition);

  void _startFloatingAnimation() => _startAnimation(_updateFloatingPosition);

  void _startPulsingAnimation() {
    _controller.dispose();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.addListener(_updateMovingPosition);
    _controller.repeat(reverse: true);
  }

  void _startFadeAnimation() {
    _controller.dispose();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (!_isAnimating || !mounted) return;
        _setRandomInitialPosition();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_isAnimating && mounted) _controller.reverse();
        });
      } else if (status == AnimationStatus.dismissed) {
        if (!_isAnimating || !mounted) return;
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (_isAnimating && mounted) _controller.forward();
        });
      }
    });
    _controller.forward();
  }

  void _handleCollisionEvent() {
    widget.onSendToBack();
    _collisionCount++;
    if (_collisionCount >= 3) {
      widget.onReplaceRequest();
      _collisionCount = 0;
    }
  }

  void _updateMovingPosition() {
    if (!mounted) return;

    final parentWidth = widget.parentConstraints.maxWidth;
    final parentHeight = widget.parentConstraints.maxHeight;
    final factor = _getVelocityFactor();

    // Calcule la prochaine position potentielle
    final double nextX = _positionX + (_velocityX * factor);
    final double nextY = _positionY + (_velocityY * factor);

    bool hasCollided = false;

    // --- LOGIQUE DE COLLISION CORRIGÉE ---

    // Vérifie les collisions sur l'axe horizontal (murs gauche et droit)
    if (nextX <= 0 && _velocityX < 0) {
      _velocityX = -_velocityX;
      _positionX = 0; // Correction : On repositionne le widget pile sur le bord
      hasCollided = true;
    } else if (nextX + cardWidth >= parentWidth && _velocityX > 0) {
      _velocityX = -_velocityX;
      _positionX = parentWidth - cardWidth; // Correction : On repositionne sur le bord droit
      hasCollided = true;
    }

    // Vérifie les collisions sur l'axe vertical (murs haut et bas)
    if (nextY <= 0 && _velocityY < 0) {
      _velocityY = -_velocityY;
      _positionY = 0; // Correction : On repositionne sur le bord haut
      hasCollided = true;
    } else if (nextY + cardHeight >= parentHeight && _velocityY > 0) {
      _velocityY = -_velocityY;
      _positionY = parentHeight - cardHeight; // Correction : On repositionne sur le bord bas
      hasCollided = true;
    }

    // Si aucune collision n'a été détectée, on met à jour la position normalement.
    // Sinon, la position a déjà été corrigée et on déclenche l'événement.
    if (!hasCollided) {
      _positionX = nextX;
      _positionY = nextY;
    } else {
      _handleCollisionEvent();
      // Ajoute une petite variation aléatoire à la vitesse pour éviter les boucles
      _velocityX *= (0.95 + random.nextDouble() * 0.1);
      _velocityY *= (0.95 + random.nextDouble() * 0.1);
    }

    // S'assure que la vitesse ne devient pas trop grande ou trop petite
    _velocityX = _velocityX.clamp(-maxSpeed, maxSpeed);
    _velocityY = _velocityY.clamp(-maxSpeed, maxSpeed);
    if (_velocityX.abs() < 0.5) _velocityX = 0.5 * _velocityX.sign;
    if (_velocityY.abs() < 0.5) _velocityY = 0.5 * _velocityY.sign;

    // Demande à Flutter de redessiner le widget à sa nouvelle position
    if (mounted) {
      setState(() {});
    }
  }

  void _updateRotationPosition() {
    _rotation += 0.02 * _getVelocityFactor();
    _updateMovingPosition();
  }

  void _updateFloatingPosition() {
    if (!mounted) return;

    final baseFactor = _getVelocityFactor() * 0.5;
    final time = _controller.value * 2 * pi;

    final driftX = sin(time * _randomFrequencyX + _randomOffsetX) *
        _randomAmplitudeX;
    final driftY = cos(time * _randomFrequencyY + _randomOffsetY) *
        _randomAmplitudeY;

    _positionX += _velocityX.sign * driftX * baseFactor;
    _positionY += _velocityY.sign * driftY * baseFactor;

    _handleCollisionsAfterMove();

    setState(() {});
  }

  void _handleCollisionsAfterMove() {
    final shapePath = _getCardShape(widget.design).getOuterPath(
        Rect.fromLTWH(0, 0, cardWidth, cardHeight));
    final localBounds = shapePath.getBounds();
    final currentPath = shapePath.shift(Offset(_positionX, _positionY));
    final currentBounds = currentPath.getBounds();
    final parentWidth = widget.parentConstraints.maxWidth;
    final parentHeight = widget.parentConstraints.maxHeight;
    bool collided = false;

    if (currentBounds.left <= 0) {
      _velocityX = _velocityX.abs();
      _positionX = 0 - localBounds.left;
      collided = true;
    }
    if (currentBounds.right >= parentWidth) {
      _velocityX = -_velocityX.abs();
      _positionX = parentWidth - localBounds.right;
      collided = true;
    }
    if (currentBounds.top <= 0) {
      _velocityY = _velocityY.abs();
      _positionY = 0 - localBounds.top;
      collided = true;
    }
    if (currentBounds.bottom >= parentHeight) {
      _velocityY = -_velocityY.abs();
      _positionY = parentHeight - localBounds.bottom;
      collided = true;
    }

    if (collided) {
      _handleCollisionEvent();
    }
  }

  Future<Color> _loadCardColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorKey = prefs.getString('journeeCardColor') ?? 'default';
    switch (colorKey) {
      case 'noir':
        return Colors.black;
      case 'bleu':
        return Colors.blue.shade300;
      case 'rouge':
        return Colors.red.shade300;
      case 'vert':
        return Colors.green.shade300;
      default:
        return Colors.blue.shade100;
    }
  }

  ShapeBorder _getCardShape(String design) {
    switch (design) {
      case 'rond':
        return const RoundShapeBorder();
      case 'coeur':
        return const HeartShapeBorder();
      case 'etoile':
        return const StarShapeBorder();
      case 'minimaliste':
        return const JourneeMinimalistShapeBorder();
      case 'default':
      default:
        return const JourneeMinimalistShapeBorder();
    }
  }

// --- AMÉLIORATION : Restauration du popup au long-press ---
  void _showPopupCard(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      // Le popup peut être fermé en touchant en dehors
      barrierLabel: MaterialLocalizations
          .of(context)
          .modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      // Fond sombre semi-transparent
      transitionDuration: const Duration(milliseconds: 300),
      // Durée de l'animation d'apparition
      pageBuilder: (context, animation, secondaryAnimation) {
        // Le contenu du dialogue
        return Center(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            // Effet de flou en arrière-plan
            child: ScaleTransition( // Animation d'échelle pour l'apparition du popup
              scale: CurvedAnimation(
                  parent: animation, curve: Curves.easeOutBack),
              child: Container(
                width: MediaQuery
                    .of(context)
                    .size
                    .width * 0.9, // Largeur du popup
                height: MediaQuery
                    .of(context)
                    .size
                    .height * 0.7, // Hauteur du popup
                margin: const EdgeInsets.all(16),
                child: Material( // Utilisation de Material pour l'élévation et les coins arrondis
                  elevation: 10,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient( // Dégradé pour le fond du popup
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.blue.shade100, Colors.white],
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView( // Permet de faire défiler le contenu si trop long
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                            child: StatefulBuilder( // Permet de mettre à jour l'état à l'intérieur du dialogue
                              builder: (BuildContext context,
                                  StateSetter setDialogState) {
                                bool isSearching = false;
                                String? searchError;
                                List<MapEntry<JourneeModel,
                                    double>>? displayedSimilarities;
                                DateTime? lastSearchDate;
                                bool hasResultsInCache = false;

                                // Charge les résultats de similarité en cache (s'ils existent)
                                Future<void> loadCache() async {
                                  if (widget.journee.id == null) return;
                                  final doc = await FirebaseFirestore.instance
                                      .collection('journees')
                                      .doc(widget.journee.id)
                                      .get();
                                  if (!doc.exists) return;

                                  final data = doc.data();
                                  final cache = data?['similarJourneesCache'] as Map<
                                      String,
                                      dynamic>?;
                                  final lastSearchTimestamp = data?['lastSimilaritySearchDate'] as Timestamp?;

                                  if (lastSearchTimestamp != null) {
                                    lastSearchDate =
                                        lastSearchTimestamp.toDate();
                                  }

                                  if (cache != null && cache.isNotEmpty) {
                                    hasResultsInCache = true;
                                    // Reconstitue les objets JourneeModel à partir des IDs en cache
                                    final futures = cache.entries.map((
                                        entry) async {
                                      final journeeDoc = await FirebaseFirestore
                                          .instance
                                          .collection('journees')
                                          .doc(entry.key)
                                          .get();
                                      if (journeeDoc.exists) {
                                        return MapEntry(
                                          JourneeModel.fromFirestore(
                                              journeeDoc),
                                          (entry.value as num).toDouble(),
                                        );
                                      }
                                      return null;
                                    }).toList();

                                    final results = (await Future.wait(futures))
                                        .whereType<
                                        MapEntry<JourneeModel, double>>()
                                        .toList();
                                    results.sort((a, b) => b.value.compareTo(
                                        a.value)); // Trie par similarité
                                    displayedSimilarities = results;
                                  }
                                }

                                // Gère la recherche et la mise à jour des journées similaires
                                Future<void> handleSearch() async {
                                  setDialogState(() {
                                    isSearching = true;
                                    searchError = null;
                                  });

                                  try {
                                    // Appelle la fonction de recherche de similarité
                                    final results = await _findSimilarJournees(
                                        widget.journee,
                                        searchAfter: lastSearchDate);

                                    // Sauvegarde les résultats et le timestamp de recherche dans Firestore
                                    await FirebaseFirestore.instance.collection(
                                        'journees').doc(widget.journee.id).set({
                                      'similarJourneesCache': results.map((key,
                                          value) => MapEntry(key.id!, value)),
                                      'lastSimilaritySearchDate': FieldValue
                                          .serverTimestamp(),
                                    }, SetOptions(merge: true));

                                    setDialogState(() {
                                      displayedSimilarities =
                                          results.entries.toList();
                                      hasResultsInCache = results.isNotEmpty;
                                      lastSearchDate = DateTime.now();
                                    });
                                  } catch (e) {
                                    setDialogState(() {
                                      searchError = "Erreur: ${e.toString()}";
                                    });
                                  } finally {
                                    setDialogState(() {
                                      isSearching = false;
                                    });
                                  }
                                }

                                // Construction de l'UI du contenu du dialogue
                                return FutureBuilder(
                                    future: loadCache(),
                                    // Charge le cache au démarrage
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Center(
                                            child: CircularProgressIndicator());
                                      }

                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment
                                            .start,
                                        children: [
                                          // Informations sur la journée actuelle
                                          Text(
                                              DateFormat('EEEE d MMMM yyyy')
                                                  .format(widget.journee.date),
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue)
                                          ),
                                          const SizedBox(height: 12),
                                          Text(widget.journee.texte1 ??
                                              'Aucune description',
                                              style: const TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.black87,
                                                  height: 1.4)),
                                          const SizedBox(height: 16),

                                          const Divider(height: 32),

                                          // Affichage des journées similaires ou des messages d'erreur/absence
                                          if (searchError != null)
                                            Center(child: Text(searchError!,
                                                style: const TextStyle(
                                                    color: Colors.red)))
                                          else
                                            if (displayedSimilarities != null &&
                                                displayedSimilarities!
                                                    .isNotEmpty)
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment
                                                    .start,
                                                children: [
                                                  const Text(
                                                      'Journées similaires',
                                                      style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: FontWeight
                                                              .bold,
                                                          color: Colors.blue)),
                                                  const SizedBox(height: 8),
                                                  ...displayedSimilarities!
                                                      .map((entry) {
                                                    // Carte pour chaque journée similaire trouvée
                                                    return Card(
                                                      margin: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 4),
                                                      child: ListTile(
                                                        title: Text(DateFormat(
                                                            'd MMMM yyyy')
                                                            .format(
                                                            entry.key.date)),
                                                        subtitle: Text(
                                                            entry.key.texte1 ??
                                                                '', maxLines: 1,
                                                            overflow: TextOverflow
                                                                .ellipsis),
                                                        trailing: Text(
                                                            '${entry.value
                                                                .toStringAsFixed(
                                                                0)}%',
                                                            style: const TextStyle(
                                                                fontWeight: FontWeight
                                                                    .bold)),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ],
                                              )
                                            else
                                              if (lastSearchDate != null &&
                                                  !hasResultsInCache)
                                                const Center(
                                                  child: Padding(
                                                    padding: EdgeInsets
                                                        .symmetric(
                                                        vertical: 16.0),
                                                    child: Text(
                                                      "Aucune journée similaire n'a été trouvée lors de la dernière analyse.",
                                                      textAlign: TextAlign
                                                          .center,
                                                      style: TextStyle(
                                                          fontStyle: FontStyle
                                                              .italic,
                                                          color: Colors.grey),
                                                    ),
                                                  ),
                                                ),

                                          const SizedBox(height: 20),

                                          // Bouton de recherche/mise à jour
                                          Center(
                                            child: isSearching
                                                ? const CircularProgressIndicator()
                                                : ElevatedButton.icon(
                                              icon: Icon(hasResultsInCache
                                                  ? Icons.sync
                                                  : Icons.search),
                                              label: Text(hasResultsInCache
                                                  ? 'Mettre à jour'
                                                  : 'Rechercher des journées similaires'),
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
                        // Bouton de fermeture
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

  Future<Map<JourneeModel, double>> _findSimilarJournees(
      JourneeModel selectedJournee, {DateTime? searchAfter}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    final selectedText = selectedJournee.texte1 ??
        selectedJournee.commentaire ?? '';
    if (selectedText
        .trim()
        .isEmpty) return {}; // Pas de texte, pas de similarité

    Query journeesQuery = FirebaseFirestore.instance
        .collection('journees')
        .where('userId', isEqualTo: user.uid)
        .where(
        'id', isNotEqualTo: selectedJournee.id); // Exclure la journée elle-même

    if (searchAfter != null) {
      journeesQuery = journeesQuery.where(
          'date', isGreaterThan: Timestamp.fromDate(searchAfter));
    }

    final allJourneesSnapshot = await journeesQuery.get();
    final similarJourneesFutures = <Future<MapEntry<JourneeModel, double>?>>[];

    for (var doc in allJourneesSnapshot.docs) {
      final journee = JourneeModel.fromFirestore(doc); // Crée un modèle Journee
      final journeeText = journee.texte1 ?? journee.commentaire ?? '';
      if (journeeText.isEmpty) continue; // Si le texte est vide, on l'ignore

      // Calcule la similarité entre les deux textes en utilisant l'API DeepSeek
      similarJourneesFutures.add(
          _calculateSimilarity(selectedText, journeeText).then((similarity) {
            if (similarity >
                30) { // Seuil de 30% pour considérer comme similaire
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

    // Trie les journées similaires par ordre décroissant de similarité
    final sortedEntries = similarJournees.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Map.fromEntries(
        sortedEntries.take(5)); // Retourne les 5 journées les plus similaires
  }

  /// Calcule un pourcentage de similarité entre deux chaînes de texte en utilisant l'API DeepSeek.
  ///
  /// @param text1 Le premier texte à comparer.
  /// @param text2 Le deuxième texte à comparer.
  /// @returns Un double représentant le pourcentage de similarité (0-100).
  Future<double> _calculateSimilarity(String text1, String text2) async {
    // ... (Logique d'appel à l'API DeepSeek pour le calcul de similarité,
    //      incluant l'envoi des deux textes et la récupération du pourcentage) ...
    //      Cette méthode est déjà présente dans le code que vous avez fourni
    //      dans `HomePageState` et a été dupliquée pour la clarté et l'encapsulation ici.
    //      Je ne la répète pas entièrement pour économiser de l'espace.
    // ... (Code existant pour _calculateSimilarity) ...
    if (DEEPSEEK_API_KEY == 'sk-2891f44dd4e344908dda525bf5852649') {
      // Message d'erreur ou comportement par défaut si la clé API n'est pas configurée
    }
    const String url = 'https://api.deepseek.com/v1/chat/completions';

    if (text1
        .trim()
        .isEmpty || text2
        .trim()
        .isEmpty) return 0.0;

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {
              'role': 'user',
              'content':
              '''Compare les deux textes suivants et donne un pourcentage de similarité basé sur leur contenu, leur ton et leurs thèmes principaux. Réponds uniquement avec un nombre entier entre 0 et 100 suivi de "/100", par exemple "75/100".

                  Texte 1: $text1
                  Texte 2: $text2'''
            }
          ],
          'max_tokens': 50,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]['message']['content']?.toString() ??
            '';

        if (content.isEmpty) {
          print(
              'Avertissement: Réponse vide de DeepSeek pour le calcul de similarité.');
          return 0.0;
        }

        final match = RegExp(r'(\d+)\s*/\s*100').firstMatch(content);
        if (match != null && match.group(1) != null) {
          return double.parse(match.group(1)!);
        }

        final numberMatch = RegExp(r'\b(\d+)\b').firstMatch(content);
        if (numberMatch != null && numberMatch.group(1) != null) {
          return double.parse(numberMatch.group(1)!);
        }

        print(
            'Avertissement: Format de réponse de similarité inattendu: "$content"');
        return 0.0;
      } else {
        print('Erreur API DeepSeek pour similarité: ${response
            .statusCode} - ${response.body}');
        return 0.0;
      }
    } catch (e, stacktrace) {
      print('Erreur lors du calcul de la similarité : $e\n$stacktrace');
      return 0.0;
    }
  }



  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bool isSpecialShape = widget.design == 'coeur' || widget.design == 'etoile' || widget.design == 'rond';

    return FutureBuilder<Color>(
      future: _loadCardColor(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final cardColor = snapshot.data!;

        return Positioned(
            left: _positionX,
            top: _positionY,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                double currentScale = 1.0;
                double currentOpacity = 1.0;

                if (_animationStyle == 'changer') {
                  currentOpacity = _fadeAnimation.value;
                } else if (_animationStyle == 'pulsation' && _controller.isAnimating) {
                  currentScale = _pulseAnimation.value;
                }

                return Opacity(
                  opacity: currentOpacity,
                  child: Transform.rotate(
                    angle: _rotation,
                    child: Transform.scale(
                      scale: currentScale,
                      child: child,
                    ),
                  ),
                );
              },
              // --- CORRECTION : SizedBox est maintenant un carré ---
              child: GestureDetector(
                onLongPress: () => _showPopupCard(context),
                child: SizedBox(
                  width: cardWidth, // Utilise cardWidth (qui est égal à cardHeight)
                  height: cardHeight, // Utilise cardHeight (qui est égal à cardWidth)
                  child: Container(
                    decoration: BoxDecoration(
                      // La bordure verte est appliquée au conteneur carré
                      border: Border.all(color: Colors.green, width: 2.0),
                    ),
                    child: Card(
                      margin: EdgeInsets.zero,
                      elevation: 8,
                      clipBehavior: Clip.antiAlias,
                      shape: _getCardShape(widget.design),
                      child: Container(
                        padding: widget.design == 'minimaliste' ? const EdgeInsets.all(12.0) : const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [cardColor, Colors.white],
                          ),
                        ),
                        child: _buildRectangularContent(
                          isMinimaliste: widget.design == 'minimaliste',
                          isSpecialShape: isSpecialShape,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
        );
      },
    );
  }

// --- AMÉLIORATION : Contenu conditionnel pour les formes spéciales
  Widget _buildRectangularContent({
    required bool isMinimaliste,
    double? titleFontSize,
    int? titleMaxLines,
    bool isSpecialShape = false,
  }) {
    if (isSpecialShape) {
      // Pour les formes spéciales (cœur, étoile, rond), on retire le 'Padding'
      // redondant pour que le texte remplisse mieux la forme, comme pour les souvenirs.
      return Center(
        child: Text(
          widget.journee.texte1 ?? 'Aucune description',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Colors.black87, height: 1.4),
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    // Le reste de la logique pour les cartes "standard" et "minimaliste" reste inchangé.
    if (isMinimaliste) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.journee.emoji ?? '', style: const TextStyle(fontSize: 24)),
              Text(
                DateFormat('dd/MM/yyyy').format(widget.journee.date),
                style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 11),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Text(
                widget.journee.texte1 ?? 'Aucune description',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              'Note: ${widget.journee.note ?? 'N/A'}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 11),
            ),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.journee.isRepost)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(
                'De ${widget.journee.repostedFromUserName ?? 'un ami'}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.journee.emoji ?? '', style: const TextStyle(fontSize: 28)),
              Chip(
                label: Text(
                  widget.journee.estPublic ? 'Public' : 'Privé',
                  style: TextStyle(
                      color: widget.journee.estPublic ? Colors.green : Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
                backgroundColor: widget.journee.estPublic ? Colors.green.shade50 : Colors.red.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            child: Text(
              widget.journee.texte1 ?? 'Aucune description',
              style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
            ),
          ),
          if (widget.journee.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.journee.photoUrls.length,
                itemBuilder: (context, index) {
                  final imageUrl = widget.journee.photoUrls[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image.network(imageUrl, width: 60, height: 60, fit: BoxFit.cover),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                DateFormat('yyyy-MM-dd').format(widget.journee.date),
                style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 11),
              ),
              Text(
                'Note: ${widget.journee.note ?? 'Non évaluée'}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 11),
              ),
            ],
          ),
        ],
      );
    }
  }
  @override
  void dispose() {
    _isAnimating = false;
    _controller.dispose();
    super.dispose();
  }
}

class _BlinkingDots extends StatefulWidget {
  const _BlinkingDots({Key? key}) : super(key: key);

  @override
  _BlinkingDotsState createState() => _BlinkingDotsState();
}

class _BlinkingDotsState extends State<_BlinkingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _controller.value,
          child: const Text(
            '...',
            style: TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  TabController? _tabController;
  List<JourneeModel> _myJournees = [];
  List<SouvenirModel> _mySouvenirs = [];
  ValueNotifier<String> journeeFilterNotifier = ValueNotifier<String>('tout');
  ValueNotifier<String> souvenirFilterNotifier = ValueNotifier<String>('tout');
  List<JourneeModel> _displayedJournees = [];
  List<JourneeModel> _filteredJournees = [];
  List<SouvenirModel> _displayedSouvenirs = [];
  List<SouvenirModel> _filteredSouvenirs = [];
  late Future<String> _cardSizeFuture;

  List<JourneeModel> _friendsJournees = [];
  List<JourneeModel> _globalJournees = [];
  List<SouvenirModel> _souvenirs = [];
  List<String> _friendIds = [];
  final _firestore = FirebaseFirestore.instance;
  DateTime _today = DateTime.now();
  bool _isLoading = false;
  ValueNotifier<Brightness> appBrightnessNotifier = ValueNotifier<Brightness>(Brightness.light);

  late PageController _verticalMainPageController;
  late PageController _journeePageController;
  StreamSubscription<QuerySnapshot>? _myJourneesSubscription;
  StreamSubscription<QuerySnapshot>? _friendsJourneesSubscription;
  StreamSubscription<QuerySnapshot>? _globalJourneesSubscription;
  StreamSubscription<QuerySnapshot>? _mySouvenirsSubscription;
  Map<String, double> _journeeZOrders = {};
  Map<String, double> _souvenirZOrders = {};
  TextEditingController _controller = TextEditingController();
  List<String> _motsCles = [];
  int? _note;
  bool _isNoteObtained = false;
  static const int _maxDisplayedCards = 100;
  late Future<String> _journeeCardDesignFuture;
  late Future<String> _souvenirCardDesignFuture;
  @override
  bool get wantKeepAlive => true;
  bool _isVip = false;
  Map<String, Map<String, dynamic>> _userCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _verticalMainPageController = PageController(initialPage: 0);
    _journeePageController = PageController(viewportFraction: 0.85);
    _scheduleMidnightUpdate();
    _loadAppBrightness();
    _setupRealtimeListeners();
    _cardSizeFuture = _getCardSizeFromPreferences(); // <-- AJOUTEZ CETTE LIGNE

    journeeFilterNotifier.addListener(_updateDisplayedJournees);
    souvenirFilterNotifier.addListener(_updateDisplayedSouvenirs);
    _loadVipStatus();

    _journeeCardDesignFuture = _getJourneeCardDesignFromPreferences();
    _souvenirCardDesignFuture = _getCardDesignFromPreferences();
  }
  Future<void> _loadVipStatus() async {
    final data = await getUserSubscriptionData();
    if(mounted) {
      setState(() {
        _isVip = data['isVip'];
      });
    }
  }
  Future<String> _getCardSizeFromPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // La clé 'cardSize' doit correspondre à celle que vous sauvegardez dans profil_page.dart
    return prefs.getString('cardSize') ?? 'normal';
  }
  Future<Map<String, dynamic>> _getUserData(String userId) async {
    // Si l'utilisateur est déjà dans le cache, on le retourne immédiatement
    if (_userCache.containsKey(userId)) {
      return _userCache[userId]!;
    }

    // Sinon, on va le chercher dans Firestore
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        // On met à jour le cache pour les prochaines fois
        if (mounted) {
          setState(() {
            _userCache[userId] = userData;
          });
        }
        return userData;
      }
    } catch (e) {
      print("Erreur de récupération des données utilisateur pour $userId: $e");
    }
    // Retourne une valeur par défaut en cas d'erreur
    return {'username': 'Utilisateur Inconnu'};
  }

  void _updateDisplayedJournees() {
    setState(() {
      _filteredJournees = _filterJournees(_myJournees, journeeFilterNotifier.value)
          .where((j) => j.note != null)
          .toList();
      _displayedJournees = _filteredJournees.take(_maxDisplayedCards).toList();


      _journeeZOrders.clear();
      for (var i = 0; i < _displayedJournees.length; i++) {
        final journee = _displayedJournees[i];
        if (journee.id != null) {
          _journeeZOrders[journee.id!] = i.toDouble();
        }
      }
    });
  }
  void _updateDisplayedSouvenirs() {
    setState(() {
      _filteredSouvenirs = _filterSouvenirs(_mySouvenirs, souvenirFilterNotifier.value);
      _displayedSouvenirs = _filteredSouvenirs.take(_maxDisplayedCards).toList();
      _souvenirZOrders.clear();
      for (var i = 0; i < _displayedSouvenirs.length; i++) {
        final souvenir = _displayedSouvenirs[i];
        if (souvenir.id != null) {
          _souvenirZOrders[souvenir.id!] = i.toDouble();
        }
      }
    });
  }


  void _setupRealtimeListeners() {
    if (!mounted) return;

    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    setState(() {
      _isLoading = true;
    });

    _myJourneesSubscription = _firestore
        .collection('journees')
        .where('userId', isEqualTo: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _myJournees = snapshot.docs
              .map((doc) => JourneeModel.fromFirestore(doc))
              .toList();
          _isLoading = false;
          _updateDisplayedJournees();
        });
      }
    }, onError: (e) {
      print('Erreur lors de l\'écoute des journées: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });

    _loadFriends().then((_) {
      if (_friendIds.isNotEmpty) {
        _friendsJourneesSubscription = _firestore
            .collection('journees')
            .where('userId', whereIn: _friendIds)
            .where('estPublic', isEqualTo: true)
        // --- CORRECTION ---
        // 1. On supprime les filtres de date pour charger l'historique
        // .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday)) // Supprimé
        // .where('date', isLessThan: Timestamp.fromDate(endOfToday)) // Supprimé

        // 2. On trie par date pour afficher les plus récentes en premier
            .orderBy('date', descending: true) // Ajouté

        // 3. On ajoute une limite pour optimiser les performances et les coûts
            .limit(50) // Ajouté (charge les 50 journées les plus récentes)

            .snapshots()
            .listen((snapshot) {
          if (mounted) {
            setState(() {
              _friendsJournees = snapshot.docs
                  .map((doc) => JourneeModel.fromFirestore(doc))
                  .toList();
            });
          }
        }, onError: (e) {
          print('Erreur lors de l\'écoute des journées des amis: $e');
        });
      }
    });

    _globalJourneesSubscription = _firestore
        .collection('journees')
        .where('estPublic', isEqualTo: true)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
        .where('date', isLessThan: Timestamp.fromDate(endOfToday))
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _globalJournees = snapshot.docs
              .map((doc) => JourneeModel.fromFirestore(doc))
              .toList();
        });
      }
    }, onError: (e) {
      print('Erreur lors de l\'écoute des journées mondiales: $e');
    });

    _mySouvenirsSubscription = _firestore
        .collection('souvenirs')
        .where('userId', isEqualTo: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _mySouvenirs = snapshot.docs
              .map((doc) => SouvenirModel.fromFirestore(doc))
              .toList();
          _updateDisplayedSouvenirs();
        });
      }
    }, onError: (e) {
      print('Erreur lors de l\'écoute des souvenirs: $e');
    });
  }

  void _scheduleMidnightUpdate() {
    if (!mounted) return;

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    Future.delayed(timeUntilMidnight, () {
      if (mounted) {
        setState(() {
          _today = tomorrow;
        });
        _scheduleMidnightUpdate();
      }
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _verticalMainPageController.dispose();
    _journeePageController.dispose();
    _myJourneesSubscription?.cancel();
    _friendsJourneesSubscription?.cancel();
    _globalJourneesSubscription?.cancel();
    _mySouvenirsSubscription?.cancel();
    _controller.dispose();
    journeeFilterNotifier.removeListener(_updateDisplayedJournees);
    souvenirFilterNotifier.removeListener(_updateDisplayedSouvenirs);
    super.dispose();
  }

  Future<void> _loadAppBrightness() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? themeMode = prefs.getString('themeMode');

      Brightness loadedBrightness = Brightness.light;
      if (themeMode == 'dark') {
        loadedBrightness = Brightness.dark;
      } else if (themeMode == 'light') {
        loadedBrightness = Brightness.light;
      } else {
        loadedBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      }

      if (mounted) {
        appBrightnessNotifier.value = loadedBrightness;
      }
    } catch (e) {
      print('Erreur de chargement de la couleur de fond : $e');
    }
  }

  Future<void> _loadFriends() async {
    if (!mounted) return;

    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      QuerySnapshot friendsSnapshot = await _firestore
          .collection('friends')
          .where('users', arrayContains: currentUser.uid)
          .get();

      if (mounted) {
        setState(() {
          _friendIds = friendsSnapshot.docs.map((doc) {
            List<String> users = List<String>.from(doc['users']);
            return users.firstWhere((id) => id != currentUser.uid);
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading friends: $e');
    }
  }

  Future<bool> _hasPostedJourneeOnDate(DateTime date) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    final querySnapshot = await _firestore
        .collection('journees')
        .where('userId', isEqualTo: currentUser.uid)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .get();

    return querySnapshot.docs.isNotEmpty;
  }

  Future<void> _showConseilsDialog(JourneeModel journee) async {
    if (DEEPSEEK_API_KEY == 'VOTRE_CLÉ_API_DEEPSEEK') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clé API DeepSeek non configurée.')),
      );
      return;
    }

    try {
      const url = 'https://api.deepseek.com/v1/chat/completions';
      final currentUser = FirebaseAuth.instance.currentUser;

      String prompt = '''
      Analyse cette journée et donne-moi 5 conseils courts et précis pour l'améliorer :

      Texte : ${journee.texte1 ?? ''}
      Note : ${journee.note ?? 'Non notée'}
      Emoji : ${journee.emoji ?? 'Aucun'}

      Chaque conseil ne doit pas dépasser 1-2 phrases. Sois constructif et bienveillant.
      ''';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'max_tokens': 200,
          'messages': [
            {
              'role': 'user',
              'content': prompt
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        final conseils = responseData['choices'][0]['message']['content'];

        if (currentUser != null && journee.id != null) {
          await FirebaseFirestore.instance
              .collection('journees')
              .doc(journee.id)
              .update({
            'conseils': conseils,
            'dateConseil': FieldValue.serverTimestamp(),
          });
        }

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Conseils pour votre journée', style: TextStyle(color: Colors.blue)),
            content: SingleChildScrollView(
              child: Text(conseils, style: const TextStyle(fontSize: 16)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        );
      } else {
        print('Erreur API DeepSeek: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la génération des conseils')),
        );
      }
    } catch (e) {
      print('Erreur : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de générer les conseils')),
      );
    }
  }
  void _sendJourneeToBack(JourneeModel journee) {
    if (journee.id == null || _journeeZOrders.isEmpty) return;
    final minZ = _journeeZOrders.values.reduce((a, b) => a < b ? a : b);

    setState(() {
      _journeeZOrders[journee.id!] = minZ - 1;
    });
  }

  void _replaceJournee(JourneeModel oldJournee) {
    if (_filteredJournees.length <= _maxDisplayedCards) return;

    final displayedIds = _displayedJournees.map((j) => j.id).toSet();
    final availableToDisplay = _filteredJournees.where((j) => !displayedIds.contains(j.id)).toList();

    if (availableToDisplay.isNotEmpty) {
      setState(() {
        final indexToReplace = _displayedJournees.indexOf(oldJournee);
        if (indexToReplace != -1) {
          _displayedJournees[indexToReplace] = availableToDisplay.first;
        }
      });
    }
  }
  void _sendSouvenirToBack(SouvenirModel souvenir) {
    if (souvenir.id == null || _souvenirZOrders.isEmpty) return;
    final minZ = _souvenirZOrders.values.reduce((a, b) => a < b ? a : b);
    setState(() {
      _souvenirZOrders[souvenir.id!] = minZ - 1;
    });
  }

  void _replaceSouvenir(SouvenirModel oldSouvenir) {
    if (_filteredSouvenirs.length <= _maxDisplayedCards) return;

    final displayedIds = _displayedSouvenirs.map((s) => s.id).toSet();
    final availableToDisplay = _filteredSouvenirs.where((s) => !displayedIds.contains(s.id)).toList();

    if (availableToDisplay.isNotEmpty) {
      setState(() {
        final indexToReplace = _displayedSouvenirs.indexOf(oldSouvenir);
        if (indexToReplace != -1) {
          _displayedSouvenirs[indexToReplace] = availableToDisplay.first;
        }
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);

    bool hasPostedToday = _hasPostedToday();
    ValueNotifier<String> _tabTitleNotifier = ValueNotifier<String>('Mes Journées');

    return DefaultTabController(
      length: 3,
      child: ValueListenableBuilder<Brightness>(
        valueListenable: appBrightnessNotifier,
        builder: (context, currentBrightness, child) {
          final isDarkMode = currentBrightness == Brightness.dark;
          final textColor = isDarkMode ? Colors.white : Colors.white;
          final appBarColor = isDarkMode ? Colors.black : Colors.blue.shade700;
          final iconColor = isDarkMode ? Colors.white : Colors.white;

          return Scaffold(
            backgroundColor: isDarkMode ? Colors.black : Colors.white,
            appBar: AppBar(
              backgroundColor: appBarColor,
              leading: IconButton(
                icon: Icon(Icons.group_add, color: iconColor),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AddFriendsPage()),
                  );
                },
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(3.14159),
                    child: IconButton(
                      icon: Icon(
                        Icons.auto_stories,
                        color: isDarkMode ? Colors.white : Colors.amber.shade300,
                        size: 28,
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => const AutobiographieDialog(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Daytalia',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontSize: 24,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _showNiveauDeVieDialog();
                    },
                    child: Icon(
                      Icons.favorite,
                      color: isDarkMode ? Colors.white : Colors.red.shade300,
                      size: 28,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.person, color: iconColor),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ProfilePage()),
                    );
                    if (mounted) {
                      _loadVipStatus();
                    }
                  },
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: iconColor,
                labelColor: textColor,
                unselectedLabelColor: isDarkMode ? Colors.grey : Colors.blue.shade200,
                tabs: [
                  ValueListenableBuilder<String>(
                    valueListenable: _tabTitleNotifier,
                    builder: (context, tabTitle, _) {
                      return Tab(text: tabTitle);
                    },
                  ),
                  const Tab(text: 'Amis'),
                  const Tab(text: 'Mondial'),
                ],
                onTap: (index) {
                  if (index == 0) {
                  } else {
                    if (_verticalMainPageController.page == 1) {
                      _verticalMainPageController.jumpToPage(0);
                      _tabTitleNotifier.value = 'Mes Journées';
                    }
                  }
                },
              ),
            ),
            body: TabBarView(
              controller: _tabController,
              children: [
                PageView(
                  controller: _verticalMainPageController,
                  onPageChanged: (index) {
                    if (index == 0) {
                      _tabTitleNotifier.value = 'Mes Journées';
                    } else if (index == 1) {
                      _tabTitleNotifier.value = 'Mes Souvenirs';
                    }
                  },
                  scrollDirection: Axis.vertical,
                  children: [
                    _buildMyJourneesTab(hasPostedToday),
                    _buildMySouvenirsTab(),
                  ],
                ),
                _buildFriendsJourneesTab(hasPostedToday),
                _buildGlobalJourneesTab(hasPostedToday),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMyJourneesTab(bool hasPostedToday) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            if (!hasPostedToday)
            // ENVELOPPEZ VOTRE FUTUREBUILDER EXISTANT DANS CELUI-CI
              FutureBuilder<String>(
                future: _cardSizeFuture, // On charge la taille
                builder: (context, sizeSnapshot) {
                  if (!sizeSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final cardSize = sizeSnapshot.data!;

                  return FutureBuilder<String>(
                    future: _journeeCardDesignFuture,
                    builder: (context, designSnapshot) {
                      if (designSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final journeeCardDesign = designSnapshot.data ?? 'default';

                      final sortedJournees = List<JourneeModel>.from(_displayedJournees);
                      sortedJournees.sort((a, b) {
                        final zA = _journeeZOrders[a.id] ?? 0.0;
                        final zB = _journeeZOrders[b.id] ?? 0.0;
                        return zA.compareTo(zB);
                      });

                      return Stack(
                        fit: StackFit.expand,
                        children: sortedJournees.map((journee) {
                          return MovingJourneeCard(
                            key: ValueKey(journee.id),
                            journee: journee,
                            design: journeeCardDesign,
                            // UTILISEZ LA TAILLE CHARGÉE AU LIEU DE 'normal'
                            size: cardSize,
                            onSendToBack: () => _sendJourneeToBack(journee),
                            onReplaceRequest: () => _replaceJournee(journee),
                            parentConstraints: constraints,
                          );
                        }).toList(),
                      );
                    },
                  );
                },
              )
            else
              ValueListenableBuilder<String>(
                valueListenable: journeeFilterNotifier,
                builder: (context, filter, _) {
                  final filteredJournees = _filterJournees(_myJournees, filter);
                  return _buildJourneeList(
                    filteredJournees,
                    'Mes Journées',
                    showRepublishButton: false,
                    hasUserPostedToday: hasPostedToday,
                  );
                },
              ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: Icon(
                  Icons.filter_list,
                  color: appBrightnessNotifier.value == Brightness.dark
                      ? Colors.white
                      : Colors.blue.shade700,
                ),
                onPressed: () => _showJourneeFilterDialog(journeeFilterNotifier),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: GestureDetector(
                onTap: () {
                  if (_isVip) {
                    _showSimilarJourneesDialog();
                  } else {
                    showVipPromotionPopup(context, "Journées Similaires");
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isVip ? Colors.blue.shade100 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (_isVip ? Colors.blue : Colors.grey)
                            .withOpacity(0.2),
                        blurRadius: 5,
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isVip ? Icons.compare_arrows : Icons.lock,
                        color: _isVip ? Colors.blue.shade700 : Colors.grey.shade600,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Similaires',
                        style: TextStyle(
                          color: _isVip
                              ? Colors.blue.shade700
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMySouvenirsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // ENVELOPPEZ VOTRE FUTUREBUILDER EXISTANT DANS CELUI-CI
            FutureBuilder<String>(
              future: _cardSizeFuture, // On charge la taille
              builder: (context, sizeSnapshot) {
                if (!sizeSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final cardSize = sizeSnapshot.data!;

                return FutureBuilder<String>(
                  future: _souvenirCardDesignFuture,
                  builder: (context, designSnapshot) {
                    if (designSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final cardDesign = designSnapshot.data ?? 'default';
                    final sortedSouvenirs =
                    List<SouvenirModel>.from(_displayedSouvenirs);
                    sortedSouvenirs.sort((a, b) {
                      final zA = _souvenirZOrders[a.id] ?? 0.0;
                      final zB = _souvenirZOrders[b.id] ?? 0.0;
                      return zA.compareTo(zB);
                    });

                    return Stack(
                      fit: StackFit.expand,
                      children: sortedSouvenirs.map((souvenir) {
                        return MovingSouvenirCard(
                          key: ValueKey(souvenir.id),
                          souvenir: souvenir,
                          design: cardDesign,
                          // UTILISEZ LA TAILLE CHARGÉE AU LIEU DE 'normal'
                          size: cardSize,
                          onSendToBack: () => _sendSouvenirToBack(souvenir),
                          onReplaceRequest: () => _replaceSouvenir(souvenir),
                          parentConstraints: constraints,
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: Icon(
                  Icons.filter_list,
                  color: appBrightnessNotifier.value == Brightness.dark
                      ? Colors.white
                      : Colors.blue.shade700,
                ),
                onPressed: () =>
                    _showSouvenirFilterDialog(souvenirFilterNotifier),
              ),
            ),
          ],
        );
      },
    );
  }
  Widget _buildFriendsJourneesTab(bool hasPostedToday) {
    return _buildJourneeList(_friendsJournees, 'Journées de mes amis', showRepublishButton: true, hasUserPostedToday: hasPostedToday);
  }

  Widget _buildGlobalJourneesTab(bool hasPostedToday) {
    return _buildJourneeList(_globalJournees, 'Journées mondiales', showRepublishButton: true, hasUserPostedToday: hasPostedToday);
  }


  Future<String> _getCardDesignFromPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('cardDesign') ?? 'default';
  }

  Future<String> _getJourneeCardDesignFromPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('journeeCardDesign') ?? 'default';
  }

  List<SouvenirModel> _filterSouvenirs(List<SouvenirModel> souvenirs, String filter) {
    return souvenirs.where((souvenir) {
      switch (filter) {
        case 'public':
          return souvenir.estPublic;
        case 'prive':
          return !souvenir.estPublic;
        case 'nostalgie':
          return souvenir.qualite == sm.SouvenirQualite.nostalgie;
        case 'bonheur':
          return souvenir.qualite == sm.SouvenirQualite.bonheur;
        case 'jamais_oublie':
          return souvenir.qualite == sm.SouvenirQualite.jamaisOublie;
        default:
          return true;
      }
    }).toList();
  }

  void _showSouvenirFilterDialog(ValueNotifier<String> filterNotifier) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filtrer les souvenirs', style: TextStyle(color: Colors.blue)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFilterRadioListTile(filterNotifier, 'tout', 'Tous'),
                _buildFilterRadioListTile(filterNotifier, 'public', 'Public'),
                _buildFilterRadioListTile(filterNotifier, 'prive', 'Privé'),
                const Divider(),
                _buildFilterRadioListTile(filterNotifier, 'nostalgie', 'Nostalgie'),
                _buildFilterRadioListTile(filterNotifier, 'bonheur', 'Bonheur'),
                _buildFilterRadioListTile(filterNotifier, 'jamais_oublie', 'Jamais oublié'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer', style: TextStyle(color: Colors.blue)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterRadioListTile(ValueNotifier<String> filterNotifier, String value, String title) {
    return ValueListenableBuilder<String>(
      valueListenable: filterNotifier,
      builder: (context, currentFilter, child) {
        return RadioListTile<String>(
          title: Text(title),
          value: value,
          groupValue: currentFilter,
          onChanged: (val) {
            if (val != null) {
              filterNotifier.value = val;
              Navigator.pop(context);
            }
          },
          activeColor: Colors.blue,
        );
      },
    );
  }

  Future<int> _calculateTruthPercentage() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return 0;

    try {
      final journeesSnapshot = await FirebaseFirestore.instance
          .collection('journees')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      final souvenirsSnapshot = await FirebaseFirestore.instance
          .collection('souvenirs')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      final journeesDates = journeesSnapshot.docs
          .map((doc) => (doc['date'] as Timestamp).toDate())
          .toList();

      final souvenirsDates = souvenirsSnapshot.docs
          .map((doc) => (doc['date'] as Timestamp).toDate())
          .toList();

      final Set<DateTime> uniquePostDates = {};

      for (final date in journeesDates) {
        uniquePostDates.add(DateTime(date.year, date.month, date.day));
      }

      for (final date in souvenirsDates) {
        uniquePostDates.add(DateTime(date.year, date.month, date.day));
      }

      final int activeDaysCount = uniquePostDates.length;

      final creationDate = currentUser.metadata.creationTime;
      if (creationDate == null) {
        return 0;
      }

      final int totalDaysSinceRegistration = DateTime.now().difference(creationDate.toLocal()).inDays + 1;

      if (totalDaysSinceRegistration <= 0) {
        return activeDaysCount > 0 ? 100 : 0;
      }

      final double reliabilityPercentage = (activeDaysCount / totalDaysSinceRegistration) * 100;

      return reliabilityPercentage.clamp(0, 100).round();

    } catch (e) {
      print('Erreur lors du calcul du pourcentage de fiabilité : $e');
      return 0;
    }
  }
  Future<void> _showNiveauDeVieDialog() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final userSubscriptionData = await getUserSubscriptionData();
      final isVip = userSubscriptionData['isVip'];
      final lastIaUpdateTimestamp = userSubscriptionData['lastIaUpdate'] as Timestamp?;
      final lastIaUpdate = lastIaUpdateTimestamp?.toDate();

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      bool isIAAnalysisActive = userData['isIAAnalysisActive'] ?? false;
      bool isTruthAdjustmentActive = userData['isTruthAdjustmentActive'] ?? false;
      int truthPercentage = await _calculateTruthPercentage();
      int qualiteDeVieActuelle = userData['qualiteDeVieActuelle'] ?? 50;

      int adjustNoteWithTruth(int note, int truthPercentage) {
        return (note * truthPercentage / 100).round();
      }


      Future<Map<String, dynamic>> analyseEmotionsEtSouvenirsParIA() async {
        final url = Uri.parse('https://api.deepseek.com/v1/chat/completions');
        if (currentUser == null) return {'qualiteDeVie': 50, 'analyse': 'Utilisateur non trouvé.', 'recommandations': []};

        DocumentSnapshot userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
        if (!userDoc.exists) {
          return {'qualiteDeVie': 50, 'analyse': 'Profil utilisateur non trouvé.', 'recommandations': []};
        }
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        List<Map<String, dynamic>> newLifeEvents = [];
        List<DocumentReference> elementsToUpdateRefs = [];

        final categoriesSnapshot = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .collection('categories_elements')
            .get();

        for (final categoryDoc in categoriesSnapshot.docs) {
          final categoryName = categoryDoc.data()['nom'] ?? 'Inconnue';
          final elementsSnapshot = await categoryDoc.reference
              .collection('elements')
              .where('lastAnalyzed', isEqualTo: null)
              .get();

          for (final elementDoc in elementsSnapshot.docs) {
            final elementData = elementDoc.data();
            newLifeEvents.add({
              'category': categoryName,
              'text': elementData['texte'],
              'explanation': elementData['explication'],
              'date': (elementData['date'] as Timestamp).toDate().toIso8601String(),
            });
            elementsToUpdateRefs.add(elementDoc.reference);
          }
        }
        if (newLifeEvents.isEmpty) {
          return {
            'qualiteDeVie': userData['iaQualiteDeVie'] ?? 50,
            'analyse': "Tous les éléments ont déjà été analysés. Votre note de vie reste inchangée.",
            'recommandations': userData['iaRecommendations'] ?? []
          };
        }
        int previousQualityOfLife = userData['iaQualiteDeVie'] ?? 50;
        final memoriesData = {
          "Jamais Oublié": {"count": userData['jamaisOublieCount'] ?? 0, "averageNote": userData['jamaisOublieNote'] ?? 50},
          "Bonheur": {"count": userData['bonheurCount'] ?? 0, "averageNote": userData['bonheurNote'] ?? 50},
          "Nostalgie": {"count": userData['nostalgieCount'] ?? 0, "averageNote": userData['nostalgieNote'] ?? 50},
        };

        try {
          final response = await http.post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $DEEPSEEK_API_KEY',
            },
            body: jsonEncode({
              'model': 'deepseek-chat',
              'max_tokens': 800,
              'messages': [
                {
                  'role': 'user',
                  'content': '''
                      Tu es un psychologue. Mets à jour la note de qualité de vie d'un utilisateur en te basant sur de NOUVEAUX événements.

                      Contexte :
                      1. Qualité de vie PRÉCÉDENTE : $previousQualityOfLife/100.
                      2. Souvenirs déjà connus : ${jsonEncode(memoriesData)}.
                      3. NOUVEAUX événements à analyser : ${jsonEncode(newLifeEvents)}.

                      Instructions :
                      - Analyse l'impact des NOUVEAUX événements.
                      - Ajuste la qualité de vie PRÉCÉDENTE pour calculer une NOUVELLE note.
                      - Rédige une analyse concise expliquant l'évolution.
                      - Propose 2 recommandations concrètes basées sur les nouveaux événements.

                      Réponds UNIQUEMENT au format JSON EXACT :
                      {
                        "qualiteDeVie": 0-100,
                        "analyse": "Texte d'analyse.",
                        "recommandations": ["Recommandation 1", "Recommandation 2"]
                      }
                      '''
                }
              ]
            }),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(utf8.decode(response.bodyBytes));
            final content = data['choices'][0]['message']['content'];
            final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
            if (jsonMatch != null) {
              final parsedJson = jsonDecode(jsonMatch.group(0)!);
              final int qualiteDeVieCalculee = parsedJson['qualiteDeVie'] is int ? parsedJson['qualiteDeVie'] : int.tryParse(parsedJson['qualiteDeVie'].toString()) ?? previousQualityOfLife;
              WriteBatch batch = _firestore.batch();
              for (final docRef in elementsToUpdateRefs) {
                batch.update(docRef, {'lastAnalyzed': Timestamp.now()});
              }
              await batch.commit();

              return {
                'qualiteDeVie': qualiteDeVieCalculee,
                'analyse': parsedJson['analyse'] ?? 'Analyse non disponible.',
                'recommandations': List<String>.from(parsedJson['recommandations'] ?? [])
              };
            }
          }
          return {'qualiteDeVie': previousQualityOfLife, 'analyse': 'Impossible de générer une analyse complète.', 'recommandations': []};
        } catch (e) {
          return {'qualiteDeVie': previousQualityOfLife, 'analyse': 'Erreur de connexion à l\'IA.', 'recommandations': []};
        }
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              bool isUpdatingIA = false;

              bool canUpdateIA = false;
              int remainingDays = 0;
              if (isVip) {
                canUpdateIA = true;
              } else {
                if (lastIaUpdate == null) {
                  canUpdateIA = true;
                } else {
                  remainingDays = 7 - DateTime.now().difference(lastIaUpdate).inDays;
                  canUpdateIA = remainingDays <= 0;
                }
              }

              int calculateDisplayQualiteDeVie() {
                if (!isIAAnalysisActive) {
                  return isTruthAdjustmentActive
                      ? adjustNoteWithTruth(qualiteDeVieActuelle, truthPercentage)
                      : qualiteDeVieActuelle;
                } else {
                  return isTruthAdjustmentActive
                      ? adjustNoteWithTruth(userData['iaQualiteDeVie'] ?? qualiteDeVieActuelle, truthPercentage)
                      : userData['iaQualiteDeVie'] ?? qualiteDeVieActuelle;
                }
              }

              int displayQualiteDeVie = calculateDisplayQualiteDeVie();
              String displayAnalyse = isIAAnalysisActive
                  ? (userData['iaAnalyse'] ?? 'Analyse IA non disponible')
                  : _getQualiteDeVieMessage(displayQualiteDeVie);
              List<String> recommandations = isIAAnalysisActive
                  ? List<String>.from(userData['iaRecommendations'] ?? [])
                  : [];

              Color couleur = _getQualiteDeVieColor(displayQualiteDeVie);
              String message = isIAAnalysisActive ? "Analyse IA de votre qualité de vie" : displayAnalyse;

              return AlertDialog(
                title: const Text(
                  'Votre Niveau de Vie',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: displayQualiteDeVie / 100,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(couleur),
                        minHeight: 12,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '$displayQualiteDeVie/100',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: couleur,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Fiabilité de vos données : $truthPercentage%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      if (isIAAnalysisActive)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Text(
                            displayAnalyse,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.blue.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      if (recommandations.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Recommandations :',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                              ),
                              const SizedBox(height: 8),
                              ...recommandations.map((rec) => Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Text('• $rec', style: const TextStyle(fontSize: 14, color: Colors.black87)),
                              )).toList(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  if (isIAAnalysisActive)
                    Tooltip(
                      message: !canUpdateIA ? "Disponible dans $remainingDays jour(s)" : "Mettre à jour l'analyse",
                      child: TextButton(
                        child: isUpdatingIA
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('Mettre à jour'),
                        onPressed: (isUpdatingIA || !canUpdateIA)
                            ? null
                            : () async {
                          setStateDialog(() { isUpdatingIA = true; });
                          try {
                            final resultIA = await analyseEmotionsEtSouvenirsParIA();
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(currentUser.uid)
                                .update({
                              'iaQualiteDeVie': resultIA['qualiteDeVie'],
                              'iaAnalyse': resultIA['analyse'],
                              'iaRecommendations': resultIA['recommandations'],
                              if (!isVip) 'lastIaAnalysisUpdate': FieldValue.serverTimestamp(),
                            });

                            setStateDialog(() {
                              userData['iaQualiteDeVie'] = resultIA['qualiteDeVie'];
                              userData['iaAnalyse'] = resultIA['analyse'];
                              userData['iaRecommendations'] = resultIA['recommandations'];
                            });
                            Navigator.of(context).pop();

                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erreur: $e')),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setStateDialog(() { isUpdatingIA = false; });
                            }
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green,
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  TextButton(
                    child: Text(isTruthAdjustmentActive ? 'Désactiver Fidélité' : 'Activer Fidélité'),
                    onPressed: () async {
                      setStateDialog(() {
                        isTruthAdjustmentActive = !isTruthAdjustmentActive;
                      });

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(currentUser.uid)
                          .update({
                        'isTruthAdjustmentActive': isTruthAdjustmentActive,
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    child: Text(isIAAnalysisActive ? 'Désactiver IA' : 'Activer IA'),
                    onPressed: () async {
                      if (!isIAAnalysisActive) {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => const Center(child: CircularProgressIndicator()),
                        );
                        try {
                          final resultIA = await analyseEmotionsEtSouvenirsParIA();
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(currentUser.uid)
                              .update({
                            'iaQualiteDeVie': resultIA['qualiteDeVie'],
                            'iaAnalyse': resultIA['analyse'],
                            'iaRecommendations': resultIA['recommandations'],
                            'isIAAnalysisActive': true,
                          });
                          setStateDialog(() {
                            isIAAnalysisActive = true;
                            userData['iaQualiteDeVie'] = resultIA['qualiteDeVie'];
                            userData['iaAnalyse'] = resultIA['analyse'];
                            userData['iaRecommendations'] = resultIA['recommandations'];
                          });
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Une erreur est survenue: $e')),
                          );
                        } finally {
                          Navigator.of(context).pop();
                        }
                      } else {
                        setStateDialog(() {
                          isIAAnalysisActive = false;
                        });
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(currentUser.uid)
                            .update({
                          'isIAAnalysisActive': false,
                        });
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    child: const Text('Fermer'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      print('Erreur lors de la récupération de la qualité de vie : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de récupérer votre niveau de vie'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  String _getQualiteDeVieMessage(int qualiteDeVie) {
    if (qualiteDeVie < 20) {
      return "Votre qualité de vie est actuellement très basse. Il est important de prendre soin de vous, de vous entourer et de chercher du soutien.";
    } else if (qualiteDeVie < 40) {
      return "Votre qualité de vie peut être améliorée. Concentrez-vous sur des activités positives et prenez soin de votre bien-être mental et physique.";
    } else if (qualiteDeVie < 60) {
      return "Votre qualité de vie est moyenne. Il y a des opportunités d'amélioration et de croissance personnelle.";
    } else if (qualiteDeVie < 80) {
      return "Votre qualité de vie est bonne ! Continuez à maintenir un équilibre positif dans votre vie.";
    } else {
      return "Votre qualité de vie est excellente ! Continuez à cultiver les habitudes qui vous apportent du bonheur et de la satisfaction.";
    }
  }

  Color _getQualiteDeVieColor(int qualiteDeVie) {
    if (qualiteDeVie < 20 ) {
      return Colors.red.shade700;
    } else if (qualiteDeVie < 50) {
      return Colors.orange.shade700;
    } else if (qualiteDeVie < 80) {
      return Colors.green.shade500;
    } else {
      return Colors.green.shade700;
    }
  }
  Widget _buildJourneeCard(JourneeModel journee, String title, {bool showRepublishButton = false, required bool hasUserPostedToday}) {
    bool isMyJournees = title == 'Mes Journées';
    final ValueNotifier<bool> souvenirVisible = ValueNotifier<bool>(false);
    final currentUser = FirebaseAuth.instance.currentUser;

    final bool isMentioned = (journee.mentionedUserIds ?? []).contains(currentUser?.uid);
    final bool amIInHiddenList = (journee.hiddenTextFriends ?? []).contains(currentUser?.uid);
    bool shouldBlurText = !isMyJournees && (amIInHiddenList || (!hasUserPostedToday && !isMentioned));

    bool isToday = journee.date.year == _today.year &&
        journee.date.month == _today.month &&
        journee.date.day == _today.day;

    bool isLive = journee.note == null;
    final wordCount = _countWords(journee.texte1 ?? '');

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(journee.userId).get(),
      builder: (context, userSnapshot) {
        Map<String, dynamic> personalizationPreferences =
            (userSnapshot.data?.data() as Map<String, dynamic>?)?['personalizationPreferences'] ??
                {'journeeCardColor': 'default'};

        Color cardColor = Colors.blue.shade100;
        switch (personalizationPreferences['journeeCardColor']) {
          case 'noir': cardColor = Colors.black; break;
          case 'bleu': cardColor = Colors.blue.shade300; break;
          case 'rouge': cardColor = Colors.red.shade300; break;
          case 'vert': cardColor = Colors.green.shade300; break;
          default: cardColor = Colors.blue.shade100;
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: journee.isRepost
                ? const BorderSide(color: Colors.grey, width: 2.0)
                : BorderSide.none,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cardColor,
                  Colors.white,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.2),
                  spreadRadius: 3,
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (journee.isRepost)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Text(
                                  'De ${journee.repostedFromUserName ?? 'un ami'}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (isMyJournees)
                              Chip(
                                label: Text(
                                  journee.estPublic ? 'Public' : 'Privé',
                                  style: TextStyle(
                                    color: journee.estPublic ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                                backgroundColor: journee.estPublic
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                          ],
                        ),
                      ),
                      if (isMyJournees)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
                          onSelected: (value) {
                            if (value == 'modifier') {
                              _modifierJournee(journee);
                            } else if (value == 'supprimer') {
                              _supprimerJournee(journee);
                            }
                          },
                          itemBuilder: (BuildContext context) => [
                            const PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                            const PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Expanded(
                    child: SingleChildScrollView(
                      child: shouldBlurText
                          ? ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Text(
                          journee.texte1 ?? '',
                          style: TextStyle(
                            fontSize: _calculateFontSize(journee.texte1 ?? ''),
                            color: Colors.black87,
                            height: 1.5,
                          ),
                        ),
                      )
                          : (isMyJournees
                          ? Text(
                        journee.texte1 ?? '',
                        style: TextStyle(
                          fontSize: _calculateFontSize(journee.texte1 ?? ''),
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      )
                          : _buildTextWithBlurredAsterisks(
                        journee.texte1 ?? '',
                        style: TextStyle(
                          fontSize: _calculateFontSize(journee.texte1 ?? ''),
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      )),
                    ),
                  ),
                  if (journee.photoUrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: journee.photoUrls.length,
                        itemBuilder: (context, index) {
                          final imageUrl = journee.photoUrls[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10.0),
                              child: Image.network(
                                imageUrl,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: 80, height: 80, color: Colors.grey[200],
                                    child: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue))),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 80, height: 80, color: Colors.grey[200],
                                    child: const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (journee.commentaire != null && journee.commentaire!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        journee.commentaire!,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  if (isMyJournees && isToday && isLive) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: ElevatedButton(
                        onPressed: wordCount >= 4
                            ? () {
                          _confirmerJournee(journee);
                        }
                            : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => JourneeEnDirectPage(journeeToEdit: journee),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: wordCount >= 4 ? Colors.green.shade600 : Colors.orange.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          elevation: 3,
                        ),
                        child: Text(
                          wordCount >= 4 ? 'Confirmer ma journée' : 'Écrivez pour confirmer',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (journee.emoji != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Text(
                            journee.emoji!,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      if (journee.note != null)
                        Text(
                          'Note: ${journee.note}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      const Spacer(),
                      if (journee.reactions.isNotEmpty)
                        ...journee.reactions.entries.map((entry) {
                          final hasReacted = entry.value.contains(FirebaseAuth.instance.currentUser?.uid ?? '');
                          return InkWell(
                            onTap: () {
                              if (!isMyJournees) {
                                _handleReaction(journee, entry.key);
                              }
                            },
                            borderRadius: BorderRadius.circular(15),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2.0),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: hasReacted ? Colors.blue.shade100 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(15),
                                border: hasReacted ? Border.all(color: Colors.blue, width: 1.0) : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(entry.key, style: const TextStyle(fontSize: 16)),
                                  const SizedBox(width: 4),
                                  Text(
                                    entry.value.length.toString(),
                                    style: TextStyle(
                                      color: Colors.grey.shade800,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      const Spacer(),
                      if (!isMyJournees)
                        IconButton(
                          icon: Icon(Icons.add_reaction_outlined, color: Colors.blueGrey.shade400),
                          tooltip: 'Réagir',
                          onPressed: () => _showReactionPicker(journee),
                        ),
                      IconButton(
                        icon: Icon(Icons.chat_bubble_outline, color: Colors.blueGrey.shade400),
                        tooltip: 'Commenter',
                        onPressed: () => _showCommentsDialog(journee, isMyJournees: isMyJournees),
                      ),
                      if (isMyJournees && journee.note != null)
                        IconButton(
                          icon: Icon(
                            _isVip ? Icons.lightbulb_outline : Icons.lock_outline,
                            color: _isVip ? Colors.amber.shade700 : Colors.grey,
                          ),
                          onPressed: () {
                            if (_isVip) {
                              _showConseilsDialog(journee);
                            } else {
                              showVipPromotionPopup(context, "Conseils de l'IA");
                            }
                          },
                          tooltip: _isVip ? 'Voir les conseils de l\'IA' : 'Fonctionnalité VIP',
                        ),
                    ],
                  ),
                  FutureBuilder<List<SouvenirModel>>(
                      future: _getSouvenirsForJournee(journee),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData && snapshot.data!.isNotEmpty) {
                          return Center(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: souvenirVisible,
                              builder: (context, isVisible, child) {
                                return IconButton(
                                  icon: Icon(
                                    isVisible ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    color: Colors.blue.shade700,
                                  ),
                                  onPressed: () {
                                    souvenirVisible.value = !souvenirVisible.value;
                                  },
                                );
                              },
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: souvenirVisible,
                    builder: (context, isVisible, child) {
                      if (!isVisible) return const SizedBox.shrink();
                      return FutureBuilder<List<SouvenirModel>>(
                        future: _getSouvenirsForJournee(journee),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)));
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'Aucun souvenir associé',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(color: Colors.blueAccent),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  'Souvenirs associés :',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 120,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: snapshot.data!.length,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      width: 180,
                                      margin: const EdgeInsets.only(right: 10.0),
                                      child: _buildSouvenirCard(snapshot.data![index], showRepublishButton: showRepublishButton, hasUserPostedToday: hasUserPostedToday),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildJourneeList(List<JourneeModel> journees, String title, {bool showRepublishButton = false, required bool hasUserPostedToday}) {
    final currentUser = FirebaseAuth.instance.currentUser;

    final List<JourneeModel> filteredJournees = journees.where((journee) {
      final isOwner = journee.userId == currentUser?.uid;
      if ((title == 'Journées de mes amis' || title == 'Journées mondiales') && isOwner) {
        return false;
      }
      return true;
    }).toList();

    final sortedJournees = List<JourneeModel>.from(filteredJournees)
      ..sort((a, b) => b.date.compareTo(a.date));

    final displayItems = sortedJournees.take(50).toList();

    if (displayItems.isEmpty) {
      return _buildEmptyMessage('Aucune journée disponible pour le moment.');
    }

    return Padding(
        padding: const EdgeInsets.only(bottom: 90.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((title == 'Journées de mes amis' || title == 'Journées mondiales') && !hasUserPostedToday)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'Postez votre journée pour voir le contenu complet des autres utilisateurs.',
                  style: TextStyle(
                    color: Colors.blue,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              ),
            Expanded(
              child: PageView.builder(
                controller: _journeePageController,
                itemCount: displayItems.length,
                itemBuilder: (context, index) {
                  final journee = displayItems[index];
                  final isMyJournees = title == 'Mes Journées';
                  final isOwner = journee.userId == currentUser?.uid;

                  return Column(
                    children: [
                      // --- CORRECTION CI-DESSOUS ---
                      // On utilise maintenant notre fonction _getUserData avec cache.
                      // Le FutureBuilder ne se relancera plus inutilement.
                      FutureBuilder<Map<String, dynamic>>(
                        future: _getUserData(journee.userId ?? ''),
                        builder: (context, userSnapshot) {
                          String username;
                          Widget trailingWidget;

                          if (userSnapshot.connectionState == ConnectionState.waiting && !userSnapshot.hasData) {
                            // Affiche les points qui clignotent pendant le tout premier chargement
                            username = '';
                            trailingWidget = const _BlinkingDots();
                          } else {
                            final userData = userSnapshot.data ?? {'username': 'Utilisateur Inconnu'};
                            username = userData['username'] ?? 'Utilisateur Inconnu';
                            trailingWidget = !isMyJournees
                                ? PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
                              onSelected: (value) {
                                if (value == 'signaler') {
                                  _signalerJournee(journee);
                                } else if (value == 'republier_journee') {
                                  _republierJournee(journee);
                                } else if (value == 'republier_souvenir') {
                                  _republierSouvenir(journee);
                                }
                              },
                              itemBuilder: (BuildContext context) {
                                List<PopupMenuEntry<String>> items = [];
                                if (showRepublishButton && !isOwner && !hasUserPostedToday) {
                                  items.add(const PopupMenuItem(value: 'republier_journee', child: Text('Republier cette journée')));
                                }
                                if (showRepublishButton && !isOwner) {
                                  items.add(const PopupMenuItem(value: 'republier_souvenir', child: Text('Republier en souvenir')));
                                }
                                items.add(const PopupMenuItem(value: 'signaler', child: Text('Signaler')));
                                return items;
                              },
                            )
                                : const SizedBox.shrink(); // Pas de menu pour ses propres journées ici
                          }

                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16.0, 10.0, 4.0, 5.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: isMyJournees
                                      ? Center(
                                    child: Text(
                                      _formatDate(journee.date),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  )
                                      : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ProfileUserPage(userId: journee.userId ?? ''),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          '@$username',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatDate(journee.date),
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                trailingWidget,
                              ],
                            ),
                          );
                        },
                      ),
                      Expanded(
                        child: _buildJourneeCard(journee, title, showRepublishButton: showRepublishButton, hasUserPostedToday: hasUserPostedToday),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        )
    );
  }
  void _showReactionPicker(JourneeModel journee) {
    final List<String> reactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16.0),
            padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25.0),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 20.0,
              runSpacing: 10.0,
              children: reactions.map((emoji) {
                return InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _handleReaction(journee, emoji);
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(emoji, style: const TextStyle(fontSize: 32)),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
  void _republierJournee(JourneeModel journee) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JourneePage(journeeToRepublish: journee),
      ),
    );
  }

  void _republierSouvenir(JourneeModel journee) async {
    final tempSouvenir = SouvenirModel(
      texte: journee.texte1 ?? journee.commentaire ?? 'Souvenir de ma journée',
      date: journee.date,
      estPublic: journee.estPublic,
      qualite: sm.SouvenirQualite.nostalgie,
      noteQualite: int.tryParse(journee.note?.split('/').first ?? '50') ?? 50,
      photoUrls: journee.photoUrls,
      userId: journee.userId!,
      isRepost: true,
      repostedFromUserId: journee.userId,
      repostedFromUserName: await _getUsernameById(journee.userId!),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SouvenirPage(souvenirToRepublish: tempSouvenir),
      ),
    );
  }

  Future<String?> _getUsernameById(String userId) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      return userDoc['username'];
    } catch (e) {
      print('Erreur lors de la récupération du nom d\'utilisateur pour $userId: $e');
      return null;
    }
  }


  int _countWords(String text) {
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
  }

  Future<void> _confirmerJournee(JourneeModel journee) async {
    if (journee.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur : Journée non valide')),
      );
      return;
    }

    try {
      await _obtenirNote(journee.texte1 ?? '');

      final int? note = _note;
      if (note != null && note >= 0) {
        await _firestore.collection('journees').doc(journee.id).update({
          'note': '$_note/100',
          'motsCles': _motsCles,
          'dateModification': FieldValue.serverTimestamp(),
        });

        DocumentSnapshot userDoc = await _firestore
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .get();

        int qualiteDeVieActuelle = userDoc.exists
            ? (userDoc.data() as Map<String, dynamic>)['qualiteDeVieActuelle'] ?? 50
            : 50;
        final username = (userDoc.data() as Map<String, dynamic>)['username'] ?? 'Quelqu\'un';


        int nouvelleQualiteDeVie = ((qualiteDeVieActuelle * 2 + note) / 3).round();
        nouvelleQualiteDeVie = nouvelleQualiteDeVie.clamp(0, 100);

        await _firestore
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .update({
          'qualiteDeVieActuelle': nouvelleQualiteDeVie,
        });

// AMÉLIORATION : Envoyer une notification aux amis
        NotificationService.notifyFriendsOfNewPost(username);

        setState(() {
          journee.note = '$_note/100';
          journee.motsCles = _motsCles;
          _isNoteObtained = true;
          _myJournees = List.from(_myJournees);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Journée confirmée avec succès : $_note/100'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de l\'obtention de la note'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Erreur lors de la confirmation de la journée : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _obtenirNote(String texte) async {
    if (texte.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun texte à évaluer')),
      );
      return;
    }


    SharedPreferences prefs = await SharedPreferences.getInstance();
    String iaPreference = prefs.getString('iaPreference') ?? 'ressenti';

    String prompt;
    if (iaPreference == 'ressenti') {
      prompt =
      'Analyse ce texte et donne une note sur 100 basée sur le ressenti global de la journée. Réponds uniquement avec un nombre entier entre 0 et 100 suivi de "/100", par exemple "75/100". Texte : $texte';
    } else {
      prompt =
      'Analyse ce texte et donne une note sur 100 basée sur la qualité globale des événements de la journée. Réponds uniquement avec un nombre entier entre 0 et 100 suivi de "/100", par exemple "75/100". Texte : $texte';
    }

    const url = 'https://api.deepseek.com/v1/chat/completions';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {
              'role': 'user',
              'content': prompt
            }
          ],
          'max_tokens': 50,
        }),
      );

      print('Réponse brute _obtenirNote: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data.containsKey('choices') &&
            data['choices'] is List &&
            data['choices'].isNotEmpty) {
          final noteText = data['choices'][0]['message']['content']?.toString() ?? '';

          if (noteText.isEmpty) {
            print('Contenu vide dans choices');
            setState(() {
              _note = 50;
              _isNoteObtained = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Réponse vide de l\'API pour la note.'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }

          final standardMatch = RegExp(r'(\d+)/100').firstMatch(noteText);
          if (standardMatch != null) {
            _note = int.parse(standardMatch.group(1)!);
          } else {
            final numberMatch = RegExp(r'(\d+)').firstMatch(noteText);
            if (numberMatch != null) {
              final extractedNumber = int.parse(numberMatch.group(1)!);
              _note = extractedNumber.clamp(0, 100);
            } else {
              _note = 50;
            }
          }
          setState(() {
            _isNoteObtained = true;
          });

          _motsCles = await _extraireMotsCles(texte);
          setState(() {});

          await _enregistrerElementsInteressants(texte);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Note obtenue : $_note/100'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          print('Structure de réponse invalide : $data');
          setState(() {
            _note = 50;
            _isNoteObtained = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La réponse de l\'API ne contient pas de contenu valide.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        print('Erreur API : ${response.statusCode} - ${response.body}');
        setState(() {
          _note = -1;
          _isNoteObtained = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'obtention de la note : ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Erreur de connexion _obtenirNote : $e');
      setState(() {
        _note = -1;
        _isNoteObtained = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur de connexion : $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String normaliserId(String texte) {
    final Map<String, String> accentsMap = {
      'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'ç': 'c',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ñ': 'n',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y',
      'À': 'a', 'Á': 'a', 'Â': 'a', 'Ã': 'a', 'Ä': 'a',
      'Ç': 'c',
      'È': 'e', 'É': 'e', 'Ê': 'e', 'Ë': 'e',
      'Ì': 'i', 'Í': 'i', 'Î': 'i', 'Ï': 'i',
      'Ñ': 'n',
      'Ò': 'o', 'Ó': 'o', 'Ô': 'o', 'Õ': 'o', 'Ö': 'o',
      'Ù': 'u', 'Ú': 'u', 'Û': 'u', 'Ü': 'u',
      'Ý': 'y',
    };

    String result = texte.toLowerCase();
    accentsMap.forEach((accent, normal) {
      result = result.replaceAll(accent, normal);
    });
    result = result.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    result = result.trim().replaceAll(RegExp(r'\s+'), '_');

    if (result.isEmpty) {
      result = 'categorie_${DateTime.now().millisecondsSinceEpoch}';
    }
    return result;
  }

  Future<void> _enregistrerElementsInteressants(String texte) async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous devez être connecté')),
      );
      return;
    }
    if (DEEPSEEK_API_KEY == 'VOTRE_CLÉ_API_DEEPSEEK') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clé API DeepSeek non configurée pour la catégorisation.')),
      );
      return;
    }

    print('Début de l\'analyse pour catégorisation...');
    print('Texte à analyser: $texte');

    const url = 'https://api.deepseek.com/v1/chat/completions';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {
              'role': 'user',
              'content': '''Analyse ce texte et extrais les éléments intéressants qui pourraient être expliqués dans une biographie.
          Pour chaque élément, détermine une catégorie thématique générale (comme "amis", "travail", "famille", "loisirs", "santé", "voyage", "éducation", "événements").
          Utilise uniquement des mots simples et des catégories générales.
          Réponds STRICTEMENT au format JSON suivant, sans aucun texte supplémentaire, ni préambule, ni postface. Assure-toi que la liste 'elements' est toujours présente, même vide:
          {
            "elements": [
              {
                "texte": "texte intéressant",
                "explication": "explication de l'élément",
                "categorie": "catégorie thématique"
              }
            ]
          }

          Texte à analyser : $texte'''
            }
          ],
          'max_tokens': 500,
        }),
      );

      print('Statut de la réponse: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String elementsText = data['choices']?[0]['message']['content']?.toString() ?? '';

        print('Réponse brute: $elementsText');

        Map<String, dynamic>? parsedElements;
        try {
          elementsText = elementsText.trim();
          elementsText = elementsText.replaceAll(RegExp(r'^```json\s*|\s*```$'), '');
          parsedElements = jsonDecode(elementsText);
          print('JSON parsé avec succès');
        } catch (jsonError) {
          print('Erreur lors du parse JSON direct: $jsonError');
          final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(elementsText);
          if (jsonMatch != null) {
            try {
              String matchedJson = jsonMatch.group(0)!;
              print('JSON extrait par regex: $matchedJson');
              parsedElements = jsonDecode(matchedJson);
              print('JSON récupéré via regex');
            } catch (e) {
              print('Échec de la récupération via regex: $e');
            }
          }
        }

        if (parsedElements != null && parsedElements.containsKey('elements')) {
          List<dynamic> elements = parsedElements['elements'] is List ? parsedElements['elements'] : [];
          print('Éléments trouvés: ${elements.length}');

          if (elements.isNotEmpty) {
            final categoriesSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .collection('categories_elements')
                .get();

            Map<String, String> categoriesExistantes = {};
            for (var doc in categoriesSnapshot.docs) {
              String nomCategorie = doc.data()['nom'].toString();
              categoriesExistantes[normaliserId(nomCategorie)] = doc.id;
              categoriesExistantes[nomCategorie.toLowerCase()] = doc.id;
            }

            print('Catégories existantes: ${categoriesExistantes.keys.join(", ")}');
            int elementsTraites = 0;

            for (var element in elements) {
              if (element is! Map<String, dynamic> ||
                  !element.containsKey('texte') ||
                  !element.containsKey('explication') ||
                  !element.containsKey('categorie')) {
                print('Élément incomplet ou format incorrect, ignoré: $element');
                continue;
              }

              String texteElement = element['texte'] ?? '';
              String explication = element['explication'] ?? '';
              String categorieNom = element['categorie'] ?? '';

              if (texteElement.isEmpty || categorieNom.isEmpty) {
                print('Élément avec texte ou catégorie vide, ignoré');
                continue;
              }

              String categorieNormalisee = normaliserId(categorieNom);
              print('Traitement de l\'élément: "$texteElement" (Catégorie: "$categorieNom", normalisée: "$categorieNormalisee")');

              String categorieId;
              if (categoriesExistantes.containsKey(categorieNormalisee)) {
                categorieId = categoriesExistantes[categorieNormalisee]!;
                print('Catégorie existante trouvée via ID normalisé: $categorieId');
              } else if (categoriesExistantes.containsKey(categorieNom.toLowerCase())) {
                categorieId = categoriesExistantes[categorieNom.toLowerCase()]!;
                print('Catégorie existante trouvée via nom exact: $categorieId');
              } else {
                String docId = normaliserId(categorieNom);
                if (docId.isEmpty) {
                  docId = 'categorie_${DateTime.now().millisecondsSinceEpoch}';
                }

                try {
                  final newCategorieRef = FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUser.uid)
                      .collection('categories_elements')
                      .doc(docId);

                  await newCategorieRef.set({
                    'nom': categorieNom,
                    'createdAt': Timestamp.now(),
                  });

                  categorieId = docId;
                  categoriesExistantes[categorieNormalisee] = categorieId;
                  categoriesExistantes[categorieNom.toLowerCase()] = categorieId;
                  print('Nouvelle catégorie créée: $categorieNom (ID: $categorieId)');
                } catch (e) {
                  print('Erreur lors de la création de la catégorie: $e');
                  continue;
                }
              }

              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser.uid)
                    .collection('categories_elements')
                    .doc(categorieId)
                    .collection('elements')
                    .add({
                  'texte': texteElement,
                  'explication': explication,
                  'date': Timestamp.now(),
                  'isRepost': false,
                  'repostedFromUserId': null,
                  'repostedFromUserName': null,
                });

                elementsTraites++;
                print('Élément ajouté à la catégorie: $categorieId');
              } catch (e) {
                print('Erreur lors de l\'ajout de l\'élément: $e');
              }
            }

            if (elementsTraites > 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$elementsTraites éléments intéressants classifiés et enregistrés'),
                  backgroundColor: Colors.green,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Aucun élément n\'a pu être enregistré'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } else {
            print('Aucun élément trouvé dans le JSON');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Aucun élément intéressant identifié dans le texte'),
                backgroundColor: Colors.blue,
              ),
            );
          }
        } else {
          print('Format JSON invalide ou clé "elements" non trouvée');
          print('Contenu parsé: $parsedElements');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erreur lors de l\'analyse du texte : Format de réponse IA inattendu.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        print('Erreur API: ${response.statusCode} - ${response.reasonPhrase}');
        print('Body: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur API: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Erreur globale lors de l\'enregistrement des éléments intéressants : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<List<String>> _extraireMotsCles(String texte) async {
    if (DEEPSEEK_API_KEY == 'VOTRE_CLÉ_API_DEEPSEEK') {
      print("ERREUR : Clé API DeepSeek non configurée pour les mots-clés.");
      return ['default1', 'default2', 'default3', 'default4', 'default5'];
    }
    const url = 'https://api.deepseek.com/v1/chat/completions';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {
              'role': 'user',
              'content':
              '''Analyse ce texte et extrais exactement 5 mots-clés qui résument les thèmes principaux de la journée. Réponds uniquement avec une liste JSON de 5 mots, sans texte supplémentaire, ni préambule, ni postface. Assure-toi que la liste 'mots_cles' est toujours présente, même vide si aucun mot-clé n'est pertinent:
                {
                  "mots_cles": ["mot1", "mot2", "mot3", "mot4", "mot5"]
                }
                Texte à analyser : $texte'''
            }
          ],
          'max_tokens': 100,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content = data['choices']?[0]['message']['content']?.toString() ?? '';

        if (content.isEmpty) {
          print('Contenu vide dans la réponse des mots-clés');
          return ['default1', 'default2', 'default3', 'default4', 'default5'];
        }

        content = content.trim().replaceAll(RegExp(r'^```json\s*|\s*```$'), '');

        try {
          final motsClesParsed = jsonDecode(content);
          if (motsClesParsed.containsKey('mots_cles') &&
              motsClesParsed['mots_cles'] is List) {
            List<String> extracted = List<String>.from(motsClesParsed['mots_cles']);
            if (extracted.length > 5) {
              return extracted.sublist(0, 5);
            } else if (extracted.length < 5) {
              while (extracted.length < 5) {
                extracted.add('defaut${extracted.length + 1}');
              }
            }
            return extracted;
          } else {
            print('Format de réponse invalide pour mots-clés: $content');
            return ['default1', 'default2', 'default3', 'default4', 'default5'];
          }
        } catch (e) {
          print('Erreur de parsing JSON pour mots-clés : $e, contenu : $content');
          return ['default1', 'default2', 'default3', 'default4', 'default3'];
        }
      } else {
        print('Erreur API DeepSeek pour mots-clés : ${response.statusCode}');
        return ['erreur1', 'erreur2', 'erreur3', 'erreur4', 'erreur5'];
      }
    } catch (e) {
      print('Erreur lors de l\'extraction des mots-clés : $e');
      return ['erreur1', 'erreur2', 'erreur3', 'erreur4', 'erreur5'];
    }
  }

  double _calculateFontSize(String text) {
    if (text.length < 50) {
      return 18.0;
    } else if (text.length < 100) {
      return 16.0;
    } else if (text.length < 200) {
      return 15.0;
    } else {
      return 14.0;
    }
  }

  Future<void> _handleReaction(JourneeModel journee, String selectedEmoji) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final journeeRef = _firestore.collection('journees').doc(journee.id);
      final docSnapshot = await journeeRef.get();

      if (!docSnapshot.exists) {
        throw Exception("Le document de la journée n'existe pas.");
      }

      final data = docSnapshot.data();
      if (data == null) {
        throw Exception("Les données du document sont nulles.");
      }

      Map<String, List<String>> currentReactions = {};
      if (data['reactions'] is Map) {
        final reactionsData = data['reactions'] as Map<String, dynamic>;
        reactionsData.forEach((emoji, users) {
          if (users is List) {
            currentReactions[emoji] = List<String>.from(users);
          }
        });
      }

      String? existingEmoji;
      currentReactions.forEach((emoji, users) {
        if (users.contains(userId)) {
          existingEmoji = emoji;
        }
      });

      if (existingEmoji != null) {
        if (existingEmoji == selectedEmoji) {
          currentReactions[existingEmoji]?.remove(userId);
          if (currentReactions[existingEmoji]?.isEmpty ?? false) {
            currentReactions.remove(existingEmoji);
          }
        } else {
          currentReactions[existingEmoji]?.remove(userId);
          if (currentReactions[existingEmoji]?.isEmpty ?? false) {
            currentReactions.remove(existingEmoji);
          }
          currentReactions.update(
            selectedEmoji,
                (value) => [...value, userId],
            ifAbsent: () => [userId],
          );
        }
      } else {
        currentReactions.update(
          selectedEmoji,
              (value) => [...value, userId],
          ifAbsent: () => [userId],
        );
      }

      await journeeRef.update({'reactions': currentReactions});

// --- AMÉLIORATION : Envoyer une notification ---
      final currentUserDoc = await _firestore.collection('users').doc(userId).get();
      final username = currentUserDoc.data()?['username'] ?? 'Quelqu\'un';
      NotificationService.notifyOwnerOnInteraction(
        journeeId: journee.id!,
        interactorName: username,
        action: "réagi à",
      );

    } catch (e) {
      print('Erreur lors de la gestion de la réaction: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la réaction: $e')),
      );
    }
  }

  Future<List<SouvenirModel>> _getSouvenirsForJournee(JourneeModel journee) async {
    try {
      final journeeDate = DateTime(journee.date.year, journee.date.month, journee.date.day);
      return _mySouvenirs.where((souvenir) {
        final souvenirDate = DateTime(souvenir.date.year, souvenir.date.month, souvenir.date.day);
        return souvenirDate.isAtSameMomentAs(journeeDate);
      }).toList();

    } catch (e) {
      print('Erreur lors de la récupération des souvenirs pour la journée : $e');
      return [];
    }
  }
  void _modifierSouvenir(SouvenirModel souvenir) async {
    bool canModify = await _canModify('souvenirs', souvenir.id);

    if (!mounted) return;

    if (canModify) {
      final bool? wasModified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => SouvenirPage(souvenirToEdit: souvenir),
        ),
      );

      if (wasModified == true) {
        await _firestore.collection('souvenirs').doc(souvenir.id).set({
          'dateDerniereModif': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vous avez déjà modifié ce souvenir aujourd\'hui.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Future<bool> _canModify(String collection, String? docId) async {
    if (docId == null) return false;

    final docRef = _firestore.collection(collection).doc(docId);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) return true;

    final data = docSnapshot.data();
    final lastModifiedTimestamp = data?['dateDerniereModif'] as Timestamp?;

    if (lastModifiedTimestamp == null) {
      return true;
    }

    final lastModifiedDate = lastModifiedTimestamp.toDate();
    final now = DateTime.now();

    if (!_isSameDay(lastModifiedDate, now)) {
      return true;
    }

    return false;
  }

  void _modifierJournee(JourneeModel journee) async {
    bool canModify = await _canModify('journees', journee.id);

    if (!mounted) return;

    if (canModify) {
      final bool? wasModified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => JourneePage(journeeToEdit: journee),
        ),
      );

      if (wasModified == true) {
        await _firestore.collection('journees').doc(journee.id).set({
          'dateDerniereModif': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vous avez déjà modifié cette journée aujourd\'hui.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _signalerJournee(JourneeModel journee) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Journée de ${journee.userId} signalée.')),
    );
  }

  Widget _buildTextWithBlurredAsterisks(String text, {TextStyle? style}) {
    List<TextSpan> spans = [];
    final regex = RegExp(r'\*');

    int start = 0;
    for (Match match in regex.allMatches(text)) {
      if (start < match.start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(TextSpan(
        text: '*',
        style: TextStyle(
          color: Colors.transparent,
          shadows: [
            Shadow(
              blurRadius: 10.0,
              color: Colors.black.withOpacity(0.9),
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
            fontSize: 18,
            height: 1.5,
            color: Colors.black),
        children: spans,
      ),
    );
  }

  Widget _buildSouvenirCard(SouvenirModel souvenir, {bool showRepublishButton = false, required bool hasUserPostedToday}) {
    List<JourneeModel> journeesDuSouvenir = _myJournees.where((journee) {
      return journee.date.year == souvenir.date.year &&
          journee.date.month == souvenir.date.month &&
          journee.date.day == souvenir.date.day;
    }).toList();

    ValueNotifier<bool> isJourneeVisible = ValueNotifier<bool>(false);
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = souvenir.userId == currentUser?.uid;

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .get(),
      builder: (context, userSnapshot) {
        Map<String, dynamic> personalizationPreferences =
            (userSnapshot.data?.data()
            as Map<String, dynamic>?)?['personalizationPreferences'] ??
                {'cardColor': 'default'};

        Color cardColor = Colors.blue.shade100;
        switch (personalizationPreferences['cardColor']) {
          case 'noir': cardColor = Colors.black; break;
          case 'bleu': cardColor = Colors.blue.shade300; break;
          case 'rouge': cardColor = Colors.red.shade300; break;
          case 'vert': cardColor = Colors.green.shade300; break;
          default: cardColor = Colors.blue.shade100;
        }

        return Card(
          margin: EdgeInsets.zero,
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: souvenir.isRepost
                ? const BorderSide(color: Colors.grey, width: 2.0)
                : BorderSide.none,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cardColor,
                  Colors.white,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (souvenir.isRepost)
                    Text(
                      'De ${souvenir.repostedFromUserName ?? 'un ami'}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),

                  Text(
                    souvenir.texte,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  if (souvenir.photoUrls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 50,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: souvenir.photoUrls.length,
                        itemBuilder: (context, index) {
                          final imageUrl = souvenir.photoUrls[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: Image.network(
                                imageUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: 50, height: 50, color: Colors.grey[200],
                                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  print('[UI] ERREUR de chargement de l\'image URL: $imageUrl, Erreur: $error');
                                  return Container(
                                    width: 50, height: 50, color: Colors.grey[200],
                                    child: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const Spacer(),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _formatDate(souvenir.date),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                          fontSize: 10,
                        ),
                      ),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: _getQualiteColor(souvenir.qualite)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _getQualiteLabel(souvenir.qualite),
                              style: TextStyle(
                                color: _getQualiteColor(souvenir.qualite),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: souvenir.estPublic
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              souvenir.estPublic ? 'Public' : 'Privé',
                              style: TextStyle(
                                color: souvenir.estPublic
                                    ? Colors.green
                                    : Colors.red,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
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
        );
      },
    );
  }

  String _getQualiteLabel(sm.SouvenirQualite qualite) {
    switch (qualite) {
      case sm.SouvenirQualite.nostalgie: return "Nostalgie";
      case sm.SouvenirQualite.jamaisOublie: return "Jamais Oublié";
      case sm.SouvenirQualite.bonheur: return "Bonheur";
    }
  }

  Color _getQualiteColor(sm.SouvenirQualite qualite) {
    switch (qualite) {
      case sm.SouvenirQualite.nostalgie: return Colors.purple;
      case sm.SouvenirQualite.jamaisOublie: return Colors.blue;
      case sm.SouvenirQualite.bonheur: return Colors.green;
    }
  }

  Future<void> _supprimerSouvenir(SouvenirModel souvenir) async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      int qualiteDeVieActuelle = userDoc.exists
          ? (userDoc.data() as Map<String, dynamic>)['qualiteDeVieActuelle'] ?? 50
          : 50;

      int nouvelleQualiteDeVie = ((qualiteDeVieActuelle * 2 - souvenir.noteQualite) / 3).round();
      nouvelleQualiteDeVie = nouvelleQualiteDeVie.clamp(0, 100);

      await FirebaseFirestore.instance
          .collection('souvenirs')
          .doc(souvenir.id)
          .delete();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({
        'qualiteDeVieActuelle': nouvelleQualiteDeVie,
      });

      setState(() {
        _souvenirs.remove(souvenir);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Souvenir supprimé avec succès')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression : $e')),
      );
    }
  }

  bool _hasPostedToday() {
    return _myJournees.any((journee) =>
    journee.date.year == _today.year &&
        journee.date.month == _today.month &&
        journee.date.day == _today.day);
  }

  bool _hasPostedTodayWithComment() {
    return _myJournees.any((journee) =>
    journee.date.year == _today.year &&
        journee.date.month == _today.month &&
        journee.date.day == _today.day &&
        journee.commentaire != null &&
        journee.commentaire!.isNotEmpty);
  }

  Future<double> _calculateSimilarity(String text1, String text2) async {
    if (DEEPSEEK_API_KEY == 'VOTRE_CLÉ_API_DEEPSEEK') {
    }
    const String url = 'https://api.deepseek.com/v1/chat/completions';

    if (text1.trim().isEmpty || text2.trim().isEmpty) return 0.0;

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {
              'role': 'user',
              'content':
              '''Compare les deux textes suivants et donne un pourcentage de similarité basé sur leur contenu, leur ton et leurs thèmes principaux. Réponds uniquement avec un nombre entier entre 0 et 100 suivi de "/100", par exemple "75/100".

                  Texte 1: $text1
                  Texte 2: $text2'''
            }
          ],
          'max_tokens': 50,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]['message']['content']?.toString() ?? '';

        if (content.isEmpty) {
          print('Avertissement: Réponse vide de DeepSeek pour le calcul de similarité.');
          return 0.0;
        }

        final match = RegExp(r'(\d+)\s*/\s*100').firstMatch(content);
        if (match != null && match.group(1) != null) {
          return double.parse(match.group(1)!);
        }

        final numberMatch = RegExp(r'\b(\d+)\b').firstMatch(content);
        if (numberMatch != null && numberMatch.group(1) != null) {
          return double.parse(numberMatch.group(1)!);
        }

        print('Avertissement: Format de réponse de similarité inattendu: "$content"');
        return 0.0;
      } else {
        print('Erreur API DeepSeek pour similarité: ${response.statusCode} - ${response.body}');
        return 0.0;
      }
    } catch (e, stacktrace) {
      print('Erreur lors du calcul de la similarité : $e\n$stacktrace');
      return 0.0;
    }
  }
  Future<Map<JourneeModel, double>> _findSimilarJournees(JourneeModel todayJournee) async {
    print('--- DÉBUT DE LA RECHERCHE DE JOURNÉES SIMILAIRES ---');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || todayJournee.id == null) {
      print('[ERREUR] Utilisateur non connecté ou ID de journée manquant.');
      return {};
    }

    final todayDocSnapshot = await _firestore.collection('journees').doc(todayJournee.id).get();
    if (!todayDocSnapshot.exists) {
      print('[ERREUR] Le document de la journée de référence (ID: ${todayJournee.id}) n\'a pas été trouvé.');
      return {};
    }
    final todayData = todayDocSnapshot.data() as Map<String, dynamic>? ?? {};
    final keywordsList = todayData['motsCles'] is List ? List.from(todayData['motsCles']) : [];
    final todayKeywords = keywordsList.map((k) => k.toString().toLowerCase()).toSet();

    final todayText = todayJournee.texte1 ?? todayJournee.commentaire ?? '';

    print('Journée de référence (ID: ${todayJournee.id}): "${todayText.substring(0, min(todayText.length, 50))}..."');
    print('Mots-clés de référence: $todayKeywords');

    if (todayKeywords.isEmpty) {
      print('[FIN] La journée de référence n\'a pas de mots-clés. Analyse annulée pour économiser les ressources.');
      return {};
    }

    if (todayText.trim().isEmpty) {
      print('[AVERTISSEMENT] Le texte de la journée de référence est vide.');
    }

    final allJourneesQuery = await _firestore
        .collection('journees')
        .where('userId', isEqualTo: user.uid)
        .get();
    print('Nombre total de journées de l\'utilisateur à analyser: ${allJourneesQuery.docs.length}');

    final List<Future<MapEntry<JourneeModel, double>?>> similarityFutures = [];

    for (var doc in allJourneesQuery.docs) {
      if (doc.id == todayJournee.id) continue;

      final journee = JourneeModel.fromFirestore(doc);

      final journeeData = doc.data() as Map<String, dynamic>? ?? {};
      final otherKeywordsList = journeeData['motsCles'] is List ? List.from(journeeData['motsCles']) : [];
      final journeeKeywords = otherKeywordsList.map((k) => k.toString().toLowerCase()).toSet();

      final journeeText = journee.texte1 ?? journee.commentaire ?? '';

      if (journeeText.isNotEmpty) {
        print('\n[ANALYSE] Comparaison avec la journée du ${DateFormat('yyyy-MM-dd').format(journee.date)} (ID: ${journee.id})');
        print('  -> Mots-clés: $journeeKeywords');

        final hasCommonKeyword = todayKeywords.any((keyword) => journeeKeywords.contains(keyword));

        if (hasCommonKeyword) {
          print('  -> [OK] Mot(s)-clé(s) commun(s) trouvé(s). Lancement du calcul de similarité sémantique.');
          similarityFutures.add(
            _calculateSimilarity(todayText, journeeText).then((similarity) {
              print('  -> [RÉSULTAT] Similarité sémantique pour la journée (ID: ${journee.id}) : ${similarity.toStringAsFixed(1)}%');
              if (similarity > 30) {
                print('  -> [CONSERVÉ] Seuil de similarité dépassé. Ajout à la liste.');
                return MapEntry(journee, similarity);
              } else {
                print('  -> [IGNORÉ] Seuil de similarité non atteint.');
                return null;
              }
            }),
          );
        } else {
          print('  -> [IGNORÉ] Pas de mot-clé commun. Le calcul de similarité coûteux est évité.');
        }
      } else {
        print('\n[IGNORÉ] Journée du ${DateFormat('yyyy-MM-dd').format(journee.date)} (ID: ${journee.id}) car son texte est vide.');
      }
    }

    if (similarityFutures.isEmpty) {
      print('[FIN] Aucune journée éligible avec des mots-clés communs trouvée.');
      return {};
    }

    print('\nAttente de tous les calculs de similarité...');
    final List<MapEntry<JourneeModel, double>?> results = await Future.wait(similarityFutures);

    final Map<JourneeModel, double> similarJournees = {
      for (var entry in results) if (entry != null) entry.key: entry.value
    };

    final sortedEntries = similarJournees.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    print('--- FIN DE LA RECHERCHE ---');
    print('Nombre de journées similaires trouvées au-dessus du seuil: ${sortedEntries.length}');
    for (var entry in sortedEntries) {
      print('  - ${DateFormat('yyyy-MM-dd').format(entry.key.date)}: ${entry.value.toStringAsFixed(1)}%');
    }

    return Map.fromEntries(sortedEntries);
  }
  void _showSimilarJourneesDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vous n'êtes pas connecté.")),
      );
      return;
    }

    final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final todayQuery = await _firestore
        .collection('journees')
        .where('userId', isEqualTo: user.uid)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .where('date', isLessThan: Timestamp.fromDate(todayEnd))
        .limit(1)
        .get();

    if (todayQuery.docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vous n'avez pas encore posté de journée aujourd'hui.")),
      );
      return;
    }

    final todayJourneeDoc = todayQuery.docs.first;
    final todayJournee = JourneeModel.fromFirestore(todayJourneeDoc);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)),
            SizedBox(height: 16),
            Text("Recherche de journées similaires...", style: TextStyle(color: Colors.blue)),
          ],
        ),
      ),
    );

    Map<JourneeModel, double> similarJournees = {};
    try {
      similarJournees = await _findSimilarJournees(todayJournee);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Une erreur est survenue: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        Navigator.pop(context);
      }
    }

    if (!mounted) return;

    if (similarJournees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune journée suffisamment similaire trouvée (basé sur les mots-clés).'),
          backgroundColor: Colors.blue,
        ),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('journees').doc(todayJourneeDoc.id).set({
      'similarJourneesCache': similarJournees.map((key, value) => MapEntry(key.id!, value)),
      'lastSimilaritySearchDate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Vos Journées Similaires', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Journée d'aujourd'hui :", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
                  Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      title: Text(DateFormat('dd MMMM yyyy').format(todayJournee.date), style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(todayJournee.texte1 ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const Divider(height: 24, thickness: 1),
                  const Text("Journées similaires trouvées :", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
                  const SizedBox(height: 8),
                  ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: similarJournees.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = similarJournees.entries.elementAt(index);
                      final journee = entry.key;
                      final similarity = entry.value;
                      final color = _getPercentageColor(similarity);

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: color.withOpacity(0.5), width: 1)
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('dd MMMM yyyy').format(journee.date),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                journee.texte1 ?? '...',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: similarity / 100,
                                      backgroundColor: color.withOpacity(0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(color),
                                      minHeight: 6,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${similarity.toStringAsFixed(0)}%',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
  Future<List<SouvenirModel>> _getSouvenirsForUser(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('souvenirs')
          .where('userId', isEqualTo: userId)
          .where('estPublic', isEqualTo: true)
          .get();

      return snapshot.docs.map((doc) => SouvenirModel.fromFirestore(doc)).toList();
    } catch (e) {
      print('Erreur lors de la récupération des souvenirs: $e');
      return [];
    }
  }

  Color _getPercentageColor(double percentage) {
    if (percentage > 80) return Colors.green.shade700;
    if (percentage > 60) return Colors.green.shade500;
    if (percentage > 40) return Colors.orange.shade500;
    if (percentage > 20) return Colors.red.shade500;
    return Colors.red.shade700;
  }

  void _showJourneeFilterDialog(ValueNotifier<String> filterNotifier) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filtrer mes journées', style: TextStyle(color: Colors.blue)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildJourneeFilterOption(filterNotifier, 'tout', 'Toutes les journées'),
                const Divider(),
                _buildJourneeFilterOption(filterNotifier, 'note_plus_80', 'Note > 80%'),
                _buildJourneeFilterOption(filterNotifier, 'note_50_80', 'Note 50%-80%'),
                _buildJourneeFilterOption(filterNotifier, 'note_moins_50', 'Note < 50%'),
                _buildJourneeFilterOption(filterNotifier, 'note_moins_30', 'Note < 30%'),
                const Divider(),
                _buildJourneeFilterOption(filterNotifier, 'avec_emoji', 'Avec emoji'),
                _buildJourneeFilterOption(filterNotifier, 'sans_emoji', 'Sans emoji'),
                _buildJourneeFilterOption(filterNotifier, 'avec_commentaire', 'Avec commentaire'),
                _buildJourneeFilterOption(filterNotifier, 'sans_commentaire', 'Sans commentaire'),
                const Divider(),
                _buildJourneeFilterOption(filterNotifier, 'public', 'Publiques'),
                _buildJourneeFilterOption(filterNotifier, 'prive', 'Privées'),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Annuler', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildJourneeFilterOption(ValueNotifier<String> filterNotifier, String filterValue, String label) {
    return ValueListenableBuilder<String>(
      valueListenable: filterNotifier,
      builder: (context, currentFilter, child) {
        return RadioListTile<String>(
          title: Text(label),
          value: filterValue,
          groupValue: currentFilter,
          onChanged: (String? value) {
            if (value != null) {
              filterNotifier.value = value;
              Navigator.of(context).pop();
            }
          },
          activeColor: Colors.blue,
        );
      },
    );
  }

  List<JourneeModel> _filterJournees(List<JourneeModel> journees, String filter) {
    return journees.where((journee) {
      if (filter == 'tout') return true;

      int? note;
      try {
        if (journee.note != null && journee.note!.contains('/')) {
          note = int.tryParse(journee.note!.split('/').first);
        }
      } catch (e) {
        print('Erreur conversion note: $e');
        note = null;
      }

      switch (filter) {
        case 'note_plus_80':
          return (note ?? 0) > 80;
        case 'note_50_80':
          return (note ?? 0) >= 50 && (note ?? 0) <= 80;
        case 'note_moins_50':
          return (note ?? 0) < 50;
        case 'note_moins_30':
          return (note ?? 0) < 30;
        case 'avec_emoji':
          return journee.emoji != null && journee.emoji!.isNotEmpty;
        case 'sans_emoji':
          return journee.emoji == null || journee.emoji!.isEmpty;
        case 'avec_commentaire':
          return journee.commentaire != null && journee.commentaire!.isNotEmpty;
        case 'sans_commentaire':
          return journee.commentaire == null || journee.commentaire!.isEmpty;
        case 'public':
          return journee.estPublic;
        case 'prive':
          return !journee.estPublic;
        default:
          return true;
      }
    }).toList();
  }


  bool _isDifferentDate(DateTime date1, DateTime date2) {
    return date1.year != date2.year ||
        date1.month != date2.month ||
        date1.day != date2.day;
  }

  Widget _buildEmptyMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.book_outlined, size: 100, color: Colors.grey),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${_getWeekday(date.weekday)} ${date.day} ${_getMonth(date.month)} ${date.year}';
  }

  String _getWeekday(int weekday) {
    switch (weekday) {
      case 1:
        return 'Lundi';
      case 2:
        return 'Mardi';
      case 3:
        return 'Mercredi';
      case 4:
        return 'Jeudi';
      case 5:
        return 'Vendredi';
      case 6:
        return 'Samedi';
      case 7:
        return 'Dimanche';
      default:
        return '';
    }
  }

  String _getMonth(int month) {
    switch (month) {
      case 1:
        return 'Janvier';
      case 2:
        return 'Février';
      case 3:
        return 'Mars';
      case 4:
        return 'Avril';
      case 5:
        return 'Mai';
      case 6:
        return 'Juin';
      case 7:
        return 'Juillet';
      case 8:
        return 'Août';
      case 9:
        return 'Septembre';
      case 10:
        return 'Octobre';
      case 11:
        return 'Novembre';
      case 12:
        return 'Décembre';
      default:
        return '';
    }
  }

  Future<void> _supprimerJournee(JourneeModel journee) async {
    if (journee.id == null) return;

    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      int qualiteDeVieActuelle = userDoc.exists
          ? (userDoc.data() as Map<String, dynamic>)['qualiteDeVieActuelle'] ?? 50
          : 50;

      int noteJournee = 50;
      if (journee.note != null && journee.note!.contains('/')) {
        try {
          noteJournee = int.parse(journee.note!.split('/').first);
        } catch (e) {
          noteJournee = 50;
        }
      }

      int nouvelleQualiteDeVie = ((qualiteDeVieActuelle * 2 - noteJournee) / 3).round();
      nouvelleQualiteDeVie = nouvelleQualiteDeVie.clamp(0, 100);

      await FirebaseFirestore.instance
          .collection('journees')
          .doc(journee.id)
          .delete();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({
        'qualiteDeVieActuelle': nouvelleQualiteDeVie,
      });

      setState(() {
        _myJournees.remove(journee);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Journée supprimée avec succès')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression : $e')),
      );
    }
  }
  void _showCommentsDialog(JourneeModel journee, {required bool isMyJournees}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: CommentsSection(
              journeeId: journee.id!,
              isMyJournees: isMyJournees,
            ),
          ),
        );
      },
    );
  }
}
class CommentsSection extends StatefulWidget {
  final String journeeId;
  final bool isMyJournees;

  const CommentsSection({
    Key? key,
    required this.journeeId,
    required this.isMyJournees,
  }) : super(key: key);

  @override
  _CommentsSectionState createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  Future<void> _postComment() async {
    if (_commentController.text.trim().isEmpty || currentUser == null) {
      return;
    }

    final userDoc = await _firestore.collection('users').doc(currentUser!.uid).get();
    final username = userDoc.data()?['username'] ?? 'Utilisateur anonyme';

    await _firestore
        .collection('journees')
        .doc(widget.journeeId)
        .collection('comments')
        .add({
      'text': _commentController.text,
      'userId': currentUser!.uid,
      'username': username,
      'timestamp': FieldValue.serverTimestamp(),
    });

// --- AMÉLIORATION : Envoyer une notification ---
    NotificationService.notifyOwnerOnInteraction(
      journeeId: widget.journeeId,
      interactorName: username,
      action: "commenté",
    );

    _commentController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Commentaires',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('journees')
                .doc(widget.journeeId)
                .collection('comments')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('Aucun commentaire pour le moment.'));
              }

              final comments = snapshot.data!.docs;

              return ListView.builder(
                itemCount: comments.length,
                itemBuilder: (context, index) {
                  final comment = comments[index];
                  final data = comment.data() as Map<String, dynamic>;
                  final timestamp = data['timestamp'] as Timestamp?;
                  final date = timestamp?.toDate();

                  return ListTile(
                    title: Text(data['username'] ?? 'Anonyme', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(data['text'] ?? ''),
                    trailing: date != null
                        ? Text(
                      DateFormat('dd/MM HH:mm').format(date),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    )
                        : null,
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  decoration: const InputDecoration(
                    hintText: 'Ajouter un commentaire...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: _postComment,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
class HeartShapeBorder extends ShapeBorder {
  const HeartShapeBorder();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ui.Path getInnerPath(ui.Rect rect, {ui.TextDirection? textDirection}) {
    return getOuterPath(rect, textDirection: textDirection);
  }

  @override
  ui.Path getOuterPath(ui.Rect rect, {ui.TextDirection? textDirection}) {
    final path = ui.Path();
    final double width = rect.width;
    final double height = rect.height;
    final double x = rect.left;
    final double y = rect.top;

    // Point de départ au centre en haut (la fente du cœur)
    path.moveTo(x + width / 2, y + height * 0.3);

    // Lobe supérieur gauche
    path.cubicTo(x + width * 0.2, y,
        x, y + height * 0.2,
        x, y + height * 0.4);

    // Moitié inférieure gauche jusqu'à la pointe
    path.cubicTo(x, y + height * 0.7,
        x + width * 0.4, y + height * 0.9,
        x + width / 2, y + height);

    // Moitié inférieure droite depuis la pointe
    path.cubicTo(x + width * 0.6, y + height * 0.9,
        x + width, y + height * 0.7,
        x + width, y + height * 0.4);

    // Lobe supérieur droit
    path.cubicTo(x + width, y + height * 0.2,
        x + width * 0.8, y,
        x + width / 2, y + height * 0.3);

    path.close();
    return path;
  }

  @override
  void paint(ui.Canvas canvas, ui.Rect rect, {ui.TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}
// CORRECTION : On utilise le préfixe 'ui.' pour éviter les conflits de type
class StarShapeBorder extends ShapeBorder {
  final int points;
  const StarShapeBorder({this.points = 5});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ui.Path getInnerPath(ui.Rect rect, {ui.TextDirection? textDirection}) {
    return getOuterPath(rect, textDirection: textDirection);
  }

  @override
  ui.Path getOuterPath(ui.Rect rect, {ui.TextDirection? textDirection}) {
    // 1. On dessine une étoile "modèle" sur une toile virtuelle.
    final path = ui.Path();
    const double tempSize = 100.0;
    const double centerX = tempSize / 2;
    const double centerY = tempSize / 2;
    const double outerRadius = tempSize / 2;
    const double innerRadius = outerRadius / 2.5;
    final double step = (math.pi * 2) / (points * 2);
    const double initialAngle = -math.pi / 2;

    for (int i = 0; i < points * 2; i++) {
      final double radius = (i.isEven) ? outerRadius : innerRadius;
      final double angle = initialAngle + i * step;
      final double x = centerX + radius * math.cos(angle);
      final double y = centerY + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // 2. On récupère les dimensions du modèle.
    final templateBounds = path.getBounds();

    // 3. On calcule les facteurs d'échelle.
    final double scaleX = rect.width / templateBounds.width;
    final double scaleY = rect.height / templateBounds.height;

    // 4. On crée la matrice de transformation.
    final matrix = Matrix4.identity();
    matrix.translate(rect.left, rect.top);
    matrix.scale(scaleX, scaleY);
    matrix.translate(-templateBounds.left, -templateBounds.top);

    // 5. On applique la transformation.
    return path.transform(matrix.storage);
  }

  @override
  void paint(ui.Canvas canvas, ui.Rect rect, {ui.TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}


class RoundShapeBorder extends ShapeBorder {
  const RoundShapeBorder();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ui.Path getInnerPath(ui.Rect rect, {ui.TextDirection? textDirection}) {
    return getOuterPath(rect, textDirection: textDirection);
  }

  @override
  ui.Path getOuterPath(ui.Rect rect, {ui.TextDirection? textDirection}) {
    return ui.Path()..addOval(ui.Rect.fromCircle(center: rect.center, radius: rect.shortestSide / 2));
  }

  @override
  void paint(ui.Canvas canvas, ui.Rect rect, {ui.TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

class SouvenirMinimalistShapeBorder extends ShapeBorder {
  const SouvenirMinimalistShapeBorder();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ui.Path getInnerPath(ui.Rect rect, {ui.TextDirection? textDirection}) {
    return getOuterPath(rect, textDirection: textDirection);
  }

  @override
  ui.Path getOuterPath(ui.Rect rect, {ui.TextDirection? textDirection}) {
    return ui.Path()
      ..addRRect(ui.RRect.fromRectAndRadius(rect, const Radius.circular(18.0)));
  }

  @override
  void paint(ui.Canvas canvas, ui.Rect rect, {ui.TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

class JourneeMinimalistShapeBorder extends ShapeBorder {
  const JourneeMinimalistShapeBorder();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ui.Path getInnerPath(ui.Rect rect, {ui.TextDirection? textDirection}) {
    return getOuterPath(rect, textDirection: textDirection);
  }

  @override
  ui.Path getOuterPath(ui.Rect rect, {ui.TextDirection? textDirection}) {
    return ui.Path()
      ..addRRect(ui.RRect.fromRectAndRadius(rect, const Radius.circular(20.0)));
  }

  @override
  void paint(ui.Canvas canvas, ui.Rect rect, {ui.TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}
