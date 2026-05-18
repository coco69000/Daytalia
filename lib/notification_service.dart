import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const String ONE_SIGNAL_APP_ID = '83c44506-2022-4432-a8fe-004e4406416e';
const String ONE_SIGNAL_REST_API_KEY =
    'os_v2_app_qpcekbraejcdfkh6abheibsbny3tigrupigu4vf3vtds3wnadgmdiwe7bi35yw4lcugsvh2shc5tnrnxmoru4aj3w66k6ewldrlguka';

class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static bool get _isConfigured =>
      ONE_SIGNAL_REST_API_KEY != 'VOTRE_REST_API_KEY_ONESIGNAL';

  static Future<void> sendTargetedNotification({
    required String receiverId,
    required String title,
    required String message,
    required String notifType,
  }) async {
    if (!_isConfigured) return;

    try {
      final userDoc =
          await _firestore.collection('users').doc(receiverId).get();
      if (!userDoc.exists) return;

      final data = userDoc.data();
      if (data == null) return;

      final prefs = data['notificationPrefs'] as Map<String, dynamic>? ?? {};
      final bool isEnabled = prefs[notifType] ?? true;
      if (!isEnabled) return;

      final String? playerId = data['oneSignalPlayerId'] as String?;
      if (playerId == null || playerId.isEmpty) return;

      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Basic $ONE_SIGNAL_REST_API_KEY',
        },
        body: jsonEncode({
          'app_id': ONE_SIGNAL_APP_ID,
          'include_player_ids': [playerId],
          'headings': {'en': title, 'fr': title},
          'contents': {'en': message, 'fr': message},
        }),
      );
    } catch (e) {
      print('Erreur envoi notification: $e');
    }
  }

  static Future<void> notifyFriendRequest({
    required String receiverId,
    required String senderName,
  }) async {
    await sendTargetedNotification(
      receiverId: receiverId,
      title: 'Nouvelle demande d\'ami',
      message: '$senderName vous a envoyé une demande d\'ami.',
      notifType: 'demande_amis',
    );
  }

  static Future<void> notifyOwnerOnInteraction({
    required String journeeId,
    required String interactorName,
    required String action,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final journeeDoc =
        await _firestore.collection('journees').doc(journeeId).get();
    if (!journeeDoc.exists) return;

    final data = journeeDoc.data();
    if (data == null) return;

    final ownerId = data['userId'] as String?;
    if (ownerId == null || ownerId == currentUser.uid) return;

    final notifType = action == 'commenté' ? 'commentaires' : 'reactions';
    await sendTargetedNotification(
      receiverId: ownerId,
      title: 'Nouvelle interaction !',
      message: '$interactorName a $action votre journée.',
      notifType: notifType,
    );
  }

  static Future<void> notifyMention(
    String receiverId,
    String authorName,
  ) async {
    await sendTargetedNotification(
      receiverId: receiverId,
      title: 'Vous avez été mentionné',
      message: '$authorName vous a mentionné dans une publication.',
      notifType: 'mentions_tags',
    );
  }

  static Future<void> notifyFriendsOfNewPost(String authorName) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final friendsSnapshot =
        await _firestore
            .collection('friends')
            .where('users', arrayContains: currentUser.uid)
            .get();

    final friendIds =
        friendsSnapshot.docs
            .expand((doc) => List<String>.from(doc['users']))
            .toSet()
          ..remove(currentUser.uid);

    for (final friendId in friendIds) {
      await sendTargetedNotification(
        receiverId: friendId,
        title: 'Nouvelle journée !',
        message: '$authorName a partagé sa journée.',
        notifType: 'post_amis',
      );
    }
  }
}
