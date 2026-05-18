// souvenir_page.dart

import 'dart:io';
import 'dart:typed_data'; // Pour les images web
import 'package:flutter/foundation.dart' show kIsWeb; // Pour les images web
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fbAuth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'souvenir_model.dart';
import 'package:http/http.dart' as http; // AJOUTÉ : Importation nécessaire pour les appels API
import 'dart:convert'; // AJOUTÉ : Importation nécessaire pour encoder/décoder le JSON
import 'home_page.dart' show getUserSubscriptionData, showVipPromotionPopup;
import 'ai_model_selector.dart';
import 'theme_manager.dart';

// Importez votre HomeBarrePage si vous y naviguez après la sauvegarde
import 'main.dart'; // Assurez-vous que cette importation est correcte

// AJOUTÉ : Clé API nécessaire pour l'analyse des éléments intéressants.
// (À NE PAS LAISSER EN DUR EN PRODUCTION !)
const String DEEPSEEK_API_KEY = 'HA2RvSG1u7aE7u78yXd1UqnBuMY6VV70';


class SouvenirPage extends StatefulWidget {
  final SouvenirModel? souvenirToEdit; // Pour l'édition d'un souvenir existant
  final SouvenirModel? souvenirToRepublish; // NOUVEAU: Pour la republication

  const SouvenirPage({super.key, this.souvenirToEdit, this.souvenirToRepublish});

  @override
  _SouvenirPageState createState() => _SouvenirPageState(
    originalSouvenirToRepublish: souvenirToRepublish,
  );
}

class _SouvenirPageState extends State<SouvenirPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _souvenirController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isPublic = false;
  SouvenirQualite _selectedQualite = SouvenirQualite.nostalgie;
  double _noteQualite = 50; // Note de 0 à 100, utilisée avec un Slider

  // Pour la sélection d'images
  final ImagePicker _picker = ImagePicker();
  List<dynamic> _displayImages = []; // XFile ou String (URLs)

  // Pour l'état de chargement
  bool _isLoading = false;
  bool _isVip = false;
  bool _hasDailyAnalysisChance = true;
  // NOUVEAU: Pour la republication
  final bool _isRepublishing;
  final SouvenirModel? _originalSouvenirToRepublish;
  String? _selectedCardColor; // Couleur locale de la carte (null = suivre le global)

  // NOUVEAU: Pour la mention d'amis
  List<Map<String, dynamic>> _allFriends = [];
  List<Map<String, dynamic>> _filteredFriends = [];
  OverlayEntry? _overlayEntry;
  String _currentMentionQuery = '';


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
  _SouvenirPageState({SouvenirModel? originalSouvenirToRepublish})
      : _isRepublishing = originalSouvenirToRepublish != null,
        _originalSouvenirToRepublish = originalSouvenirToRepublish;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _souvenirController.addListener(_onSouvenirTextChange);
    _checkVipAndAnalysisStatus(); // NOUVEAU: Vérifier le statut au démarrage

    if (widget.souvenirToEdit != null) {
      _loadSouvenirForEditing();
    } else if (_isRepublishing) {
      _loadSouvenirForRepublishing();
    } else {
      // On charge l'état par défaut ici
      _loadDefaultPublicState();
    }
  }

  // --- NOUVELLES METHODES DE SAUVEGARDE ---
  Future<void> _loadDefaultPublicState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isPublic = prefs.getBool('defaultVisibilityPublic') ?? false;
      });
    }
  }

  void _togglePublicState(bool value) async {
    setState(() {
      _isPublic = value;
    });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('defaultVisibilityPublic', value);
  }

  Future<void> _checkVipAndAnalysisStatus() async {
    final vipData = await getUserSubscriptionData();
    if (!mounted) return;

    bool hasChance = true;
    if (!vipData['isVip']) {
      final prefs = await SharedPreferences.getInstance();
      final lastAnalysisDateStr = prefs.getString('lastSouvenirAnalysisDate');
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      hasChance = lastAnalysisDateStr != todayStr;
    }

    setState(() {
      _isVip = vipData['isVip'];
      _hasDailyAnalysisChance = hasChance;
    });
  }

