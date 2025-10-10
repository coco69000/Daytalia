// profil_page.dart (Avec les modifications pour le paramètre de taille)

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';

// Import the HomePage to access its state for theme notification
import 'home_page.dart';

// Structures de données pour les options
class _ColorOption {
  final String value;
  final Color color;
  final String label;

  _ColorOption(this.value, this.color, this.label);
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

  // User Profile Data
  String _name = '';
  String _username = '';
  String _bio = '';
  String _profileImageUrl = '';
  bool _isVip = false; // Statut VIP

  // Controllers & Pickers
  final TextEditingController _bioController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;

  // Preferences
  Brightness _appBrightness = Brightness.light;
  String _iaPreference = 'ressenti';
  bool _notificationsEnabled = true;
  String _selectedLanguage = 'Français';

  // State
  bool _isEditingBio = false;
  List<Map<String, dynamic>?> _pinnedSouvenirs = [null, null, null];
  List<Map<String, dynamic>?> _pinnedJournees = [null, null, null];

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
        _appBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      }
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      _selectedLanguage = prefs.getString('selectedLanguage') ?? 'Français';
    });
  }

  Future<void> _loadUserProfile() async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(_currentUser.uid).get();
      if (!mounted) return;

      final data = userDoc.data() as Map<String, dynamic>? ?? {};

      setState(() {
        _name = data['firstName'] ?? '';
        _username = data['username'] ?? '';
        _bio = data['bio'] ?? '';
        _profileImageUrl = data['profileImageUrl'] ?? '';
        _isVip = data['isVip'] ?? false; // Chargement du statut VIP
        _bioController.text = _bio;
      });
    } catch (e) {
      print('Erreur de chargement du profil : $e');
    }
  }

  Future<void> _loadPinnedItems() async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(_currentUser.uid).get();
      if (!mounted) return;

      final data = userDoc.data() as Map<String, dynamic>? ?? {};
      List<dynamic> pinnedSouvenirData = data['pinnedSouvenirs'] ?? [null, null, null];
      _pinnedSouvenirs = pinnedSouvenirData.map((d) => d != null ? Map<String, dynamic>.from(d) : null).toList();
      List<dynamic> pinnedJourneeData = data['pinnedJournees'] ?? [null, null, null];
      _pinnedJournees = pinnedJourneeData.map((d) => d != null ? Map<String, dynamic>.from(d) : null).toList();

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
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
      await _firestore.collection('users').doc(_currentUser.uid).update({'profileImageUrl': downloadUrl});
      if (mounted) {
        setState(() {
          _profileImageUrl = downloadUrl;
          _imageFile = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo mise à jour!')));
      }
    } catch (e) {
      print('Erreur d\'upload : $e');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec: $e')));
      }
    }
  }

  Future<void> _updateBio() async {
    try {
      await _firestore.collection('users').doc(_currentUser.uid).update({'bio': _bioController.text});
      if (mounted) {
        setState(() {
          _bio = _bioController.text;
          _isEditingBio = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bio mise à jour!')));
      }
    } catch (e) {
      print('Erreur mise à jour bio : $e');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec: $e')));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUserItems(String collectionName) async {
    try {
      QuerySnapshot snapshot = await _firestore.collection(collectionName).where('userId', isEqualTo: _currentUser.uid).get();
      return snapshot.docs.map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id}).toList();
    } catch (e) {
      print('Erreur de récupération de $collectionName : $e');
      return [];
    }
  }

  Future<void> _savePinnedItems(String fieldName, List<Map<String, dynamic>?> items) async {
    try {
      await _firestore.collection('users').doc(_currentUser.uid).update({
        fieldName: items.map((item) => item != null ? {'id': item['id'], 'texte': item['texte1'] ?? item['texte'], 'date': item['date']} : null).toList(),
      });
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Éléments épinglés mis à jour!')));
      }
    } catch (e) {
      print('Erreur de sauvegarde de $fieldName : $e');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec: $e')));
      }
    }
  }

  void _showItemSelectionDialog({required int index, required String itemType}) async {
    final collectionName = itemType == 'souvenir' ? 'souvenirs' : 'journees';
    final dialogTitle = 'Choisir un${itemType == 'souvenir' ? '' : 'e'} ${itemType.capitalize()}';
    List<Map<String, dynamic>> items = await _fetchUserItems(collectionName);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDarkMode ? Colors.white : Colors.black;
        final subtitleColor = isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700;
        final cardColor = isDarkMode ? Colors.blueGrey.shade800 : Colors.white;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text(dialogTitle, style: TextStyle(color: textColor)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, i) {
                var item = items[i];
                return ListTile(
                  title: Text(item['texte1'] ?? item['texte'] ?? 'Élément sans texte', style: TextStyle(color: textColor)),
                  subtitle: Text(_formatDate(item['date']), style: TextStyle(color: subtitleColor)),
                  onTap: () {
                    setState(() {
                      if (itemType == 'souvenir') {
                        _pinnedSouvenirs[index] = item;
                      } else {
                        _pinnedJournees[index] = item;
                      }
                    });
                    _savePinnedItems(
                      itemType == 'souvenir' ? 'pinnedSouvenirs' : 'pinnedJournees',
                      itemType == 'souvenir' ? _pinnedSouvenirs : _pinnedJournees,
                    );
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Annuler', style: TextStyle(color: isDarkMode ? Colors.red.shade300 : Colors.red)),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    return DateFormat('dd/MM/yyyy').format(timestamp.toDate());
  }

  void _showVipSubscriptionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                const Text("Débloquez tout le potentiel de Daytalia avec le statut VIP :"),
                const SizedBox(height: 10),
                _buildVipAdvantage(Icons.auto_awesome, "Analyse IA illimitée de votre niveau de vie."),
                _buildVipAdvantage(Icons.auto_stories, "Génération et mise à jour illimitée de votre autobiographie."),
                _buildVipAdvantage(Icons.psychology, "Conseils de l'IA sur vos journées."),
                _buildVipAdvantage(Icons.compare_arrows, "Accès à la fonctionnalité 'Journées Similaires'."),
                _buildVipAdvantage(Icons.text_snippet, "Extraction illimitée des éléments intéressants pour vos souvenirs."),
                _buildVipAdvantage(Icons.palette, "Options de personnalisation exclusives (couleurs, formes, animations)."),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Plus tard'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
              child: Text(_isVip ? 'Se désabonner' : 'S\'abonner'),
              onPressed: () async {
                bool newVipStatus = !_isVip;
                await _firestore.collection('users').doc(_currentUser.uid).update({'isVip': newVipStatus});
                if(mounted) {
                  setState(() { _isVip = newVipStatus; });
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(newVipStatus ? "Bienvenue chez les VIP !" : "Votre abonnement a été annulé."),
                      backgroundColor: newVipStatus ? Colors.green : Colors.orange,
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
    Navigator.pop(context); // Fermer le bottom sheet des paramètres d'abord
    _showVipSubscriptionDialog();
  }

  void _showVipPopupForCustomization() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: [
              Icon(Icons.star, color: Colors.amber.shade700),
              const SizedBox(width: 10),
              const Text("Option VIP"),
            ],
          ),
          content: const Text("Cette option est réservée aux membres VIP. Appuyez sur 'Devenir VIP' pour en savoir plus."),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
              child: const Text('Devenir VIP'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Ferme le petit pop-up
                Navigator.of(context).pop();      // Ferme la boîte de dialogue de personnalisation
                _showVipSubscriptionDialog();     // Affiche le pop-up principal d'abonnement VIP
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
                backgroundImage: _imageFile != null
                    ? FileImage(_imageFile!)
                    : (_profileImageUrl.isNotEmpty
                    ? NetworkImage(_profileImageUrl)
                    : const AssetImage('assets/default_profile.png') as ImageProvider),
                backgroundColor: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.edit,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _name,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        Text(
          '@$_username',
          style: const TextStyle(
            color: Colors.grey,
          ),
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
      child: _isEditingBio
          ? Row(
        children: [
          Expanded(
            child: TextField(
              controller: _bioController,
              decoration: InputDecoration(
                hintText: 'Entrez votre bio',
                hintStyle: TextStyle(color: hintColor),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkMode ? Colors.blueGrey : Colors.grey)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue.shade700)),
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
                fontStyle: _bio.isEmpty ? FontStyle.italic : FontStyle.normal,
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
              children: List.generate(3, (index) {
                return _buildPinnedItemCard(
                  data: items[index],
                  isDarkMode: isDarkMode,
                  onTap: () => _showItemSelectionDialog(index: index, itemType: itemType),
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
  }) {
    final cardColor = isDarkMode ? Colors.blueGrey.shade900 : Colors.white;
    final borderColor = isDarkMode ? Colors.blue.shade700 : Colors.blue;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        height: 200,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: data == null ? (isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200) : cardColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: data == null ? (isDarkMode ? Colors.grey.shade600 : Colors.grey.shade400) : borderColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isDarkMode ? Colors.black.withOpacity(0.4) : Colors.grey.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: data == null
            ? Center(
          child: Icon(
            Icons.add_circle_outline,
            color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade600,
            size: 50,
          ),
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Text(
                data['texte1'] ?? data['texte'] ?? '',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 15),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Text(
                _formatDate(data['date']),
                style: TextStyle(color: isDarkMode ? Colors.grey.shade400 : Colors.grey, fontSize: 12),
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
        final dialogColor = isDarkMode ? Colors.blueGrey.shade900 : Colors.white;
        final textColor = isDarkMode ? Colors.white : Colors.black;
        final activeColor = Colors.blue.shade700;

        return AlertDialog(
          backgroundColor: dialogColor,
          title: Text('Personnalisation de l\'IA', style: TextStyle(color: textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: Text('IA basée sur mon ressenti', style: TextStyle(color: textColor)),
                value: 'ressenti',
                groupValue: _iaPreference,
                onChanged: (value) {
                  Navigator.pop(context, value);
                },
                activeColor: activeColor,
              ),
              RadioListTile<String>(
                title: Text('IA basée sur ma qualité de journée', style: TextStyle(color: textColor)),
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
              child: Text('Annuler', style: TextStyle(color: isDarkMode ? Colors.red.shade300 : Colors.red)),
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

  void _showPersonalizationDialog() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    String currentThemeMode = prefs.getString('themeMode') ?? 'system';
    String selectedCardColor = prefs.getString('cardColor') ?? 'default';
    String selectedCardAnimation = prefs.getString('cardAnimation') ?? 'default';
    String selectedJourneeCardColor = prefs.getString('journeeCardColor') ?? 'default';
    String selectedJourneeAnimation = prefs.getString('journeeAnimation') ?? 'default';
    String selectedCardDesign = prefs.getString('cardDesign') ?? 'default';
    String selectedAnimationSpeed = prefs.getString('animationSpeed') ?? 'normal';
    String selectedJourneeCardDesign = prefs.getString('journeeCardDesign') ?? 'default';
    // --- NOUVEAU --- : Charger la préférence de taille
    String selectedCardSize = prefs.getString('cardSize') ?? 'normal';

    const Map<String, String> animationLabels = {
      'default': 'Rebondissant',
      'rotation': 'Rotation',
      'changer': 'Fondu',
      'flottant': 'Flottant',
      'pulsation': 'Pulsation',
    };
    const Map<String, String> designLabels = {
      'default': 'Standard',
      'minimaliste': 'Minimaliste',
      'coeur': 'Coeur',
      'etoile': 'Étoile',
      'rond': 'Rond',
    };
    const Map<String, String> speedLabels = {
      'lent': 'Lente',
      'normal': 'Normale',
      'rapide': 'Rapide',
    };
    // --- NOUVEAU --- : Labels pour les tailles
    const Map<String, String> sizeLabels = {
      'tres_petit': 'Très Petit',
      'petit': 'Petit',
      'normal': 'Normal',
      'gros': 'Gros',
    };

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            final isDialogDarkMode = Theme.of(context).brightness == Brightness.dark;
            final textColor = isDialogDarkMode ? Colors.white : Colors.black;
            final dialogBgColor = isDialogDarkMode ? Colors.blueGrey.shade900 : Colors.white;

            void updateSelection(String type, String value) {
              setStateInDialog(() {
                switch (type) {
                  case 'themeMode':
                    currentThemeMode = value;
                    break;
                  case 'card':
                    selectedCardColor = value;
                    break;
                  case 'animation':
                    selectedCardAnimation = value;
                    break;
                  case 'journee':
                    selectedJourneeCardColor = value;
                    break;
                  case 'journeeAnimation':
                    selectedJourneeAnimation = value;
                    break;
                  case 'design':
                    selectedCardDesign = value;
                    break;
                  case 'journeeDesign':
                    selectedJourneeCardDesign = value;
                    break;
                  case 'speed':
                    selectedAnimationSpeed = value;
                    break;
                // --- NOUVEAU --- : Gérer la mise à jour de la taille
                  case 'cardSize':
                    selectedCardSize = value;
                    break;
                }
              });
            }

            return AlertDialog(
              backgroundColor: dialogBgColor,
              title: Text('Personnalisation', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildSectionTitle('Thème de l\'application', textColor),
                    _buildThemeModeSelection(currentThemeMode, (v) => updateSelection('themeMode', v), isDialogDarkMode),
                    const SizedBox(height: 16),

                    _buildSectionTitle('Couleur des cartes Souvenir', textColor),
                    _buildColorGrid(
                      options: [
                        _ColorOption('default', Colors.blue.shade100, 'Défaut'),
                        _ColorOption('noir', Colors.black, 'Noir'),
                        _ColorOption('bleu', Colors.blue.shade300, 'Bleu'),
                        _ColorOption('rouge', Colors.red.shade300, 'Rouge'),
                        _ColorOption('vert', Colors.green.shade300, 'Vert'),
                      ],
                      selectedValue: selectedCardColor,
                      onChanged: (v) => updateSelection('card', v),
                      isDarkMode: isDialogDarkMode,
                    ),
                    const SizedBox(height: 16),

                    _buildSectionTitle('Couleur des cartes Journée', textColor),
                    _buildColorGrid(
                      options: [
                        _ColorOption('default', Colors.blue.shade100, 'Défaut'),
                        _ColorOption('noir', Colors.black, 'Noir'),
                        _ColorOption('bleu', Colors.blue.shade300, 'Bleu'),
                        _ColorOption('rouge', Colors.red.shade300, 'Rouge'),
                        _ColorOption('vert', Colors.green.shade300, 'Vert'),
                      ],
                      selectedValue: selectedJourneeCardColor,
                      onChanged: (v) => updateSelection('journee', v),
                      isDarkMode: isDialogDarkMode,
                    ),
                    const SizedBox(height: 16),

                    _buildSectionTitle('Animation des cartes Souvenir', textColor),
                    _buildSelectionOptions(
                      options: ['default', 'rotation', 'changer', 'flottant', 'pulsation'],
                      labels: animationLabels,
                      selectedValue: selectedCardAnimation,
                      onChanged: (v) => updateSelection('animation', v),
                      isDarkMode: isDialogDarkMode,
                      vipOptions: const ['flottant', 'pulsation'],
                    ),
                    const SizedBox(height: 16),

                    _buildSectionTitle('Animation des cartes Journée', textColor),
                    _buildSelectionOptions(
                      options: ['default', 'rotation', 'changer', 'flottant', 'pulsation'],
                      labels: animationLabels,
                      selectedValue: selectedJourneeAnimation,
                      onChanged: (v) => updateSelection('journeeAnimation', v),
                      isDarkMode: isDialogDarkMode,
                      vipOptions: const ['flottant', 'pulsation'],
                    ),
                    const SizedBox(height: 16),

                    _buildSectionTitle('Vitesse d\'animation', textColor),
                    _buildSelectionOptions(
                      options: ['lent', 'normal', 'rapide'],
                      labels: speedLabels,
                      selectedValue: selectedAnimationSpeed,
                      onChanged: (v) => updateSelection('speed', v),
                      isDarkMode: isDialogDarkMode,
                    ),
                    const SizedBox(height: 16),

                    _buildSectionTitle('Design des cartes Souvenir', textColor),
                    _buildSelectionOptions(
                      options: ['default', 'minimaliste', 'coeur', 'etoile', 'rond'],
                      labels: designLabels,
                      selectedValue: selectedCardDesign,
                      onChanged: (v) => updateSelection('design', v),
                      isDarkMode: isDialogDarkMode,
                      vipOptions: const ['etoile'],
                    ),
                    const SizedBox(height: 16),

                    _buildSectionTitle('Design des cartes Journée', textColor),
                    _buildSelectionOptions(
                      options: ['default', 'minimaliste', 'coeur', 'etoile', 'rond'],
                      labels: designLabels,
                      selectedValue: selectedJourneeCardDesign,
                      onChanged: (v) => updateSelection('journeeDesign', v),
                      isDarkMode: isDialogDarkMode,
                      vipOptions: const ['etoile'],
                    ),
                    const SizedBox(height: 16),

                    // --- NOUVEAU --- : Section pour la taille des cartes
                    _buildSectionTitle('Taille des cartes', textColor),
                    _buildSelectionOptions(
                      options: ['tres_petit', 'petit', 'normal', 'gros'],
                      labels: sizeLabels,
                      selectedValue: selectedCardSize,
                      onChanged: (v) => updateSelection('cardSize', v),
                      isDarkMode: isDialogDarkMode,
                      vipOptions: const ['tres_petit', 'petit', 'gros'],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Annuler', style: TextStyle(color: isDialogDarkMode ? Colors.red.shade300 : Colors.red)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _savePersonalizationPreferences(
                      themeMode: currentThemeMode,
                      cardColor: selectedCardColor,
                      cardAnimation: selectedCardAnimation,
                      journeeCardColor: selectedJourneeCardColor,
                      journeeAnimation: selectedJourneeAnimation,
                      cardDesign: selectedCardDesign,
                      journeeCardDesign: selectedJourneeCardDesign,
                      animationSpeed: selectedAnimationSpeed,
                      // --- NOUVEAU --- : Passer la taille pour la sauvegarde
                      cardSize: selectedCardSize,
                    );
                    if (mounted) {
                      Navigator.pop(dialogContext);
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

  Widget _buildSectionTitle(String title, Color textColor) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
      ),
    );
  }

  Widget _buildThemeModeSelection(String currentThemeMode, ValueChanged<String> onChanged, bool isDarkMode) {
    return Column(
      children: [
        RadioListTile<String>(
          title: Text('Clair', style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
          value: 'light',
          groupValue: currentThemeMode,
          onChanged: (val) => onChanged(val!),
          activeColor: Colors.blue,
        ),
        RadioListTile<String>(
          title: Text('Sombre', style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
          value: 'dark',
          groupValue: currentThemeMode,
          onChanged: (val) => onChanged(val!),
          activeColor: Colors.blue,
        ),
        RadioListTile<String>(
          title: Text('Système', style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
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
  }) {
    const vipColors = ['noir', 'bleu'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isVipOption = vipColors.contains(option.value);
        final bool isDisabled = isVipOption && !_isVip;

        return GestureDetector(
          onTap: () {
            if (isDisabled) {
              _showVipPopupForCustomization();
            } else {
              onChanged(option.value);
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: option.color,
                  borderRadius: BorderRadius.circular(10),
                  border: selectedValue == option.value
                      ? Border.all(color: Colors.blue.shade700, width: 3)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
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
                      color: option.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
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
                  child: Icon(Icons.star, color: Colors.amber.shade700, size: 30),
                ),
            ],
          ),
        );
      }).toList(),
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
      children: options.map((option) {
        final isSelected = selectedValue == option;
        final isVipOption = vipOptions.contains(option);
        final bool isDisabled = isVipOption && !_isVip;

        return GestureDetector(
          onTap: () {
            if (isDisabled) {
              _showVipPopupForCustomization();
            } else {
              onChanged(option);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.blue.shade700
                  : (isDisabled
                  ? (isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300)
                  : (isDarkMode ? Colors.blueGrey.shade700 : Colors.grey.shade200)),
              borderRadius: BorderRadius.circular(20),
              border: isSelected
                  ? Border.all(color: Colors.white, width: 1.5)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  labels[option] ?? option.capitalize(), // Utilisation du label
                  style: TextStyle(
                    color: isDisabled
                        ? Colors.grey.shade500
                        : (isSelected ? Colors.white : (isDarkMode ? Colors.white70 : Colors.black87)),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (isVipOption) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.star, color: Colors.amber.shade700, size: 14),
                ]
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _savePersonalizationPreferences({
    required String themeMode,
    required String cardColor,
    required String cardAnimation,
    required String journeeCardColor,
    required String journeeAnimation,
    required String cardDesign,
    required String animationSpeed,
    required String journeeCardDesign,
    // --- NOUVEAU --- : Ajout du paramètre de taille
    required String cardSize,
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
      // --- NOUVEAU --- : Sauvegarder la taille
      await prefs.setString('cardSize', cardSize);

      if (mounted) {
        setState(() {
          if (themeMode == 'dark') {
            _appBrightness = Brightness.dark;
          } else if (themeMode == 'light') {
            _appBrightness = Brightness.light;
          } else { // System
            _appBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
          }
        });

        final homePageState = context.findAncestorStateOfType<HomePageState>();
        if (homePageState != null) {
          homePageState.appBrightnessNotifier.value = _appBrightness;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Préférences de personnalisation enregistrées!')),
        );
      }
    } catch (e) {
      print('Erreur de sauvegarde des préférences : $e');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de l\'enregistrement des préférences: $e')),
        );
      }
    }
  }


  Future<void> _logout() async {
    try {
      await _auth.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      print('Erreur de déconnexion : $e');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de la déconnexion: $e')),
        );
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
      trailing: trailing ?? Icon(Icons.chevron_right, color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700),
      onTap: onTap,
    );
  }

  void _showAboutDialog(bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? Colors.blueGrey.shade900 : Colors.white,
          title: Text('À Propos', style: TextStyle(color: isDarkMode ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
          content: Text('Daytalia : Votre journal de vie personnel, enrichi par l\'IA.', style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Fermer', style: TextStyle(color: isDarkMode ? Colors.blue.shade300 : Colors.blue)),
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
    final appBarColor = isDarkMode ? Colors.black : Colors.blue.shade700;
    final textColor = isDarkMode ? Colors.white : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        title: Text('Profil', style: TextStyle(color: textColor)),
        actions: [
          InkWell(
            onTap: _showSettingsBottomSheet,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.settings, color: textColor),
                  const SizedBox(width: 8),
                  Text(
                    'Personnalisation',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
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
            return Center(child: Text(
              "Erreur de chargement des données: ${snapshot.error}",
              textAlign: TextAlign.center,
              style: TextStyle(color: isDarkMode ? Colors.red.shade300 : Colors.red.shade700),
            ));
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
                  title: 'Journées Épinglées',
                  items: _pinnedJournees,
                  itemType: 'journee',
                  isDarkMode: isDarkMode,
                ),
                _buildPinnedSection(
                  title: 'Souvenirs Épinglés',
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
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.grey[900]
          : Colors.white,
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final sheetBackgroundColor = isDarkMode ? Colors.grey[900] : Colors.white;
        final textColor = isDarkMode ? Colors.white : Colors.black;

        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: sheetBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                          Text('Actif', style: TextStyle(color: Colors.green.shade400, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700),
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
                      icon: Icon(Icons.arrow_drop_down, color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700),
                      items: ['Français', 'English', 'Español']
                          .map((lang) => DropdownMenuItem(
                        value: lang,
                        child: Text(lang, style: TextStyle(color: textColor)),
                      ))
                          .toList(),
                      onChanged: (value) async {
                        if (value != null) {
                          SharedPreferences prefs = await SharedPreferences.getInstance();
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
                    title: 'Notifications',
                    isDarkMode: isDarkMode,
                    trailing: Switch(
                      value: _notificationsEnabled,
                      onChanged: (bool value) async {
                        SharedPreferences prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('notificationsEnabled', value);
                        if (mounted) {
                          setState(() {
                            _notificationsEnabled = value;
                          });
                        }
                      },
                      activeColor: Colors.blue.shade700,
                      inactiveThumbColor: isDarkMode ? Colors.grey.shade600 : Colors.grey.shade400,
                      inactiveTrackColor: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300,
                    ),
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
                    icon: Icons.smart_toy,
                    title: 'Personnalisation de l\'IA',
                    isDarkMode: isDarkMode,
                    trailing: Text(
                      _iaPreference == 'ressenti' ? 'Ressenti' : 'Qualité de journée',
                      style: TextStyle(color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700),
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
                    onTap: () {
// Navigate to privacy settings
                    },
                  ),
                  _buildSettingTile(
                    icon: Icons.help,
                    title: 'Aide',
                    isDarkMode: isDarkMode,
                    onTap: () {
// Navigate to help page
                    },
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