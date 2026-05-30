// lib/inscription_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart'; // Import pour accéder à HomeBarrePage

enum AuthFlow {
  phoneInput,
  otpVerification,
  newUserInfo,
  changeNumber_EnterOld,
  changeNumber_EnterNew,
  changeNumber_VerifyNew,
  recoveryInfo,
}

class InscriptionPage extends StatefulWidget {
  final AuthFlow initialFlow;

  const InscriptionPage({super.key, this.initialFlow = AuthFlow.phoneInput});

  @override
  _InscriptionPageState createState() => _InscriptionPageState();
}

class _InscriptionPageState extends State<InscriptionPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final RegExp _e164PhonePattern = RegExp(r'^\+[1-9]\d{7,14}$');

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
  DateTime? _birthDate;
  final _birthDateController = TextEditingController();
  String? _recoveryUserUid;
  Map<String, dynamic>? _recoveryUserData;
  File? _profileImage;
  double _qualityOfLife = 50.0;

  @override
void initState() {
  super.initState();
  _currentFlow = widget.initialFlow;
  FirebaseAuth.instance.setSettings(
    appVerificationDisabledForTesting: true,
  );
}

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _otpController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  void _resetToStart() {
    setState(() {
      _currentFlow = AuthFlow.phoneInput;
      _isLoading = false;
      _verificationId = null;
      _otpController.clear();
      _phoneNumber = '';
      _oldPhoneNumber = '';
      _newPhoneNumber = '';
      _birthDate = null;
      _birthDateController.clear();
      _recoveryUserUid = null;
      _recoveryUserData = null;
      _isExistingUser = false;
    });
  }

  Future<void> _selectBirthDate() async {
    final initialDate = _birthDate ?? DateTime(1995, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Choisissez votre date de naissance',
    );

    if (picked != null && mounted) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _sendOtp({
    required String phoneNumber,
    required AuthFlow nextFlow,
  }) async {
    final normalizedPhoneNumber = _normalizePhoneNumber(phoneNumber);
    if (!_isValidE164PhoneNumber(normalizedPhoneNumber)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Le numéro de téléphone doit être au format international, par exemple +33612345678.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: normalizedPhoneNumber,
        verificationCompleted: (credential) async {
          if (!mounted) return;
          await _signInAndNavigate(credential);
          if (mounted) setState(() => _isLoading = false);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          print('verificationFailed: ${e.code} — ${e.message}');
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur : ${e.message ?? e.code}'),
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
          if (mounted) _verificationId = verificationId;
        },
      );
    } catch (e) {
      print('_sendOtp error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyOtpAndProceed() async {
    if (_otpController.text.isEmpty || _verificationId == null) return;
    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text,
      );
      if (_currentFlow == AuthFlow.otpVerification) {
        await _signInAndNavigate(credential);
      } else if (_currentFlow == AuthFlow.changeNumber_VerifyNew) {
        if (mounted) {
          setState(() {
            _currentFlow = AuthFlow.recoveryInfo;
            _nameController.text =
                (_recoveryUserData?['name'] as String? ?? '').trim();
            _usernameController.text =
                (_recoveryUserData?['username'] as String? ?? '').trim();
            final birthValue = _recoveryUserData?['birthDate'];
            if (birthValue is Timestamp) {
              _birthDate = birthValue.toDate();
              _birthDateController.text = DateFormat(
                'dd/MM/yyyy',
              ).format(_birthDate!);
            }
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code OTP invalide ou expiré.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkPhoneAndSendOtp() async {
    if (_phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer votre numéro de téléphone.'),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      print('Searching Firestore for phoneNumber=$_phoneNumber');
      final userQuery =
          await _firestore
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
      setState(() => _isExistingUser = false);
    }
    await _sendOtp(
      phoneNumber: _phoneNumber,
      nextFlow: AuthFlow.otpVerification,
    );
  }

  Future<void> _checkRecoveryOldNumber() async {
    if (_oldPhoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer votre ancien numéro.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userQuery =
          await _firestore
              .collection('users')
              .where('phoneNumber', isEqualTo: _oldPhoneNumber)
              .limit(1)
              .get();

      if (userQuery.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucun compte trouvé avec cet ancien numéro.'),
          ),
        );
        return;
      }

      final doc = userQuery.docs.first;
      setState(() {
        _recoveryUserUid = doc.id;
        _recoveryUserData = doc.data();
        _currentFlow = AuthFlow.changeNumber_EnterNew;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Une erreur est survenue.')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _normalizePhoneNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final compacted = trimmed.replaceAll(RegExp(r'[\s\-()\.]+'), '');
    return compacted.startsWith('+') ? compacted : '+$compacted';
  }

  bool _isValidE164PhoneNumber(String value) {
    return _e164PhonePattern.hasMatch(value);
  }

  Future<void> _signInAndNavigate(PhoneAuthCredential credential) async {
    try {
      final userCredential = await _auth.signInWithCredential(credential);
      print('signInWithCredential OK: uid=${userCredential.user?.uid}');
      if (!mounted) return;
      if (!_isExistingUser) {
        setState(() {
          _isLoading = false;
          _currentFlow = AuthFlow.newUserInfo;
        });
      } else {
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
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
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

      final userData = {
        'uid': user.uid,
        'phoneNumber': _phoneNumber,
        'name': _nameController.text.trim(),
        'username': _usernameController.text.toLowerCase().trim(),
        'birthDate':
            _birthDate != null ? Timestamp.fromDate(_birthDate!) : null,
        'country': _countryISOCode,
        'createdAt': FieldValue.serverTimestamp(),
        'mondialPublicKey': false,
        'profileImageUrl': profileImageUrl,
        'qualityOfLife': _qualityOfLife.toInt(),
        'accountBlocked': false,
        'recoveryStatus': 'none',
        'notificationPrefs': {
          'post_amis': true,
          'demande_amis': true,
          'mentions_tags': true,
          'commentaires': true,
          'reactions': true,
          'amis_retour': true,
          'post_populaire': true,
          'recommandations': true,
          'memories': true,
        },
      };

      batch.set(_firestore.collection('users').doc(user.uid), userData);

      batch.set(
        _firestore
            .collection('usernames')
            .doc(_usernameController.text.toLowerCase().trim()),
        {'uid': user.uid},
      );

      await batch.commit();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeBarrePage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur lors de la création du profil."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitRecoveryRequest() async {
    if (!_formKey.currentState!.validate() || _birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complétez tous les champs requis.')),
      );
      return;
    }

    if (_recoveryUserUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte à récupérer introuvable.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final requestData = {
        'oldUserUid': _recoveryUserUid,
        'oldPhoneNumber': _oldPhoneNumber,
        'newPhoneNumber': _newPhoneNumber,
        'name': _nameController.text.trim(),
        'username': _usernameController.text.toLowerCase().trim(),
        'birthDate': Timestamp.fromDate(_birthDate!),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };

      final batch = _firestore.batch();
      final requestRef = _firestore.collection('recovery_requests').doc();
      batch.set(requestRef, requestData);

      batch.update(_firestore.collection('users').doc(_recoveryUserUid), {
        'accountBlocked': true,
        'recoveryStatus': 'pending',
        'pendingRecoveryRequestId': requestRef.id,
        'pendingPhoneNumber': _newPhoneNumber,
        'pendingUsername': _usernameController.text.toLowerCase().trim(),
        'pendingBirthDate': Timestamp.fromDate(_birthDate!),
      });

      await batch.commit();
      await _sendRecoveryEmailDraft(requestData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Demande envoyée. Votre compte sera débloqué après validation Firebase.',
          ),
        ),
      );
      _resetToStart();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'envoi de la demande : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendRecoveryEmailDraft(Map<String, dynamic> requestData) async {
    final subject = Uri.encodeComponent('Demande de récupération Daytalia');
    final body = Uri.encodeComponent(
      'Nouvelle demande de récupération Daytalia\n\n'
      'UID: ${requestData['oldUserUid']}\n'
      'Ancien numéro: ${requestData['oldPhoneNumber']}\n'
      'Nouveau numéro: ${requestData['newPhoneNumber']}\n'
      'Nom Prénom: ${requestData['name']}\n'
      'Pseudo: ${requestData['username']}\n'
      'Date de naissance: ${DateFormat('dd/MM/yyyy').format(_birthDate!)}\n',
    );
    final uri = Uri.parse(
      'mailto:corentinparrel2@gmail.com?subject=$subject&body=$body',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _checkUsername(String username) async {
    if (username.length < 3) return;
    setState(() => _isCheckingUsername = true);
    final doc =
        await _firestore
            .collection('usernames')
            .doc(username.toLowerCase())
            .get();
    if (mounted) {
      setState(() {
        _usernameError = doc.exists ? 'Ce pseudo est déjà pris' : '';
        _isCheckingUsername = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode ? Colors.black : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildCurrentFlow(isDarkMode),
              ),
            ),
            if (_currentFlow != AuthFlow.phoneInput)
              Positioned(
                top: 10,
                left: 10,
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                  onPressed: _resetToStart,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentFlow(bool isDarkMode) {
    switch (_currentFlow) {
      case AuthFlow.phoneInput:
        return _buildPhoneInputUI(isDarkMode);
      case AuthFlow.otpVerification:
        return _buildOtpUI(isDarkMode: isDarkMode, phoneNumber: _phoneNumber);
      case AuthFlow.newUserInfo:
        return _buildNewUserInfoUI(isDarkMode);
      case AuthFlow.changeNumber_EnterOld:
        return _buildEnterPhoneUI(isDarkMode: isDarkMode, isOldNumber: true);
      case AuthFlow.changeNumber_EnterNew:
        return _buildEnterPhoneUI(isDarkMode: isDarkMode, isOldNumber: false);
      case AuthFlow.changeNumber_VerifyNew:
        return _buildOtpUI(
          isDarkMode: isDarkMode,
          phoneNumber: _newPhoneNumber,
        );
      case AuthFlow.recoveryInfo:
        return _buildRecoveryInfoUI(isDarkMode);
    }
  }

  Widget _buildPhoneInputUI(bool isDarkMode) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor =
        isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
    final cardColor = isDarkMode ? Colors.grey.shade900 : Colors.white;
    final themeColor = Theme.of(context).colorScheme.primary;
    final btnTextColor = Theme.of(context).colorScheme.onPrimary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow:
            isDarkMode
                ? []
                : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Entrez votre numéro pour continuer',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Recevez un code pour vous connecter ou démarrer la création de votre compte.',
            textAlign: TextAlign.center,
            style: TextStyle(color: subtitleColor, height: 1.4),
          ),
          const SizedBox(height: 32),
          IntlPhoneField(
            style: TextStyle(color: textColor),
            dropdownTextStyle: TextStyle(color: textColor),
            dropdownIcon: Icon(Icons.arrow_drop_down, color: textColor),
            decoration: InputDecoration(
              labelText: 'Numéro de téléphone',
              labelStyle: TextStyle(color: subtitleColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color:
                      isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color:
                      isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: themeColor),
              ),
            ),
            initialCountryCode: 'FR',
            onChanged: (phone) {
              _phoneNumber = phone.completeNumber;
              _countryISOCode = phone.countryISOCode;
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
                backgroundColor: themeColor,
              foregroundColor: btnTextColor,
              elevation: 0,
            ),
            onPressed: _isLoading ? null : _checkPhoneAndSendOtp,
            child:
                _isLoading
                    ? SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: btnTextColor,
                        strokeWidth: 2,
                      ),
                    )
                    : const Text(
                      'Continuer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
          ),
          const SizedBox(height: 16),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: subtitleColor),
            onPressed:
                () => setState(
                  () => _currentFlow = AuthFlow.changeNumber_EnterOld,
                ),
            child: const Text('Récupérer mon compte'),
          ),
        ],
      ),
    );
  }

  Widget _buildEnterPhoneUI({
    required bool isDarkMode,
    required bool isOldNumber,
  }) {
    final hintText =
        isOldNumber
            ? 'Entrez le numéro associé à votre compte'
            : 'Entrez votre nouveau numéro';

    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor =
        isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
    final cardColor = isDarkMode ? Colors.grey.shade900 : Colors.white;
    final themeColor = Theme.of(context).colorScheme.primary;
    final btnTextColor = Theme.of(context).colorScheme.onPrimary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow:
            isDarkMode
                ? []
                : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            isOldNumber ? Icons.restore_rounded : Icons.verified_user_outlined,
            color: textColor,
            size: 48,
          ),
          const SizedBox(height: 24),
          Text(
            hintText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isOldNumber
                ? 'Nous allons identifier le compte associé à ce numéro.'
                : 'Nous allons envoyer un code sur votre nouveau numéro.',
            textAlign: TextAlign.center,
            style: TextStyle(color: subtitleColor, height: 1.4),
          ),
          const SizedBox(height: 32),
          IntlPhoneField(
            style: TextStyle(color: textColor),
            dropdownTextStyle: TextStyle(color: textColor),
            dropdownIcon: Icon(Icons.arrow_drop_down, color: textColor),
            decoration: InputDecoration(
              labelText: 'Numéro de téléphone',
              labelStyle: TextStyle(color: subtitleColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color:
                      isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color:
                      isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: themeColor),
              ),
            ),
            initialCountryCode: 'FR',
            onChanged: (phone) {
              if (isOldNumber) {
                _oldPhoneNumber = phone.completeNumber;
              } else {
                _newPhoneNumber = phone.completeNumber;
              }
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
                backgroundColor: themeColor,
              foregroundColor: btnTextColor,
              elevation: 0,
            ),
            onPressed:
                _isLoading
                    ? null
                    : () async {
                      if (isOldNumber) {
                        await _checkRecoveryOldNumber();
                      } else {
                        if (_newPhoneNumber.isEmpty) return;
                        await _sendOtp(
                          phoneNumber: _newPhoneNumber,
                          nextFlow: AuthFlow.changeNumber_VerifyNew,
                        );
                      }
                    },
            child:
                _isLoading
                    ? SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: btnTextColor,
                        strokeWidth: 2,
                      ),
                    )
                    : Text(
                      isOldNumber ? 'Continuer' : 'Envoyer le code',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpUI({required bool isDarkMode, required String phoneNumber}) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor =
        isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
    final btnColor = isDarkMode ? Colors.white : Colors.black87;
    final btnTextColor = isDarkMode ? Colors.black : Colors.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Entrez le code envoyé au\n$phoneNumber',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: textColor),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            letterSpacing: 8,
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            labelText: 'Code de vérification',
            labelStyle: TextStyle(
              color: subtitleColor,
              letterSpacing: 0,
              fontSize: 14,
              fontWeight: FontWeight.normal,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: btnColor),
            ),
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: btnColor,
            foregroundColor: btnTextColor,
            elevation: 0,
          ),
          onPressed: _isLoading ? null : _verifyOtpAndProceed,
          child:
              _isLoading
                  ? SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: btnTextColor,
                      strokeWidth: 2,
                    ),
                  )
                  : const Text(
                    'Vérifier',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
        ),
      ],
    );
  }

  Widget _buildRecoveryInfoUI(bool isDarkMode) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor =
        isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
    final btnColor = isDarkMode ? Colors.white : Colors.black87;
    final btnTextColor = isDarkMode ? Colors.black : Colors.white;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Finalisez la récupération de votre compte',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Le nouveau numéro a été vérifié. Complétez les informations pour envoyer la demande de déblocage.',
            textAlign: TextAlign.center,
            style: TextStyle(color: subtitleColor, height: 1.4),
          ),
          const SizedBox(height: 32),
          _buildTextField(
            controller: _nameController,
            label: 'Nom Prénom',
            icon: Icons.person_outline,
            isDarkMode: isDarkMode,
            validator:
                (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Veuillez entrer votre nom et prénom'
                        : null,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _selectBirthDate,
            child: AbsorbPointer(
              child: _buildTextField(
                controller: _birthDateController,
                label: 'Date de naissance',
                icon: Icons.cake_outlined,
                isDarkMode: isDarkMode,
                validator:
                    (_) =>
                        _birthDate == null
                            ? 'Veuillez choisir votre date de naissance'
                            : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _usernameController,
            label: 'Pseudo',
            icon: Icons.alternate_email,
            isDarkMode: isDarkMode,
            onChanged: _checkUsername,
            errorText: _usernameError.isEmpty ? null : _usernameError,
            suffixIcon:
                _isCheckingUsername
                    ? Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: btnColor,
                        ),
                      ),
                    )
                    : null,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Veuillez entrer un pseudo';
              if (v.length < 3)
                return 'Le pseudo doit faire au moins 3 caractères';
              if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v))
                return 'Format invalide (lettres, chiffres, _ )';
              return null;
            },
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey.shade900 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Votre demande sera envoyée à corentinparrel2@gmail.com et enregistrée dans Firebase en attente de validation.',
              style: TextStyle(color: subtitleColor, height: 1.4, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: btnColor,
              foregroundColor: btnTextColor,
              elevation: 0,
            ),
            onPressed: _isLoading ? null : _submitRecoveryRequest,
            child:
                _isLoading
                    ? SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: btnTextColor,
                        strokeWidth: 2,
                      ),
                    )
                    : const Text(
                      'Envoyer ma demande',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewUserInfoUI(bool isDarkMode) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor =
        isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
    final btnColor = isDarkMode ? Colors.white : Colors.black87;
    final btnTextColor = isDarkMode ? Colors.black : Colors.white;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Finalisez votre inscription',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Créez votre profil pour personnaliser votre espace Daytalia.',
            textAlign: TextAlign.center,
            style: TextStyle(color: subtitleColor, height: 1.4),
          ),
          const SizedBox(height: 32),
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor:
                        isDarkMode
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                    backgroundImage:
                        _profileImage != null
                            ? FileImage(_profileImage!)
                            : null,
                    child:
                        _profileImage == null
                            ? Icon(
                              Icons.person,
                              color:
                                  isDarkMode
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade400,
                              size: 48,
                            )
                            : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: btnColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDarkMode ? Colors.black : Colors.white,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        color: btnTextColor,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          _buildTextField(
            controller: _nameController,
            label: 'Nom Prénom',
            icon: Icons.person_outline,
            isDarkMode: isDarkMode,
            validator:
                (v) =>
                    (v == null || v.isEmpty)
                        ? 'Veuillez entrer votre nom et prénom'
                        : null,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _selectBirthDate,
            child: AbsorbPointer(
              child: _buildTextField(
                controller: _birthDateController,
                label: 'Date de naissance',
                icon: Icons.cake_outlined,
                isDarkMode: isDarkMode,
                validator:
                    (_) =>
                        _birthDate == null
                            ? 'Veuillez choisir votre date de naissance'
                            : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _usernameController,
            label: 'Pseudo',
            icon: Icons.alternate_email,
            isDarkMode: isDarkMode,
            onChanged: _checkUsername,
            errorText: _usernameError.isEmpty ? null : _usernameError,
            suffixIcon:
                _isCheckingUsername
                    ? Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: btnColor,
                        ),
                      ),
                    )
                    : null,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Veuillez entrer un pseudo';
              if (v.length < 3)
                return 'Le pseudo doit faire au moins 3 caractères';
              if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v))
                return 'Format invalide (lettres, chiffres, _ )';
              return null;
            },
          ),
          const SizedBox(height: 32),
          Text(
            "Votre qualité de vie actuelle : ${_qualityOfLife.toInt()}",
            style: TextStyle(
              fontSize: 16,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: btnColor,
              inactiveTrackColor:
                  isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300,
              thumbColor: btnColor,
              overlayColor: btnColor.withOpacity(0.2),
            ),
            child: Slider(
              value: _qualityOfLife,
              min: 0,
              max: 100,
              divisions: 100,
              label: _qualityOfLife.round().toString(),
              onChanged:
                  (double value) => setState(() => _qualityOfLife = value),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: btnColor,
              foregroundColor: btnTextColor,
              elevation: 0,
            ),
            onPressed: _isLoading ? null : _createAccount,
            child:
                _isLoading
                    ? SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: btnTextColor,
                        strokeWidth: 2,
                      ),
                    )
                    : const Text(
                      "Terminer l'inscription",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDarkMode,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    String? errorText,
    Widget? suffixIcon,
  }) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor =
        isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
    final borderColor =
        isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300;
    final focusedColor = isDarkMode ? Colors.white : Colors.black87;

    return TextFormField(
      controller: controller,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subtitleColor),
        prefixIcon: Icon(icon, color: subtitleColor),
        suffixIcon: suffixIcon,
        errorText: errorText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: focusedColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }
}
