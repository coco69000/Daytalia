import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// NOUVEAU: Importation pour la navigation vers la page de profil utilisateur
import 'profiluser_page.dart';

// --- AMÉLIORATION : CONFIGURATION ONESIGNAL (À METTRE À JOUR) ---
const String ONE_SIGNAL_APP_ID = "83c44506-2022-4432-a8fe-004e4406416e";
// ATTENTION : NE JAMAIS LAISSER CETTE CLÉ DANS LE CODE CLIENT EN PRODUCTION !
const String ONE_SIGNAL_REST_API_KEY = "os_v2_app_qpcekbraejcdfkh6abheibsbny3tigrupigu4vf3vtds3wnadgmdiwe7bi35yw4lcugsvh2shc5tnrnxmoru4aj3w66k6ewldrlguka";


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

  // Couleurs du thème
  Color _backgroundColor = Colors.white;
  Color _textColor = Colors.black;
  Color _cardBackgroundColor = Colors.white;
  Color _cardTextColor = Colors.black;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadThemePreferences();
    _loadFriendRequests();
    _loadFriends();
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
        isDarkMode = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
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

      final results = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: query)
          .where('username', isLessThan: '${query}z')
          .limit(10)
          .get();

      setState(() {
        _searchResults = results.docs
            .where((doc) => doc.id != currentUser?.uid)
            .map((doc) => {
          'id': doc.id,
          'name': doc.data()['firstName'] ?? '',
          'username': doc.data()['username'] ?? '',
          'profilePicUrl': doc.data()['profilePicUrl'] ?? '',
        })
            .toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de recherche : $e')),
      );
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
          final senderDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(doc.data()['senderId'])
              .get();

          if (senderDoc.exists) {
            requests.add({
              'requestId': doc.id,
              'senderId': doc.data()['senderId'],
              'name': senderDoc.data()?['firstName'] ?? '',
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

  void _loadFriends() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      FirebaseFirestore.instance
          .collection('friends')
          .where('users', arrayContains: currentUser.uid)
          .snapshots()
          .listen((snapshot) async {
        List<Map<String, dynamic>> friends = [];

        for (var doc in snapshot.docs) {
          final friendId = (doc.data()['users'] as List)
              .firstWhere((id) => id != currentUser.uid, orElse: () => '');

          if (friendId.isEmpty) continue;

          final friendDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(friendId)
              .get();

          if (friendDoc.exists) {
            friends.add({
              // NOUVEAU : On stocke l'ID du document d'amitié pour la suppression
              'friendshipId': doc.id,
              'id': friendId,
              'name': friendDoc.data()?['firstName'] ?? '',
              'username': friendDoc.data()?['username'] ?? '',
              'profilePicUrl': friendDoc.data()?['profilePicUrl'] ?? '',
            });
          }
        }
        if (mounted) {
          setState(() {
            _friends = friends;
          });
        }
      });
    } catch (e) {
      print('Erreur lors du chargement des amis : $e');
    }
  }

  // --- AMÉLIORATION : Fonction pour envoyer une notification ---
  Future<void> _sendFriendRequestNotification(String receiverId, String senderName) async {
    print('DEBUG: Début de _sendFriendRequestNotification pour receiverId: $receiverId');

    if (ONE_SIGNAL_REST_API_KEY == "bahq3hwrousomzsj2tkiel5az") { // Je garde votre clé pour l'exemple
      print("--- INFO NOTIFICATION: Clé REST API OneSignal configurée.");
    }

    try {
      // 1. Récupérer le Player ID du destinataire
      print('DEBUG: Recherche du Player ID pour l\'utilisateur $receiverId dans Firestore...');
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(receiverId).get();

      if (!userDoc.exists) {
        print("--- ERREUR DEBUG: Le document de l'utilisateur $receiverId n'existe PAS.");
        return;
      }

      if (!userDoc.data()!.containsKey('oneSignalPlayerId') || userDoc.data()!['oneSignalPlayerId'] == null) {
        print("--- ERREUR DEBUG: Le champ 'oneSignalPlayerId' est MANQUANT ou NULL pour l'utilisateur $receiverId.");
        return;
      }

      final String playerId = userDoc.data()!['oneSignalPlayerId'];
      print('DEBUG: Player ID trouvé: $playerId');

      // 2. Envoyer la notification via l'API REST de OneSignal
      print('DEBUG: Préparation de l\'envoi de la requête à OneSignal...');
      final response = await http.post( // On capture la réponse
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Basic $ONE_SIGNAL_REST_API_KEY', // N'oubliez pas l'espace après Basic
        },
        body: jsonEncode(<String, dynamic>{
          "app_id": ONE_SIGNAL_APP_ID,
          "include_player_ids": [playerId],
          "headings": {"en": "Nouvelle demande d'ami !"},
          "contents": {"en": "$senderName vous a envoyé une demande d'ami."},
          // Ajout pour forcer la notification même si l'app est ouverte
          "content_available": true,
        }),
      );

      print('DEBUG: Réponse de OneSignal - Statut Code: ${response.statusCode}');
      print('DEBUG: Réponse de OneSignal - Corps: ${response.body}');

      if (response.statusCode == 200) {
        print("--- SUCCÈS NOTIFICATION: Notification de demande d'ami envoyée à $receiverId");
      } else {
        print("--- ERREUR NOTIFICATION: OneSignal a renvoyé une erreur.");
      }

    } catch (e) {
      print("--- ERREUR CRITIQUE: Échec de l'envoi de la notification: $e");
    }
  }

  void _sendFriendRequest(String userId) async {
    print("--- DÉBUT: _sendFriendRequest pour l'utilisateur $userId ---");
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print("--- ERREUR: Utilisateur courant est null. Arrêt.");
      return;
    }
    print("Utilisateur courant: ${currentUser.uid}");

    try {
      final friendRequestRef =
      FirebaseFirestore.instance.collection('friend_requests');

      // Vérification 1
      print("Vérification 1: Demande existante de MOI vers LUI...");
      final existingRequest = await friendRequestRef
          .where('senderId', isEqualTo: currentUser.uid)
          .where('receiverId', isEqualTo: userId)
          .get();

      if (existingRequest.docs.isNotEmpty) {
        print("--- BLOCAGE: Une demande existe déjà. Affichage SnackBar et arrêt.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demande d\'ami déjà envoyée')),
        );
        return;
      }

      // Vérification 2
      print("Vérification 2: Demande existante de LUI vers MOI...");
      final existingRequestReverse = await friendRequestRef
          .where('senderId', isEqualTo: userId)
          .where('receiverId', isEqualTo: currentUser.uid)
          .get();

      if (existingRequestReverse.docs.isNotEmpty) {
        print("--- BLOCAGE: Une demande inverse existe déjà. Affichage SnackBar et arrêt.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cet utilisateur vous a déjà envoyé une demande.')),
        );
        return;
      }

      // Vérification 3
      print("Vérification 3: Amitié existante...");
      final existingFriendship = await FirebaseFirestore.instance
          .collection('friends')
          .where('users', arrayContains: currentUser.uid)
          .get();

      final isAlreadyFriend = existingFriendship.docs
          .any((doc) => (doc.data()['users'] as List).contains(userId));

      if (isAlreadyFriend) {
        print("--- BLOCAGE: Vous êtes déjà amis. Affichage SnackBar et arrêt.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vous êtes déjà amis')),
        );
        return;
      }

      // Si on arrive ici, tout est bon
      print("--- SUCCÈS: Toutes les vérifications sont passées. Création de la demande...");
      await friendRequestRef.add({
        'senderId': currentUser.uid,
        'receiverId': userId,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      print("--- ACTION: Appel de _sendFriendRequestNotification ---");
      final senderDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      final senderName = senderDoc.data()?['username'] ?? 'Quelqu\'un';
      await _sendFriendRequestNotification(userId, senderName);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande d\'ami envoyée')),
      );
    } catch (e) {
      print("--- ERREUR CRITIQUE dans _sendFriendRequest: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'envoi de la demande : $e')),
      );
    }
  }

  void _handleFriendRequest(String requestId, bool accept) async {
    try {
      final requestDoc = await FirebaseFirestore.instance
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
      }

      await requestDoc.reference.delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Ami ajouté' : 'Demande refusée'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors du traitement de la demande : $e'),
        ),
      );
    }
  }

  // --- AMÉLIORATION : Fonction pour supprimer un ami ---
  void _deleteFriend(String friendshipId, String friendName) async {
    // Confirmation de la suppression
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Supprimer un ami'),
          content: Text('Êtes-vous sûr de vouloir supprimer $friendName de votre liste d\'amis ?'),
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
        title: Text(
          'Gestion des amis',
          style: TextStyle(color: _textColor),
        ),
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
        children: [
          _buildSearchTab(),
          _buildRequestsTab(),
          _buildFriendsTab(),
        ],
      ),
      backgroundColor: _backgroundColor,
    );
  }

  Widget _buildSearchTab() {
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
                    color: Theme.of(context).primaryColor, width: 2),
              ),
              filled: true,
              fillColor: _cardBackgroundColor.withOpacity(0.5),
            ),
            onSubmitted: (_) => _searchUsers(),
          ),
        ),
        _isLoading
            ? CircularProgressIndicator(color: _textColor)
            : Expanded(
          child: _searchResults.isEmpty
              ? Center(
              child: Text('Aucun résultat',
                  style: TextStyle(color: _textColor.withOpacity(0.7))))
              : ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final user = _searchResults[index];
              final profilePicUrl = user['profilePicUrl'];
              return Card(
                color: _cardBackgroundColor,
                margin: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 4.0),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: (profilePicUrl != null && profilePicUrl.isNotEmpty)
                        ? NetworkImage(profilePicUrl)
                        : null,
                    backgroundColor: _textColor.withOpacity(0.2),
                    child: (profilePicUrl == null || profilePicUrl.isEmpty)
                        ? Icon(Icons.person, color: _textColor)
                        : null,
                  ),
                  title: Text(user['name'],
                      style: TextStyle(color: _cardTextColor)),
                  subtitle: Text('@${user['username']}',
                      style: TextStyle(
                          color: _cardTextColor.withOpacity(0.7))),
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
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRequestsTab() {
    return _friendRequests.isEmpty
        ? Center(
        child: Text('Aucune demande d\'ami',
            style: TextStyle(color: _textColor.withOpacity(0.7))))
        : ListView.builder(
      itemCount: _friendRequests.length,
      itemBuilder: (context, index) {
        final request = _friendRequests[index];
        final profilePicUrl = request['profilePicUrl'];
        return Card(
          color: _cardBackgroundColor,
          margin: const EdgeInsets.symmetric(
              horizontal: 16.0, vertical: 4.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: (profilePicUrl != null && profilePicUrl.isNotEmpty)
                  ? NetworkImage(profilePicUrl)
                  : null,
              backgroundColor: _textColor.withOpacity(0.2),
              child: (profilePicUrl == null || profilePicUrl.isEmpty)
                  ? Icon(Icons.person, color: _textColor)
                  : null,
            ),
            title: Text(request['name'],
                style: TextStyle(color: _cardTextColor)),
            subtitle: Text('@${request['username']}',
                style:
                TextStyle(color: _cardTextColor.withOpacity(0.7))),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () =>
                      _handleFriendRequest(request['requestId'], true),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () =>
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
        child: Text('Vous n\'avez pas encore d\'amis',
            style: TextStyle(color: _textColor.withOpacity(0.7))))
        : ListView.builder(
      itemCount: _friends.length,
      itemBuilder: (context, index) {
        final friend = _friends[index];
        final profilePicUrl = friend['profilePicUrl'];
        return Card(
          color: _cardBackgroundColor,
          margin: const EdgeInsets.symmetric(
              horizontal: 16.0, vertical: 4.0),
          child: ListTile(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileUserPage(userId: friend['id']),
                ),
              );
            },
            leading: CircleAvatar(
              backgroundImage: (profilePicUrl != null && profilePicUrl.isNotEmpty)
                  ? NetworkImage(profilePicUrl)
                  : null,
              backgroundColor: _textColor.withOpacity(0.2),
              child: (profilePicUrl == null || profilePicUrl.isEmpty)
                  ? Icon(Icons.person, color: _textColor)
                  : null,
            ),
            title: Text(friend['name'],
                style: TextStyle(color: _cardTextColor)),
            subtitle: Text('@${friend['username']}',
                style:
                TextStyle(color: _cardTextColor.withOpacity(0.7))),
            // --- AMÉLIORATION : Ajout du bouton de suppression ---
            trailing: IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              tooltip: 'Supprimer cet ami',
              onPressed: () => _deleteFriend(friend['friendshipId'], friend['name']),
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