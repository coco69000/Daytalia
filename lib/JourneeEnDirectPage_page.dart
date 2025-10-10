import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'journee_model.dart';

// AJOUTÉ : Imports nécessaires pour la gestion des images
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;


class JourneeEnDirectPage extends StatefulWidget {
  final JourneeModel? journeeToEdit;

  const JourneeEnDirectPage({super.key, this.journeeToEdit});

  @override
  _JourneeEnDirectPageState createState() => _JourneeEnDirectPageState();
}

class _JourneeEnDirectPageState extends State<JourneeEnDirectPage> {
  final quill.QuillController _controller = quill.QuillController.basic();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _estPublic = false;
  bool _isLoading = false;
  late stt.SpeechToText _speech;
  bool _isListening = false;

  // AJOUTÉ : Variables d'état pour la gestion des images
  final ImagePicker _picker = ImagePicker();
  List<dynamic> _displayImages = []; // Peut contenir des XFile (nouvelles) ou des String (URLs existantes)

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    if (widget.journeeToEdit != null) {
      _controller.document = quill.Document.fromJson([
        {'insert': widget.journeeToEdit!.texte1 ?? ''}
      ]);
      // AJOUTÉ : Charger les images existantes si on édite une journée
      if (widget.journeeToEdit!.photoUrls.isNotEmpty) {
        setState(() {
          _displayImages.addAll(widget.journeeToEdit!.photoUrls);
        });
      }
    }
  }

  // AJOUTÉ : Logique pour sélectionner des images depuis la galerie
  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(imageQuality: 85);
      if (pickedFiles.isNotEmpty) {
        setState(() => _displayImages.addAll(pickedFiles));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur lors de la sélection d'images: $e")));
    }
  }

  // AJOUTÉ : Logique pour retirer une image de la sélection
  void _removeImage(int index) {
    setState(() => _displayImages.removeAt(index));
  }
// dans la classe _JourneeEnDirectPageState

  void _toggleListening() async {
    var status = await Permission.microphone.request();

    if (status.isGranted) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (errorNotification) {
          if (mounted) {
            setState(() {
              _isListening = false;
            });
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: ${errorNotification.errorMsg}')),
          );
        },
      );

      if (available) {
        if (!_isListening) {
          setState(() => _isListening = true);
          _speech.listen(
            onResult: (result) {
              // --- DÉBUT DE LA CORRECTION ---
              final selection = _controller.selection;
              final textToInsert = result.recognizedWords;

              // CORRECTION ICI : Remplacer .length par le calcul correct
              final lengthToReplace = selection.end - selection.start;

              // Utiliser .replace() avec les 3 arguments corrects
              _controller.document.replace(selection.start, lengthToReplace, textToInsert);

              // Mettre à jour la position du curseur
              _controller.updateSelection(
                TextSelection.collapsed(
                  offset: selection.start + textToInsert.length,
                ),
                quill.ChangeSource.local,
              );
              // --- FIN DE LA CORRECTION ---
            },
            localeId: 'fr_FR',
          );
        } else {
          setState(() => _isListening = false);
          _speech.stop();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La reconnaissance vocale n\'est pas disponible sur cet appareil')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission d\'accès au microphone refusée')),
      );
    }
  }

  Future<void> _enregistrerJournee() async {
    User? currentUser  = FirebaseAuth.instance.currentUser ;
    if (currentUser  == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous devez être connecté')),
      );
      return;
    }

    final texte = _controller.document.toPlainText().trim();

    if (texte.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez écrire quelque chose')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // AJOUTÉ : Logique d'upload des images
      List<String> uploadedImageUrls = [];
      for (final item in _displayImages) {
        if (item is XFile) { // Si c'est un nouveau fichier image
          final userId = currentUser.uid;
          final fileExt = p.extension(item.name);
          final fileName = '$userId/uploads/${DateTime.now().millisecondsSinceEpoch}_${p.basename(item.name)}';
          final fileBytes = await item.readAsBytes();

          final ref = FirebaseStorage.instance.ref().child('photos').child(fileName);
          final uploadTask = ref.putData(fileBytes, SettableMetadata(contentType: 'image/${fileExt.substring(1)}'));
          final snapshot = await uploadTask.whenComplete(() {});
          final imageUrl = await snapshot.ref.getDownloadURL();
          uploadedImageUrls.add(imageUrl);
        } else if (item is String) { // Si c'est une URL existante
          uploadedImageUrls.add(item);
        }
      }
      // FIN DE L'AJOUT DE LOGIQUE D'UPLOAD

      final journeeData = {
        'texte1': texte,
        'estPublic': _estPublic,
        'date': Timestamp.fromDate(DateTime.now()),
        'userId': currentUser.uid,
        'photoUrls': uploadedImageUrls, // AJOUTÉ : Sauvegarde des URLs dans Firestore
        // Les autres champs comme 'note', 'emoji' etc. sont nuls car c'est une "journée en direct"
        'note': null,
        'emoji': null,
        'commentaire': null,
      };

      if (widget.journeeToEdit != null) {
        await FirebaseFirestore.instance
            .collection('journees')
            .doc(widget.journeeToEdit!.id)
            .update(journeeData);
      } else {
        await FirebaseFirestore.instance.collection('journees').add(journeeData);
      }

      // --- MODIFICATION ICI ---
      // Au lieu de juste pop(), on renvoie `true` pour indiquer un succès.
      if (mounted) {
        Navigator.pop(context, true);
      }

      // On peut garder le SnackBar si on le souhaite, mais le pop est plus important
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Journée enregistrée avec succès'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'enregistrement : $e'), backgroundColor: Colors.red),
      );
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.journeeToEdit == null ? 'Journée en direct' : 'Modifier la journée'),
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: quill.QuillEditor.basic(
                  controller: _controller,
                  focusNode: _focusNode,
                  configurations: quill.QuillEditorConfigurations(
                      padding: const EdgeInsets.all(12),
                      placeholder: 'Écrivez votre journée ici...',
                      scrollable: true
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // AJOUTÉ : Widget pour afficher les images sélectionnées
            _buildImagePreviews(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      onPressed: _pickImages,
                      tooltip: 'Ajouter une photo',
                      color: Colors.green,
                    ),
                    IconButton(
                      onPressed: _toggleListening,
                      icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                      color: _isListening ? Colors.red : Theme.of(context).iconTheme.color,
                      tooltip: 'Dictée vocale',
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(_estPublic ? 'Public' : 'Privé'),
                    Switch(
                      value: _estPublic,
                      onChanged: (value) {
                        setState(() {
                          _estPublic = value;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _enregistrerJournee,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3,))
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  // AJOUTÉ : Widget pour construire la prévisualisation des images
  Widget _buildImagePreviews() {
    if (_displayImages.isEmpty) {
      return const SizedBox.shrink(); // Ne rien afficher si pas d'images
    }
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _displayImages.length,
        itemBuilder: (context, index) {
          final item = _displayImages[index];
          Widget imageWidget;

          if (item is XFile) {
            if (kIsWeb) {
              imageWidget = Image.network(item.path, width: 100, height: 100, fit: BoxFit.cover);
            } else {
              imageWidget = Image.file(File(item.path), width: 100, height: 100, fit: BoxFit.cover);
            }
          } else if (item is String) {
            imageWidget = Image.network(item, width: 100, height: 100, fit: BoxFit.cover);
          } else {
            imageWidget = const SizedBox.shrink();
          }

          return Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(12.0), child: imageWidget),
                GestureDetector(
                  onTap: () => _removeImage(index),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}