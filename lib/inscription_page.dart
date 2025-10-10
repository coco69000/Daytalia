import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';

class InscriptionPage extends StatefulWidget {
  const InscriptionPage({super.key});

  @override
  _InscriptionPageState createState() => _InscriptionPageState();
}

class _InscriptionPageState extends State<InscriptionPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();


  bool _isLoading = false;
  bool _isCheckingUsername = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _qualiteDeVieController = TextEditingController();

  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inscription'),
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

                _buildNameField(),
                const SizedBox(height: 15),

                _buildUsernameField(),
                const SizedBox(height: 15),

                _buildEmailField(),
                const SizedBox(height: 15),

                _buildPasswordField(),
                const SizedBox(height: 15),

                _buildConfirmPasswordField(),
                const SizedBox(height: 20),

                _buildQualiteDeVieField(), // Nouveau champ
                const SizedBox(height: 20),

                if (_errorMessage.isNotEmpty)
                  Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                  ),
                const SizedBox(height: 15),

                _buildInscriptionButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: 'Nom',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Veuillez entrer votre nom';
        }
        return null;
      },
    );
  }

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      decoration: InputDecoration(
        labelText: 'Pseudo',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.alternate_email),
        suffixIcon: _isCheckingUsername
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        )
            : null,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Veuillez entrer un pseudo';
        }
        if (value.length < 3) {
          return 'Le pseudo doit faire au moins 3 caractères';
        }
        // Vérification du format (lettres, chiffres et underscores uniquement)
        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
          return 'Le pseudo ne peut contenir que des lettres, chiffres et underscores';
        }
        // Here you can add a check for the error message if it exists
        if (_errorMessage.isNotEmpty) {
          return _errorMessage; // Return the error message if the username is taken
        }
        return null;
      },
      onChanged: (value) {
        _checkUsername(value); // Call the async check on change
      },
    );
  }

  Widget _buildQualiteDeVieField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Qualité de vie actuelle (0-100)',
          style: TextStyle(fontSize: 16),
        ),
        Slider(
          value: double.parse(_qualiteDeVieController.text.isEmpty ? '50' : _qualiteDeVieController.text),
          min: 0,
          max: 100,
          divisions: 100,
          label: _qualiteDeVieController.text.isEmpty ? '50' : _qualiteDeVieController.text,
          onChanged: (double value) {
            setState(() {
              _qualiteDeVieController.text = value.round().toString();
            });
          },
        ),
        Text(
          'Valeur actuelle : ${_qualiteDeVieController.text.isEmpty ? '50' : _qualiteDeVieController.text}',
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
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
      decoration: const InputDecoration(
        labelText: 'Mot de passe',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.lock),
      ),
      obscureText: true,
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

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      decoration: const InputDecoration(
        labelText: 'Confirmer le mot de passe',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.lock),
      ),
      obscureText: true,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Veuillez confirmer votre mot de passe';
        }
        if (value != _passwordController.text) {
          return 'Les mots de passe ne correspondent pas';
        }
        return null;
      },
    );
  }

  Widget _buildInscriptionButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
      ),
      onPressed: _isLoading ? null : _handleInscription,
      child: _isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text('S\'inscrire'),
    );
  }

  Future<void> _checkUsername(String username) async {
    if (username.length < 3) return;

    setState(() {
      _isCheckingUsername = true;
    });

    try {
      // Vérification si le pseudo existe déjà
      final usernameDoc = await _firestore
          .collection('usernames')
          .doc(username.toLowerCase())
          .get();

      if (usernameDoc.exists) {
        setState(() {
          _errorMessage = 'Ce pseudo est déjà pris';
        });
      } else {
        setState(() {
          _errorMessage = '';
        });
      }
    } catch (e) {
      print('Erreur lors de la vérification du pseudo: $e');
    } finally {
      setState(() {
        _isCheckingUsername = false;
      });
    }
  }

  void _handleInscription() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      try {
        // Vérification finale du pseudo
        final usernameDoc = await _firestore
            .collection('usernames')
            .doc(_usernameController.text.toLowerCase())
            .get();

        if (usernameDoc.exists) {
          setState(() {
            _errorMessage = 'Ce pseudo est déjà pris';
            _isLoading = false;
          });
          return;
        }

        // Création du compte
        UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // Création des documents utilisateur
        await Future.wait([
          _createUserDocument(userCredential.user),
          _reserveUsername(_usernameController.text.toLowerCase(), userCredential.user?.uid),
        ]);

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

  Future<void> _createUserDocument(User? user) async {
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'name': _nameController.text.trim(),
        'username': _usernameController.text.toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
        'qualiteDeVieActuelle': int.parse(_qualiteDeVieController.text.isEmpty ? '50' : _qualiteDeVieController.text),
        'personalizationPreferences': {
          'backgroundColor': 'blanc',
          'cardColor': 'default',
          'cardAnimation': 'default',
          'journeeCardColor': 'default',
        },
        'souvenirStyle': 'default',
        'conseilFinal': 'default',
      });
    } catch (e) {
      print('Erreur lors de la création du document utilisateur : $e');
      rethrow;
    }
  }

  Future<void> _reserveUsername(String username, String? uid) async {
    if (uid == null) return;

    try {
      await _firestore.collection('usernames').doc(username).set({
        'uid': uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Erreur lors de la réservation du pseudo : $e');
      rethrow;
    }
  }

  String _getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Un compte existe déjà avec cet email.';
      case 'invalid-email':
        return 'L\'email est invalide.';
      case 'weak-password':
        return 'Le mot de passe est trop faible.';
      default:
        return 'Une erreur est survenue : ${e.message}';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}