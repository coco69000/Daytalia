import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JourneeModel {
  String? texte;
  String? texte1;
  String?
  texte1Masked; // Version avec les parties masquées remplacées par des *
  bool estPublic;
  DateTime date;
  String? id;
  String? userId;
  String? userCountry;
  List<String>? hiddenTextFriends;
  List<Map<String, dynamic>>?
  hiddenTextDetails; // Détails des masques par segment
  String? emoji;
  String? commentaire;
  final List<String> mentionedUserIds;

  // --- MODIFICATIONS CI-DESSOUS ---
  final String qualite; // 1. AJOUTER LE CHAMP
  // Votre champ 'note' est un String?, mais vos commentaires dans le code
  // indiquent qu'il pourrait être un int. Cela fonctionne pour l'affichage,
  // mais c'est une chose à garder à l'esprit.
  String? note;
  // --- FIN DES MODIFICATIONS ---

  List<String>? motsCles;
  List<String> photoUrls;
  Map<String, List<String>> reactions;

  bool isRepost;
  String? repostedFromUserId;
  String? repostedFromUserName;
  String? cardColor; // Couleur spécifique de la carte

  JourneeModel({
    this.texte,
    this.texte1,
    this.texte1Masked,
    required this.estPublic,
    required this.date,
    this.id,
    this.userId,
    this.userCountry,
    this.hiddenTextFriends,
    this.hiddenTextDetails,
    this.emoji,
    this.commentaire,
    required this.qualite, // 2. AJOUTER AU CONSTRUCTEUR
    this.note,
    this.motsCles,
    this.photoUrls = const [],
    this.reactions = const {},
    this.mentionedUserIds = const [],
    this.isRepost = false,
    this.repostedFromUserId,
    this.repostedFromUserName,
    this.cardColor,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'texte': texte,
      'texte1': texte1,
      'texte1Masked': texte1Masked,
      'estPublic': estPublic,
      'date': Timestamp.fromDate(date),
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'userCountry': userCountry,
      'hiddenTextFriends': hiddenTextFriends ?? [],
      'hiddenTextDetails': hiddenTextDetails,
      'emoji': emoji,
      'commentaire': commentaire,
      'qualite': qualite, // 4. AJOUTER À FIRESTORE
      'note': note,
      'mots_cles': motsCles,
      'photoUrls': photoUrls,
      'reactions': reactions,
      'mentionedUserIds': mentionedUserIds,
      'isRepost': isRepost,
      'repostedFromUserId': repostedFromUserId,
      'repostedFromUserName': repostedFromUserName,
      'cardColor': cardColor,
    }..removeWhere((key, value) => value == null);
  }

  factory JourneeModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    Map<String, List<String>> reactionsMap = {};
    if (data['reactions'] != null) {
      (data['reactions'] as Map<String, dynamic>).forEach((key, value) {
        if (value is List) {
          reactionsMap[key] = List<String>.from(value);
        }
      });
    }

    return JourneeModel(
      id: doc.id,
      texte: data['texte'],
      texte1: data['texte1'],
      texte1Masked: data['texte1Masked'],
      estPublic: data['estPublic'] ?? false,
      date: (data['date'] as Timestamp).toDate(),
      userId: data['userId'],
      userCountry: data['userCountry'],
      hiddenTextFriends: List<String>.from(data['hiddenTextFriends'] ?? []),
      hiddenTextDetails:
          data['hiddenTextDetails'] != null
              ? List<Map<String, dynamic>>.from(
                (data['hiddenTextDetails'] as List).map(
                  (e) => Map<String, dynamic>.from(e),
                ),
              )
              : null,
      emoji: data['emoji'],
      commentaire: data['commentaire'],
      // 3. LIRE DEPUIS FIRESTORE (avec une valeur par défaut)
      qualite: data['qualite'] ?? 'normale',
      note: data['note'],
      motsCles:
          data['mots_cles'] != null
              ? List<String>.from(data['mots_cles'])
              : null,
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
      reactions: reactionsMap,
      mentionedUserIds: List<String>.from(data['mentionedUserIds'] ?? []),
      isRepost: data['isRepost'] ?? false,
      repostedFromUserId: data['repostedFromUserId'],
      repostedFromUserName: data['repostedFromUserName'],
      cardColor: data['cardColor'],
    );
  }

  bool isValid() {
    return (texte?.isNotEmpty ?? false) &&
        (texte?.length ?? 0) <= 1000 &&
        date.isBefore(DateTime.now());
  }

  bool hasUserReacted(String userId, String emojiType) {
    return reactions[emojiType]?.contains(userId) ?? false;
  }

  void toggleReaction(String userId, String emojiType) {
    if (hasUserReacted(userId, emojiType)) {
      reactions[emojiType]?.remove(userId);
      if (reactions[emojiType]?.isEmpty ?? false) {
        reactions.remove(emojiType);
      }
    } else {
      if (!reactions.containsKey(emojiType)) {
        reactions[emojiType] = [];
      }
      reactions[emojiType]?.add(userId);
    }
  }

  int getReactionCount(String emojiType) {
    return reactions[emojiType]?.length ?? 0;
  }
}
