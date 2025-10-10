import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JourneeModel {
  String? texte;
  String? texte1;
  bool estPublic;
  DateTime date;
  String? id;
  String? userId;
  List<String>? hiddenTextFriends;
  String? emoji;
  String? commentaire;
  final List<String> mentionedUserIds; // NOUVEAU

  String? note;
  List<String>? motsCles;
  List<String> photoUrls;
  Map<String, List<String>> reactions;
  // NOUVEAU: Liste des IDs des utilisateurs mentionnés dans la journée

  // NOUVEAUX CHAMPS POUR LES REPUBLICATIONS
  bool isRepost;
  String? repostedFromUserId;
  String? repostedFromUserName;

  JourneeModel({
    this.texte,
    this.texte1,
    required this.estPublic,
    required this.date,
    this.id,
    this.userId,
    this.hiddenTextFriends,
    this.emoji,
    this.commentaire,
    this.note,
    this.motsCles,
    this.photoUrls = const [],
    this.reactions = const {},
    this.mentionedUserIds = const [], // NOUVEAU
    this.isRepost = false,
    this.repostedFromUserId,
    this.repostedFromUserName,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'texte': texte,
      'texte1': texte1,
      'estPublic': estPublic,
      'date': Timestamp.fromDate(date),
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'hiddenTextFriends': hiddenTextFriends ?? [],
      'emoji': emoji,
      'commentaire': commentaire,
      'note': note,
      'mots_cles': motsCles,
      'photoUrls': photoUrls,
      'reactions': reactions,
      'mentionedUserIds': mentionedUserIds, // <--- SÉRIALISEZ-LE ICI
      'isRepost': isRepost,
      'repostedFromUserId': repostedFromUserId,
      'repostedFromUserName': repostedFromUserName,
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
      estPublic: data['estPublic'] ?? false,
      date: (data['date'] as Timestamp).toDate(),
      userId: data['userId'],
      hiddenTextFriends: List<String>.from(data['hiddenTextFriends'] ?? []),
      emoji: data['emoji'],
      commentaire: data['commentaire'],
      note: data['note'],
      motsCles: data['mots_cles'] != null
          ? List<String>.from(data['mots_cles'])
          : null,
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
      reactions: reactionsMap,
      mentionedUserIds: List<String>.from(data['mentionedUserIds'] ?? []),
      isRepost: data['isRepost'] ?? false,
      repostedFromUserId: data['repostedFromUserId'],
      repostedFromUserName: data['repostedFromUserName'],
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