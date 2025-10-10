// journee_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_storage/firebase_storage.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'main.dart'; // Assurez-vous que cette importation est correcte pour votre HomeBarrePage
import 'journee_model.dart'; // Assurez-vous que cette importation est correcte
import 'souvenir_model.dart'; // Importez le modèle de souvenir
import 'home_page.dart' show getUserSubscriptionData, showVipPromotionPopup;

// Définissez SouvenirQualite si ce n'est pas déjà dans souvenir_model.dart

// THEME: Variable d'état pour le mode sombre avec ValueNotifier
final ValueNotifier<Brightness> appBrightnessNotifier = ValueNotifier<Brightness>(Brightness.light);

// AJOUTÉ : Clé API nécessaire pour l'analyse des éléments intéressants.
// (À NE PAS LAISSER EN DUR EN PRODUCTION !)
const String DEEPSEEK_API_KEY = 'sk-2891f44dd4e344908dda525bf5852649'; // REMPLACEZ PAR VOTRE VRAIE CLÉ !


class JourneePage extends StatefulWidget {
  final JourneeModel? journeeToEdit;
  final JourneeModel? journeeToRepublish;

  const JourneePage({super.key, this.journeeToEdit, this.journeeToRepublish});

  @override
  _JourneePageState createState() => _JourneePageState(originalJourneeToRepublish: journeeToRepublish);
}

class _JourneePageState extends State<JourneePage> {
  // AJOUTÉ : Constante pour la longueur minimale du texte
  static const int _minTextLength = 20;

  // Contrôleurs et State
  final quill.QuillController _controller = quill.QuillController.basic();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  TextSelection? _previousSelection;

  // Données de la journée
  bool _estPublic = false;
  String? _selectedEmoji;
  String? _commentaire = '';
  int? _note; // Note IA (ou manuelle finale)
  List<String> _motsCles = []; // Initialisé vide
  List<dynamic> _displayImages = []; // Combined list for XFile and URLs
  List<String> _mentionedUserIds = []; // Pour stocker les ID des mentions

  // State pour l'UI et les fonctionnalités
  bool _isCommentEnabled = true;
  double _manualProgress = 50.0; // Initialisé à 50
  bool _isManualProgressActive = false; // Indique si le slider de note manuelle a été déplacé
  bool _isEditingManualNote = false; // Indique si le slider de note manuelle est actuellement affiché
  bool _manualNoteSelected = false; // Indique si une note manuelle a été explicitement choisie (via slider)

  // Reconnaissance vocale
  late stt.SpeechToText _speech;
  bool _isListening = false;

  // Texte masqué (fonctionnalité avancée)
  final List<Map<String, dynamic>> _hiddenTextDetails = [];
  List<String> _selectedFriendIds = [];

  // Outils
  final ImagePicker _picker = ImagePicker();

  final List<Map<String, String>> _emojis = [
    {'emoji': '😊', 'comment': 'Content', 'note': '80'},
    {'emoji': '😢', 'comment': 'Triste', 'note': '20'},
    {'emoji': '😡', 'comment': 'Fâché', 'note': '10'},
    {'emoji': '😱', 'comment': 'Surpris', 'note': '60'},
    {'emoji': '😌', 'comment': 'Détendu', 'note': '70'},
  ];

  // Variable pour le bouton "Poster en tant que souvenir"
  bool _postAsSouvenir = false;

  // Pour la mention d'amis
  List<Map<String, dynamic>> _allFriends = [];
  List<Map<String, dynamic>> _filteredFriends = [];
  OverlayEntry? _overlayEntry;
  String _currentMentionQuery = '';

  // Pour la republication
  final bool _isRepublishing;
  final JourneeModel? _originalJourneeToRepublish;

  bool _showMentionSuggestions = false;
  bool _hasHiddenText = false;

  // NOUVEAU : Variable d'état pour le statut VIP
  bool _isVip = false;

  // CONSTRUCTEUR
  _JourneePageState({JourneeModel? originalJourneeToRepublish})
      : _isRepublishing = originalJourneeToRepublish != null,
        _originalJourneeToRepublish = originalJourneeToRepublish;

