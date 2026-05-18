import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:ui'; // Requis pour ImageFilter.blur
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'home_page.dart';
import 'memories_page.dart';
import 'inscription_page.dart';
import 'main.dart';
import 'journee_model.dart';
import 'souvenir_model.dart';
import 'onboarding_tutorial_page.dart';

// NOTE: Pense à importer tes pages d'édition si tu veux que les boutons "Modifier" marchent
// import 'journee_page.dart';
// import 'souvenir_page.dart';

// Structures de données pour les options (utilisées dans la personnalisation)
class _ColorOption {
  final String value;
  final Color color;
  final String label;
  final bool isVip;

  _ColorOption(this.value, this.color, this.label, {this.isVip = false});
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  late User _currentUser;
  late Future<void> _loadDataFuture;

  // Données du profil utilisateur
  String _name = '';
  String _username = '';
  String _bio = '';
  String _profileImageUrl = '';
  bool _isVip = false;
  int _likeCount = 0;
  // Variables pour les amis
  int _friendCount = 0;
  List<String> _myFriends = [];

  // Définition du nombre d'emplacements d'épingles
  final int _totalPinSlots = 7;
  final int _nonVipPinSlots = 3;

  // Contrôleurs & Pickers
  final TextEditingController _bioController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;

  // Préférences
  Brightness _appBrightness = Brightness.light;
  String _iaPreference = 'ressenti';
  String _selectedLanguage = 'Français';
  bool _profileCardBlurEnabled = false;

