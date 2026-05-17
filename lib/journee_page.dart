// journee_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_storage/firebase_storage.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
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
import 'ai_model_selector.dart';

// Définissez SouvenirQualite si ce n'est pas déjà dans souvenir_model.dart

// THEME: Variable d'état pour le mode sombre avec ValueNotifier
final ValueNotifier<Brightness> appBrightnessNotifier = ValueNotifier<Brightness>(Brightness.light);

// AJOUTÉ : Clé API nécessaire pour l'analyse des éléments intéressants.
// (À NE PAS LAISSER EN DUR EN PRODUCTION !)
const String DEEPSEEK_API_KEY = 'HA2RvSG1u7aE7u78yXd1UqnBuMY6VV70'; // REMPLACEZ PAR VOTRE VRAIE CLÉ !


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
  // REMOVED: String? _commentaire = ''; // Le commentaire n'est plus un champ distinct de la UI
  int? _note; // Note IA (ou manuelle finale)
  List<String> _motsCles = []; // Initialisé vide
  List<dynamic> _displayImages = []; // Combined list for XFile and URLs
  List<String> _mentionedUserIds = []; // Pour stocker les ID des mentions

  // State pour l'UI et les fonctionnalités
  // REMOVED: bool _isCommentEnabled = true; // Plus besoin car plus de section commentaire
  double _manualProgress = 50.0; // Initialisé à 50
  // REMOVED: bool _isManualProgressActive = false; // Plus pertinent
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
  // REMOVED: final TextEditingController _commentController = TextEditingController(); // Plus utilisé
  // REMOVED: final FocusNode _commentFocusNode = FocusNode(); // Plus utilisé

  // Pour la republication
  final bool _isRepublishing;
  final JourneeModel? _originalJourneeToRepublish;

  // REMOVED: bool _showMentionSuggestions = false; // Simplifié, géré par l'overlay
  bool _hasHiddenText = false;

  // NOUVEAU : Variable d'état pour le statut VIP
  bool _isVip = false;
  String? _selectedCardColor; // Couleur locale de la carte (null = suivre le global)

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
    _checkVipStatus();

    _previousSelection = _controller.selection;

    // Seul le contrôleur Quill est écouté maintenant
    _controller.addListener(_handleControllerChanges);

    if (widget.journeeToEdit != null) {
      _loadJourneeForEditing();
    } else if (_isRepublishing) {
      _loadJourneeForRepublishing();
    } else {
      // On charge l'état par défaut enregistré lors d'une nouvelle création
      _loadDefaultPublicState(); 
    }
  }

  // --- NOUVELLES METHODES DE SAUVEGARDE ---
  Future<void> _loadDefaultPublicState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _estPublic = prefs.getBool('defaultVisibilityPublic') ?? false;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanges);
    _controller.dispose();
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  // THEME: Nouvelle fonction pour charger la préférence de thème
  Future<void>_loadAppBrightness() async {
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

    String mainContent = originalJournee.texte1 ?? originalJournee.commentaire ?? '\n';
    if (mainContent.trim().isEmpty) {
      mainContent = '\n';
    }
    if (!mainContent.endsWith('\n')) {
      mainContent += '\n';
    }

    _controller.document = quill.Document.fromJson([{'insert': mainContent}]);

    setState(() {
      _estPublic = originalJournee.estPublic;
      _note = null;
      _selectedEmoji = originalJournee.emoji;
      _displayImages.addAll(originalJournee.photoUrls);
      _selectedCardColor = originalJournee.cardColor;
      // REMOVED: _isCommentEnabled = true; // Plus besoin de ce flag
    });
  }

  void _loadJourneeForEditing() {
    final journee = widget.journeeToEdit!;

    // Si la journée originale avait un commentaire, on le met dans le texte principal pour l'édition
    String contentToEdit = journee.texte1 ?? journee.commentaire ?? '';
    if (!contentToEdit.endsWith('\n')) {
      contentToEdit += '\n';
    }
    _controller.document = quill.Document.fromJson([{'insert': contentToEdit}]);

    setState(() {
      _estPublic = journee.estPublic;
      _selectedEmoji = journee.emoji;
      _selectedCardColor = journee.cardColor;
      // REMOVED: _commentaire et _isCommentEnabled ne sont plus gérés ici.

      if (journee.note != null && journee.note!.contains('/')) {
        int? parsedNote = int.tryParse(journee.note!.split('/').first);
        if (parsedNote != null) {
          _note = parsedNote;
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

      // Restaurer les détails de masquage par segment
      if (journee.hiddenTextDetails != null &&
          journee.hiddenTextDetails!.isNotEmpty) {
        _hiddenTextDetails.clear();
        _hiddenTextDetails.addAll(
          journee.hiddenTextDetails!.map((d) => {
            'text': d['text'] as String? ?? '',
            'friendIds': List<String>.from(d['friendIds'] as List? ?? []),
          }),
        );
        _hasHiddenText = true;
      }
    });

    // Ré-appliquer le surlignage jaune après que le document soit construit
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fullText = _controller.document.toPlainText();
      for (final detail in _hiddenTextDetails) {
        final text = detail['text'] as String? ?? '';
        if (text.isEmpty) continue;
        final idx = fullText.indexOf(text);
        if (idx >= 0) {
          _controller.formatText(
              idx, text.length, quill.Attribute.fromKeyValue('background', '#FFFF00'));
          _controller.formatText(
              idx, text.length, quill.Attribute.fromKeyValue('color', '#000000'));
        }
      }
    });
  }

  // METHODE DE SELECTION DE COULEUR
  void _showColorPickerDialog() {
    final colors = {
      'bleu': Colors.blue, 'vert': Colors.green, 'rouge': Colors.red,
      'orange': Colors.orange, 'jaune': Colors.yellow, 'violet': Colors.purple, 'rose': Colors.pink, 'blanc': Colors.grey.shade300
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Couleur de cette publication'),
        content: Wrap(
          spacing: 12, runSpacing: 12,
          children: colors.keys.map((String key) {
            return GestureDetector(
              onTap: () {
                setState(() => _selectedCardColor = key);
                Navigator.pop(context);
              },
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: colors[key],
                  shape: BoxShape.circle,
                  border: Border.all(color: _selectedCardColor == key ? Colors.black : Colors.transparent, width: 3),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _selectedCardColor = null);
              Navigator.pop(context);
            },
            child: const Text("Suivre le paramètre global"),
          )
        ],
      ),
    );
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

  Future<void> _analyserEtEnregistrer(bool avecNoteIA) async {
    final currentText = _controller.document.toPlainText().trim();
    if (currentText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez écrire quelque chose à analyser.')));
      return;
    }

    if (currentText.length < _minTextLength) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Veuillez écrire au moins $_minTextLength caractères pour votre journée afin de procéder à l\'analyse IA.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      _motsCles = await _extraireMotsCles(currentText);
      await _enregistrerElementsInteressants(currentText);

      if (avecNoteIA) {
        bool noteSuccess = await _obtenirNote(currentText);
        if (!noteSuccess) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d\'obtenir la note IA, utilisant 50/100 par défaut.'), backgroundColor: Colors.orange));
          }
          setState(() {
            _note = 50;
            _manualNoteSelected = false;
          });
        }
      } else {
        setState(() {
          _note = null;
        });
      }

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

  Future<void> _enregistrerJournee() async {
    auth.User? currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vous devez être connecté')));
      return;
    }

    final textePrincipal = _controller.document.toPlainText().trim();

      // Calcul du texte masqué (parties cachées remplacées par des *)
      String maskedText = textePrincipal;
      for (var detail in _hiddenTextDetails) {
        // trim() pour ignorer les \n de fin que Quill ajoute à la sélection
        final hiddenText = (detail['text'] as String? ?? '').trim();
        if (hiddenText.isNotEmpty) {
          if (maskedText.contains(hiddenText)) {
            maskedText = maskedText.replaceFirst(hiddenText, '*' * hiddenText.length);
          } else {
            // Fallback: normaliser les espaces/sauts de ligne pour la comparaison
            final hiddenNorm = hiddenText.replaceAll(RegExp(r'\s+'), ' ');
            final maskedNorm = maskedText.replaceAll(RegExp(r'\s+'), ' ');
            if (maskedNorm.contains(hiddenNorm)) {
              maskedText = maskedNorm.replaceFirst(hiddenNorm, '*' * hiddenNorm.length);
            }
          }
        }
      }
      final String? texte1Masked = _hiddenTextDetails.isNotEmpty ? maskedText : null;
    // Condition d'enregistrement générale
    if (textePrincipal.isEmpty && _displayImages.isEmpty && _selectedEmoji == null && !_manualNoteSelected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez écrire quelque chose, ajouter une image, un emoji ou une note manuelle.')));
      return;
    }

    if (!_isLoading) setState(() => _isLoading = true);

    try {
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

      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();

      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      final int qualiteDeVieActuelle = userData['qualiteDeVieActuelle'] ?? 50;
      final String? userCountry = userData['country'];

      int noteFinale;
      if (_manualNoteSelected) {
        noteFinale = _manualProgress.round();
      } else {
        noteFinale = _note ?? 50;
      }

      int nouvelleQualiteDeVie = ((qualiteDeVieActuelle + noteFinale) / 2).round();
      String noteToSave = '$noteFinale/100';

      Map<String, dynamic> journeeData = {
        'texte1': textePrincipal.isNotEmpty ? textePrincipal : null, // Store if not empty
        'texte1Masked': texte1Masked, // Version avec * pour les non-autorisés
        'hiddenTextDetails': _hiddenTextDetails.isNotEmpty
            ? _hiddenTextDetails.map((d) => {
                'text': d['text'],
                'friendIds': List<String>.from(d['friendIds'] as List? ?? []),
              }).toList()
            : null,
        'estPublic': _estPublic,

        // 👇 LA CORRECTION EST ICI 👇
        'date': widget.journeeToEdit != null 
            ? Timestamp.fromDate(widget.journeeToEdit!.date) 
            : Timestamp.now(),
        // 👆 FIN DE LA CORRECTION 👆

        'userId': currentUser.uid,
        'emoji': _selectedEmoji,
        'commentaire': null, // REMOVED: Commentaire n'est plus un champ distinct de la UI
        'note': noteToSave,
        'motsCles': _motsCles,
        'photoUrls': uploadedImageUrls,
        'cardColor': _selectedCardColor,
        'hiddenTextFriends': _selectedFriendIds.isNotEmpty ? _selectedFriendIds : null,
        'mentionedUserIds': _mentionedUserIds,
        'isRepost': _isRepublishing,
        'repostedFromUserId': _isRepublishing ? _originalJourneeToRepublish!.userId : null,
        'repostedFromUserName': _isRepublishing ? await _getUsernameById(_originalJourneeToRepublish!.userId!) : null,
      };

      if (userCountry != null && userCountry.isNotEmpty) {
        journeeData['userCountry'] = userCountry;
      }

      String? journeeId;
      if (widget.journeeToEdit != null) {
        journeeId = widget.journeeToEdit!.id;
        await FirebaseFirestore.instance.collection('journees').doc(journeeId).update(journeeData);
      } else {
        DocumentReference docRef = await FirebaseFirestore.instance.collection('journees').add(journeeData);
        journeeId = docRef.id;
      }

      if (_postAsSouvenir) {
        // Générer un résumé court (2-3 phrases max) en fonction de la préférence IA
        String souvenirTexte = textePrincipal;
        try {
          final String? generated = await _generateSouvenirSummary(textePrincipal);
          if (generated != null && generated.trim().isNotEmpty) {
            souvenirTexte = generated.trim();
          }
        } catch (e) {
          print('Erreur génération résumé souvenir : $e');
        }

        await FirebaseFirestore.instance.collection('souvenirs').add({
          'userId': currentUser.uid,
          'journeeId': journeeId,
          'date': Timestamp.now(),
          'texte': souvenirTexte,
          'photoUrls': uploadedImageUrls,
          'emoji': _selectedEmoji,
          'commentaire': null, // Le commentaire n'est plus un champ distinct
          'qualite': SouvenirQualite.bonheur.toString(),
          'isRepost': _isRepublishing,
          'repostedFromUserId': _isRepublishing ? _originalJourneeToRepublish!.userId : null,
        });
      }

      await FirebaseFirestore.instance.collection('users')
          .doc(currentUser.uid)
          .update({'qualiteDeVieActuelle': nouvelleQualiteDeVie});

      // Classify excerpts into biographical themes (fire-and-forget)
      if (textePrincipal.isNotEmpty && journeeId != null) {
        _classifierExtraitsParThemes(textePrincipal, journeeId, widget.journeeToEdit?.date ?? DateTime.now());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Journée enregistrée !'),
            backgroundColor: Colors.green));
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
    auth.User? currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    print('Début de l\'analyse pour catégorisation...');

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
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String elementsText = data['choices']?[0]['message']['content']?.toString() ?? '';
        elementsText = elementsText.trim().replaceAll(RegExp(r'^```json\s*|\s*```$'), '');

        Map<String, dynamic>? parsedElements;
        try {
          parsedElements = jsonDecode(elementsText);
        } catch (_) {
          try {
            final sanitized = elementsText.replaceAllMapped(
                RegExp(r'[\x00-\x1F]'), (m) => ' ');
            parsedElements = jsonDecode(sanitized);
          } catch (e) {
            print("Erreur de parsing JSON pour les éléments intéressants: $e");
            return;
          }
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

  /// Génère un résumé court (2-3 phrases max) adapté à la préférence IA de l'utilisateur.
  Future<String?> _generateSouvenirSummary(String texte) async {
    if (texte.trim().isEmpty) return null;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String iaPreference = prefs.getString('iaPreference') ?? 'ressenti';

    String instruction;
    if (iaPreference == 'ressenti') {
      instruction = 'Reformule ce texte en un résumé très court (2 à 3 phrases maximum) en mettant l\'accent sur le ressenti émotionnel et ce qui a le plus compté dans la journée. Utilise un ton chaleureux et concis.';
    } else {
      instruction = 'Reformule ce texte en un résumé très court (2 à 3 phrases maximum) en focalisant sur les événements et la qualité générale de la journée. Sois précis et concis.';
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
            {'role': 'system', 'content': 'Tu es un assistant qui résume du texte en français de manière claire et concise.'},
            {'role': 'user', 'content': '$instruction\n\nTexte : $texte'},
          ],
          'max_tokens': 150,
          'temperature': 0.6,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['choices']?[0]['message']?['content']?.toString();
        if (content == null) return null;
        String result = content.trim();
        // Supprimer les éventuels délimiteurs de code
        result = result.replaceAll(RegExp(r'^```(?:json)?\s*|\s*```\s*\$', multiLine: false), '');
        // Forcer à 2-3 phrases max : couper après 3 points.
        final sentences = RegExp(r'([^.!?]+[.!?])').allMatches(result).map((m) => m.group(0)!.trim()).toList();
        if (sentences.isEmpty) return result;
        final limited = sentences.take(3).join(' ');
        return limited;
      } else {
        print('Erreur API résumé souvenir: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Exception génération résumé souvenir: $e');
      return null;
    }
  }

  /// Classifie des extraits de la journée dans des thèmes/sous-thèmes biographiques sur Firebase.
  Future<void> _classifierExtraitsParThemes(String texte, String journeeId, DateTime dateEvent) async {
    auth.User? currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null || texte.isEmpty) return;
    debugPrint('[THEME_CLASSIFY] ── Début classification journée $journeeId (${texte.length} chars) ──');
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
          'temperature': 0.1,
          'messages': [
            {
              'role': 'system',
              'content': 'Tu es un assistant expert en analyse textuelle. Tu réponds UNIQUEMENT avec du JSON valide, sans aucun texte avant ou après le JSON. Ne fournis jamais d\'explication, de commentaire ou de texte en dehors de l\'objet JSON demandé.',
            },
            {
              'role': 'user',
              'content': '''Analyse ce texte de journal intime et découpe-le en segments sémantiques significatifs. Pour CHAQUE segment pertinent :
- Extrais le passage exact (une phrase ou groupe de phrases cohérentes).
- Attribue un thème principal en UN seul mot (catégorie large : famille, travail, amour, santé, amis, loisirs, voyage, école, argent, spiritualité, enfance, nature, créativité, etc.).
- Crée un sous-thème court et très descriptif de 3 à 7 mots (formule émotionnelle ou contextuelle précise, exemples : "Malheur à la maternelle", "Bonheur au nouveau travail", "Dispute avec un ami proche", "Peur de l\'avenir professionnel", "Fierté après une réussite scolaire", "Deuil d\'un proche aimé", "Nouveau départ dans une ville inconnue").

RÈGLE ABSOLUE : Multiplie les extraits. Chaque émotion, événement ou contexte important = un extrait séparé avec son propre sous-thème unique. Ne regroupe pas des événements différents dans un seul extrait.

Réponds UNIQUEMENT avec ce JSON, sans aucun autre texte :
{"extraits":[{"theme":"famille","sous_theme":"Dispute avec la mère ce matin","extrait":"passage exact tiré du texte"}]}

Texte à analyser : $texte'''
            }
          ],
          'max_tokens': 2000,
        }),
      );
      debugPrint('[THEME_CLASSIFY] Réponse API: status=${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('[THEME_CLASSIFY] ERREUR API: ${response.body}');
        return;
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      String raw = (data['choices']?[0]['message']['content'] as String? ?? '').trim();
      debugPrint('[THEME_CLASSIFY] Réponse brute IA: ${raw.length > 200 ? raw.substring(0, 200) : raw}');
      raw = raw.replaceAll(RegExp(r'^```json\s*|\s*```$'), '');
      final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(raw);
      if (jsonMatch == null) {
        debugPrint('[THEME_CLASSIFY] Impossible de trouver le JSON dans la réponse');
        return;
      }
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(jsonMatch.group(0)!);
      } catch (_) {
        try {
          final sanitized = jsonMatch.group(0)!.replaceAllMapped(
              RegExp(r'[\x00-\x1F]'), (m) => ' ');
          parsed = jsonDecode(sanitized);
        } catch (e) {
          debugPrint('[THEME_CLASSIFY] Erreur parsing JSON: $e');
          return;
        }
      }
      final extraits = parsed?['extraits'] as List?;
      if (extraits == null || extraits.isEmpty) {
        debugPrint('[THEME_CLASSIFY] Aucun extrait retourné par l\'IA');
        return;
      }
      debugPrint('[THEME_CLASSIFY] ${extraits.length} extraits à enregistrer');

      final db = FirebaseFirestore.instance;
      int saved = 0;
      for (final extrait in extraits) {
        final theme = (extrait['theme'] as String? ?? '').trim();
        final sousTheme = (extrait['sous_theme'] as String? ?? '').trim();
        final texteExtrait = (extrait['extrait'] as String? ?? '').trim();
        if (theme.isEmpty || sousTheme.isEmpty || texteExtrait.isEmpty) continue;
        final themeId = normaliserId(theme);
        final sousThemeId = normaliserId(sousTheme);
        debugPrint('[THEME_CLASSIFY] → thème="$theme" ($themeId) | sous-thème="$sousTheme" ($sousThemeId)');
        final themeRef = db
            .collection('users')
            .doc(currentUser.uid)
            .collection('themes_biographiques')
            .doc(themeId);
        await themeRef.set({'nom': theme, 'createdAt': Timestamp.now()}, SetOptions(merge: true));
        final sousThemeRef = themeRef.collection('sous_themes').doc(sousThemeId);
        await sousThemeRef.set(
            {'nom': sousTheme, 'updatedAt': Timestamp.now()}, SetOptions(merge: true));

        final startOfDay = DateTime(dateEvent.year, dateEvent.month, dateEvent.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));

        final existingSnap = await sousThemeRef.collection('extraits')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('date', isLessThan: Timestamp.fromDate(endOfDay))
            .limit(1)
            .get();

        if (existingSnap.docs.isNotEmpty) {
          final doc = existingSnap.docs.first;
          final existingTexte = doc.get('texte') as String? ?? '';
          final mergedTexte = existingTexte + '\n' + texteExtrait;
          await doc.reference.update({
             'texte': mergedTexte,
             'lastAnalyzedAutobiographie': FieldValue.delete(), // Mettre à null pour repasser en IA si besoin
             'journeeId': journeeId,
             'sourceType': 'journee_et_souvenir', // On indique que ça peut être mixte
          });
        } else {
          await sousThemeRef.collection('extraits').add({
            'texte': texteExtrait,
            'journeeId': journeeId,
            'sourceType': 'journee',
            'date': Timestamp.fromDate(dateEvent),
          });
        }
        saved++;
      }
      debugPrint('[THEME_CLASSIFY] ✓ $saved extraits enregistrés dans themes_biographiques (journée)');
    } catch (e) {
      debugPrint('[THEME_CLASSIFY] EXCEPTION: $e');
    }
  }

  Future<List<String>> _extraireMotsCles(String texte) async {
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
          'temperature': 0.1,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content': 'Tu es un assistant qui répond UNIQUEMENT avec du JSON valide. Aucun texte avant ou après le JSON.',
            },
            {
              'role': 'user',
              'content': 'Extrais 5 mots-clés importants de ce texte. Si tu en trouves plus, choisis les 5 plus importants. Réponds UNIQUEMENT avec ce JSON : {"mots_cles":["mot1","mot2","mot3","mot4","mot5"]}\n\nTexte : $texte'
            }
          ],
          'max_tokens': 150,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String content = data['choices']?[0]['message']['content']?.toString() ?? '';

        // Strip invisible unicode chars (zero-width space, BOM, etc.)
        content = content.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), '').trim();

        if (content.isEmpty) {
          print('Contenu vide dans la réponse des mots-clés');
          return _extraireMotsClesLocalement(texte);
        }

        content = content.replaceAll(RegExp(r'^```json\s*|\s*```$', multiLine: false), '');

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
            return _extraireMotsClesLocalement(texte);
          }
        } catch (e) {
          print('Erreur de parsing JSON pour mots-clés : $e, contenu : $content');
          // Fallback: extract top words directly from the original text
          return _extraireMotsClesLocalement(texte);
        }
      } else {
        print('Erreur API DeepSeek pour mots-clés : ${response.statusCode}');
        return _extraireMotsClesLocalement(texte);
      }
    } catch (e) {
      print('Erreur lors de l\'extraction des mots-clés : $e');
      return _extraireMotsClesLocalement(texte);
    }
  }

  /// Fallback: extract the 5 most frequent meaningful words directly from [texte].
  List<String> _extraireMotsClesLocalement(String texte) {
    const stopWords = {
      'je', 'tu', 'il', 'elle', 'nous', 'vous', 'ils', 'elles', 'me', 'te',
      'se', 'le', 'la', 'les', 'un', 'une', 'des', 'du', 'de', 'et', 'ou',
      'mais', 'donc', 'or', 'ni', 'car', 'que', 'qui', 'quoi', 'dont', 'où',
      'est', 'sont', 'était', 'avec', 'dans', 'sur', 'pour', 'par', 'en',
      'au', 'aux', 'ce', 'cet', 'cette', 'ces', 'mon', 'ton', 'son', 'ma',
      'ta', 'sa', 'mes', 'tes', 'ses', 'pas', 'plus', 'très', 'bien', 'tout',
      'aussi', 'si', 'ne', 'ai', 'as', 'a', 'our', 'été', 'avoir', 'être',
    };
    final freq = <String, int>{};
    for (final word in texte.toLowerCase().split(RegExp(r'[^a-zàâäéèêëîïôùûüç]+'))) {
      if (word.length >= 4 && !stopWords.contains(word)) {
        freq[word] = (freq[word] ?? 0) + 1;
      }
    }
    final sorted = freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final result = sorted.take(5).map((e) => e.key).toList();
    while (result.length < 5) result.add('mot${result.length + 1}');
    return result;
  }

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
                    _buildSaveButtons(),
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
                config: quill.QuillEditorConfig(
                  placeholder: _isRepublishing
                      ? 'Texte original (non modifiable)'
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
            IconButton(
              onPressed: _isRepublishing ? null : _showColorPickerDialog,
              icon: const Icon(Icons.palette_outlined),
              color: _selectedCardColor != null 
                  ? Colors.blue
                  : (isDarkMode ? Colors.white70 : Colors.grey.shade700),
              tooltip: 'Couleur de la publication',
            ),
            const Spacer(),
            Text(
              _estPublic ? 'Public' : 'Privé',
              style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
            ),
            Switch(
              value: _estPublic,
              onChanged: _togglePublicState, // <-- ON UTILISE LA NOUVELLE FONCTION ICI
              activeColor: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  void _togglePublicState(bool value) async {
    setState(() {
      _estPublic = value;
    });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('defaultVisibilityPublic', value);
  }

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _emojis.map((emojiData) {
                final isSelected = _selectedEmoji == emojiData['emoji'];
                return GestureDetector(
                  onTap: () {
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
            const SizedBox(height: 16),
            _buildNoteManualSection(isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteManualSection(bool isDarkMode) {
    if (_isEditingManualNote) {
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
                      _manualNoteSelected = true;
                      _note = null;
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
                    _isEditingManualNote = false;
                    _manualNoteSelected = false;
                    _manualProgress = 50.0;
                  });
                },
                child: const Text('Annuler', style: TextStyle(color: Colors.red)),
              ),
            ],
          )
        ],
      );
    } else {
      return OutlinedButton.icon(
        icon: const Icon(Icons.edit_note, size: 20),
        label: Text(_manualNoteSelected ? 'Note Manuelle: ${_manualProgress.round()}/100' : "Note Manuelle"),
        onPressed: () {
          setState(() {
            _isEditingManualNote = true;
            _manualNoteSelected = true;
            _note = null;
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

  Widget _buildPostAsSouvenirSwitch(bool isDarkMode) {
    final bool canPostAsSouvenir = (_controller.document.toPlainText().trim().isNotEmpty || _displayImages.isNotEmpty || _selectedEmoji != null || _manualNoteSelected);

    return Card(
      elevation: 2,
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Row(
          children: [
            const Flexible(
              child: Text(
                "Poster en tant que souvenir",
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
            showVipPromotionPopup(context, "Poster en tant que souvenir");
          } else {
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

  Widget _buildSaveButtons() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final bool hasTextInEditor = _controller.document.toPlainText().trim().isNotEmpty;
    final bool hasEnoughTextForIA = hasTextInEditor && _controller.document.toPlainText().trim().length >= _minTextLength;
    final bool hasAnyContent = hasTextInEditor || _displayImages.isNotEmpty || _selectedEmoji != null || _manualNoteSelected;


    // CAS 1 : Une note manuelle a été sélectionnée par l'utilisateur.
    if (_manualNoteSelected) {
      return ElevatedButton(
        onPressed: hasAnyContent ? () {
          // Si le texte est suffisant pour l'IA, on lance l'analyse (mots-clés, etc.) mais sans générer de note IA.
          // La fonction _enregistrerJournee utilisera la note manuelle (_manualProgress).
          if (hasEnoughTextForIA) {
            _analyserEtEnregistrer(false);
          } else {
            // S'il n'y a pas assez de texte (ou aucun texte), on enregistre directement sans analyse IA.
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
        child: const Text('Enregistrer sans note IA'),
      );
    }
    // CAS 2 : Aucune note manuelle n'a été sélectionnée.
    else {
      // S'il y a assez de texte pour l'IA, on affiche le bouton par défaut qui analyse ET note avec l'IA.
      if (hasEnoughTextForIA) {
        return ElevatedButton(
          onPressed: () => _analyserEtEnregistrer(true),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          child: const Text('Analyser et noter avec IA'),
        );
      }
      // S'il n'y a pas assez de texte (mais d'autres contenus), un simple bouton "Enregistrer" est affiché.
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
          child: Text(hasTextInEditor ? 'Enregistrer (texte trop court pour IA)' : 'Enregistrer'),
        );
      }
    }
  }


  void _toggleHiddenTextVisibility(int textIndex) async {
    final hiddenDetail = _hiddenTextDetails[textIndex];
    final hiddenText = hiddenDetail['text'] as String? ?? '';

    // Charger la liste complète des amis
    List<Map<String, dynamic>> friends = _allFriends.isNotEmpty
        ? _allFriends
        : await _getFriendsList();
    if (!mounted) return;

    List<String> tempFriendIds = List<String>.from(hiddenDetail['friendIds'] as List? ?? []);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDarkMode = appBrightnessNotifier.value == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              title: Row(
                children: [
                  const Icon(Icons.visibility_off, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Gérer le masquage',
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
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.yellow.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.yellow.withOpacity(0.5)),
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
                      'Cacher ce texte à :',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (friends.isEmpty)
                      Text(
                        'Aucun ami trouvé.',
                        style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey.shade600),
                      )
                    else
                      ...friends.map((friend) {
                        final friendId = friend['id'] as String? ?? '';
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            friend['username'] ?? 'Sans nom',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black,
                              fontSize: 14,
                            ),
                          ),
                          value: tempFriendIds.contains(friendId),
                          activeColor: Colors.blue,
                          onChanged: (bool? value) {
                            setDialogState(() {
                              if (value == true) {
                                if (!tempFriendIds.contains(friendId)) {
                                  tempFriendIds.add(friendId);
                                }
                              } else {
                                tempFriendIds.remove(friendId);
                              }
                            });
                          },
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
                  child: Text('Annuler', style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: const Text('Confirmer', style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    if (tempFriendIds.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sélectionnez au moins un ami')),
                      );
                      return;
                    }
                    setState(() {
                      _hiddenTextDetails[textIndex] = {
                        'friendIds': List<String>.from(tempFriendIds),
                        'text': hiddenText,
                      };
                      // Recalculer _selectedFriendIds
                      _selectedFriendIds.clear();
                      for (var detail in _hiddenTextDetails) {
                        for (final id in List<String>.from(detail['friendIds'] as List? ?? [])) {
                          if (!_selectedFriendIds.contains(id)) _selectedFriendIds.add(id);
                        }
                      }
                      _hasHiddenText = _hiddenTextDetails.isNotEmpty;
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _removeHiddenText(int index) {
    setState(() {
      final removedDetail = _hiddenTextDetails.removeAt(index);
      _hasHiddenText = _hiddenTextDetails.isNotEmpty;

      _selectedFriendIds.clear();
      for (var detail in _hiddenTextDetails) {
        List<String> friendIds = List<String>.from(detail['friendIds']);
        for (String friendId in friendIds) {
          if (!_selectedFriendIds.contains(friendId)) {
            _selectedFriendIds.add(friendId);
          }
        }
      }

      final documentText = _controller.document.toPlainText();
      final targetText = removedDetail['text'] as String;

      int startIndex = 0;
      while (true) {
        startIndex = documentText.indexOf(targetText, startIndex);
        if (startIndex == -1) break;

        _controller.formatText(
          startIndex,
          targetText.length,
          quill.Attribute.fromKeyValue('background', null),
        );

        startIndex += targetText.length;
      }
    });
  }

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

  void _handleControllerChanges() {
    final bool isQuillActive = _focusNode.hasFocus;

    // Si le QuillEditor n'est pas actif, on cache les suggestions
    if (!isQuillActive) {
      _removeOverlay();
      return;
    }

    final String plainText = _controller.document.toPlainText();
    final TextSelection selection = _controller.selection;

    // Logique de clic sur du texte masqué
    if (_previousSelection != null &&
        plainText.length == _controller.document.toPlainText().length &&
        selection != _previousSelection &&
        selection.isCollapsed) {
      final style = _controller.getSelectionStyle();
      if (style.containsKey('background') && style.attributes['background']!.value == '#FFFF00') {
        // Find which hidden text detail matches the selected range
        final int? index = _hiddenTextDetails.indexWhere((detail) {
          final String targetText = detail['text'];
          final int textStart = plainText.indexOf(targetText, selection.baseOffset - targetText.length);
          return textStart != -1 && selection.baseOffset >= textStart && selection.baseOffset <= textStart + targetText.length;
        });
        if (index != -1 && index != null) {
          _toggleHiddenTextVisibility(index);
        }
      }
    }
    _previousSelection = selection;

    // Logique de détection des mentions (uniquement pour l'éditeur Quill)
    if (selection.baseOffset > 0) {
      final textBeforeCursor = plainText.substring(0, selection.baseOffset);
      final lastAtIndex = textBeforeCursor.lastIndexOf('@');

      if (lastAtIndex != -1) {
        final textAfterAt = textBeforeCursor.substring(lastAtIndex + 1);
        if (!textAfterAt.contains(' ')) {
          _currentMentionQuery = textAfterAt;
          setState(() {
            _filteredFriends = _allFriends
                .where((friend) =>
            (friend['username']?.toLowerCase() ?? '').contains(_currentMentionQuery.toLowerCase()) ||
                (friend['name']?.toLowerCase() ?? '').contains(_currentMentionQuery.toLowerCase()))
                .toList();
          });
          _showOverlay(); // Affiche l'overlay pour l'éditeur Quill
        } else {
          _removeOverlay();
        }
      } else {
        _removeOverlay();
      }
    } else {
      _removeOverlay();
    }

    // Mise à jour de l'UI (si le texte principal est vide, les notes IA sont réinitialisées)
    final trimmedText = plainText.trim();
    if (mounted) {
      setState(() {
        // _isCommentEnabled est retiré, donc pas de logique ici
        if (trimmedText.isEmpty && !_manualNoteSelected) {
          _note = null;
          _isEditingManualNote = false;
          _manualProgress = 50.0;
        }
        _postAsSouvenir = false;
      });
    }
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
                      'Texte masqué : "$selectedText"',
                      style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Cacher ce texte à :',
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

                    _controller.formatSelection(
                        quill.Attribute.fromKeyValue('background', '#FFFF00')
                    );
                    // Texte noir sur fond jaune pour être lisible
                    _controller.formatSelection(
                        quill.Attribute.fromKeyValue('color', '#000000')
                    );

                    setState(() {
                      if (indexToEdit != null) {
                        _hiddenTextDetails[indexToEdit] = {
                          'friendIds': List<String>.from(tempSelectedFriendIds),
                          'text': selectedText.trim()
                        };
                      } else {
                        _hiddenTextDetails.add({
                          'friendIds': List<String>.from(tempSelectedFriendIds),
                          'text': selectedText.trim()
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
                    backgroundColor: Colors.blue,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showOverlay({bool isForCommentField = false}) { // isForCommentField n'est plus utilisé
    if (_overlayEntry != null) _removeOverlay();
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
                        child: Text((friend['username']?.substring(0, 1) ?? 'U').toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(friend['username'] ?? 'Inconnu', style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
                      subtitle: friend['name']?.isNotEmpty == true ? Text(friend['name'], style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey.shade700)) : null,
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

  Future<bool> _obtenirNote(String currentText) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String iaPreference = prefs.getString('iaPreference') ?? 'ressenti';
    String prompt = iaPreference == 'ressenti'
        ? 'Analyse ce texte et donne une note sur 100 basée sur le ressenti. Réponds uniquement avec un nombre entier suivi de "/100". Texte : $currentText'
        : 'Analyse ce texte et donne une note sur 100 basée sur la qualité de la journée. Réponds uniquement avec un nombre entier suivi de "/100". Texte : $currentText';

    const url = 'https://api.deepinfra.com/v1/openai/chat/completions';
    try {
      final response = await http.post(Uri.parse(url),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $DEEPSEEK_API_KEY'},
          body: jsonEncode({
            'model': await resolveAiModel(),
            'messages': [{'role': 'user', 'content': prompt}],
            'max_tokens': 50
          }));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final noteText = data['choices'][0]['message']['content']?.toString() ?? '';
        final standardMatch = RegExp(r'(\d+)/100').firstMatch(noteText);

        int? parsedNote = standardMatch != null
            ? int.tryParse(standardMatch.group(1)!)
            : int.tryParse(RegExp(r'(\d+)').firstMatch(noteText)?.group(1) ?? '');

        if (parsedNote != null) {
          setState(() {
            _note = parsedNote.clamp(0, 100);
            _manualNoteSelected = false;
            _isEditingManualNote = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Note IA obtenue : $_note/100'), backgroundColor: Colors.green));
          return true;
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
      return false;
    }
  }

  Future<String?> _getUsernameById(String userId) async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (userDoc.exists) {
        return (userDoc.data() as Map<String, dynamic>)['username'];
      }
      return null;
    } catch (e) {
      print("Erreur de récupération de l'username : $e");
      return null;
    }
  }
}