  @override
  void initState() {
    super.initState();
    _loadAppBrightness();
    _speech = stt.SpeechToText();
    _loadFriends();
    _checkVipStatus(); // NOUVEAU : Vérifier le statut VIP de l'utilisateur

    // On initialise la sélection précédente
    _previousSelection = _controller.selection;

    // On renomme l'écouteur pour refléter son double rôle
    _controller.addListener(_handleControllerChanges);

    if (widget.journeeToEdit != null) {
      _loadJourneeForEditing();
    } else if (_isRepublishing) {
      _loadJourneeForRepublishing();
    }
  }

// Assurez-vous aussi de retirer l'écouteur dans dispose
  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanges);
    _controller.dispose();
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  // THEME: Nouvelle fonction pour charger la préférence de thème
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
        loadedBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
      }

      if (mounted) {
        appBrightnessNotifier.value = loadedBrightness;
      }
    } catch (e) {
      print('Erreur de chargement de la couleur de fond : $e');
    }
  }

  // --- MÉTHODES DE CHARGEMENT ---

  // NOUVEAU : Méthode pour vérifier le statut VIP
  Future<void> _checkVipStatus() async {
    auth.User? currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      // CORRIGÉ : Appel sans argument, comme requis par l'erreur.
      final subData = await getUserSubscriptionData();
      if (mounted) {
        setState(() {
          _isVip = subData['isVip'] ?? false;
        });
      }
    }
  }

  void _loadJourneeForRepublishing() {
    final originalJournee = _originalJourneeToRepublish!;

    String contentToRepublish = originalJournee.texte1 ?? originalJournee.texte ?? '';
    if (!contentToRepublish.endsWith('\n')) {
      contentToRepublish += '\n';
    }
    _controller.document = quill.Document.fromJson([{'insert': contentToRepublish}]);

    setState(() {
      _selectedEmoji = originalJournee.emoji;
      _commentaire = originalJournee.commentaire;
      _note = null; // La note IA sera recalculée si l'utilisateur choisit l'analyse
      _displayImages.addAll(originalJournee.photoUrls);
      _estPublic = originalJournee.estPublic;
      _isCommentEnabled = true; // Forcer l'affichage du champ de commentaire
      _isManualProgressActive = false;
      _isEditingManualNote = false;
      _manualNoteSelected = false; // Par défaut, pas de note manuelle sélectionnée pour une republication
    });
  }

  void _loadJourneeForEditing() {
    final journee = widget.journeeToEdit!;

    String contentToEdit = journee.texte1 ?? '';
    if (!contentToEdit.endsWith('\n')) {
      contentToEdit += '\n';
    }
    _controller.document = quill.Document.fromJson([{'insert': contentToEdit}]);

    setState(() {
      _estPublic = journee.estPublic;
      _selectedEmoji = journee.emoji;
      if (journee.commentaire != null) {
        _commentaire = journee.commentaire;
        _isCommentEnabled = true;
      } else {
        _isCommentEnabled = false;
      }

      // NOUVELLE LOGIQUE : toute note existante est considérée comme une sélection manuelle.
      if (journee.note != null && journee.note!.contains('/')) {
        int? parsedNote = int.tryParse(journee.note!.split('/').first);
        if (parsedNote != null) {
          _note = parsedNote;
          // On considère la note enregistrée comme un choix manuel pour l'édition
          _manualProgress = _note!.toDouble();
          _manualNoteSelected = true;
        }
      }
      _displayImages.addAll(journee.photoUrls);
      _mentionedUserIds = List<String>.from(journee.mentionedUserIds ?? []);

      if (journee.hiddenTextFriends != null &&
          journee.hiddenTextFriends!.isNotEmpty) {
        _selectedFriendIds = List<String>.from(journee.hiddenTextFriends!);
        _hasHiddenText = _selectedFriendIds.isNotEmpty;
      }
    });
  }

  // --- MÉTHODES POUR LES FONCTIONNALITÉS ---

  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(imageQuality: 85);
      if (pickedFiles.isNotEmpty) {
        setState(() => _displayImages.addAll(pickedFiles));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors de la sélection d'images: $e")));
    }
  }

  void _removeImage(int index) {
    setState(() => _displayImages.removeAt(index));
  }

  Future<void> _toggleListening() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permission microphone refusée")));
      return;
    }
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    bool available = await _speech.initialize(
      onStatus: (status) =>
          setState(() => _isListening = status == 'listening'),
      onError: (error) => setState(() => _isListening = false),
    );
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            final selection = _controller.selection;
            _controller.document.insert(
                selection.baseOffset, result.recognizedWords);
            _controller.updateSelection(
              TextSelection.collapsed(
                  offset: selection.baseOffset + result.recognizedWords.length),
              quill.ChangeSource.local,
            );
          }
        },
        localeId: 'fr_FR',
      );
    }
  }

  // MODIFIÉ : Ajout d'une vérification de la longueur minimale du texte
  Future<void> _analyserEtEnregistrer(bool avecNoteIA) async {
    final currentText = _controller.document.toPlainText().trim();
    if (currentText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez écrire quelque chose à analyser.')));
      return;
    }

    // CORRIGÉ : Vérification de la longueur minimale du texte
    if (currentText.length < _minTextLength) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Veuillez écrire au moins $_minTextLength caractères pour votre journée.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Étape 1: Exécuter les analyses communes (mots-clés et éléments intéressants)
      _motsCles = await _extraireMotsCles(currentText);
      await _enregistrerElementsInteressants(currentText);

      // Étape 2: Obtenir la note si demandé
      if (avecNoteIA) {
        bool noteSuccess = await _obtenirNote(currentText);
        if (!noteSuccess) {
          // Si l'obtention de la note IA échoue, on continue avec une note par défaut de 50
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d\'obtenir la note IA, utilisant 50/100 par défaut.'), backgroundColor: Colors.orange));
          }
          setState(() {
            _note = 50;
            _manualNoteSelected = false; // Ne pas considérer comme sélection manuelle
          });
        }
      } else {
        // Si on analyse sans note IA (parce qu'une note manuelle est fixée),
        // on s'assure que la note IA est nulle pour que la note manuelle soit utilisée.
        setState(() {
          _note = null;
        });
      }

      // Étape 3: Enregistrer la journée avec les données obtenues
      await _enregistrerJournee();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Une erreur est survenue lors de l\'analyse ou l\'enregistrement : $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  // LOGIQUE DE SAUVEGARDE (légèrement ajustée pour être appelée par _analyserEtEnregistrer ou directement par le bouton "Enregistrer")
  Future<void> _enregistrerJournee() async {
    auth.User? currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vous devez être connecté')));
      return;
    }

    final texteOriginal = _controller.document.toPlainText().trim();
    final String actualContent = _isCommentEnabled ? (_commentaire?.trim() ?? '') : texteOriginal;

    // Condition d'enregistrement générale
    if (actualContent.isEmpty && _displayImages.isEmpty && _selectedEmoji == null && !_manualNoteSelected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez écrire quelque chose, laisser un commentaire, ajouter une image, un emoji ou une note manuelle.')));
      return;
    }

    // Afficher le chargement si ce n'est pas déjà géré par _analyserEtEnregistrer
    if (!_isLoading) setState(() => _isLoading = true);

    try {
      // 1. Upload des images
      List<String> uploadedImageUrls = [];
      for (final item in _displayImages) {
        if (item is XFile) {
          final userId = currentUser.uid;
          final fileExt = p.extension(item.name);
          final fileName = '$userId/uploads/${DateTime.now().millisecondsSinceEpoch}_${p.basename(item.name)}';
          final fileBytes = await item.readAsBytes();
          final ref = FirebaseStorage.instance.ref().child('photos').child(fileName);
          final uploadTask = ref.putData(fileBytes, SettableMetadata(contentType: 'image/${fileExt.substring(1)}'));
          final snapshot = await uploadTask.whenComplete(() {});
          final imageUrl = await snapshot.ref.getDownloadURL();
          uploadedImageUrls.add(imageUrl);
        } else if (item is String) {
          uploadedImageUrls.add(item);
        }
      }

      // 2. Logique de note
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      int qualiteDeVieActuelle = (userDoc.data() as Map<String, dynamic>?)?['qualiteDeVieActuelle'] ?? 50;

      int noteFinale;
      if (_manualNoteSelected) { // L'utilisateur a explicitement choisi une note manuelle (via le slider)
        noteFinale = _manualProgress.round();
      } else { // Pas de note manuelle, on utilise la note IA (ou 50 si pas d'IA)
        noteFinale = _note ?? 50; // _note est la note de l'IA si elle a été obtenue, sinon 50
      }

      int nouvelleQualiteDeVie = ((qualiteDeVieActuelle + noteFinale) / 2).round();
      String noteToSave = '$noteFinale/100';


      // 3. Construction de l'objet de données
      Map<String, dynamic> journeeData = {
        'texte1': _isCommentEnabled ? null : texteOriginal,
        'estPublic': _estPublic,
        'date': Timestamp.now(),
        'userId': currentUser.uid,
        'emoji': _selectedEmoji,
        'commentaire': _isCommentEnabled ? _commentaire : null,
        'note': noteToSave,
        'motsCles': _motsCles, // Mots-clés déjà extraits ou vides si pas de texte
        'photoUrls': uploadedImageUrls,
        'hiddenTextFriends': _selectedFriendIds.isNotEmpty ? _selectedFriendIds : null,
        'isRepost': _isRepublishing,
        'repostedFromUserId': _isRepublishing ? _originalJourneeToRepublish!.userId : null,
        'repostedFromUserName': _isRepublishing ? await _getUsernameById(_originalJourneeToRepublish!.userId!) : null,
        'mentionedUserIds': _mentionedUserIds,
      };

      // 4. Sauvegarde dans Firestore
      String? journeeId;
      if (widget.journeeToEdit != null) {
        journeeId = widget.journeeToEdit!.id;
        await FirebaseFirestore.instance.collection('journees').doc(journeeId).update(journeeData);
      } else {
        DocumentReference docRef = await FirebaseFirestore.instance.collection('journees').add(journeeData);
        journeeId = docRef.id;
      }

      // MODIFIÉ : La logique de résumé est retirée. Le souvenir est créé avec le texte intégral.
      if (_postAsSouvenir) {
        await FirebaseFirestore.instance.collection('souvenirs').add({
          'userId': currentUser.uid,
          'journeeId': journeeId,
          'date': Timestamp.now(),
          'texte': texteOriginal, // Texte complet de la journée
          'photoUrls': uploadedImageUrls,
          'emoji': _selectedEmoji,
          'commentaire': _commentaire, // Le commentaire si activé
          'qualite': SouvenirQualite.bonheur.toString(), // Vous pouvez adapter la qualité
          // Le champ 'summary' a été retiré.
          'isRepost': _isRepublishing,
          'repostedFromUserId': _isRepublishing ? _originalJourneeToRepublish!.userId : null,
        });
      }

      await FirebaseFirestore.instance.collection('users')
          .doc(currentUser.uid)
          .update({'qualiteDeVieActuelle': nouvelleQualiteDeVie});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Journée enregistrée !'),
            backgroundColor: Colors.green));
        // MODIFIÉ : On renvoie 'true' pour indiquer que la sauvegarde a réussi.
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const HomeBarrePage()),
                (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur lors de l\'enregistrement : $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  // AJOUTÉ : Copie de la logique d'extraction des éléments intéressants depuis home_page.dart
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

  // AJOUTÉ : Copie de la logique principale de sauvegarde des éléments
  Future<void> _enregistrerElementsInteressants(String texte) async {
    auth.User? currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;



    print('Début de l\'analyse pour catégorisation...');

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

      if (response.statusCode == 200) {
        // CORRIGÉ : Forcer le décodage en UTF-8 pour éviter les problèmes de caractères
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String elementsText = data['choices']?[0]['message']['content']?.toString() ?? '';
        elementsText = elementsText.trim().replaceAll(RegExp(r'^```json\s*|\s*```$'), '');

        Map<String, dynamic>? parsedElements;
        try {
          parsedElements = jsonDecode(elementsText);
        } catch (e) {
          print("Erreur de parsing JSON pour les éléments intéressants: $e");
          return;
        }

        if (parsedElements != null && parsedElements.containsKey('elements')) {
          List<dynamic> elements = parsedElements['elements'] is List ? parsedElements['elements'] : [];
          if (elements.isEmpty) {
            print("Aucun élément intéressant identifié par l'IA.");
            return;
          }

          final categoriesSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('categories_elements')
              .get();

          Map<String, String> categoriesExistantes = {
            for (var doc in categoriesSnapshot.docs) normaliserId(doc.data()['nom'].toString()): doc.id
          };

          int elementsTraites = 0;
          for (var element in elements) {
            String categorieNom = element['categorie'] ?? '';
            String texteElement = element['texte'] ?? '';
            if (categorieNom.isEmpty || texteElement.isEmpty) continue;

            String categorieNormalisee = normaliserId(categorieNom);
            String categorieId;

            if (categoriesExistantes.containsKey(categorieNormalisee)) {
              categorieId = categoriesExistantes[categorieNormalisee]!;
            } else {
              final newCategorieRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .collection('categories_elements')
                  .doc(categorieNormalisee);
              await newCategorieRef.set({'nom': categorieNom, 'createdAt': Timestamp.now()});
              categorieId = categorieNormalisee;
              categoriesExistantes[categorieNormalisee] = categorieId;
            }

            await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .collection('categories_elements')
                .doc(categorieId)
                .collection('elements')
                .add({
              'texte': texteElement,
              'explication': element['explication'] ?? '',
              'date': Timestamp.now(),
              'isRepost': false,
              'repostedFromUserId': null,
              'repostedFromUserName': null,
            });
            elementsTraites++;
          }
          print('$elementsTraites éléments intéressants ont été enregistrés.');
        }
      } else {
        print('Erreur API lors de l\'extraction des éléments : ${response.body}');
      }
    } catch (e) {
      print('Erreur globale lors de l\'enregistrement des éléments intéressants : $e');
    }
  }


  // NOUVELLE MÉTHODE : _extraireMotsCles
  Future<List<String>> _extraireMotsCles(String texte) async {

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
        // CORRIGÉ : Forcer le décodage en UTF-8 pour éviter les problèmes de caractères
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String content = data['choices']?[0]['message']['content']?.toString() ?? '';

        if (content.isEmpty) {
          print('Contenu vide dans la réponse des mots-clés');
          return List.generate(5, (index) => 'défaut${index + 1}');
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
                extracted.add('défaut${extracted.length + 1}');
              }
            }
            return extracted;
          } else {
            print('Format de réponse invalide pour mots-clés: $content');
            return List.generate(5, (index) => 'défaut${index + 1}');
          }
        } catch (e) {
          print('Erreur de parsing JSON pour mots-clés : $e, contenu : $content');
          return List.generate(5, (index) => 'défaut${index + 1}');
        }
      } else {
        print('Erreur API DeepSeek pour mots-clés : ${response.statusCode}');
        return List.generate(5, (index) => 'erreur${index + 1}');
      }
    } catch (e) {
      print('Erreur lors de l\'extraction des mots-clés : $e');
      return List.generate(5, (index) => 'erreur${index + 1}');
    }
  }

  // SUPPRIMÉ : La méthode _summarizeForSouvenir n'est plus nécessaire.

  // --- WIDGETS DE CONSTRUCTION DE L'UI ---
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Brightness>(
      valueListenable: appBrightnessNotifier,
      builder: (context, brightness, child) {
        final isDarkMode = brightness == Brightness.dark;

        return Theme(
          data: isDarkMode ? ThemeData.dark() : ThemeData.light(),
          child: Scaffold(
            backgroundColor: isDarkMode
                ? const Color(0xFF121212)
                : Colors.grey.shade50,
            appBar: AppBar(
              title: Text(
                _isRepublishing
                    ? 'Republier la journée'
                    : (widget.journeeToEdit == null ? 'Nouvelle Journée' : 'Modifier la Journée'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: isDarkMode
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
              foregroundColor: isDarkMode ? Colors.white : Colors.black,
              elevation: 1,
              centerTitle: true,
            ),
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildEditorCard(isDarkMode),
                    const SizedBox(height: 16),
                    _buildImagePreviews(),
                    const SizedBox(height: 16),
                    _buildActionToolbar(isDarkMode),
                    const SizedBox(height: 16),
                    _buildEmojiAndNoteCard(isDarkMode),
                    const SizedBox(height: 16),
                    _buildPostAsSouvenirSwitch(isDarkMode),
                    const SizedBox(height: 24),
                    _buildSaveButtons(), // <- WIDGET MODIFIÉ
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditorCard(bool isDarkMode) {
    return Card(
      elevation: 2,
      color: _isRepublishing
          ? (isDarkMode ? Colors.grey.shade800.withOpacity(0.5) : Colors.grey.shade100.withOpacity(0.5))
          : (isDarkMode ? const Color(0xFF1E1E1E) : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Stack(
        children: [
          Container(
            height: 250,
            padding: const EdgeInsets.all(8),
            child: DefaultTextStyle(
              style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
              child: quill.QuillEditor.basic(
                controller: _controller,
                focusNode: _focusNode,
                configurations: quill.QuillEditorConfigurations(
                  placeholder: _isRepublishing
                      ? 'Texte original (non modifiable)'
                  // MODIFIÉ : Le message inclut la limite de caractères
                      : 'Écrivez votre journée ici (minimum $_minTextLength caractères)...',
                ),
              ),
            ),
          ),
          if (_isRepublishing)
            Positioned.fill(
              child: Container(
                color: Colors.transparent,
                child: AbsorbPointer(absorbing: true, child: Container()),
              ),
            ),
          if (_isRepublishing)
            Positioned(
              top: 8,
              right: 8,
              child: Tooltip(
                message: 'Le texte original ne peut pas être modifié.',
                child: Icon(
                  Icons.lock_outline,
                  color: isDarkMode ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagePreviews() {
    if (_displayImages.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _displayImages.length,
        itemBuilder: (context, index) {
          final item = _displayImages[index];
          Widget imageWidget;

          if (item is XFile) {
            if (kIsWeb) {
              imageWidget = FutureBuilder<Uint8List>(
                future: item.readAsBytes(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                    return Image.memory(snapshot.data!, width: 110, height: 110, fit: BoxFit.cover);
                  }
                  return const SizedBox(width: 110, height: 110, child: Center(child: CircularProgressIndicator()));
                },
              );
            } else {
              imageWidget = Image.file(File(item.path), width: 110, height: 110, fit: BoxFit.cover);
            }
          } else if (item is String) {
            imageWidget = Image.network(item, width: 110, height: 110, fit: BoxFit.cover,);
          } else {
            imageWidget = const SizedBox.shrink();
          }

          return Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(12.0), child: imageWidget),
                GestureDetector(
                  onTap: () => _removeImage(index),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // CORRIGÉ : La structure a été simplifiée pour éviter le RenderFlex overflow
  Widget _buildActionToolbar(bool isDarkMode) {
    return Card(
      elevation: 2,
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: [
            IconButton(
              onPressed: _isRepublishing ? null : _toggleListening,
              icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
              color: _isListening
                  ? Colors.red
                  : (isDarkMode ? Colors.white70 : Colors.grey.shade700),
              tooltip: 'Dictée vocale',
            ),
            IconButton(
              onPressed: _pickImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              color: Colors.green,
              tooltip: 'Ajouter une photo',
            ),
            IconButton(
              onPressed: _isRepublishing ? null : () => _showFriendSelectionDialog(),
              icon: const Icon(Icons.visibility_off_outlined),
              color: _hasHiddenText
                  ? Colors.red.shade700
                  : (isDarkMode ? Colors.white70 : Colors.grey.shade700),
              tooltip: 'Masquer du texte',
            ),
            const Spacer(), // Le Spacer pousse les éléments suivants vers la droite
            Text(
              _estPublic ? 'Public' : 'Privé',
              style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
            ),
            Switch(
              value: _estPublic,
              onChanged: (value) => setState(() => _estPublic = value),
              activeColor: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  // MODIFIÉ : La logique des émojis est maintenant indépendante de la note manuelle.
  Widget _buildEmojiAndNoteCard(bool isDarkMode) {
    return Card(
      elevation: 2,
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Section Emojis
            AnimatedOpacity(
              opacity: _isCommentEnabled ? 0.5 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: AbsorbPointer( // Désactiver les emojis si le champ commentaire est actif
                absorbing: _isCommentEnabled,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _emojis.map((emojiData) {
                    final isSelected = _selectedEmoji == emojiData['emoji'];
                    return GestureDetector(
                      onTap: () {
                        // NOUVELLE LOGIQUE SIMPLE : sélectionne/désélectionne l'émoji sans aucun autre effet.
                        setState(() {
                          if (_selectedEmoji == emojiData['emoji']) {
                            _selectedEmoji = null;
                          } else {
                            _selectedEmoji = emojiData['emoji'];
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.blue.withOpacity(0.2)
                                : Colors.transparent,
                            shape: BoxShape.circle),
                        child: Text(emojiData['emoji']!, style: TextStyle(fontSize: isSelected ? 34 : 30)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (_isRepublishing)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Text(
                  "Ajoutez votre commentaire sur ce souvenir :",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              ),
            if (_isCommentEnabled)
              TextField(
                controller: TextEditingController(text: _commentaire),
                onChanged: (value) => setState(() => _commentaire = value),
                style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Votre commentaire ici...',
                  labelStyle: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey.shade600),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade100,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: isDarkMode ? Colors.grey.shade600 : Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.blue),
                  ),
                ),
              )
            else
              _buildNoteManualSection(isDarkMode),
          ],
        ),
      ),
    );
  }

  // MODIFIÉ : L'activation de la note manuelle ne désélectionne plus l'émoji.
  Widget _buildNoteManualSection(bool isDarkMode) {
    if (_isEditingManualNote) {
      // Afficher le slider et le bouton "Annuler"
      return Column(
        children: [
          Row(
            children: [
              Icon(Icons.sentiment_dissatisfied, color: Colors.grey.shade600),
              Expanded(
                child: Slider(
                  value: _manualProgress,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: _manualProgress.round().toString(),
                  onChanged: (double value) {
                    setState(() {
                      _manualProgress = value;
                      _manualNoteSelected = true;     // Confirme qu'une note manuelle est sélectionnée
                      _note = null;                 // Réinitialise la note IA
                    });
                  },
                  activeColor: Colors.blue,
                  inactiveColor: Colors.blue.withOpacity(0.3),
                ),
              ),
              const Icon(Icons.sentiment_satisfied, color: Colors.green),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Note manuelle : ${_manualProgress.round()}/100',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: isDarkMode ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isEditingManualNote = false; // Cache le slider
                    _manualNoteSelected = false;  // Annule la sélection manuelle
                    _manualProgress = 50.0;     // Réinitialiser à la valeur par défaut
                  });
                },
                child: const Text('Annuler', style: TextStyle(color: Colors.red)),
              ),
            ],
          )
        ],
      );
    } else {
      // Afficher le bouton "Note Manuelle"
      return OutlinedButton.icon(
        icon: const Icon(Icons.edit_note, size: 20),
        label: Text(_manualNoteSelected ? 'Note Manuelle: ${_manualProgress.round()}/100' : "Note Manuelle"),
        onPressed: () {
          setState(() {
            _isEditingManualNote = true;      // Affiche le slider
            _manualNoteSelected = true;       // Indique qu'une note manuelle est en cours de sélection
            // On ne touche plus à _selectedEmoji, les deux peuvent coexister
            _note = null;                   // Réinitialise la note IA
          });
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: isDarkMode ? Colors.white70 : Colors.black54,
          side: BorderSide(color: isDarkMode ? Colors.white30 : Colors.black26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }


  // MODIFIÉ : Le switch vérifie maintenant le statut VIP
  Widget _buildPostAsSouvenirSwitch(bool isDarkMode) {
    final bool canPostAsSouvenir = (_controller.document.toPlainText().trim().isNotEmpty || (_commentaire?.trim().isNotEmpty ?? false) || _displayImages.isNotEmpty || _selectedEmoji != null || _manualNoteSelected);

    return Card(
      elevation: 2,
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Row(
          children: [
            const Text("Poster en tant que souvenir"),
            const SizedBox(width: 8),
            Icon(Icons.star, color: Colors.amber.shade700, size: 16),
          ],
        ),
        secondary: Icon(
          Icons.auto_stories_outlined,
          color: isDarkMode ? Colors.white70 : Colors.grey.shade700,
        ),
        value: _postAsSouvenir && canPostAsSouvenir,
        onChanged: canPostAsSouvenir
            ? (value) {
          if (value && !_isVip) {
            // CORRIGÉ : Appel avec 2 arguments : context et une fonction de rappel.
            showVipPromotionPopup(context, () {
              // Ce code est exécuté si l'utilisateur devient VIP depuis la popup.
              if (mounted) {
                setState(() {
                  _isVip = true;
                  _postAsSouvenir = true; // Activer le switch
                });
              }
            } as String);
          } else {
            // Si l'utilisateur est VIP ou s'il désactive le switch
            setState(() => _postAsSouvenir = value);
          }
        }
            : null,
        subtitle: !canPostAsSouvenir
            ? const Text("Écrivez, ajoutez une image, un emoji ou une note pour activer.", style: TextStyle(color: Colors.redAccent, fontSize: 12))
            : Text(
          "Option réservée aux membres VIP.",
          style: TextStyle(
            color: isDarkMode ? Colors.amber.shade300 : Colors.amber.shade900,
            fontSize: 12,
          ),
        ),
        activeColor: Colors.amber.shade700,
      ),
    );
  }

  // MODIFIÉ : La logique d'affichage des boutons a été entièrement revue.
  Widget _buildSaveButtons() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final bool hasTextToAnalyze = _controller.document.toPlainText().trim().isNotEmpty;
    final bool hasAnyContent = hasTextToAnalyze ||
        (_commentaire?.trim().isNotEmpty ?? false) ||
        _displayImages.isNotEmpty ||
        _selectedEmoji != null ||
        _manualNoteSelected;

    // CAS 1 : Une note manuelle a été sélectionnée par l'utilisateur.
    if (_manualNoteSelected) {
      return ElevatedButton(
        onPressed: hasAnyContent ? () {
          // S'il y a du texte, on lance l'analyse (mots-clés, etc.) mais sans générer de note IA.
          // La fonction _enregistrerJournee utilisera la note manuelle (_manualProgress).
          if (hasTextToAnalyze) {
            _analyserEtEnregistrer(false);
          } else {
            // S'il n'y a pas de texte (ex: juste une photo et une note), on enregistre directement.
            _enregistrerJournee();
          }
        } : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Colors.orange.shade700,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        // Le texte du bouton est "Analyser et enregistrer sans note IA" comme demandé.
        child: const Text('Analyser et enregistrer sans note IA'),
      );
    }
    // CAS 2 : Aucune note manuelle n'a été sélectionnée.
    else {
      // S'il y a du texte à analyser, on affiche le bouton par défaut qui analyse ET note avec l'IA.
      if (hasTextToAnalyze) {
        return ElevatedButton(
          onPressed: () => _analyserEtEnregistrer(true),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          // Le texte du bouton est "Analyser et noter avec IA" comme demandé.
          child: const Text('Analyser et noter avec IA'),
        );
      }
      // S'il n'y a pas de texte (mais d'autres contenus), un simple bouton "Enregistrer" est affiché.
      else {
        return ElevatedButton(
          onPressed: hasAnyContent ? _enregistrerJournee : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          child: const Text('Enregistrer'),
        );
      }
    }
  }


  // 5. Améliorer le popup pour un meilleur design :
  void _toggleHiddenTextVisibility(int textIndex) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ValueListenableBuilder<Brightness>(
          valueListenable: appBrightnessNotifier,
          builder: (context, brightness, child) {
            final isDarkMode = brightness == Brightness.dark;
            final hiddenDetail = _hiddenTextDetails[textIndex];
            final friendIds = List<String>.from(hiddenDetail['friendIds']);
            final hiddenText = hiddenDetail['text'];

            return AlertDialog(
              backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              title: Row(
                children: [
                  Icon(
                    Icons.visibility_off,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Texte masqué',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.yellow.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.yellow.withOpacity(0.4)),
                      ),
                      child: Text(
                        '"$hiddenText"',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Visible uniquement pour :',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...friendIds.map((friendId) {
                      final friend = _allFriends.firstWhere(
                            (f) => f['id'] == friendId,
                        orElse: () => {'username': 'Ami inconnu'},
                      );
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: 16,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              friend['username'],
                              style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey.shade700),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Supprimer le masquage'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () {
                    _removeHiddenText(textIndex);
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('Fermer', style: TextStyle(color: Colors.blue)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 4. Modifier _removeHiddenText pour retirer le surlignage :
  void _removeHiddenText(int index) {
    setState(() {
      final removedDetail = _hiddenTextDetails.removeAt(index);
      _hasHiddenText = _hiddenTextDetails.isNotEmpty;

      // Recalculer la liste globale des amis masqués
      _selectedFriendIds.clear();
      for (var detail in _hiddenTextDetails) {
        List<String> friendIds = List<String>.from(detail['friendIds']);
        for (String friendId in friendIds) {
          if (!_selectedFriendIds.contains(friendId)) {
            _selectedFriendIds.add(friendId);
          }
        }
      }

      // Retirer le surlignage du texte dans l'éditeur
      final documentText = _controller.document.toPlainText();
      final targetText = removedDetail['text'] as String;

      // Chercher toutes les occurrences et les dé-surligner
      int startIndex = 0;
      while (true) {
        startIndex = documentText.indexOf(targetText, startIndex);
        if (startIndex == -1) break;

        // Retirer le surlignage en utilisant background avec null
        _controller.formatText(
          startIndex,
          targetText.length,
          quill.Attribute.fromKeyValue('background', null),
        );

        startIndex += targetText.length;
      }
    });
  }

  // --- AUTRES MÉTHODES (logique existante) ---

  Future<List<Map<String, dynamic>>> _getFriendsList() async {
    auth.User? currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    try {
      QuerySnapshot friendsSnapshot = await FirebaseFirestore.instance
          .collection('friends')
          .where('users', arrayContains: currentUser.uid)
          .get();

      List<Future<Map<String, dynamic>>> friendFutures = friendsSnapshot.docs.map((doc) async {
        List<String> users = List<String>.from(doc['users']);
        String friendId = users.firstWhere((id) => id != currentUser.uid);
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(friendId).get();
        return {
          'id': friendId,
          'username': userDoc['username'] ?? 'Utilisateur inconnu',
          'name': userDoc['name'] ?? '',
        };
      }).toList();
      return await Future.wait(friendFutures);
    } catch (e) {
      return [];
    }
  }

  void _loadFriends() async {
    List<Map<String, dynamic>> friends = await _getFriendsList();
    if (mounted) {
      setState(() {
        _allFriends = friends;
      });
    }
  }

// MODIFICATION ICI: La logique qui effaçait la note manuelle en tapant du texte a été supprimée.
  void _handleControllerChanges() {
    final currentSelection = _controller.selection;
    final doc = _controller.document;
    final plainText = doc.toPlainText();

    // --- 1. GESTION DU CLIC SUR TEXTE MASQUÉ ---
    if (_previousSelection != null &&
        plainText.length == doc.toPlainText().length && // Le texte n'a pas changé
        currentSelection != _previousSelection &&      // La sélection a changé
        currentSelection.isCollapsed) {                // C'est un clic (curseur)

      final style = _controller.getSelectionStyle();
      if (style.containsKey('background') && style.attributes['background']!.value == '#FFFF00') {
        final offset = currentSelection.baseOffset;
        int foundIndex = -1;
        int currentPos = 0;

        for (int i = 0; i < _hiddenTextDetails.length; i++) {
          final detail = _hiddenTextDetails[i];
          final textToFind = detail['text'] as String;

          int startIndex = plainText.indexOf(textToFind, currentPos);
          if (startIndex != -1) {
            final endIndex = startIndex + textToFind.length;
            if (offset >= startIndex && offset < endIndex) {
              foundIndex = i;
              break;
            }
            currentPos = endIndex;
          }
        }

        if (foundIndex != -1) {
          Future.microtask(() {
            _focusNode.unfocus();
            _toggleHiddenTextVisibility(foundIndex);
          });
        }
      }
    }


    // --- 2. GESTION DES MENTIONS ---
    if (currentSelection.baseOffset > 0) {
      final textBeforeCursor = plainText.substring(0, currentSelection.baseOffset);
      final lastAtIndex = textBeforeCursor.lastIndexOf('@');

      if (lastAtIndex != -1) {
        final textAfterAt = textBeforeCursor.substring(lastAtIndex + 1);
        if (!textAfterAt.contains(' ')) {
          _currentMentionQuery = textAfterAt;
          setState(() {
            _filteredFriends = _allFriends
                .where((friend) =>
            (friend['username']?.toLowerCase() ?? '')
                .contains(_currentMentionQuery.toLowerCase()) ||
                (friend['name']?.toLowerCase() ?? '')
                    .contains(_currentMentionQuery.toLowerCase()))
                .toList();
            _showMentionSuggestions = true;
          });
          _showOverlay();
        } else {
          _removeOverlay();
        }
      } else {
        _removeOverlay();
      }
    } else {
      _removeOverlay();
    }

    // --- 3. GESTION DE L'UI ---
    final trimmedText = plainText.trim();
    if (mounted) {
      setState(() {
        // Active/désactive le champ commentaire si l'éditeur est vide
        _isCommentEnabled = trimmedText.isEmpty;

        // Si le texte est vide, et qu'aucune note manuelle n'est active, on réinitialise tout
        if (trimmedText.isEmpty && !_manualNoteSelected) {
          _note = null;
          _isEditingManualNote = false;
          _manualProgress = 50.0;
        }

        // CORRECTION IMPORTANTE : Suppression de la logique qui désélectionnait
        // l'emoji/note manuelle quand l'utilisateur tapait du texte.
        // Cela permet au texte et à la note manuelle de coexister.

        _postAsSouvenir = false;
      });
    }

    // --- 4. MISE À JOUR DE LA SÉLECTION PRÉCÉDENTE ---
    _previousSelection = currentSelection;
  }
  void _insertMentionInQuill(String friendName, String friendId) {
    final text = _controller.document.toPlainText();
    final selection = _controller.selection;
    final textBeforeCursor = text.substring(0, selection.baseOffset);
    final lastAtIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtIndex != -1) {
      final deleteLength = selection.baseOffset - lastAtIndex;
      _controller.document.delete(lastAtIndex, deleteLength);
      _controller.document.insert(lastAtIndex, '@$friendName ');
      _controller.updateSelection(
        TextSelection.collapsed(offset: lastAtIndex + friendName.length + 2),
        quill.ChangeSource.local,
      );

      setState(() {
        if (!_mentionedUserIds.contains(friendId)) {
          _mentionedUserIds.add(friendId);
        }
      });
    }
    _removeOverlay();
  }


  void _showFriendSelectionDialog({Map<String, dynamic>? existingDetail, int? indexToEdit}) async {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez sélectionner du texte à masquer dans l\'éditeur'))
      );
      return;
    }

    final selectedText = _controller.document.toPlainText().substring(
        selection.baseOffset,
        selection.extentOffset
    );

    if (selectedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La sélection est vide'))
      );
      return;
    }

    List<Map<String, dynamic>> friends = await _getFriendsList();
    if (!mounted) return;

    List<String> tempSelectedFriendIds = [];
    if (existingDetail != null) {
      tempSelectedFriendIds = List<String>.from(existingDetail['friendIds']);
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDarkMode = appBrightnessNotifier.value == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              title: Text(
                existingDetail != null ? 'Modifier les amis' : 'Sélectionner les amis',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Texte à masquer: "$selectedText"',
                      style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Sélectionnez qui peut voir ce texte:',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...friends.isEmpty
                        ? [
                      Text(
                        'Aucun ami trouvé.',
                        style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey.shade700),
                      )
                    ]
                        : friends.map((friend) {
                      return CheckboxListTile(
                        title: Text(
                          friend['username'] ?? 'Sans nom',
                          style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                        ),
                        subtitle: friend['name']?.isNotEmpty == true
                            ? Text(
                          friend['name'],
                          style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey.shade700),
                        )
                            : null,
                        value: tempSelectedFriendIds.contains(friend['id']),
                        onChanged: (bool? value) {
                          setDialogState(() {
                            if (value == true) {
                              tempSelectedFriendIds.add(friend['id']);
                            } else {
                              tempSelectedFriendIds.remove(friend['id']);
                            }
                          });
                        },
                        activeColor: Colors.blue,
                        checkColor: Colors.white,
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Annuler', style: TextStyle(color: Colors.red)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('Confirmer', style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    if (tempSelectedFriendIds.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Veuillez sélectionner au moins un ami'))
                      );
                      return;
                    }

                    // Modifier la méthode de formatage pour utiliser un surlignage au lieu du rouge :
                    _controller.formatSelection(
                        quill.Attribute.fromKeyValue('background', '#FFFF00') // Surlignage jaune
                    );

                    setState(() {
                      if (indexToEdit != null) {
                        _hiddenTextDetails[indexToEdit] = {
                          'friendIds': List<String>.from(tempSelectedFriendIds),
                          'text': selectedText
                        };
                      } else {
                        _hiddenTextDetails.add({
                          'friendIds': List<String>.from(tempSelectedFriendIds),
                          'text': selectedText
                        });
                      }

                      _selectedFriendIds.clear();
                      for (var detail in _hiddenTextDetails) {
                        List<String> friendIds = List<String>.from(detail['friendIds']);
                        for (String friendId in friendIds) {
                          if (!_selectedFriendIds.contains(friendId)) {
                            _selectedFriendIds.add(friendId);
                          }
                        }
                      }
                      _hasHiddenText = _hiddenTextDetails.isNotEmpty;
                    });

                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue, // Couleur du bouton
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _removeOverlay();
    }

    if (_filteredFriends.isEmpty) return;

    OverlayState? overlayState = Overlay.of(context);
    final RenderBox? editorRenderBox = _focusNode.context?.findRenderObject() as RenderBox?;
    if (editorRenderBox == null) return;
    final Offset editorOffset = editorRenderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<Brightness>(
        valueListenable: appBrightnessNotifier,
        builder: (context, brightness, child) {
          final isDarkMode = brightness == Brightness.dark;

          return Positioned(
            top: editorOffset.dy + editorRenderBox.size.height + 8,
            left: editorOffset.dx + 16,
            width: editorRenderBox.size.width - 32,
            child: Material(
              elevation: 8.0,
              borderRadius: BorderRadius.circular(8),
              color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _filteredFriends.length,
                  itemBuilder: (context, index) {
                    final friend = _filteredFriends[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Text(
                          (friend['username']?.substring(0, 1) ?? 'U').toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        friend['username'] ?? 'Inconnu',
                        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                      ),
                      subtitle: friend['name']?.isNotEmpty == true
                          ? Text(
                        friend['name'],
                        style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey.shade700),
                      )
                          : null,
                      onTap: () => _insertMentionInQuill(friend['username'] ?? 'Inconnu', friend['id']),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );

    overlayState.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // OBTENIR NOTE (MODIFIÉE pour prendre le texte en paramètre et retourner un booléen pour le succès)
  Future<bool> _obtenirNote(String currentText) async {

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String iaPreference = prefs.getString('iaPreference') ?? 'ressenti';
    String prompt = iaPreference == 'ressenti'
        ? 'Analyse ce texte et donne une note sur 100 basée sur le ressenti. Réponds uniquement avec un nombre entier suivi de "/100". Texte : $currentText'
        : 'Analyse ce texte et donne une note sur 100 basée sur la qualité de la journée. Réponds uniquement avec un nombre entier suivi de "/100". Texte : $currentText';

    const url = 'https://api.deepseek.com/v1/chat/completions';
    try {
      final response = await http.post(Uri.parse(url),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $DEEPSEEK_API_KEY'},
          body: jsonEncode({
            'model': 'deepseek-chat',
            'messages': [{'role': 'user', 'content': prompt}],
            'max_tokens': 50
          }));

      if (response.statusCode == 200) {
        // CORRIGÉ : Forcer le décodage en UTF-8 pour éviter les problèmes de caractères
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final noteText = data['choices'][0]['message']['content']?.toString() ?? '';
        final standardMatch = RegExp(r'(\d+)/100').firstMatch(noteText);

        int? parsedNote = standardMatch != null
            ? int.tryParse(standardMatch.group(1)!)
            : int.tryParse(RegExp(r'(\d+)').firstMatch(noteText)?.group(1) ?? '');

        if (parsedNote != null) {
          setState(() {
            _note = parsedNote.clamp(0, 100);
            _manualNoteSelected = false; // La note IA désactive la note manuelle explicite
            _isEditingManualNote = false; // Cache le slider manuel
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Note IA obtenue : $_note/100'), backgroundColor: Colors.green));
          return true; // Succès
        } else {
          throw Exception("Format de note non reconnu par l'IA");
        }
      } else {
        throw Exception('Erreur API DeepSeek lors de l\'obtention de la note: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur d\'obtention de la note: $e'), backgroundColor: Colors.red));
      }
      return false; // Échec
    }
  }

  Future<String?> _getUsernameById(String userId) async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      return userDoc['username'];
    } catch (e) {
      return null;
    }
  }
}