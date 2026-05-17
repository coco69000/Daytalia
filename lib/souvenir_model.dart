// dans souvenir_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum SouvenirQualite { nostalgie, jamaisOublie, bonheur }

class SouvenirModel {
  final String? id;
  final String userId;
  final String texte;
  final DateTime date;
  final bool estPublic;
  final SouvenirQualite qualite;
  final String? cardColor;
  final int noteQualite;
  int qualiteDeVieActuelle;
  final List<String> photoUrls; // CHANGEMENT ICI: N'est plus nullable (List<String>?)

  final bool isRepost;
  final String? repostedFromUserId;
  final String? repostedFromUserName;

  SouvenirModel({
    this.id,
    required this.userId,
    required this.texte,
    required this.date,
    this.cardColor,
    required this.estPublic,
    required this.qualite,
    required this.noteQualite,
    this.qualiteDeVieActuelle = 50,
    this.photoUrls = const [], // CHANGEMENT ICI: Valeur par défaut liste vide
    this.isRepost = false,
    this.repostedFromUserId,
    this.repostedFromUserName,
  });

  factory SouvenirModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // --- PRINTS IMPORTANTS ---
    print('--- [MODEL] Parsing du Souvenir ID: ${doc.id} ---');
    // On regarde ce que Firestore nous donne pour le champ 'photoUrls'
    final dynamic photoUrlsFromDb = data['photoUrls'];
    print('[MODEL] Raw data pour "photoUrls" depuis Firestore: $photoUrlsFromDb');
    print('[MODEL] Type de "photoUrls" depuis Firestore: ${photoUrlsFromDb.runtimeType}');

    List<String> parsedPhotoUrls = [];
    if (photoUrlsFromDb is List) {
      // Si c'est une liste, on la convertit en List<String>
      // Le .where((item) => item is String) est une sécurité supplémentaire
      parsedPhotoUrls = List<String>.from(photoUrlsFromDb.where((item) => item is String));
      print('[MODEL] "photoUrls" est une liste, conversion réussie.');
    } else {
      print('[MODEL] ATTENTION: "photoUrls" n\'est pas une liste ou est null.');
    }
    print('[MODEL] Liste finale des URLs après parsing: $parsedPhotoUrls');
    // --- FIN DES PRINTS ---

    return SouvenirModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      texte: data['texte'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      estPublic: data['estPublic'] ?? false,
      qualite: SouvenirQualite.values.firstWhere(
            (e) => e.name == data['qualite'],
        orElse: () => SouvenirQualite.nostalgie,
      ),
      noteQualite: data['noteQualite'] ?? 0,
      qualiteDeVieActuelle: data['qualiteDeVieActuelle'] ?? 50,

      // On utilise notre variable parsée et vérifiée
      photoUrls: parsedPhotoUrls,

      isRepost: data['isRepost'] ?? false,
      repostedFromUserId: data['repostedFromUserId'],
      repostedFromUserName: data['repostedFromUserName'],
      cardColor: data['cardColor'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'texte': texte,
      'date': date,
      'estPublic': estPublic,
      'qualite': qualite.name,
      'noteQualite': noteQualite,
      'cardColor': cardColor,
      'qualiteDeVieActuelle': qualiteDeVieActuelle,
      'photoUrls': photoUrls,
      'isRepost': isRepost,
      'repostedFromUserId': repostedFromUserId,
      'repostedFromUserName': repostedFromUserName,
    };
  }
}