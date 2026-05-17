// lib/inscription_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'main.dart'; // Import pour accéder à HomeBarrePage

enum AuthFlow {
  phoneInput,
  otpVerification,
  newUserInfo,
  changeNumber_EnterOld,
  changeNumber_EnterNew,
  changeNumber_VerifyNew,
}

class InscriptionPage extends StatefulWidget {
  const InscriptionPage({super.key});

  @override
  _InscriptionPageState createState() => _InscriptionPageState();
}

class _InscriptionPageState extends State<InscriptionPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _otpController = TextEditingController();

  AuthFlow _currentFlow = AuthFlow.phoneInput;
  bool _isLoading = false;
  bool _isCheckingUsername = false;
  String? _verificationId;
  bool _isExistingUser = false;
  String _usernameError = '';
  String _phoneNumber = '';
  String _countryISOCode = 'FRA';
  String _oldPhoneNumber = '';
  String _newPhoneNumber = '';
  File? _profileImage;
  double _qualityOfLife = 50.0;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // Dans lib/inscription_page.dart, classe _InscriptionPageState

  void _resetToStart() {
    setState(() {
      _currentFlow = AuthFlow.phoneInput;
      _isLoading = false;
      _verificationId = null;
      _otpController.clear();
      _phoneNumber = '';
      _oldPhoneNumber = '';
      _newPhoneNumber = '';

      // ▼▼▼ LIGNE À AJOUTER ▼▼▼
      _isExistingUser = false;
      // ▲▲▲ FIN DE L'AJOUT ▲▲▲
    });
  }

  Future<void> _sendOtp({required String phoneNumber, required AuthFlow nextFlow}) async {
    setState(() => _isLoading = true);
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          if (!mounted) return;
          if (_currentFlow == AuthFlow.phoneInput ||
              _currentFlow == AuthFlow.otpVerification) {
            await _signInAndNavigate(credential);
          }
          if (mounted) setState(() => _isLoading = false);
        },
        verificationFailed: (e) {
          if (!mounted) return;
          print('verificationFailed: ${e.code} — ${e.message}');
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur d\'envoi du code : ${e.message ?? e.code}'),
              duration: const Duration(seconds: 6),
            ),
          );
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;
          print('codeSent: verificationId=$verificationId');
          setState(() {
            _verificationId = verificationId;
            _currentFlow = nextFlow;
            _isLoading = false;
          });
        },
        codeAutoRetrievalTimeout: (verificationId) {
          print('codeAutoRetrievalTimeout');
          if (mounted) _verificationId = verificationId;
        },
      );
    } catch (e) {
      print('_sendOtp exception: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur inattendue : $e'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _verifyOtpAndProceed() async {
    if (_otpController.text.isEmpty || _verificationId == null) return;
    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: _otpController.text);
      if (_currentFlow == AuthFlow.otpVerification) {
        await _signInAndNavigate(credential);
      } else if (_currentFlow == AuthFlow.changeNumber_VerifyNew) {
        await _updatePhoneNumberInFirestore();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code OTP invalide ou expiré.')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkPhoneAndSendOtp() async {
    if (_phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer votre numéro de téléphone.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      print('Searching Firestore for phoneNumber=$_phoneNumber');
      final userQuery = await _firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: _phoneNumber)
          .limit(1)
          .get();
      print('Firestore result: ${userQuery.docs.length} doc(s) found');
      setState(() {
        _isExistingUser = userQuery.docs.isNotEmpty;
      });
    } catch (e) {
      print('Firestore query error: $e');
      // Continue anyway — just treat as new user
      setState(() => _isExistingUser = false);
    }
    await _sendOtp(phoneNumber: _phoneNumber, nextFlow: AuthFlow.otpVerification);
  }

  Future<void> _findAccountAndProceed() async {
    if (_oldPhoneNumber.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final userQuery = await _firestore.collection('users').where('phoneNumber', isEqualTo: _oldPhoneNumber).limit(1).get();
      if (userQuery.docs.isNotEmpty) {
        setState(() => _currentFlow = AuthFlow.changeNumber_EnterNew);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Aucun compte n'est associé à cet ancien numéro.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Une erreur est survenue.")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInAndNavigate(PhoneAuthCredential credential) async {
    try {
      final userCredential = await _auth.signInWithCredential(credential);
      print('signInWithCredential OK: uid=${userCredential.user?.uid}');
      if (!mounted) return;
      if (!_isExistingUser) {
        // Nouvel utilisateur : afficher le formulaire de création de profil
        setState(() {
          _isLoading = false;
          _currentFlow = AuthFlow.newUserInfo;
        });
      } else {
        // Utilisateur existant : naviguer directement vers l'accueil
        // (on ne peut pas se fier à authStateChanges car l'utilisateur était
        //  peut-être déjà connecté → le stream ne re-émet pas)
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeBarrePage()),
          (_) => false,
        );
      }
    } catch (e) {
      print('signInWithCredential error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connexion échouée : $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (pickedFile != null) {
      setState(() => _profileImage = File(pickedFile.path));
    }
  }

  Future<String> _uploadProfilePicture(String uid) async {
    if (_profileImage == null) return '';
    try {
      final ref = _storage.ref().child('profile_pictures').child('$uid.jpg');
      await ref.putFile(_profileImage!);
      return await ref.getDownloadURL();
    } catch (e) {
      print("Erreur d'upload d'image: $e");
      return '';
    }
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate() || _usernameError.isNotEmpty) return;
    setState(() => _isLoading = true);

    final user = _auth.currentUser;
    if (user == null) {
      _resetToStart();
      return;
    }

    try {
      String profileImageUrl = await _uploadProfilePicture(user.uid);
      final batch = _firestore.batch();

      // La carte de données à enregistrer dans Firestore
      final userData = {
        'uid': user.uid,
        'phoneNumber': _phoneNumber,
        'name': _nameController.text.trim(),
        'username': _usernameController.text.toLowerCase().trim(),
        // ▼▼▼ LA MODIFICATION EST ICI ▼▼▼
        'country': _countryISOCode, // On utilise 'country' au lieu de 'countryCode'
        // ▲▲▲ FIN DE LA MODIFICATION ▲▲▲
        'createdAt': FieldValue.serverTimestamp(),
        'mondialPublicKey': false,
        'profileImageUrl': profileImageUrl,
        'qualityOfLife': _qualityOfLife.toInt(),
      };

      // Création du document utilisateur dans la collection 'users'
      batch.set(_firestore.collection('users').doc(user.uid), userData);

      // Création du document pour la vérification de l'unicité du pseudo
      batch.set(_firestore.collection('usernames').doc(_usernameController.text.toLowerCase().trim()), {'uid': user.uid});

      // Envoi des opérations à Firestore
      await batch.commit();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeBarrePage()), (route) => false);
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur lors de la création du profil.")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePhoneNumberInFirestore() async {
    // Logique de mise à jour du numéro...
  }

  Future<void> _checkUsername(String username) async {
    if (username.length < 3) return;
    setState(() => _isCheckingUsername = true);
    final doc = await _firestore.collection('usernames').doc(username.toLowerCase()).get();
    if (mounted) {
      setState(() {
        _usernameError = doc.exists ? 'Ce pseudo est déjà pris' : '';
        _isCheckingUsername = false;
      });
    }
  }

  String _getPageTitle() {
    switch (_currentFlow) {
      case AuthFlow.phoneInput: return 'Bienvenue';
      case AuthFlow.otpVerification: return 'Vérification';
      case AuthFlow.newUserInfo: return 'Créez votre profil';
      case AuthFlow.changeNumber_EnterOld: return 'Ancien numéro';
      case AuthFlow.changeNumber_EnterNew: return 'Nouveau numéro';
      case AuthFlow.changeNumber_VerifyNew: return 'Vérifier le nouveau numéro';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getPageTitle()),
        leading: _currentFlow != AuthFlow.phoneInput ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _resetToStart) : null,
      ),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: _buildCurrentFlow())),
    );
  }

  Widget _buildCurrentFlow() {
    switch (_currentFlow) {
      case AuthFlow.phoneInput: return _buildPhoneInputUI();
      case AuthFlow.otpVerification: return _buildOtpUI(phoneNumber: _phoneNumber);
      case AuthFlow.newUserInfo: return _buildNewUserInfoUI();
      case AuthFlow.changeNumber_EnterOld: return _buildEnterPhoneUI(isOldNumber: true);
      case AuthFlow.changeNumber_EnterNew: return _buildEnterPhoneUI(isOldNumber: false);
      case AuthFlow.changeNumber_VerifyNew: return _buildOtpUI(phoneNumber: _newPhoneNumber);
    }
  }

  Widget _buildPhoneInputUI() {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const FlutterLogo(size: 80), const SizedBox(height: 30),
      const Text('Entrez votre numéro pour commencer', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
      const SizedBox(height: 30),
      IntlPhoneField(
        decoration: const InputDecoration(labelText: 'Numéro de téléphone', border: OutlineInputBorder()),
        initialCountryCode: 'FR',
        onChanged: (phone) { _phoneNumber = phone.completeNumber; _countryISOCode = phone.countryISOCode; },
      ),
      const SizedBox(height: 20),
      ElevatedButton(
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
        onPressed: _isLoading ? null : _checkPhoneAndSendOtp,
        child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Continuer'),
      ),
      TextButton(onPressed: () => setState(() => _currentFlow = AuthFlow.changeNumber_EnterOld), child: const Text('Vous avez changé de numéro ?')),
    ]);
  }

  Widget _buildEnterPhoneUI({required bool isOldNumber}) {
    return Column(children: [/* ... UI pour changer de numéro ... */]);
  }

  Widget _buildOtpUI({required String phoneNumber}) {
    return Column(children: [
      Text('Entrez le code envoyé au\n$phoneNumber', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 20),
      TextFormField(
        controller: _otpController, keyboardType: TextInputType.number, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, letterSpacing: 8),
        decoration: const InputDecoration(labelText: 'Code de vérification', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 20),
      ElevatedButton(
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
        onPressed: _isLoading ? null : _verifyOtpAndProceed,
        child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Vérifier'),
      ),
    ]);
  }

  Widget _buildNewUserInfoUI() {
    return Form(
      key: _formKey,
      child: Column(children: [
        const Text("Finalisez votre inscription", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 25),
        GestureDetector(
          onTap: _pickImage,
          child: CircleAvatar(
            radius: 50, backgroundColor: Colors.grey.shade200,
            backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
            child: _profileImage == null ? Icon(Icons.camera_alt, color: Colors.grey.shade800, size: 40) : null,
          ),
        ),
        const SizedBox(height: 8), const Text("Ajouter une photo"), const SizedBox(height: 25),
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Nom complet', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
          validator: (v) => (v == null || v.isEmpty) ? 'Veuillez entrer votre nom' : null,
        ),
        const SizedBox(height: 15),
        TextFormField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: 'Pseudo', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.alternate_email),
            errorText: _usernameError.isEmpty ? null : _usernameError,
            suffixIcon: _isCheckingUsername ? const Padding(padding: EdgeInsets.all(12.0), child: SizedBox(height: 10, width: 10, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
          onChanged: _checkUsername,
          validator: (v) {
            if (v == null || v.isEmpty) return 'Veuillez entrer un pseudo';
            if (v.length < 3) return 'Le pseudo doit faire au moins 3 caractères';
            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) return 'Format invalide (lettres, chiffres, _ )';
            return null;
          },
        ),
        const SizedBox(height: 25),
        Text("Votre qualité de vie actuelle : ${_qualityOfLife.toInt()}", style: const TextStyle(fontSize: 16)),
        Slider(
          value: _qualityOfLife, min: 0, max: 100, divisions: 100, label: _qualityOfLife.round().toString(),
          onChanged: (double value) => setState(() => _qualityOfLife = value),
        ),
        const SizedBox(height: 25),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          onPressed: _isLoading ? null : _createAccount,
          child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Terminer l'inscription"),
        ),
      ]),
    );
  }
}