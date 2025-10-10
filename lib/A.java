// souvenir_model.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Correction : Ajout de l'alias 'fbAuth'
import 'package:firebase_auth/firebase_auth.dart' as fbAuth;
// Supprimez Supabase si vous n'en avez plus besoin
// import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:path/path.dart' as p; // Plus besoin ici si upload est géré ailleurs

// Énumération pour les qualités de souvenir
enum SouvenirQualite { nostalgie, jamaisOublie, bonheur }

// Modèle de données pour un Souvenir
class SouvenirModel {
  final String id;
  final String userId;
  final String texte;
  final DateTime date;
  final bool estPublic;
  final SouvenirQualite qualite;
  final int noteQualite;
  int qualiteDeVieActuelle;
  final List<String>? photoUrls; // Champ pour les URLs des photos

  // NOUVEAUX CHAMPS POUR LES REPUBLICATIONS
  final bool isRepost;
  final String? repostedFromUserId;
  final String? repostedFromUserName; // Pour afficher le nom de l'ami

  SouvenirModel({
    required this.id,
    required this.userId,
    required this.texte,
    required this.date,
    required this.estPublic,
    required this.qualite,
    required this.noteQualite,
    this.qualiteDeVieActuelle = 50,
    this.photoUrls,
    // Initialisation des nouveaux champs
    this.isRepost = false,
    this.repostedFromUserId,
    this.repostedFromUserName,
  });

  factory SouvenirModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
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
      // Gérer la conversion de la liste d'URLs depuis Firestore
      photoUrls: data['photoUrls'] != null ? List<String>.from(data['photoUrls']) : null,
      // Désérialisation des nouveaux champs
      isRepost: data['isRepost'] ?? false,
      repostedFromUserId: data['repostedFromUserId'],
      repostedFromUserName: data['repostedFromUserName'],
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
      'qualiteDeVieActuelle': qualiteDeVieActuelle,
      'photoUrls': photoUrls,
      // Ajout des nouveaux champs pour la republication
      'isRepost': isRepost,
      'repostedFromUserId': repostedFromUserId,
      'repostedFromUserName': repostedFromUserName,
    };
  }
}