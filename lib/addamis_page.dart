import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notification_service.dart';
import 'profiluser_page.dart';

class AddFriendsPage extends StatefulWidget {
  const AddFriendsPage({super.key});

  @override
  _AddFriendsPageState createState() => _AddFriendsPageState();
}

class _AddFriendsPageState extends State<AddFriendsPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  late TabController _tabController;
  List<Map<String, dynamic>> _friendRequests = [];
  List<Map<String, dynamic>> _friends = [];

  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _contactsOnApp = [];
  List<Contact> _contactsToInvite = [];
  bool _isLoadingSuggestions = false;
  PermissionStatus? _contactPermissionStatus;

  Color _backgroundColor = Colors.white;
  Color _textColor = Colors.black;
  Color _cardBackgroundColor = Colors.white;
  Color _cardTextColor = Colors.black;

  String _normalizePhoneNumber(String value) {
    return value.replaceAll(RegExp(r'[^\d+]'), '');
  }

  Set<String> _phoneNumberVariants(String value) {
    final normalized = _normalizePhoneNumber(value);
    final digitsOnly = normalized.replaceAll(RegExp(r'\D'), '');
    final variants = <String>{};

    if (normalized.isNotEmpty) variants.add(normalized);
    if (digitsOnly.isNotEmpty) variants.add(digitsOnly);
    if (digitsOnly.isNotEmpty && !normalized.startsWith('+')) {
      variants.add('+$digitsOnly');
    }
    if (digitsOnly.startsWith('33') && digitsOnly.length > 2) {
      variants.add('0${digitsOnly.substring(2)}');
    }
    if (digitsOnly.startsWith('0') && digitsOnly.length > 1) {
      variants.add(digitsOnly.substring(1));
    }

    return variants;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadThemePreferences();
    _loadFriendRequests();
    // Charger les amis, PUIS charger les suggestions basées sur les amis et contacts
    _loadFriends().then((_) {
      _loadAllSuggestions();
    });

    _searchController.addListener(() {
      if (_searchController.text.isEmpty) {
        setState(() {
          _searchResults = [];
        });
      }
    });
  }

  Future<void> _loadThemePreferences() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? themeMode = prefs.getString('themeMode');

      bool isDarkMode;
      if (themeMode == 'dark') {
        isDarkMode = true;
      } else if (themeMode == 'light') {
        isDarkMode = false;
      } else {
        isDarkMode =
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
      }

      setState(() {
        if (isDarkMode) {
          _backgroundColor = Colors.black;
          _textColor = Colors.white;
          _cardBackgroundColor = Colors.grey.shade900;
          _cardTextColor = Colors.white;
        } else {
          _backgroundColor = Colors.white;
          _textColor = Colors.black;
          _cardBackgroundColor = Colors.white;
          _cardTextColor = Colors.black;
        }
      });
    } catch (e) {
      print('Erreur de chargement des préférences de thème : $e');
    }
  }

  void _searchUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final query = _searchController.text.trim().toLowerCase();

      if (query.isEmpty) {
        setState(() {
          _searchResults = [];
          _isLoading = false;
        });
        return;
      }

      final results =
          await FirebaseFirestore.instance
              .collection('users')
              .where('username', isGreaterThanOrEqualTo: query)
              .where('username', isLessThan: '${query}z')
              .limit(10)
              .get();

      setState(() {
        final myFriendIds = _friends.map((f) => f['id'] as String).toSet();
        _searchResults =
            results.docs
                .where(
                  (doc) =>
                      doc.id != currentUser?.uid &&
                      !myFriendIds.contains(doc.id),
                )
                .map(
                  (doc) => {
                    'id': doc.id,
                    'name': doc.data()['name'] ?? '',
                    'username': doc.data()['username'] ?? '',
                    'profilePicUrl': doc.data()['profilePicUrl'] ?? '',
                  },
                )
                .toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur de recherche : $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _loadFriendRequests() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      FirebaseFirestore.instance
          .collection('friend_requests')
          .where('receiverId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen((snapshot) async {
            List<Map<String, dynamic>> requests = [];

            for (var doc in snapshot.docs) {
              final senderDoc =
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(doc.data()['senderId'])
                      .get();

              if (senderDoc.exists) {
                requests.add({
                  'requestId': doc.id,
                  'senderId': doc.data()['senderId'],
                  'name': senderDoc.data()?['name'] ?? '',
                  'username': senderDoc.data()?['username'] ?? '',
                  'profilePicUrl': senderDoc.data()?['profilePicUrl'] ?? '',
                });
              }
            }

            if (mounted) {
              setState(() {
                _friendRequests = requests;
              });
            }
          });
    } catch (e) {
      print('Erreur lors du chargement des demandes d\'ami : $e');
    }
  }

  Future<void> _loadFriends() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    print("[DEBUG] _loadFriends: Début du chargement des amis."); // <-- DEBUG
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('friends')
              .where('users', arrayContains: currentUser.uid)
              .get();

      List<Map<String, dynamic>> friendsList = [];

      for (var doc in snapshot.docs) {
        final friendId = (doc.data()['users'] as List).firstWhere(
          (id) => id != currentUser.uid,
          orElse: () => '',
        );

        if (friendId.isEmpty) continue;

        final friendDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(friendId)
                .get();

        if (friendDoc.exists) {
          friendsList.add({
            'friendshipId': doc.id,
            'id': friendId,
            'name': friendDoc.data()?['name'] ?? '',
            'username': friendDoc.data()?['username'] ?? '',
            'profilePicUrl': friendDoc.data()?['profilePicUrl'] ?? '',
          });
        }
      }
      if (mounted) {
        setState(() {
          _friends = friendsList;
        });
      }
      print(
        "[DEBUG] _loadFriends: Chargement terminé. Nombre d'amis trouvés : ${_friends.length}",
      ); // <-- DEBUG
    } catch (e) {
      print('[DEBUG] Erreur lors du chargement des amis : $e'); // <-- DEBUG
    }
  }

  // --- NOUVELLES FONCTIONS POUR LES SUGGESTIONS ---

  Future<void> _loadAllSuggestions() async {
    print(
      "[DEBUG] _loadAllSuggestions: DÉBUT du chargement de toutes les suggestions.",
    ); // <-- DEBUG
    setState(() => _isLoadingSuggestions = true);

    final results = await Future.wait([
      _getFriendsOfFriends(),
      _getContactsOnApp(),
    ]);

    final friendsOfFriends = results[0];
    final contactsOnApp = results[1];

    print(
      "[DEBUG] _loadAllSuggestions: Amis d'amis reçus : ${friendsOfFriends.length}",
    ); // <-- DEBUG
    print(
      "[DEBUG] _loadAllSuggestions: Contacts sur l'app reçus : ${contactsOnApp.length}",
    ); // <-- DEBUG

    // Utilisation d'une Map pour dédupliquer automatiquement
    final allSuggestions = <String, Map<String, dynamic>>{};
    // Prioriser les contacts du téléphone s'ils apparaissent aussi dans les amis d'amis
    for (var user in friendsOfFriends) {
      allSuggestions[user['id']] = user;
    }
    for (var user in contactsOnApp) {
      allSuggestions[user['id']] = user;
    }

    if (mounted) {
      setState(() {
        _suggestions = allSuggestions.values.toList();
        _isLoadingSuggestions = false;
      });
    }
    print(
      "[DEBUG] _loadAllSuggestions: FIN. Nombre total de suggestions uniques: ${_suggestions.length}. Contacts sur l'app: ${_contactsOnApp.length}. Contacts à inviter: ${_contactsToInvite.length}.",
    ); // <-- DEBUG
  }

  Future<List<Map<String, dynamic>>> _getFriendsOfFriends() async {
    print(
      "[DEBUG] _getFriendsOfFriends: DÉBUT de la recherche des amis d'amis.",
    ); // <-- DEBUG
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _friends.isEmpty) {
      print(
        "[DEBUG] _getFriendsOfFriends: Arrêt car l'utilisateur n'est pas connecté ou n'a pas d'amis. (Nombre d'amis: ${_friends.length})",
      ); // <-- DEBUG
      return [];
    }

    try {
      final myFriendIds = _friends.map((f) => f['id'] as String).toList();
      final friendOfFriendIds = <String>{};

      final friendsToCheck = myFriendIds.take(10).toList();
      if (friendsToCheck.isEmpty) {
        print(
          "[DEBUG] _getFriendsOfFriends: Arrêt car la liste d'amis à vérifier est vide.",
        ); // <-- DEBUG
        return [];
      }
      print(
        "[DEBUG] _getFriendsOfFriends: Recherche des amis de mes ${friendsToCheck.length} premiers amis.",
      ); // <-- DEBUG

      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('friends')
              .where('users', arrayContainsAny: friendsToCheck)
              .limit(50)
              .get();

      print(
        "[DEBUG] _getFriendsOfFriends: Trouvé ${querySnapshot.docs.length} documents d'amitié liés à mes amis.",
      ); // <-- DEBUG
      for (var doc in querySnapshot.docs) {
        final users = doc.data()['users'] as List;
        friendOfFriendIds.addAll(users.map((u) => u.toString()));
      }
      print(
        "[DEBUG] _getFriendsOfFriends: IDs bruts collectés (avant filtrage): ${friendOfFriendIds.length}",
      ); // <-- DEBUG

      friendOfFriendIds.remove(currentUser.uid);
      friendOfFriendIds.removeAll(myFriendIds);
      print(
        "[DEBUG] _getFriendsOfFriends: IDs restants après filtrage (moi et mes amis directs): ${friendOfFriendIds.length}",
      ); // <-- DEBUG

      if (friendOfFriendIds.isEmpty) return [];

      final userDocs =
          await FirebaseFirestore.instance
              .collection('users')
              .where(
                FieldPath.documentId,
                whereIn: friendOfFriendIds.toList().take(20).toList(),
              )
              .get();

      final finalSuggestions =
          userDocs.docs
              .map(
                (doc) => {
                  'id': doc.id,
                  'name': doc.data()['name'] ?? '',
                  'username': doc.data()['username'] ?? '',
                  'profilePicUrl': doc.data()['profilePicUrl'] ?? '',
                },
              )
              .toList();
      print(
        "[DEBUG] _getFriendsOfFriends: FIN. Retourne ${finalSuggestions.length} profils d'utilisateurs.",
      ); // <-- DEBUG
      return finalSuggestions;
    } catch (e) {
      print("[DEBUG] Erreur dans _getFriendsOfFriends: $e"); // <-- DEBUG
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getContactsOnApp() async {
    print(
      "[DEBUG] _getContactsOnApp: #1 Demande de permission pour les contacts.",
    ); // <-- DEBUG
    _contactPermissionStatus = await Permission.contacts.request();
    print(
      "[DEBUG] _getContactsOnApp: #1.1 Statut de la permission: $_contactPermissionStatus",
    ); // <-- DEBUG
    if (_contactPermissionStatus != PermissionStatus.granted) {
      if (mounted) setState(() {});
      return [];
    }

    try {
      final List<Contact> phoneContacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      print(
        "[DEBUG] _getContactsOnApp: #2 Trouvé ${phoneContacts.length} contacts sur l'appareil.",
      ); // <-- DEBUG

      final List<String> phoneNumbers =
          phoneContacts
              .where((c) => c.phones.isNotEmpty)
              .expand((c) => _phoneNumberVariants(c.phones.first.number))
              .toList();

      print(
        "[DEBUG] _getContactsOnApp: #3 Extrait ${phoneNumbers.length} numéros de téléphone à vérifier.",
      ); // <-- DEBUG
      if (phoneNumbers.isNotEmpty) {
        print(
          "[DEBUG] _getContactsOnApp: #3.1 Exemple de numéros formatés : ${phoneNumbers.take(5).toList()}",
        ); // <-- DEBUG
        print(
          "ATTENTION: Comparez ces numéros avec le format des numéros dans votre base de données Firestore (champ 'phoneNumber') !",
        ); // <-- DEBUG
      }

      if (phoneNumbers.isEmpty) {
        print(
          "[DEBUG] _getContactsOnApp: Arrêt car aucun numéro de téléphone n'a été trouvé dans les contacts.",
        ); // <-- DEBUG
        return [];
      }

      final foundUsers = <Map<String, dynamic>>[];
      final foundNumbers = <String>{};

      for (var i = 0; i < phoneNumbers.length; i += 30) {
        final batch = phoneNumbers.sublist(
          i,
          i + 30 > phoneNumbers.length ? phoneNumbers.length : i + 30,
        );
        print(
          "[DEBUG] _getContactsOnApp: #4 Recherche Firestore avec un lot de ${batch.length} numéros.",
        ); // <-- DEBUG
        final querySnapshot =
            await FirebaseFirestore.instance
                .collection('users')
                .where('phoneNumber', whereIn: batch)
                .get();

        for (var doc in querySnapshot.docs) {
          if (doc.id == FirebaseAuth.instance.currentUser?.uid) continue;

          final data = doc.data();
          foundUsers.add({
            'id': doc.id,
            'name': data['name'] ?? '',
            'username': data['username'] ?? '',
            'profilePicUrl': data['profilePicUrl'] ?? '',
          });
          if (data['phoneNumber'] != null) {
            foundNumbers.addAll(_phoneNumberVariants(data['phoneNumber'].toString()));
          }
        }
      }
      print(
        "[DEBUG] _getContactsOnApp: #5 Recherche terminée. Total d'utilisateurs trouvés sur l'app : ${foundUsers.length}",
      ); // <-- DEBUG

      final contactsToInvite =
          phoneContacts.where((c) {
            if (c.phones.isEmpty) return false;
            final numberVariants = _phoneNumberVariants(c.phones.first.number);
            return numberVariants.every((number) => !foundNumbers.contains(number));
          }).toList();
      print(
        "[DEBUG] _getContactsOnApp: #6 Total de contacts à inviter (non présents sur l'app) : ${contactsToInvite.length}",
      ); // <-- DEBUG

      if (mounted) {
        setState(() {
          _contactsOnApp = foundUsers;
          _contactsToInvite = contactsToInvite;
        });
      }

      return foundUsers;
    } catch (e) {
      print("[DEBUG] Erreur dans _getContactsOnApp: $e"); // <-- DEBUG
      return [];
    }
  }

  // Le reste du code reste inchangé
  void _inviteContact(Contact contact) async {
    if (contact.phones.isEmpty) return;
    final phoneNumber = contact.phones.first.number;

    const String message =
        "Salut ! Rejoins-moi sur Daytalia. Voici le lien : https://monapp.com/dl";
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: phoneNumber,
      queryParameters: {'body': message},
    );

    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Impossible d'ouvrir l'application SMS."),
          ),
        );
      }
    } catch (e) {
      print("Erreur d'invitation: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Une erreur est survenue lors de l'invitation."),
        ),
      );
    }
  }

  Future<void> _sendFriendRequestNotification(
    String receiverId,
    String senderName,
  ) async {
    try {
      await NotificationService.notifyFriendRequest(
        receiverId: receiverId,
        senderName: senderName,
      );
    } catch (e) {
      print("Échec de l'envoi de la notification: $e");
    }
  }

  void _sendFriendRequest(String userId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      final friendRequestRef = FirebaseFirestore.instance.collection(
        'friend_requests',
      );
      final existingRequest =
          await friendRequestRef
              .where('senderId', isEqualTo: currentUser.uid)
              .where('receiverId', isEqualTo: userId)
              .get();
      if (existingRequest.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demande d\'ami déjà envoyée')),
        );
        return;
      }
      final existingRequestReverse =
          await friendRequestRef
              .where('senderId', isEqualTo: userId)
              .where('receiverId', isEqualTo: currentUser.uid)
              .get();
      if (existingRequestReverse.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cet utilisateur vous a déjà envoyé une demande.'),
          ),
        );
        return;
      }
      final existingFriendship =
          await FirebaseFirestore.instance
              .collection('friends')
              .where('users', arrayContains: currentUser.uid)
              .get();
      final isAlreadyFriend = existingFriendship.docs.any(
        (doc) => (doc.data()['users'] as List).contains(userId),
      );
      if (isAlreadyFriend) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Vous êtes déjà amis')));
        return;
      }
      await friendRequestRef.add({
        'senderId': currentUser.uid,
        'receiverId': userId,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
      final senderDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
      final senderName = senderDoc.data()?['username'] ?? 'Quelqu\'un';
      await _sendFriendRequestNotification(userId, senderName);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Demande d\'ami envoyée')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'envoi de la demande : $e')),
      );
    }
  }

  void _handleFriendRequest(String requestId, bool accept) async {
    try {
      final requestDoc =
          await FirebaseFirestore.instance
              .collection('friend_requests')
              .doc(requestId)
              .get();
      if (!requestDoc.exists) return;
      final requestData = requestDoc.data()!;
      if (accept) {
        await FirebaseFirestore.instance.collection('friends').add({
          'users': [requestData['senderId'], requestData['receiverId']],
          'timestamp': FieldValue.serverTimestamp(),
        });

        final myDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(requestData['receiverId'])
                .get();
        final myName = myDoc.data()?['username'] ?? 'Quelqu\'un';

        await NotificationService.sendTargetedNotification(
          receiverId: requestData['senderId'],
          title: 'Demande acceptée !',
          message: '$myName a accepté votre demande d\'ami.',
          notifType: 'amis_retour',
        );
      }
      await requestDoc.reference.delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? 'Ami ajouté' : 'Demande refusée')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du traitement de la demande : $e')),
      );
    }
  }

  void _deleteFriend(String friendshipId, String friendName) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Supprimer un ami'),
          content: Text(
            'Êtes-vous sûr de vouloir supprimer $friendName de votre liste d\'amis ?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );
    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('friends')
            .doc(friendshipId)
            .delete();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$friendName a été supprimé(e) de vos amis.')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        title: Text('Gestion des amis', style: TextStyle(color: _textColor)),
        iconTheme: IconThemeData(color: _textColor),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: _backgroundColor,
            child: TabBar(
              controller: _tabController,
              labelColor: _textColor,
              unselectedLabelColor: _textColor.withOpacity(0.6),
              indicatorColor: _textColor,
              tabs: [
                const Tab(text: 'Rechercher'),
                Tab(text: 'Demandes (${_friendRequests.length})'),
                Tab(text: 'Amis (${_friends.length})'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSearchTab(), _buildRequestsTab(), _buildFriendsTab()],
      ),
      backgroundColor: _backgroundColor,
    );
  }

  Widget _buildSearchTab() {
    bool isSearching = _searchController.text.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: _textColor),
            decoration: InputDecoration(
              hintText: 'Rechercher par pseudo',
              hintStyle: TextStyle(color: _textColor.withOpacity(0.6)),
              suffixIcon: IconButton(
                icon: Icon(Icons.search, color: _textColor),
                onPressed: _searchUsers,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _textColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _textColor.withOpacity(0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: _cardBackgroundColor.withOpacity(0.5),
            ),
            onChanged: (value) => setState(() {}),
            onSubmitted: (_) => _searchUsers(),
          ),
        ),
        Expanded(
          child:
              isSearching
                  ? _buildSearchResultsList()
                  : _buildSuggestionsSection(),
        ),
      ],
    );
  }

  Widget _buildSearchResultsList() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _textColor));
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'Aucun résultat',
          style: TextStyle(color: _textColor.withOpacity(0.7)),
        ),
      );
    }
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return _buildUserTile(user);
      },
    );
  }

  Widget _buildSuggestionsSection() {
    if (_isLoadingSuggestions) {
      return Center(child: CircularProgressIndicator(color: _textColor));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      children: [
        if (_contactsOnApp.isNotEmpty)
          _buildSuggestionCategory(
            'Retrouvés dans vos contacts',
            _contactsOnApp,
          ),
        if (_suggestions.isNotEmpty)
          _buildSuggestionCategory(
            'Personnes que vous pourriez connaître',
            _suggestions,
          ),
        if (_contactsToInvite.isNotEmpty)
          _buildInviteCategory('Inviter des amis', _contactsToInvite),
        if (_contactsOnApp.isEmpty &&
            _suggestions.isEmpty &&
            _contactsToInvite.isEmpty &&
            _contactPermissionStatus == PermissionStatus.granted)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                'Aucune suggestion pour le moment. Essayez de rechercher un ami !',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textColor.withOpacity(0.7)),
              ),
            ),
          ),
        if (_contactPermissionStatus == PermissionStatus.denied ||
            _contactPermissionStatus == PermissionStatus.permanentlyDenied)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Text(
                    "Autorisez l'accès à vos contacts pour trouver vos amis plus facilement.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textColor.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: openAppSettings,
                    child: const Text("Ouvrir les paramètres"),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSuggestionCategory(
    String title,
    List<Map<String, dynamic>> users,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              color: _textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: users.length,
          itemBuilder:
              (context, index) => _buildUserTile(
                users[index],
                statusLabel: title == 'Retrouvés dans vos contacts'
                    ? 'est sur Daytalia'
                    : null,
              ),
        ),
        const Divider(height: 32),
      ],
    );
  }

  Widget _buildInviteCategory(String title, List<Contact> contacts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              color: _textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: contacts.length,
          itemBuilder: (context, index) {
            final contact = contacts[index];
            return Card(
              color: _cardBackgroundColor,
              margin: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).primaryColor.withOpacity(0.2),
                  child: Text(
                    contact.displayName?.isNotEmpty == true
                        ? contact.displayName![0]
                        : '?',
                    style: TextStyle(color: Theme.of(context).primaryColor),
                  ),
                ),
                title: Text(
                  contact.displayName ?? "Contact sans nom",
                  style: TextStyle(color: _cardTextColor),
                ),
                subtitle: Text(
                  contact.phones?.isNotEmpty == true
                      ? contact.phones!.first.number ?? ""
                      : "Numéro inconnu",
                  style: TextStyle(color: _cardTextColor.withOpacity(0.7)),
                ),
                trailing: ElevatedButton(
                  onPressed: () => _inviteContact(contact),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Inviter'),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user, {String? statusLabel}) {
    final profilePicUrl = user['profilePicUrl'];
    return Card(
      color: _cardBackgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileUserPage(userId: user['id']),
              ),
            ),
        leading: CircleAvatar(
          backgroundImage:
              (profilePicUrl != null && profilePicUrl.isNotEmpty)
                  ? NetworkImage(profilePicUrl)
                  : null,
          backgroundColor: _textColor.withOpacity(0.2),
          child:
              (profilePicUrl == null || profilePicUrl.isEmpty)
                  ? Icon(Icons.person, color: _textColor)
                  : null,
        ),
        title: Text(user['name'], style: TextStyle(color: _cardTextColor)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '@${user['username']}',
              style: TextStyle(color: _cardTextColor.withOpacity(0.7)),
            ),
            if (statusLabel != null)
              Text(
                statusLabel,
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _sendFriendRequest(user['id']),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Ajouter'),
        ),
      ),
    );
  }

  Widget _buildRequestsTab() {
    return _friendRequests.isEmpty
        ? Center(
          child: Text(
            'Aucune demande d\'ami',
            style: TextStyle(color: _textColor.withOpacity(0.7)),
          ),
        )
        : ListView.builder(
          itemCount: _friendRequests.length,
          itemBuilder: (context, index) {
            final request = _friendRequests[index];
            final profilePicUrl = request['profilePicUrl'];
            return Card(
              color: _cardBackgroundColor,
              margin: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: ListTile(
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) =>
                                ProfileUserPage(userId: request['senderId']),
                      ),
                    ),
                leading: CircleAvatar(
                  backgroundImage:
                      (profilePicUrl != null && profilePicUrl.isNotEmpty)
                          ? NetworkImage(profilePicUrl)
                          : null,
                  backgroundColor: _textColor.withOpacity(0.2),
                  child:
                      (profilePicUrl == null || profilePicUrl.isEmpty)
                          ? Icon(Icons.person, color: _textColor)
                          : null,
                ),
                title: Text(
                  request['name'],
                  style: TextStyle(color: _cardTextColor),
                ),
                subtitle: Text(
                  '@${request['username']}',
                  style: TextStyle(color: _cardTextColor.withOpacity(0.7)),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed:
                          () =>
                              _handleFriendRequest(request['requestId'], true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed:
                          () =>
                              _handleFriendRequest(request['requestId'], false),
                    ),
                  ],
                ),
              ),
            );
          },
        );
  }

  Widget _buildFriendsTab() {
    return _friends.isEmpty
        ? Center(
          child: Text(
            'Vous n\'avez pas encore d\'amis',
            style: TextStyle(color: _textColor.withOpacity(0.7)),
          ),
        )
        : ListView.builder(
          itemCount: _friends.length,
          itemBuilder: (context, index) {
            final friend = _friends[index];
            final profilePicUrl = friend['profilePicUrl'];
            return Card(
              color: _cardBackgroundColor,
              margin: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: ListTile(
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => ProfileUserPage(userId: friend['id']),
                      ),
                    ),
                leading: CircleAvatar(
                  backgroundImage:
                      (profilePicUrl != null && profilePicUrl.isNotEmpty)
                          ? NetworkImage(profilePicUrl)
                          : null,
                  backgroundColor: _textColor.withOpacity(0.2),
                  child:
                      (profilePicUrl == null || profilePicUrl.isEmpty)
                          ? Icon(Icons.person, color: _textColor)
                          : null,
                ),
                title: Text(
                  friend['name'],
                  style: TextStyle(color: _cardTextColor),
                ),
                subtitle: Text(
                  '@${friend['username']}',
                  style: TextStyle(color: _cardTextColor.withOpacity(0.7)),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.delete_forever,
                    color: Colors.redAccent,
                  ),
                  tooltip: 'Supprimer cet ami',
                  onPressed:
                      () =>
                          _deleteFriend(friend['friendshipId'], friend['name']),
                ),
              ),
            );
          },
        );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }
}
