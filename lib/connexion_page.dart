import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'inscription_page.dart';
import 'home_page.dart'; // Remplacez par votre page principale avec bottom navigation
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class ConnexionPage extends StatefulWidget {
  const ConnexionPage({super.key});

  @override
  _ConnexionPageState createState() => _ConnexionPageState();
}

class _ConnexionPageState extends State<ConnexionPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _formKey = GlobalKey<FormState>();
  final _storage = const FlutterSecureStorage();

  bool _isLoading = false;
  bool _obscurePassword = true;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connexion'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const FlutterLogo(size: 100),
                const SizedBox(height: 20),

                _buildEmailField(),
                const SizedBox(height: 15),

                _buildPasswordField(),
                const SizedBox(height: 10),

                _buildRememberMeAndForgotPassword(),
                const SizedBox(height: 20),

                if (_errorMessage.isNotEmpty)
                  Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                  ),
                const SizedBox(height: 15),

                _buildConnexionButton(),
                const SizedBox(height: 15),

                _buildInscriptionLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRememberMeAndForgotPassword() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Checkbox(
              value: false, // Vous pouvez implémenter la logique de "Se souvenir de moi"
              onChanged: (bool? value) {
                // Logique pour se souvenir de l'utilisateur
              },
            ),
            const Text('Se souvenir de moi'),
          ],
        ),
        TextButton(
          onPressed: _handleForgotPassword,
          child: const Text('Mot de passe oublié ?'),
        ),
      ],
    );
  }

  void _handleForgotPassword() async {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer votre email')),
      );
      return;
    }

    try {
      await _auth.sendPasswordResetEmail(email: _emailController.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email de réinitialisation envoyé')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    }
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      decoration: const InputDecoration(
        labelText: 'Email',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.email),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Veuillez entrer un email';
        }
        final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
        if (!emailRegex.hasMatch(value)) {
          return 'Email invalide';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      decoration: InputDecoration(
        labelText: 'Mot de passe',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
      ),
      obscureText: _obscurePassword,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Veuillez entrer un mot de passe';
        }
        if (value.length < 6) {
          return 'Le mot de passe doit faire au moins 6 caractères';
        }
        return null;
      },
    );
  }

  Widget _buildConnexionButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
      ),
      onPressed: _isLoading ? null : _handleConnexion,
      child: _isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text('Connexion'),
    );
  }

  Widget _buildInscriptionLink() {
    return TextButton(
      onPressed: _isLoading ? null : () {
        Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const InscriptionPage())
        );
      },
      child: const Text('Pas de compte ? Inscrivez-vous'),
    );
  }

  void _handleConnexion() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      try {
        UserCredential userCredential = await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // Récupérer l'ID OneSignal
        final oneSignalId = OneSignal.User.pushSubscription.id;

        if (oneSignalId != null) {
          // Mettre à jour l'ID OneSignal dans Firestore
          await FirebaseFirestore.instance.collection('users').doc(userCredential.user?.uid).update({
            'oneSignalId': oneSignalId,
          });
        }

        // Sauvegarde des identifiants (optionnel et à utiliser avec précaution)
        await _storage.write(key: 'user_email', value: _emailController.text.trim());
        await _storage.write(key: 'user_password', value: _passwordController.text.trim());

        // Navigation vers la page d'accueil
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      } on FirebaseAuthException catch (e) {
        setState(() {
          _errorMessage = _getErrorMessage(e);
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _errorMessage = 'Une erreur inattendue est survenue.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> saveFcmToken() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      String? fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'fcmToken': fcmToken,
        });
      }
    }
  }

  String _getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Aucun utilisateur trouvé pour cet email.';
      case 'wrong-password':
        return 'Mot de passe incorrect.';
      case 'invalid-email':
        return 'L\'email est invalide.';
      default:
        return 'Une erreur est survenue : ${e.message}';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}