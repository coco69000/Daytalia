import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String kDefaultAiModel = 'mistralai/Mistral-Nemo-Instruct-2407';
const String kVipAiModel = 'google/gemini-2.5-flash';

Future<String> resolveAiModel({bool? isVip}) async {
  if (isVip != null) {
    return isVip ? kVipAiModel : kDefaultAiModel;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return kDefaultAiModel;
  }

  try {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final vip = userDoc.data()?['isVip'] ?? false;
    return vip ? kVipAiModel : kDefaultAiModel;
  } catch (_) {
    return kDefaultAiModel;
  }
}