  // État
  bool _isEditingBio = false;
  List<Map<String, dynamic>?> _pinnedSouvenirs = List.filled(7, null);
  List<Map<String, dynamic>?> _pinnedJournees = List.filled(7, null);

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser!;
    _loadDataFuture = _loadAllInitialData();
  }

  Future<void> _loadAllInitialData() async {
    await Future.wait([
      _loadUserProfile(),
      _loadPinnedItems(),
      _loadAllPreferences(),
    ]);
  }

  Future<void> _loadAllPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _iaPreference = prefs.getString('iaPreference') ?? 'ressenti';
      String? themeMode = prefs.getString('themeMode');
      if (themeMode == 'dark') {
        _appBrightness = Brightness.dark;
      } else if (themeMode == 'light') {
        _appBrightness = Brightness.light;
      } else {
        _appBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
      }
      _selectedLanguage = prefs.getString('selectedLanguage') ?? 'Français';
      _profileCardBlurEnabled =
          prefs.getBool('profileCardBlurEnabled') ?? false;
    });
  }

  Future<void> _loadUserProfile() async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(_currentUser.uid).get();
      if (!mounted) return;

      final data = userDoc.data() as Map<String, dynamic>? ?? {};
      final friendsList = List<String>.from(data['friends'] ?? []);

      final String fullName = data['name'] ?? '';
      final String firstName =
          fullName.isNotEmpty ? fullName.split(' ').first : '';

      setState(() {
        _name = firstName;
        _username = data['username'] ?? '';
        _bio = data['bio'] ?? '';
        _profileImageUrl = data['profileImageUrl'] ?? '';
        _isVip = data['isVip'] ?? false;
        _profileCardBlurEnabled = data['profileCardBlurEnabled'] ?? false;
        _likeCount = data['likeCount'] ?? 0;
        _bioController.text = _bio;
        _myFriends = friendsList;
        _friendCount = friendsList.length;
      });
    } catch (e) {
      print('Erreur de chargement du profil : $e');
    }
  }

  Future<void> _loadPinnedItems() async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(_currentUser.uid).get();
      if (!mounted) return;

      final data = userDoc.data() as Map<String, dynamic>? ?? {};

      List<dynamic> pinnedSouvenirData = data['pinnedSouvenirs'] ?? [];
      _pinnedSouvenirs = List.generate(_totalPinSlots, (i) {
        return i < pinnedSouvenirData.length && pinnedSouvenirData[i] != null
            ? Map<String, dynamic>.from(pinnedSouvenirData[i])
            : null;
      });

      List<dynamic> pinnedJourneeData = data['pinnedJournees'] ?? [];
      _pinnedJournees = List.generate(_totalPinSlots, (i) {
        return i < pinnedJourneeData.length && pinnedJourneeData[i] != null
            ? Map<String, dynamic>.from(pinnedJourneeData[i])
            : null;
      });

      setState(() {});
    } catch (e) {
      print('Erreur de chargement des éléments épinglés : $e');
    }
  }

  Future<void> _pickAndUploadProfileImage() async {
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() => _imageFile = File(pickedFile.path));
        await _uploadProfileImage(_imageFile!);
      }
    } catch (e) {
      print('Erreur de sélection ou d\'upload d\'image : $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  Future<void> _uploadProfileImage(File image) async {
    try {
      final String filePath = 'profile_images/${_currentUser.uid}.jpg';
      final Reference ref = _storage.ref().child(filePath);
      final UploadTask uploadTask = ref.putFile(image);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      await _firestore.collection('users').doc(_currentUser.uid).update({
        'profileImageUrl': downloadUrl,
      });
      if (mounted) {
        setState(() {
          _profileImageUrl = downloadUrl;
          _imageFile = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo mise à jour!')));
      }
    } catch (e) {
      print('Erreur d\'upload : $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Échec: $e')));
      }
    }
  }

  Future<void> _updateBio() async {
    try {
      await _firestore.collection('users').doc(_currentUser.uid).update({
        'bio': _bioController.text,
      });
      if (mounted) {
        setState(() {
          _bio = _bioController.text;
          _isEditingBio = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bio mise à jour!')));
      }
    } catch (e) {
      print('Erreur mise à jour bio : $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Échec: $e')));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // GESTION DU CLIC SUR UNE ÉPINGLE
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _handlePinTap(
    Map<String, dynamic> pinnedData,
    String itemType,
  ) async {
    // Affiche un loader pendant la récupération des données complètes
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final docId = pinnedData['id'];

      if (itemType == 'journee') {
        final doc = await _firestore.collection('journees').doc(docId).get();
        Navigator.pop(context); // Ferme le loader

        if (doc.exists) {
          final journee = JourneeModel.fromFirestore(doc);
          _showJourneeDetailDialog(journee);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Journée introuvable (peut-être supprimée).'),
            ),
          );
        }
      } else {
        final doc = await _firestore.collection('souvenirs').doc(docId).get();
        Navigator.pop(context); // Ferme le loader

        if (doc.exists) {
          final souvenir = SouvenirModel.fromFirestore(doc);
          _showSouvenirDetailDialog(souvenir);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Souvenir introuvable (peut-être supprimé).'),
            ),
          );
        }
      }
    } catch (e) {
      Navigator.pop(context); // Ferme le loader en cas d'erreur
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // POPUP JOURNEE (Identique à home_page)
  // ═══════════════════════════════════════════════════════════════════════
  void _showJourneeDetailDialog(JourneeModel journee) {
    final isDark = _appBrightness == Brightness.dark;

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
            color: Colors.black.withValues(alpha: 0.55),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
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
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Header ──
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${journee.date.day.toString().padLeft(2, '0')}/'
                                    '${journee.date.month.toString().padLeft(2, '0')}/'
                                    '${journee.date.year}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          isDark
                                              ? Colors.white
                                              : Colors.black87,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Modifier',
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    color:
                                        isDark
                                            ? Colors.blue.shade300
                                            : Colors.blue,
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _modifierJournee(journee);
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color:
                                        isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                ),
                              ],
                            ),
                          ),
                          // ── Content ──
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                10,
                                20,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (journee.emoji != null) ...[
                                    Text(
                                      journee.emoji!,
                                      style: const TextStyle(fontSize: 36),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Text(
                                    journee.texte1 ?? '',
                                    style: TextStyle(
                                      fontSize: _calculateFontSize(
                                        journee.texte1 ?? '',
                                      ),
                                      height: 1.65,
                                      color:
                                          isDark
                                              ? Colors.grey.shade100
                                              : Colors.black87,
                                    ),
                                  ),
                                  if (journee.note != null) ...[
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          color: Colors.amber,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Note : ${journee.note}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blueGrey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (journee.photoUrls.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      height: 120,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: journee.photoUrls.length,
                                        itemBuilder:
                                            (_, i) => Padding(
                                              padding: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.network(
                                                  journee.photoUrls[i],
                                                  width: 120,
                                                  height: 120,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                      ),
                                    ),
                                  ],
                                  if ((journee.motsCles ?? []).isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children:
                                          (journee.motsCles ?? [])
                                              .map(
                                                (k) => Chip(
                                                  label: Text(
                                                    k,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: EdgeInsets.zero,
                                                ),
                                              )
                                              .toList(),
                                    ),
                                  ],
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

  // ═══════════════════════════════════════════════════════════════════════
  // POPUP SOUVENIR (Identique à home_page)
  // ═══════════════════════════════════════════════════════════════════════
  void _showSouvenirDetailDialog(SouvenirModel souvenir) {
    final isDark = _appBrightness == Brightness.dark;

    final Map<String, Map<String, dynamic>> qualiteInfo = {
      'nostalgie': {
        'label': 'Nostalgie',
        'icon': Icons.history,
        'color': Colors.purple,
      },
      'jamaisOublie': {
        'label': 'Jamais oublié',
        'icon': Icons.favorite,
        'color': Colors.red,
      },
      'bonheur': {
        'label': 'Bonheur',
        'icon': Icons.wb_sunny_rounded,
        'color': Colors.orange,
      },
    };

    String qKey = souvenir.qualite.toString().toLowerCase();
    Map<String, dynamic> qInfo = qualiteInfo['bonheur']!; // Par défaut
    if (qKey.contains('nostalgie')) qInfo = qualiteInfo['nostalgie']!;
    if (qKey.contains('jamais')) qInfo = qualiteInfo['jamaisOublie']!;

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
            color: Colors.black.withValues(alpha: 0.55),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
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
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Header ──
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${souvenir.date.day.toString().padLeft(2, '0')}'
                                    '/${souvenir.date.month.toString().padLeft(2, '0')}'
                                    '/${souvenir.date.year}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          isDark
                                              ? Colors.white
                                              : Colors.black87,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Modifier',
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    color:
                                        isDark
                                            ? Colors.blue.shade300
                                            : Colors.blue,
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _modifierSouvenir(souvenir);
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color:
                                        isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                ),
                              ],
                            ),
                          ),
                          // ── Content ──
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                10,
                                20,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Qualité badge
                                  Row(
                                    children: [
                                      Icon(
                                        qInfo['icon'] as IconData,
                                        color: qInfo['color'] as Color,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        qInfo['label'] as String,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: qInfo['color'] as Color,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    souvenir.texte,
                                    style: TextStyle(
                                      fontSize: _calculateFontSize(
                                        souvenir.texte,
                                      ),
                                      height: 1.65,
                                      color:
                                          isDark
                                              ? Colors.grey.shade100
                                              : Colors.black87,
                                    ),
                                  ),
                                  if (souvenir.photoUrls.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      height: 120,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: souvenir.photoUrls.length,
                                        itemBuilder:
                                            (_, i) => Padding(
                                              padding: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.network(
                                                  souvenir.photoUrls[i],
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

  // ═══════════════════════════════════════════════════════════════════════
  // UTILITAIRES
  // ═══════════════════════════════════════════════════════════════════════
  double _calculateFontSize(String text) {
    if (text.length < 50) return 18.0;
    if (text.length < 100) return 16.0;
    if (text.length < 200) return 15.0;
    return 14.0;
  }

  void _modifierJournee(JourneeModel journee) {
    // Redirection vers la page d'édition.
    // Il faut que la route existe dans ton application.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Naviguez vers la page d\'édition (à connecter avec votre routeur).',
        ),
      ),
    );
    // Exemple d'implémentation :
    // Navigator.push(context, MaterialPageRoute(builder: (_) => JourneePage(journeeToEdit: journee))).then((_) => _loadPinnedItems());
  }

  void _modifierSouvenir(SouvenirModel souvenir) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Naviguez vers la page d\'édition (à connecter avec votre routeur).',
        ),
      ),
    );
    // Exemple d'implémentation :
    // Navigator.push(context, MaterialPageRoute(builder: (_) => SouvenirPage(souvenirToEdit: souvenir))).then((_) => _loadPinnedItems());
  }

  Future<void> _selectItemToPin({
    required int index,
    required String itemType,
  }) async {
    final selectedItem = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                MemoriesPage(isPinningMode: true, pinItemType: itemType),
      ),
    );

    if (selectedItem == null) return;

    final customization = await _showPinCustomizationDialog();
    if (customization == null) return;

    setState(() {
      final newItem = {
        ...selectedItem,
        'pin_shape': customization['shape'],
        'pin_color': customization['color'],
      };

      if (itemType == 'journee') {
        _pinnedJournees[index] = newItem;
        _savePinnedItems('pinnedJournees', _pinnedJournees);
      } else {
        _pinnedSouvenirs[index] = newItem;
        _savePinnedItems('pinnedSouvenirs', _pinnedSouvenirs);
      }
    });
  }

  Future<Map<String, String>?> _showPinCustomizationDialog() async {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (BuildContext context) {
        String selectedShape = 'carrer';
        String selectedColor = 'bleu';

        final shapes = {
          'carrer': 'Carré',
          'rond': 'Rond',
          'rectangle': 'Rectangle',
          'coeur': 'Coeur',
          'etoile': 'Étoile',
        };
        final colors = {
          'bleu': Colors.blue,
          'vert': Colors.green,
          'rouge': Colors.red,
          'jaune': Colors.yellow,
          'violet': Colors.purple,
        };

        return AlertDialog(
          title: const Text('Personnaliser l\'épingle'),
          content: SizedBox(
            width: double.maxFinite,
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setStateDialog) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Quelle forme ?'),
                      DropdownButton<String>(
                        value: selectedShape,
                        onChanged: (String? newValue) {
                          setStateDialog(() => selectedShape = newValue!);
                        },
                        items:
                            shapes.keys.map<DropdownMenuItem<String>>((
                              String value,
                            ) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(shapes[value]!),
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 20),
                      const Text('Quelle couleur ?'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children:
                            colors.keys.map((String key) {
                              return GestureDetector(
                                onTap:
                                    () => setStateDialog(
                                      () => selectedColor = key,
                                    ),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: colors[key],
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          selectedColor == key
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.onSurface
                                              : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Annuler'),
              onPressed: () => Navigator.of(context).pop(null),
            ),
            ElevatedButton(
              child: const Text('Valider'),
              onPressed: () {
                Navigator.of(
                  context,
                ).pop({'shape': selectedShape, 'color': selectedColor});
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _savePinnedItems(
    String fieldName,
    List<Map<String, dynamic>?> items,
  ) async {
    try {
      await _firestore.collection('users').doc(_currentUser.uid).update({
        fieldName:
            items
                .map(
                  (item) =>
                      item != null
                          ? {
                            'id': item['id'],
                            'texte': item['texte1'] ?? item['texte'],
                            'date': item['date'],
                            'pin_shape': item['pin_shape'] ?? 'carrer',
                            'pin_color': item['pin_color'] ?? 'bleu',
                          }
                          : null,
                )
                .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Éléments épinglés mis à jour!')),
        );
      }
    } catch (e) {
      print('Erreur de sauvegarde de $fieldName : $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Échec: $e')));
      }
    }
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return '';

    DateTime date;
    if (dateValue is Timestamp) {
      date = dateValue.toDate();
    } else if (dateValue is DateTime) {
      date = dateValue;
    } else {
      return '';
    }

    return 'Le ${DateFormat('d MMMM yyyy', 'fr').format(date)}';
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
              .doc(_currentUser.uid)
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
          final userData = userDoc.data();
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
            title: const Text('Personnes qui ont aimé votre profil'),
            content: SizedBox(
              width: double.maxFinite,
              child:
                  likers.isEmpty
                      ? const Center(
                        child: Text("Personne n'a encore aimé votre profil."),
                      )
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: likers.length,
                        itemBuilder: (context, index) {
                          final liker = likers[index];
                          final bool isFriend = _myFriends.contains(
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

  void _showVipSubscriptionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: [
              Icon(Icons.star, color: Colors.amber.shade700),
              const SizedBox(width: 10),
              const Text("Devenez VIP !"),
            ],
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text(
                  "Débloquez tout le potentiel de Daytalia avec le statut VIP :",
                ),
                const SizedBox(height: 10),
                _buildVipAdvantage(
                  Icons.auto_awesome,
                  "Analyse IA illimitée de votre niveau de vie.",
                ),
                _buildVipAdvantage(
                  Icons.auto_stories,
                  "Accès à un modèle IA plus intelligent (Gemini 2.5 Flash) pour toutes les fonctionnalités IA, y compris l'autobiographie.",
                ),
                _buildVipAdvantage(
                  Icons.autorenew,
                  "Poster automatiquement les journées en souvenir IA.",
                ),
                _buildVipAdvantage(
                  Icons.psychology,
                  "Conseils de l'IA sur vos journées.",
                ),
                _buildVipAdvantage(
                  Icons.compare_arrows,
                  "Accès à la fonctionnalité 'Journées Similaires'.",
                ),
                _buildVipAdvantage(
                  Icons.text_snippet,
                  "Extraction illimitée des éléments intéressants pour vos souvenirs.",
                ),
                _buildVipAdvantage(
                  Icons.palette,
                  "Options de personnalisation exclusives (couleurs, formes, animations).",
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Plus tard'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
              ),
              child: Text(_isVip ? 'Se désabonner' : 'S\'abonner'),
              onPressed: () async {
                bool newVipStatus = !_isVip;
                await _firestore
                    .collection('users')
                    .doc(_currentUser.uid)
                    .update({'isVip': newVipStatus});
                if (mounted) {
                  setState(() {
                    _isVip = newVipStatus;
                  });
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        newVipStatus
                            ? "Bienvenue chez les VIP !"
                            : "Votre abonnement a été annulé.",
                      ),
                      backgroundColor:
                          newVipStatus ? Colors.green : Colors.orange,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showVipPopup() {
    Navigator.pop(context);
    _showVipSubscriptionDialog();
  }

  void _showVipPopupForCustomization() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: [
              Icon(Icons.star, color: Colors.amber.shade700),
              const SizedBox(width: 10),
              const Text("Option VIP"),
            ],
          ),
          content: const Text(
            "Cette option est réservée aux membres VIP. Appuyez sur 'Devenir VIP' pour en savoir plus.",
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
              ),
              child: const Text('Devenir VIP'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
                _showVipSubscriptionDialog();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildVipAdvantage(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(bool isDarkMode) {
    final textColor = isDarkMode ? Colors.white : Colors.black;
    return Column(
      children: [
        GestureDetector(
          onTap: _pickAndUploadProfileImage,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundImage:
                    _imageFile != null
                        ? FileImage(_imageFile!)
                        : (_profileImageUrl.isNotEmpty
                            ? NetworkImage(_profileImageUrl)
                            : null),
                backgroundColor:
                    isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
                child:
                    (_imageFile == null && _profileImageUrl.isEmpty)
                        ? Icon(
                          Icons.person,
                          size: 60,
                          color:
                              isDarkMode
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                        )
                        : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDarkMode ? Colors.black : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: const Icon(Icons.edit, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _name,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            if (_isVip)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Icon(Icons.star, color: Colors.amber.shade700, size: 24),
              ),
          ],
        ),
        Text('@$_username', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                Text(
                  _friendCount.toString(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                Text(
                  'Amis',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: _showLikesPopup,
              child: Column(
                children: [
                  Text(
                    _likeCount.toString(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite, color: Colors.pink, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'J\'aime',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white70 : Colors.black87,
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
    );
  }

  Widget _buildBioSection(bool isDarkMode) {
    final textColor = isDarkMode ? Colors.white70 : Colors.black87;
    final hintColor = isDarkMode ? Colors.grey.shade600 : Colors.grey;
    final iconColor = isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child:
          _isEditingBio
              ? Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bioController,
                      decoration: InputDecoration(
                        hintText: 'Entrez votre bio',
                        hintStyle: TextStyle(color: hintColor),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: isDarkMode ? Colors.blueGrey : Colors.grey,
                          ),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue.shade700),
                        ),
                      ),
                      maxLength: 150,
                      style: TextStyle(color: textColor),
                      cursorColor: Colors.blue.shade700,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.check, color: Colors.green.shade600),
                    onPressed: _updateBio,
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.red.shade600),
                    onPressed: () {
                      setState(() {
                        _isEditingBio = false;
                        _bioController.text = _bio;
                      });
                    },
                  ),
                ],
              )
              : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _bio.isEmpty ? 'Ajouter une bio' : _bio,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _bio.isEmpty ? hintColor : textColor,
                        fontStyle:
                            _bio.isEmpty ? FontStyle.italic : FontStyle.normal,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 18, color: iconColor),
                    onPressed: () {
                      setState(() {
                        _isEditingBio = true;
                      });
                    },
                  ),
                ],
              ),
    );
  }

  Widget _buildPinnedSection({
    required String title,
    required List<Map<String, dynamic>?> items,
    required String itemType,
    required bool isDarkMode,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 0, 16),
            child: Row(
              children: List.generate(_totalPinSlots, (index) {
                final bool isVipSlot = index >= _nonVipPinSlots;
                final Map<String, dynamic>? maybeData =
                    items.length > index ? items[index] : null;
                return _buildPinnedItemCard(
                  data: maybeData,
                  isDarkMode: isDarkMode,
                  onTap: () {
                    if (isVipSlot && !_isVip) {
                      _showVipPopupForCustomization();
                      return;
                    }
                    if (maybeData == null) {
                      _selectItemToPin(index: index, itemType: itemType);
                    } else {
                      _handlePinTap(
                        maybeData,
                        itemType,
                      ); // APPEL DU NOUVEAU POPUP
                    }
                  },
                  isVipLocked: isVipSlot && !_isVip,
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPinnedItemCard({
    required Map<String, dynamic>? data,
    required bool isDarkMode,
    required VoidCallback onTap,
    bool isVipLocked = false,
  }) {
    if (isVipLocked) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 150,
          height: 160,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color:
                isDarkMode
                    ? Colors.grey.shade800.withOpacity(0.5)
                    : Colors.grey.shade200.withOpacity(0.5),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.amber.shade600, width: 1.5),
          ),
          child: Center(
            child: Icon(Icons.star, color: Colors.amber.shade700, size: 50),
          ),
        ),
      );
    }

    if (data == null) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 150,
          height: 160,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Center(
            child: Icon(
              Icons.add_circle_outline,
              color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade600,
              size: 50,
            ),
          ),
        ),
      );
    }

    final String shape = data['pin_shape'] ?? 'carrer';
    final String color = data['pin_color'] ?? 'bleu';
    final String assetPath = 'assets/${shape}_${color}.png';

    final String contentText =
        data['texte1'] ?? data['texte'] ?? 'Contenu indisponible';
    final String contentDate = _formatDate(data['date']);

    final EdgeInsets contentPadding;
    switch (shape) {
      case 'coeur':
        contentPadding = const EdgeInsets.fromLTRB(24, 48, 24, 14);
        break;
      case 'etoile':
        contentPadding = const EdgeInsets.fromLTRB(28, 40, 28, 16);
        break;
      case 'rond':
        contentPadding = const EdgeInsets.all(22);
        break;
      default:
        contentPadding = const EdgeInsets.fromLTRB(16, 16, 16, 8);
    }

    final Color dateChipColor =
        isDarkMode
            ? Colors.white.withOpacity(0.14)
            : Colors.black.withOpacity(0.42);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        height: 192,
        margin: const EdgeInsets.only(right: 16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              assetPath,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.blue),
                  ),
                );
              },
            ),
            Padding(
              padding: contentPadding.copyWith(
                bottom: contentPadding.bottom + 12,
              ),
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  contentText,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    height: 1.3,
                    shadows: [Shadow(blurRadius: 4.0, color: Colors.black54)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: dateChipColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.18),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    contentDate,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      shadows: [Shadow(blurRadius: 3.0, color: Colors.black87)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showIAPersonalizationDialog() async {
    String? selectedIAPreference = await showDialog<String>(
      context: context,
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final dialogColor =
            isDarkMode ? Colors.blueGrey.shade900 : Colors.white;
        final textColor = isDarkMode ? Colors.white : Colors.black;
        final activeColor = Colors.blue.shade700;

        return AlertDialog(
          backgroundColor: dialogColor,
          title: Text(
            'Personnalisation de l\'IA',
            style: TextStyle(color: textColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: Text(
                  'IA basée sur mon ressenti',
                  style: TextStyle(color: textColor),
                ),
                value: 'ressenti',
                groupValue: _iaPreference,
                onChanged: (value) {
                  Navigator.pop(context, value);
                },
                activeColor: activeColor,
              ),
              RadioListTile<String>(
                title: Text(
                  'IA basée sur ma qualité de journée',
                  style: TextStyle(color: textColor),
                ),
                value: 'qualite_journee',
                groupValue: _iaPreference,
                onChanged: (value) {
                  Navigator.pop(context, value);
                },
                activeColor: activeColor,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Annuler',
                style: TextStyle(
                  color: isDarkMode ? Colors.red.shade300 : Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (selectedIAPreference != null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('iaPreference', selectedIAPreference);
      if (mounted) {
        setState(() {
          _iaPreference = selectedIAPreference;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Préférence IA mise à jour!')),
        );
      }
    }
  }

  Future<void> _launchOnboardingTutorial() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OnboardingTutorialPage()));
  }

  void _showPersonalizationDialog() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool currentProfileCardBlur = _profileCardBlurEnabled;
    final String initialThemeMode = prefs.getString('themeMode') ?? 'system';

    String currentThemeMode = prefs.getString('themeMode') ?? 'system';
    String selectedCardColor = prefs.getString('cardColor') ?? 'bleu';
    String selectedCardAnimation =
        prefs.getString('cardAnimation') ?? 'rebondissant';
    String selectedJourneeCardColor =
        prefs.getString('journeeCardColor') ?? 'bleu';
    String selectedJourneeAnimation =
        prefs.getString('journeeAnimation') ?? 'rebondissant';
    String selectedCardDesign = prefs.getString('cardDesign') ?? 'carrer';
    String selectedJourneeCardDesign =
        prefs.getString('journeeCardDesign') ?? 'carrer';
    String selectedAnimationSpeed =
        prefs.getString('animationSpeed') ?? 'normal';
    String selectedCardSize = prefs.getString('cardSize') ?? 'normal';

    bool forceGlobalJourneeColor =
        prefs.getBool('forceGlobalJourneeColor') ?? false;
    bool forceGlobalSouvenirColor =
        prefs.getBool('forceGlobalSouvenirColor') ?? false;

    final Map<String, String> animationLabels = {
      'rebondissant': 'Rebondissant (Défaut)',
      'rotation': 'Rotation',
      'changer': 'Fondu',
      'flottant': 'Flottant (VIP)',
      'pulsation': 'Pulsation (VIP)',
    };
    final Map<String, String> designLabels = {
      'carrer': 'Carré (Défaut)',
      'rectangle': 'Rectangle',
      'coeur': 'Coeur',
      'etoile': 'Étoile (VIP)',
      'rond': 'Rond',
    };
    final Map<String, String> speedLabels = {
      'lent': 'Lente',
      'normal': 'Normale (Défaut)',
      'rapide': 'Rapide',
    };
    final Map<String, String> sizeLabels = {
      'tres_petit': 'Très Petit (VIP)',
      'petit': 'Petit (VIP)',
      'normal': 'Normal (Défaut)',
      'gros': 'Gros (VIP)',
    };
    final List<_ColorOption> colorOptions = [
      _ColorOption('bleu', Colors.blue.shade300, 'Bleu (Défaut)'),
      _ColorOption('vert', Colors.green.shade300, 'Vert'),
      _ColorOption('rouge', Colors.red.shade300, 'Rouge'),
      _ColorOption(
        'orange',
        Colors.orange.shade300,
        'Orange (VIP)',
        isVip: true,
      ),
      _ColorOption('jaune', Colors.yellow.shade400, 'Jaune (VIP)', isVip: true),
      _ColorOption(
        'violet',
        Colors.purple.shade300,
        'Violet (VIP)',
        isVip: true,
      ),
      _ColorOption('rose', Colors.pink.shade200, 'Rose (VIP)', isVip: true),
      _ColorOption('blanc', Colors.grey.shade200, 'Blanc (VIP)', isVip: true),
    ];

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            final isDialogDarkMode =
                Theme.of(context).brightness == Brightness.dark;
            final textColor = isDialogDarkMode ? Colors.white : Colors.black;
            final dialogBgColor =
                isDialogDarkMode ? Colors.blueGrey.shade900 : Colors.white;

            void updateSelection(String type, dynamic value) {
              setStateInDialog(() {
                switch (type) {
                  case 'themeMode':
                    currentThemeMode = value;
                    break;
                  case 'cardColor':
                    selectedCardColor = value;
                    break;
                  case 'cardAnimation':
                    selectedCardAnimation = value;
                    break;
                  case 'journeeColor':
                    selectedJourneeCardColor = value;
                    break;
                  case 'journeeAnimation':
                    selectedJourneeAnimation = value;
                    break;
                  case 'cardDesign':
                    selectedCardDesign = value;
                    break;
                  case 'journeeDesign':
                    selectedJourneeCardDesign = value;
                    break;
                  case 'speed':
                    selectedAnimationSpeed = value;
                    break;
                  case 'cardSize':
                    selectedCardSize = value;
                    break;
                  case 'profileBlur':
                    currentProfileCardBlur = value;
                    break;
                  case 'forceJournee':
                    forceGlobalJourneeColor = value;
                    break;
                  case 'forceSouvenir':
                    forceGlobalSouvenirColor = value;
                    break;
                }
              });
            }

            return AlertDialog(
              backgroundColor: dialogBgColor,
              title: Text(
                'Personnalisation',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Thème de l\'application', textColor),
                    _buildThemeModeSelection(
                      currentThemeMode,
                      (v) => updateSelection('themeMode', v),
                      isDialogDarkMode,
                    ),
                    const Divider(height: 24),

                    _buildSectionTitle(
                      'Arrière-plan du profil public',
                      textColor,
                    ),
                    SwitchListTile(
                      title: Text(
                        'Activer le flou sur les cartes',
                        style: TextStyle(color: textColor),
                      ),
                      subtitle: Text(
                        'Rend les cartes semi-transparentes et floute le fond.',
                        style: TextStyle(
                          color:
                              isDialogDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      value: currentProfileCardBlur,
                      onChanged: (val) => updateSelection('profileBlur', val),
                      activeColor: Colors.blue.shade700,
                      secondary: Icon(
                        Icons.blur_on,
                        color:
                            isDialogDarkMode ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const Divider(height: 24),

                    _buildSectionTitle('Design des cartes', textColor),
                    _buildDropdown(
                      'Souvenirs',
                      designLabels,
                      selectedCardDesign,
                      (v) => updateSelection('cardDesign', v),
                      isDialogDarkMode,
                      vipOptions: ['etoile'],
                    ),
                    _buildDropdown(
                      'Journées',
                      designLabels,
                      selectedJourneeCardDesign,
                      (v) => updateSelection('journeeDesign', v),
                      isDialogDarkMode,
                      vipOptions: ['etoile'],
                    ),
                    const Divider(height: 24),

                    _buildSectionTitle('Couleur des cartes', textColor),
                    _buildColorGrid(
                      options: colorOptions,
                      selectedValue: selectedCardColor,
                      onChanged: (v) => updateSelection('cardColor', v),
                      isDarkMode: isDialogDarkMode,
                      title: "Souvenirs",
                    ),
                    const SizedBox(height: 16),
                    _buildColorGrid(
                      options: colorOptions,
                      selectedValue: selectedJourneeCardColor,
                      onChanged: (v) => updateSelection('journeeColor', v),
                      isDarkMode: isDialogDarkMode,
                      title: 'Journées',
                    ),
                    const Divider(height: 24),

                    _buildSectionTitle(
                      'Forcer les couleurs globales',
                      textColor,
                    ),
                    SwitchListTile(
                      title: Text(
                        'Pour les Journées',
                        style: TextStyle(color: textColor),
                      ),
                      subtitle: Text(
                        'Ignore les couleurs locales définies dans les journées',
                        style: TextStyle(
                          color:
                              isDialogDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      value: forceGlobalJourneeColor,
                      onChanged: (val) => updateSelection('forceJournee', val),
                      activeColor: Colors.blue.shade700,
                    ),
                    SwitchListTile(
                      title: Text(
                        'Pour les Souvenirs',
                        style: TextStyle(color: textColor),
                      ),
                      subtitle: Text(
                        'Ignore les couleurs locales définies dans les souvenirs',
                        style: TextStyle(
                          color:
                              isDialogDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      value: forceGlobalSouvenirColor,
                      onChanged: (val) => updateSelection('forceSouvenir', val),
                      activeColor: Colors.blue.shade700,
                    ),

                    _buildSectionTitle('Animation des cartes', textColor),
                    _buildDropdown(
                      'Souvenirs',
                      animationLabels,
                      selectedCardAnimation,
                      (v) => updateSelection('cardAnimation', v),
                      isDialogDarkMode,
                      vipOptions: ['flottant', 'pulsation'],
                    ),
                    _buildDropdown(
                      'Journées',
                      animationLabels,
                      selectedJourneeAnimation,
                      (v) => updateSelection('journeeAnimation', v),
                      isDialogDarkMode,
                      vipOptions: ['flottant', 'pulsation'],
                    ),
                    const Divider(height: 24),

                    _buildSectionTitle('Vitesse d\'animation', textColor),
                    _buildSelectionOptions(
                      options: speedLabels.keys.toList(),
                      labels: speedLabels,
                      selectedValue: selectedAnimationSpeed,
                      onChanged: (v) => updateSelection('speed', v),
                      isDarkMode: isDialogDarkMode,
                    ),
                    const Divider(height: 24),

                    _buildSectionTitle('Taille des cartes', textColor),
                    _buildSelectionOptions(
                      options: sizeLabels.keys.toList(),
                      labels: sizeLabels,
                      selectedValue: selectedCardSize,
                      onChanged: (v) => updateSelection('cardSize', v),
                      isDarkMode: isDialogDarkMode,
                      vipOptions: ['tres_petit', 'petit', 'gros'],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Annuler',
                    style: TextStyle(
                      color:
                          isDialogDarkMode ? Colors.red.shade300 : Colors.red,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final bool shouldPromptRestart =
                        await _savePersonalizationPreferences(
                          themeMode: currentThemeMode,
                          cardColor: selectedCardColor,
                          cardAnimation: selectedCardAnimation,
                          journeeCardColor: selectedJourneeCardColor,
                          journeeAnimation: selectedJourneeAnimation,
                          cardDesign: selectedCardDesign,
                          journeeCardDesign: selectedJourneeCardDesign,
                          animationSpeed: selectedAnimationSpeed,
                          cardSize: selectedCardSize,
                          profileCardBlurEnabled: currentProfileCardBlur,
                          forceGlobalJourneeColor: forceGlobalJourneeColor,
                          forceGlobalSouvenirColor: forceGlobalSouvenirColor,
                        );
                    if (mounted) Navigator.pop(dialogContext);
                    if (mounted &&
                        shouldPromptRestart &&
                        currentThemeMode != initialThemeMode) {
                      await _showRestartRequiredDialog();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showNotificationSettingsDialog() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          _appBrightness == Brightness.dark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FutureBuilder<DocumentSnapshot>(
          future: _firestore.collection('users').doc(currentUser.uid).get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final data = snapshot.data?.data() as Map<String, dynamic>?;
            final Map<String, dynamic> prefs =
                data?['notificationPrefs'] as Map<String, dynamic>? ?? {};

            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                final isDark = _appBrightness == Brightness.dark;
                final textColor = isDark ? Colors.white : Colors.black;

                Widget buildToggle(String key, String label, IconData icon) {
                  return SwitchListTile(
                    title: Text(label, style: TextStyle(color: textColor)),
                    secondary: Icon(icon, color: Colors.blue),
                    activeColor: Colors.blue,
                    value: prefs[key] ?? true,
                    onChanged: (val) async {
                      setModalState(() => prefs[key] = val);
                      await _firestore
                          .collection('users')
                          .doc(currentUser.uid)
                          .update({'notificationPrefs.$key': val});
                    },
                  );
                }

                return DraggableScrollableSheet(
                  initialChildSize: 0.7,
                  maxChildSize: 0.9,
                  minChildSize: 0.4,
                  expand: false,
                  builder:
                      (_, controller) => ListView(
                        controller: controller,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'Notifications',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          buildToggle(
                            'post_amis',
                            'Nouveaux posts de mes amis',
                            Icons.auto_stories,
                          ),
                          buildToggle(
                            'demande_amis',
                            "Demandes d'amis",
                            Icons.person_add,
                          ),
                          buildToggle(
                            'amis_retour',
                            'Amis qui m\'ont accepté',
                            Icons.how_to_reg,
                          ),
                          buildToggle(
                            'mentions_tags',
                            'Mentions',
                            Icons.alternate_email,
                          ),
                          buildToggle(
                            'commentaires',
                            'Commentaires sur mes posts',
                            Icons.chat_bubble_outline,
                          ),
                          buildToggle(
                            'reactions',
                            'Réactions sur mes posts',
                            Icons.favorite_border,
                          ),
                          const Divider(),
                          buildToggle(
                            'memories',
                            'Memories (Ce jour-là)',
                            Icons.history,
                          ),
                          buildToggle(
                            'post_populaire',
                            'Posts populaires de mes amis',
                            Icons.trending_up,
                          ),
                          buildToggle(
                            'recommandations',
                            "Recommandations d'amis",
                            Icons.people_alt,
                          ),
                        ],
                      ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildThemeModeSelection(
    String currentThemeMode,
    ValueChanged<String> onChanged,
    bool isDarkMode,
  ) {
    return Column(
      children: [
        RadioListTile<String>(
          title: Text(
            'Clair',
            style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
          ),
          value: 'light',
          groupValue: currentThemeMode,
          onChanged: (val) => onChanged(val!),
          activeColor: Colors.blue,
        ),
        RadioListTile<String>(
          title: Text(
            'Sombre',
            style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
          ),
          value: 'dark',
          groupValue: currentThemeMode,
          onChanged: (val) => onChanged(val!),
          activeColor: Colors.blue,
        ),
        RadioListTile<String>(
          title: Text(
            'Système',
            style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
          ),
          value: 'system',
          groupValue: currentThemeMode,
          onChanged: (val) => onChanged(val!),
          activeColor: Colors.blue,
        ),
      ],
    );
  }

  Widget _buildColorGrid({
    required List<_ColorOption> options,
    required String selectedValue,
    required ValueChanged<String> onChanged,
    required bool isDarkMode,
    String? title,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Text(
            title,
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              options.map((option) {
                final isDisabled = option.isVip && !_isVip;
                return GestureDetector(
                  onTap:
                      () =>
                          isDisabled
                              ? _showVipPopupForCustomization()
                              : onChanged(option.value),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: option.color,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              selectedValue == option.value
                                  ? Border.all(
                                    color: Colors.blue.shade700,
                                    width: 3,
                                  )
                                  : null,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  isDarkMode
                                      ? Colors.black.withOpacity(0.3)
                                      : Colors.grey.withOpacity(0.2),
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            option.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color:
                                  option.color.computeLuminance() > 0.5
                                      ? Colors.black
                                      : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                      if (isDisabled)
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.star,
                            color: Colors.amber.shade700,
                            size: 30,
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    String title,
    Map<String, String> items,
    String selectedValue,
    ValueChanged<String> onChanged,
    bool isDarkMode, {
    List<String> vipOptions = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
          DropdownButton<String>(
            value: selectedValue,
            dropdownColor: isDarkMode ? Colors.blueGrey.shade800 : Colors.white,
            onChanged: (String? newValue) {
              if (newValue != null) {
                if (vipOptions.contains(newValue) && !_isVip) {
                  _showVipPopupForCustomization();
                } else {
                  onChanged(newValue);
                }
              }
            },
            items:
                items.entries.map<DropdownMenuItem<String>>((entry) {
                  final bool isVip = vipOptions.contains(entry.key);
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Row(
                      children: [
                        Text(
                          entry.value,
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        if (isVip) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.star,
                            size: 14,
                            color: Colors.amber.shade700,
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionOptions({
    required List<String> options,
    required Map<String, String> labels,
    required String selectedValue,
    required ValueChanged<String> onChanged,
    required bool isDarkMode,
    List<String> vipOptions = const [],
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          options.map((option) {
            final isSelected = selectedValue == option;
            final isVipOption = vipOptions.contains(option);
            final bool isDisabled = isVipOption && !_isVip;

            return GestureDetector(
              onTap:
                  () =>
                      isDisabled
                          ? _showVipPopupForCustomization()
                          : onChanged(option),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? Colors.blue.shade700
                          : (isDisabled
                              ? (isDarkMode
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade300)
                              : (isDarkMode
                                  ? Colors.blueGrey.shade700
                                  : Colors.grey.shade200)),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      isSelected
                          ? Border.all(color: Colors.white, width: 1.5)
                          : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labels[option] ?? option.capitalize(),
                      style: TextStyle(
                        color:
                            isDisabled
                                ? Colors.grey.shade500
                                : (isSelected
                                    ? Colors.white
                                    : (isDarkMode
                                        ? Colors.white70
                                        : Colors.black87)),
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (isVipOption) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.star, color: Colors.amber.shade700, size: 14),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }

  Future<bool> _savePersonalizationPreferences({
    required String themeMode,
    required String cardColor,
    required String cardAnimation,
    required String journeeCardColor,
    required String journeeAnimation,
    required String cardDesign,
    required String animationSpeed,
    required String journeeCardDesign,
    required String cardSize,
    required bool profileCardBlurEnabled,
    required bool forceGlobalJourneeColor,
    required bool forceGlobalSouvenirColor,
  }) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('themeMode', themeMode);
      await prefs.setString('journeeCardColor', journeeCardColor);
      await prefs.setString('journeeAnimation', journeeAnimation);
      await prefs.setString('cardColor', cardColor);
      await prefs.setString('cardDesign', cardDesign);
      await prefs.setString('cardAnimation', cardAnimation);
      await prefs.setString('animationSpeed', animationSpeed);
      await prefs.setString('journeeCardDesign', journeeCardDesign);
      await prefs.setString('cardSize', cardSize);
      await prefs.setBool('forceGlobalJourneeColor', forceGlobalJourneeColor);
      await prefs.setBool('forceGlobalSouvenirColor', forceGlobalSouvenirColor);

      await _firestore.collection('users').doc(_currentUser.uid).update({
        'profileCardBlurEnabled': profileCardBlurEnabled,
      });

      try {
        await _firestore.collection('users').doc(_currentUser.uid).update({
          'personalizationPreferences': {
            'themeMode': themeMode,
            'cardColor': cardColor,
            'cardAnimation': cardAnimation,
            'journeeCardColor': journeeCardColor,
            'journeeAnimation': journeeAnimation,
            'cardDesign': cardDesign,
            'journeeCardDesign': journeeCardDesign,
            'animationSpeed': animationSpeed,
            'cardSize': cardSize,
            'forceGlobalJourneeColor': forceGlobalJourneeColor,
            'forceGlobalSouvenirColor': forceGlobalSouvenirColor,
          },
        });
      } catch (_) {
        print(
          'Impossible de mettre à jour personalizationPreferences dans Firestore',
        );
      }

      if (mounted) {
        setState(() {
          if (themeMode == 'dark')
            _appBrightness = Brightness.dark;
          else if (themeMode == 'light')
            _appBrightness = Brightness.light;
          else
            _appBrightness =
                WidgetsBinding.instance.platformDispatcher.platformBrightness;

          _profileCardBlurEnabled = profileCardBlurEnabled;
        });

        // Met à jour globalement si HomePageState est présent dans l'arbre
        // (Peut ne pas être le cas ici directement, mais par sécurité)
        final homePageState = context.findAncestorStateOfType<HomePageState>();
        homePageState?.appBrightnessNotifier.value = _appBrightness;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Préférences enregistrées!')),
        );
      }

      return themeMode == 'dark' || themeMode == 'light';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de l\'enregistrement: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _showRestartRequiredDialog() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        final isDarkMode =
            Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkMode ? Colors.blueGrey.shade900 : Colors.white,
          title: Text(
            'Redémarrage conseillé',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Le nouveau thème sera mieux pris en compte après un redémarrage de l’application. Voulez-vous relancer maintenant ?',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Plus tard',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                RestartWidget.restartApp(context);
              },
              child: const Text('Relancer maintenant'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    try {
      await _auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const InscriptionPage()),
          (_) => false,
        );
      }
    } catch (e) {
      print('Erreur de déconnexion : $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Échec de la déconnexion: $e')));
      }
    }
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
    Widget? trailing,
    required bool isDarkMode,
  }) {
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final iconColor = isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700;

    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: TextStyle(color: textColor)),
      trailing:
          trailing ??
          Icon(
            Icons.chevron_right,
            color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
          ),
      onTap: onTap,
    );
  }

  void _showAboutDialog(bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? Colors.blueGrey.shade900 : Colors.white,
          title: Text(
            'À Propos',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Daytalia : Votre journal de vie personnel, enrichi par l\'IA.',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Fermer',
                style: TextStyle(
                  color: isDarkMode ? Colors.blue.shade300 : Colors.blue,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = _appBrightness == Brightness.dark;
    final backgroundColor = isDarkMode ? Colors.black : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _name.isNotEmpty ? _name : 'Profil',
          style: TextStyle(color: textColor),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: textColor),
            onPressed: _showSettingsBottomSheet,
            tooltip: 'Paramètres',
          ),
        ],
      ),
      body: FutureBuilder(
        future: _loadDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            print(snapshot.error);
            return Center(
              child: Text(
                "Erreur de chargement des données: ${snapshot.error}",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDarkMode ? Colors.red.shade300 : Colors.red.shade700,
                ),
              ),
            );
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                _buildProfileHeader(isDarkMode),
                const SizedBox(height: 20),
                _buildBioSection(isDarkMode),
                const SizedBox(height: 20),
                _buildPinnedSection(
                  title: 'Mes journées épinglées',
                  items: _pinnedJournees,
                  itemType: 'journee',
                  isDarkMode: isDarkMode,
                ),
                _buildPinnedSection(
                  title: 'Mes souvenirs épinglés',
                  items: _pinnedSouvenirs,
                  itemType: 'souvenir',
                  isDarkMode: isDarkMode,
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor:
          Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[900]
              : Colors.white,
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final sheetBackgroundColor =
            isDarkMode ? Colors.grey[900] : Colors.white;
        final textColor = isDarkMode ? Colors.white : Colors.black;

        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: sheetBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: ListView(
                controller: controller,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Paramètres',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  _buildSettingTile(
                    icon: Icons.star,
                    title: 'Abonnement VIP',
                    isDarkMode: isDarkMode,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isVip)
                          Text(
                            'Actif',
                            style: TextStyle(
                              color: Colors.green.shade400,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          color:
                              isDarkMode
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                        ),
                      ],
                    ),
                    onTap: _showVipPopup,
                  ),

                  _buildSettingTile(
                    icon: Icons.language,
                    title: 'Langue',
                    isDarkMode: isDarkMode,
                    trailing: DropdownButton<String>(
                      value: _selectedLanguage,
                      dropdownColor: sheetBackgroundColor,
                      style: TextStyle(color: textColor),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color:
                            isDarkMode
                                ? Colors.blue.shade300
                                : Colors.blue.shade700,
                      ),
                      items:
                          ['Français', 'English', 'Español']
                              .map(
                                (lang) => DropdownMenuItem(
                                  value: lang,
                                  child: Text(
                                    lang,
                                    style: TextStyle(color: textColor),
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (value) async {
                        if (value != null) {
                          SharedPreferences prefs =
                              await SharedPreferences.getInstance();
                          await prefs.setString('selectedLanguage', value);
                          if (mounted) {
                            setState(() {
                              _selectedLanguage = value;
                            });
                          }
                        }
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  _buildSettingTile(
                    icon: Icons.notifications,
                    title: 'Gérer les notifications',
                    isDarkMode: isDarkMode,
                    trailing: Icon(
                      Icons.chevron_right,
                      color:
                          isDarkMode
                              ? Colors.grey.shade400
                              : Colors.grey.shade700,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showNotificationSettingsDialog();
                    },
                  ),
                  _buildSettingTile(
                    icon: Icons.palette,
                    title: 'Personnalisation des thèmes et cartes',
                    isDarkMode: isDarkMode,
                    onTap: () {
                      Navigator.pop(context);
                      _showPersonalizationDialog();
                    },
                  ),
                  _buildSettingTile(
                    icon: Icons.school_outlined,
                    title: 'Tutoriel d\'intégration',
                    isDarkMode: isDarkMode,
                    onTap: () {
                      Navigator.pop(context);
                      _launchOnboardingTutorial();
                    },
                  ),
                  _buildSettingTile(
                    icon: Icons.smart_toy,
                    title: 'Personnalisation de l\'IA',
                    isDarkMode: isDarkMode,
                    trailing: Text(
                      _iaPreference == 'ressenti'
                          ? 'Ressenti'
                          : 'Qualité de journée',
                      style: TextStyle(
                        color:
                            isDarkMode
                                ? Colors.grey.shade400
                                : Colors.grey.shade700,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showIAPersonalizationDialog();
                    },
                  ),

                  _buildSettingTile(
                    icon: Icons.privacy_tip,
                    title: 'Vie Privée',
                    isDarkMode: isDarkMode,
                    onTap: () {},
                  ),
                  _buildSettingTile(
                    icon: Icons.help,
                    title: 'Aide',
                    isDarkMode: isDarkMode,
                    onTap: () {},
                  ),
                  _buildSettingTile(
                    icon: Icons.info,
                    title: 'À Propos',
                    isDarkMode: isDarkMode,
                    onTap: () {
                      Navigator.pop(context);
                      _showAboutDialog(isDarkMode);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.exit_to_app, color: Colors.red),
                    title: const Text(
                      'Déconnexion',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: _logout,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