// NOUVEAU: Widget pour l'alerte VIP
  Widget _buildVipAlert(bool isDarkMode) {
    // Ne s'affiche que si l'utilisateur n'est pas VIP et a épuisé sa chance
    if (_isVip || _hasDailyAnalysisChance) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 20.0),
      color: isDarkMode ? Colors.yellow.shade900.withOpacity(0.5) : Colors.yellow.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade700, width: 1),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Text(
                  "Limite quotidienne atteinte",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "L'analyse de ce souvenir pour votre autobiographie ne sera pas prise en compte.",
              style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _showAnalysisInfoDialog(isDarkMode),
                  child: Text("En savoir plus", style: TextStyle(color: Colors.amber.shade900)),
                ),
                ElevatedButton(
                  onPressed: () {
                    showVipPromotionPopup(context, "Analyse illimitée");
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text("Devenir VIP"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

// NOUVEAU: Popup d'information
  void _showAnalysisInfoDialog(bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Analyse des souvenirs"),
        content: const Text(
            "Chaque jour, votre premier souvenir est analysé par notre IA pour enrichir automatiquement votre autobiographie et affiner votre niveau de vie.\n\n"
                "Les membres VIP bénéficient de l'analyse de TOUS leurs souvenirs, sans limite quotidienne."
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Compris"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _souvenirController.dispose();
    _removeOverlay(); // Supprime l'overlay si visible
    super.dispose();
  }

  void _loadSouvenirForEditing() {
    final souvenir = widget.souvenirToEdit!;
    _souvenirController.text = souvenir.texte;
    setState(() {
      _selectedDate = souvenir.date;
      _isPublic = souvenir.estPublic;
      _selectedQualite = souvenir.qualite;
      _noteQualite = souvenir.noteQualite.toDouble();
      _displayImages.addAll(souvenir.photoUrls);
      _selectedCardColor = souvenir.cardColor;
    });
  }

  void _loadSouvenirForRepublishing() {
    final originalSouvenir = _originalSouvenirToRepublish!;
    _souvenirController.text = 'Republié de ${originalSouvenir.repostedFromUserName ?? 'un ami'} :\n${originalSouvenir.texte}';
    setState(() {
      _selectedDate = DateTime.now();
      _isPublic = originalSouvenir.estPublic;
      _selectedQualite = originalSouvenir.qualite;
      _noteQualite = originalSouvenir.noteQualite.toDouble();
      _displayImages.addAll(originalSouvenir.photoUrls);
      _selectedCardColor = originalSouvenir.cardColor;
    });
  }

  Future<void> _loadFriends() async {
    List<Map<String, dynamic>> friends = await _getFriendsList();
    if (mounted) {
      setState(() {
        _allFriends = friends;
      });
    }
  }

  // Logique de détection des mentions pour TextFormField
  void _onSouvenirTextChange() {
    final text = _souvenirController.text;
    final int cursorPosition = _souvenirController.selection.baseOffset;
    if (cursorPosition < 0) return; // Sécurité

    final textBeforeCursor = text.substring(0, cursorPosition);
    final lastAtIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtIndex != -1) {
      final query = textBeforeCursor.substring(lastAtIndex + 1);
      if (!query.contains(' ')) { // Ne montre les suggestions que s'il n'y a pas d'espace
        _currentMentionQuery = query;
        setState(() {
          _filteredFriends = _allFriends
              .where((friend) =>
          (friend['username']?.toLowerCase() ?? '')
              .contains(query.toLowerCase()) ||
              (friend['name']?.toLowerCase() ?? '')
                  .contains(query.toLowerCase()))
              .toList();
        });
        _showOverlay();
      } else {
        _removeOverlay();
      }
    } else {
      _removeOverlay();
    }
  }

  // THEME: L'overlay doit maintenant s'adapter au thème
  void _showOverlay() {
    if (_overlayEntry != null) {
      _removeOverlay();
    }
    if (_filteredFriends.isEmpty) return;


    OverlayState? overlayState = Overlay.of(context);
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final double fieldWidth = renderBox.size.width;
    final double fieldHeight = renderBox.size.height;

    _overlayEntry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<Brightness>(
        valueListenable: appBrightnessNotifier,
        builder: (context, brightness, child) {
          final isDarkMode = brightness == Brightness.dark;
          return Positioned(
            top: offset.dy + fieldHeight + 50, // Ajusté pour être sous le champ
            left: offset.dx,
            width: fieldWidth,
            child: Material(
              elevation: 4.0,
              color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _filteredFriends.length,
                  itemBuilder: (context, index) {
                    final friend = _filteredFriends[index];
                    return ListTile(
                      title: Text(
                        friend['username'] ?? friend['name'] ?? 'Inconnu',
                        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                      ),
                      onTap: () {
                        _insertMention(friend['username'] ?? friend['name'] ?? 'Inconnu');
                        _removeOverlay();
                      },
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

  void _insertMention(String friendName) {
    final text = _souvenirController.text;
    final int cursorPosition = _souvenirController.selection.baseOffset;
    if (cursorPosition < 0) return;

    final textBeforeCursor = text.substring(0, cursorPosition);
    final lastAtIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtIndex != -1) {
      final String beforeAt = text.substring(0, lastAtIndex);
      final String afterMention = text.substring(cursorPosition);
      final String newText = '$beforeAt@$friendName $afterMention'; // Ajouter un espace après le nom

      _souvenirController.text = newText;
      _souvenirController.selection = TextSelection.fromPosition(
        TextPosition(offset: beforeAt.length + friendName.length + 2), // +2 pour '@' et l'espace
      );
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(imageQuality: 85);
      if (pickedFiles.isNotEmpty) {
        setState(() => _displayImages.addAll(pickedFiles)); // Add XFile objects
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur lors de la sélection d'images: $e")));
    }
  }

  void _removeImage(int index) {
    setState(() => _displayImages.removeAt(index));
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _saveSouvenir() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    fbAuth.User? currentUser = fbAuth.FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vous n'êtes pas connecté.")),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      List<String> uploadedImageUrls = [];
      final userId = currentUser.uid;

      for (final item in _displayImages) {
        if (item is XFile) {
          final fileExt = p.extension(item.name);
          final fileName = '$userId/souvenirs/${DateTime.now().millisecondsSinceEpoch}_${p.basename(item.name)}';
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
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>? ?? {};
      int qualiteDeVieActuelle = userData['qualiteDeVieActuelle'] ?? 50;
      int nouvelleQualiteDeVie = ((qualiteDeVieActuelle + _noteQualite.toInt()) / 2).round();

      Map<String, dynamic> souvenirData = {
        'userId': currentUser.uid,
        'texte': _souvenirController.text,
        'date': Timestamp.fromDate(_selectedDate),
        'estPublic': _isPublic,
        'qualite': _selectedQualite.name,
        'noteQualite': _noteQualite.toInt(),
        'cardColor': _selectedCardColor,
        'qualiteDeVieActuelle': nouvelleQualiteDeVie,
        'photoUrls': uploadedImageUrls,
        'isRepost': _isRepublishing,
        'repostedFromUserId': _isRepublishing ? _originalSouvenirToRepublish!.userId : null,
        'repostedFromUserName': _isRepublishing ? await _getUsernameById(_originalSouvenirToRepublish!.userId!) : null,
      };

      String souvenirId;
      if (widget.souvenirToEdit != null) {
        souvenirId = widget.souvenirToEdit!.id!;
        await FirebaseFirestore.instance.collection('souvenirs').doc(souvenirId).update(souvenirData);
      } else {
        final docRef = await FirebaseFirestore.instance.collection('souvenirs').add(souvenirData);
        souvenirId = docRef.id;
      }

      // --- VIP --- : L'analyse des éléments intéressants est maintenant conditionnelle
      final vipData = await getUserSubscriptionData();
      if (vipData['isVip']) {
        // Les VIP peuvent extraire les éléments sans limite
        await _enregistrerElementsInteressants(_souvenirController.text);
      } else {
        // Pour les non-VIP, on vérifie la date du dernier appel
        final prefs = await SharedPreferences.getInstance();
        final lastAnalysisDateStr = prefs.getString('lastSouvenirAnalysisDate');
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

        if (lastAnalysisDateStr != todayStr) {
          // Si ce n'est pas aujourd'hui, on autorise l'appel et on sauvegarde la date
          await _enregistrerElementsInteressants(_souvenirController.text);
          await prefs.setString('lastSouvenirAnalysisDate', todayStr);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Éléments intéressants extraits pour aujourd\'hui !')),
            );
          }
        } else {
          // Si l'appel a déjà été fait aujourd'hui, on informe l'utilisateur
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Limite quotidienne atteinte pour l\'extraction d\'éléments. Devenez VIP pour un accès illimité !'),
                action: SnackBarAction(
                  label: 'Devenir VIP',
                  onPressed: () => showVipPromotionPopup(context, "Extraction d'éléments"),
                ),
              ),
            );
          }
        }
      }

      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({'qualiteDeVieActuelle': nouvelleQualiteDeVie});

      // Classify excerpts into biographical themes (fire-and-forget)
      if (_souvenirController.text.isNotEmpty) {
        _classifierExtraitsParThemes(_souvenirController.text, souvenirId, _selectedDate);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Souvenir sauvegardé !'), backgroundColor: Colors.green));
        // MODIFIÉ : On renvoie 'true' pour indiquer que la sauvegarde a réussi.
        // On suppose que la page souvenir a été ouverte avec push(), donc on utilise pop().
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        } else {
          // Fallback si la page ne peut pas être "popped" (ex: page racine)
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeBarrePage()), (route) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sauvegarde : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // AJOUTÉ : Copie de la logique d'extraction des éléments intéressants
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
    fbAuth.User? currentUser = fbAuth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;


    print('Début de l\'analyse du souvenir pour catégorisation...');

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
        final data = jsonDecode(response.body);
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
            print("Aucun élément intéressant identifié par l'IA dans le souvenir.");
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

            // Pour un souvenir, la date de l'élément est la date du souvenir lui-même
            await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .collection('categories_elements')
                .doc(categorieId)
                .collection('elements')
                .add({
              'texte': texteElement,
              'explication': element['explication'] ?? '',
              'date': Timestamp.fromDate(_selectedDate), // Date du souvenir
              'isRepost': _isRepublishing, // Si le souvenir est une republication
              'repostedFromUserId': _isRepublishing ? _originalSouvenirToRepublish!.userId : null,
              'repostedFromUserName': _isRepublishing ? await _getUsernameById(_originalSouvenirToRepublish!.userId!) : null,
            });
            elementsTraites++;
          }
          print('$elementsTraites éléments intéressants du souvenir ont été enregistrés.');
        }
      } else {
        print('Erreur API lors de l\'extraction des éléments : ${response.body}');
      }
    } catch (e) {
      print('Erreur globale lors de l\'enregistrement des éléments intéressants : $e');
    }
  }

  /// Classifie des extraits du souvenir dans des thèmes/sous-thèmes biographiques sur Firebase.
  Future<void> _classifierExtraitsParThemes(String texte, String souvenirId, DateTime dateEvent) async {
    fbAuth.User? currentUser = fbAuth.FirebaseAuth.instance.currentUser;
    if (currentUser == null || texte.isEmpty) return;
    debugPrint('[THEME_CLASSIFY] ── Début classification souvenir $souvenirId (${texte.length} chars) ──');
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
              'content': '''Analyse ce texte de journal intime et extrait des passages spécifiques et significatifs. Pour chaque passage, attribue :
- un thème principal en UN mot (ex: famille, travail, amour, santé, amis, loisirs, voyage, école, argent, spiritualité)
- un sous-thème très précis et descriptif en 2-5 mots (ex: "relation difficile avec la mère", "nouveau travail et bonheur", "dispute amicale douloureuse", "malheur maternel", "réussite scolaire"). N\'hésite pas à créer de nombreux sous-thèmes différents et précis.

Réponds STRICTEMENT au format JSON suivant, sans aucun texte supplémentaire :
{
  "extraits": [
    {
      "theme": "famille",
      "sous_theme": "relation difficile avec la mère",
      "extrait": "passage exact tiré du texte"
    }
  ]
}

Texte à analyser : $texte'''
            }
          ],
          'max_tokens': 1200,
        }),
      );
      debugPrint('[THEME_CLASSIFY] Réponse API: status=${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('[THEME_CLASSIFY] ERREUR API souvenir: ${response.body}');
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
             'souvenirId': souvenirId,
             'sourceType': 'journee_et_souvenir', // Indique fusion
          });
        } else {
          await sousThemeRef.collection('extraits').add({
            'texte': texteExtrait,
            'souvenirId': souvenirId,
            'sourceType': 'souvenir',
            'date': Timestamp.fromDate(dateEvent),
          });
        }
        saved++;
      }
      debugPrint('[THEME_CLASSIFY] ✓ $saved extraits enregistrés dans themes_biographiques (souvenir)');
    } catch (e) {
      debugPrint('[THEME_CLASSIFY] EXCEPTION souvenir: $e');
    }
  }

  String _getQualiteLabel(SouvenirQualite qualite) {
    switch (qualite) {
      case SouvenirQualite.nostalgie: return "Nostalgie";
      case SouvenirQualite.jamaisOublie: return "Jamais Oublié";
      case SouvenirQualite.bonheur: return "Bonheur";
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

  Future<List<Map<String, dynamic>>> _getFriendsList() async {
    fbAuth.User? currentUser = fbAuth.FirebaseAuth.instance.currentUser;
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Brightness>(
      valueListenable: appBrightnessNotifier,
      builder: (context, brightness, child) {
        final isDarkMode = brightness == Brightness.dark;
        final theme = Theme.of(context);

        return Theme(
          data: isDarkMode ? ThemeData.dark() : ThemeData.light(),
          child: Scaffold(
            backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.grey.shade50,
            appBar: AppBar(
              title: Text(
                _isRepublishing
                    ? 'Republier un Souvenir'
                    : (widget.souvenirToEdit == null ? 'Écrire un Souvenir' : 'Modifier le Souvenir'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              elevation: 1,
              backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              foregroundColor: isDarkMode ? Colors.white : Colors.black,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildVipAlert(isDarkMode),
                    Card(
                      elevation: 2,
                      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextFormField(
                          controller: _souvenirController,
                          decoration: InputDecoration(
                            labelText: "Que s'est-il passé ?",
                            labelStyle: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey.shade600),
                            hintText: "Décrivez ce moment précieux (tapez @ pour mentionner)...",
                            hintStyle: TextStyle(color: isDarkMode ? Colors.white38 : Colors.grey.shade400),
                            border: InputBorder.none,
                            icon: Icon(Icons.edit_note, color: isDarkMode ? Colors.white70 : Colors.grey.shade700),
                          ),
                          maxLines: 6,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Veuillez décrire votre souvenir.';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16.0), // Réduit l'espacement

                    // ---> AJOUT DE LA BARRE D'OUTILS ICI <---
                    _buildActionToolbar(isDarkMode),
                    const SizedBox(height: 16.0),

                    _buildPhotoSection(isDarkMode),
                    const SizedBox(height: 24.0),

                    Card(
                      elevation: 2,
                      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Column(
                          children: [
                            // Date row
                            InkWell(
                              onTap: () => _selectDate(context),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 18, color: isDarkMode ? Colors.white70 : Colors.grey.shade700),
                                  const SizedBox(width: 10),
                                  const Text('Date', style: TextStyle(fontSize: 13)),
                                  const Spacer(),
                                  Text(
                                    DateFormat('dd MMM yyyy', 'fr_FR').format(_selectedDate),
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.primary),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.edit, size: 14, color: theme.colorScheme.primary),
                                ],
                              ),
                            ),
                            const Divider(height: 14),
                            // Quality + intensity row
                            Row(
                              children: [
                                Icon(Icons.star, size: 18, color: isDarkMode ? Colors.white70 : Colors.grey.shade700),
                                const SizedBox(width: 10),
                                const Text('Qualité', style: TextStyle(fontSize: 13)),
                                const Spacer(),
                                DropdownButton<SouvenirQualite>(
                                  value: _selectedQualite,
                                  underline: const SizedBox(),
                                  isDense: true,
                                  style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white : Colors.black87),
                                  dropdownColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                                  onChanged: (SouvenirQualite? newValue) {
                                    if (newValue != null) setState(() => _selectedQualite = newValue);
                                  },
                                  items: SouvenirQualite.values.map((qualite) {
                                    return DropdownMenuItem<SouvenirQualite>(
                                      value: qualite,
                                      child: Text(_getQualiteLabel(qualite)),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                            const Divider(height: 14),
                            // Intensity slider row
                            Row(
                              children: [
                                Icon(Icons.tune, size: 18, color: isDarkMode ? Colors.white70 : Colors.grey.shade700),
                                const SizedBox(width: 6),
                                const Text('Intensité', style: TextStyle(fontSize: 13)),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                      trackHeight: 3,
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                    ),
                                    child: Slider(
                                      value: _noteQualite,
                                      min: 0,
                                      max: 100,
                                      divisions: 100,
                                      onChanged: (double value) => setState(() => _noteQualite = value),
                                    ),
                                  ),
                                ),
                                Text(
                                  '${_noteQualite.toInt()}',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.primary),
                                ),
                              ],
                            ),

                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32.0),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveSouvenir,
                        icon: _isLoading
                            ? Container(
                          width: 24,
                          height: 24,
                          padding: const EdgeInsets.all(2.0),
                          child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                        )
                            : const Icon(Icons.save),
                        label: Text(_isLoading ? 'Sauvegarde...' : 'Sauvegarder le Souvenir'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
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
              onPressed: _isRepublishing ? null : _showColorPickerDialog,
              icon: const Icon(Icons.palette_outlined),
              color: _selectedCardColor != null 
                  ? Colors.blue
                  : (isDarkMode ? Colors.white70 : Colors.grey.shade700),
              tooltip: 'Couleur de la publication',
            ),
            const Spacer(),
            Text(
              _isPublic ? 'Public' : 'Privé',
              style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
            ),
            Switch(
              value: _isPublic,
              onChanged: _togglePublicState, // <-- NOUVELLE FONCTION ICI
              activeColor: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection(bool isDarkMode) {
    return Card(
      elevation: 2,
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Photos du souvenir",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_displayImages.isEmpty)
              Center(
                child: Text(
                  "Aucune photo ajoutée.",
                  style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey.shade600),
                ),
              )
            else
              SizedBox(
                height: 100,
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
                              return Image.memory(snapshot.data!, width: 100, height: 100, fit: BoxFit.cover);
                            }
                            return const SizedBox(width: 100, height: 100, child: Center(child: CircularProgressIndicator()));
                          },
                        );
                      } else {
                        imageWidget = Image.file(File(item.path), width: 100, height: 100, fit: BoxFit.cover);
                      }
                    } else if (item is String) {
                      imageWidget = Image.network(
                        item,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      );
                    } else {
                      imageWidget = const SizedBox.shrink();
                    }

                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: imageWidget,
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removeImage(index),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.add_a_photo),
                label: const Text("Ajouter des photos"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDarkMode ? Colors.white70 : Colors.black87,
                  side: BorderSide(color: isDarkMode ? Colors.white54 : Colors.grey.shade400),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}