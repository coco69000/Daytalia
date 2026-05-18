// home_page.dart
import 'ai_model_selector.dart';
import 'profil_page.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'journee_page.dart';
import 'souvenir_page.dart';
import 'addamis_page.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:ui';
import 'profil_page.dart';
import 'dart:math';
import 'profiluser_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'JourneeEnDirectPage_page.dart';
import 'journee_model.dart';
import 'dart:async';
import 'souvenir_model.dart';
import 'souvenir_model.dart' as sm;
import 'theme_manager.dart';
import 'notification_service.dart';

const String DEEPSEEK_API_KEY = 'VOTRE_CLÉ_API_DEEPSEEK';
const int _kNonVipAutobiographyCooldownDays = 14;
const String _kApiUrl = 'https://api.deepinfra.com/v1/openai/chat/completions';
// ... Le reste du code (getUserSubscriptionData, showVipPromotionPopup, AutobiographieDialog) reste inchangé ...

Future<Map<String, dynamic>> getUserSubscriptionData() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return {
      'isVip': false,
      'lastIaUpdate': null,
      'lastAutobioUpdate': null,
      'autobioPrompt': '',
    };
  }
  try {
    final userDoc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
    if (userDoc.exists) {
      return {
        'isVip': userDoc.data()?['isVip'] ?? false,
        'lastIaAnalysisUpdate':
            userDoc.data()?['lastIaAnalysisUpdate'] as Timestamp?,
        'lastAutobiographyUpdate':
            userDoc.data()?['lastAutobiographyUpdate'] as Timestamp?,
        'autobiographyGeneralPrompt':
            userDoc.data()?['autobiographyGeneralPrompt'] ?? '',
      };
    }
  } catch (e) {
    print("Erreur de récupération des données d'abonnement: $e");
  }
  return {
    'isVip': false,
    'lastIaUpdate': null,
    'lastAutobioUpdate': null,
    'autobioPrompt': '',
  };
}

void showVipPromotionPopup(BuildContext context, String featureName) {
  showDialog(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.star, color: Colors.amber),
              SizedBox(width: 8),
              Text("Fonctionnalité Premium"),
            ],
          ),
          content: Text(
            "La fonctionnalité '$featureName' est réservée aux membres VIP. Passez à la version premium pour en profiter !",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Plus tard"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Redirection vers la page d'abonnement..."),
                  ),
                );
              },
              child: const Text("Devenir VIP"),
            ),
          ],
        ),
  );
}

enum _ContentMode { allThemes, specificThemes, custom }

class _ChapterDiff {
  /// Texte original du chapitre avant modification.
  final String originalContent;

  /// Nouveau texte proposé par l'IA (complet).
  final String newContent;

  /// Pour "Compléter" : position d'insertion + texte inséré.
  final int? insertOffset;
  final String insertedText;

  /// Pour "Mettre à jour" : texte remplacé + nouveau texte.
  final String replacedText;
  final String replacementText;

  const _ChapterDiff({
    required this.originalContent,
    required this.newContent,
    this.insertOffset,
    this.insertedText = '',
    this.replacedText = '',
    this.replacementText = '',
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 3 – DIALOG DE SÉLECTION DE THÈME
// ═══════════════════════════════════════════════════════════════════════════

class _ThemeSelectionDialog extends StatefulWidget {
  final int chapterNumber;
  final bool chapterExists;
  final bool isDarkMode;
  final List<Map<String, dynamic>> availableCategories;
  final Map<String, bool> themeHasUpdates;
  final Map<String, List<Map<String, dynamic>>> sousThemesParTheme;
  final Map<String, bool> sousThemeHasUpdates;
  final String? selectedText;
  final ScaffoldMessengerState messenger;

  final void Function({
    required _ContentMode mode,
    required Set<String> sousThemeKeys,
    required String customPrompt,
    required bool isUpdate,
  })
  onGenerate;

  final void Function({
    required _ContentMode mode,
    required Set<String> sousThemeKeys,
    required String customPrompt,
  })
  onComplete;

  final void Function({
    required String selectedText,
    required _ContentMode mode,
    required Set<String> sousThemeKeys,
    required String customPrompt,
  })
  onRewrite;

  const _ThemeSelectionDialog({
    required this.chapterNumber,
    required this.chapterExists,
    required this.isDarkMode,
    required this.availableCategories,
    required this.themeHasUpdates,
    required this.sousThemesParTheme,
    required this.sousThemeHasUpdates,
    required this.selectedText,
    required this.messenger,
    required this.onGenerate,
    required this.onComplete,
    required this.onRewrite,
  });

  @override
  State<_ThemeSelectionDialog> createState() => _ThemeSelectionDialogState();
}

class _ThemeSelectionDialogState extends State<_ThemeSelectionDialog> {
  final TextEditingController _promptCtrl = TextEditingController();
  _ContentMode _mode = _ContentMode.allThemes;
  final Set<String> _selectedSousThemes = {};
  final Set<String> _expandedThemes = {};

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  Color get _accent => widget.isDarkMode ? Colors.blue.shade300 : Colors.blue;
  Color get _bg => widget.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
  Color get _surface =>
      widget.isDarkMode ? const Color(0xFF2C2C2C) : Colors.grey.shade50;
  Color get _textPrimary => widget.isDarkMode ? Colors.white : Colors.black87;
  Color get _textSecondary =>
      widget.isDarkMode ? Colors.white60 : Colors.black54;

  Widget _modeCard({
    required _ContentMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap:
          () => setState(() {
            _mode = mode;
            if (mode != _ContentMode.specificThemes) {
              _selectedSousThemes.clear();
              _expandedThemes.clear();
            }
          }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _accent.withOpacity(0.12) : _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? _accent : _textSecondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? _accent : _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: _accent, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accent.withOpacity(0.95),
                      _accent.withOpacity(0.68),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chapitre ${widget.chapterNumber}',
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choisis le mode de génération et les thèmes associés',
                      style: TextStyle(color: _textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.68,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _accent.withOpacity(0.12)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Source du contenu',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                _modeCard(
                  mode: _ContentMode.allThemes,
                  icon: Icons.all_inclusive,
                  title: 'Tous les thèmes',
                  subtitle:
                      'Utilise tous les éléments biographiques et souvenirs',
                ),
                _modeCard(
                  mode: _ContentMode.specificThemes,
                  icon: Icons.tune,
                  title: 'Thèmes spécifiques',
                  subtitle: 'Choisissez les thèmes à inclure',
                ),
                _modeCard(
                  mode: _ContentMode.custom,
                  icon: Icons.edit_note,
                  title: 'Instruction personnalisée',
                  subtitle:
                      "L'IA sélectionne les thèmes selon votre description",
                ),
                if (_mode == _ContentMode.specificThemes) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Sélectionnez les thèmes :',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ..._buildThemeCheckboxes(),
                ],
                const SizedBox(height: 14),
                Text(
                  _mode == _ContentMode.custom
                      ? 'Décrivez le contenu souhaité *'
                      : 'Instructions supplémentaires (optionnel)',
                  style: TextStyle(
                    color:
                        _mode == _ContentMode.custom ? _accent : _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _promptCtrl,
                  maxLines: _mode == _ContentMode.custom ? 5 : 3,
                  style: TextStyle(color: _textPrimary),
                  decoration: InputDecoration(
                    hintText:
                        _mode == _ContentMode.custom
                            ? 'Ex : Parle de mes années lycée…'
                            : 'Ex : Insiste sur les moments difficiles…',
                    hintStyle: TextStyle(
                      color: _textSecondary.withOpacity(0.6),
                    ),
                    filled: true,
                    fillColor:
                        widget.isDarkMode
                            ? const Color(0xFF242424)
                            : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _accent.withOpacity(0.4)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: _textSecondary.withOpacity(0.2),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _accent, width: 1.5),
                    ),
                  ),
                ),
                if (_mode == _ContentMode.specificThemes &&
                    _selectedSousThemes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '⚠ Aucun sous-thème sélectionné → tous utilisés.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [_buildActions()],
    );
  }

  List<Widget> _buildThemeCheckboxes() {
    final widgets = <Widget>[];
    for (final cat in widget.availableCategories) {
      final themeId = cat['id'] as String;
      final themeNom = cat['nom'] as String;
      final sousThemes = widget.sousThemesParTheme[themeId] ?? [];
      final isExpanded = _expandedThemes.contains(themeId);
      final hasUpdates = widget.themeHasUpdates[themeId] ?? false;
      final allStKeys = sousThemes.map((st) => '$themeId||${st['id']}').toSet();
      final selectedCount = allStKeys.intersection(_selectedSousThemes).length;
      final isThemeChecked =
          selectedCount == allStKeys.length && allStKeys.isNotEmpty;
      final isThemeIndeterminate = selectedCount > 0 && !isThemeChecked;

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        themeNom,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (hasUpdates) _badgeNew(Colors.green),
                    if (sousThemes.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: _textSecondary,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed:
                            () => setState(
                              () =>
                                  isExpanded
                                      ? _expandedThemes.remove(themeId)
                                      : _expandedThemes.add(themeId),
                            ),
                      ),
                  ],
                ),
                value: isThemeIndeterminate ? null : isThemeChecked,
                tristate: true,
                onChanged:
                    (v) => setState(() {
                      if (v == true || v == null) {
                        _selectedSousThemes.addAll(allStKeys);
                        _expandedThemes.add(themeId);
                      } else {
                        _selectedSousThemes.removeAll(allStKeys);
                        _expandedThemes.remove(themeId);
                      }
                    }),
                activeColor: _accent,
                checkColor: Colors.white,
              ),
              if (isExpanded)
                ...sousThemes.map((st) {
                  final stKey = '$themeId||${st['id']}';
                  return Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      secondary: Icon(
                        Icons.subdirectory_arrow_right,
                        size: 14,
                        color: _textSecondary,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              st['nom'] as String,
                              style: TextStyle(
                                color: _textPrimary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (widget.sousThemeHasUpdates[stKey] ?? false)
                            _badgeNew(Colors.green.shade400),
                        ],
                      ),
                      value: _selectedSousThemes.contains(stKey),
                      onChanged:
                          (v) => setState(
                            () =>
                                v == true
                                    ? _selectedSousThemes.add(stKey)
                                    : _selectedSousThemes.remove(stKey),
                          ),
                      activeColor: _accent.withOpacity(0.8),
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _badgeNew(Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
    child: const Text(
      'Nouveau',
      style: TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _buildActions() {
    bool canProceed() {
      if (_mode == _ContentMode.custom && _promptCtrl.text.trim().isEmpty) {
        widget.messenger.showSnackBar(
          const SnackBar(
            content: Text('Veuillez écrire une instruction personnalisée.'),
          ),
        );
        return false;
      }
      return true;
    }

    Set<String> keys() =>
        _mode == _ContentMode.specificThemes
            ? Set<String>.from(_selectedSousThemes)
            : <String>{};

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        SizedBox(
          height: 44,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Annuler'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        if (widget.chapterExists)
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.expand_more, size: 18),
              label: const Text('Compléter'),
              onPressed: () {
                if (!canProceed()) return;
                Navigator.of(context).pop();
                widget.onComplete(
                  mode: _mode,
                  sousThemeKeys: keys(),
                  customPrompt: _promptCtrl.text.trim(),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.purple,
                side: BorderSide(color: Colors.purple.withOpacity(0.5)),
                backgroundColor: Colors.purple.withOpacity(0.05),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        if (widget.chapterExists)
          SizedBox(
            height: 44,
            child: Tooltip(
              message:
                  widget.selectedText == null
                      ? 'Sélectionnez du texte dans le chapitre pour activer'
                      : 'Réécrire le passage sélectionné',
              child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Mettre à jour'),
                onPressed:
                    widget.selectedText == null
                        ? null
                        : () {
                          if (!canProceed()) return;
                          Navigator.of(context).pop();
                          widget.onRewrite(
                            selectedText: widget.selectedText!,
                            mode: _mode,
                            sousThemeKeys: keys(),
                            customPrompt: _promptCtrl.text.trim(),
                          );
                        },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade500,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            icon: Icon(
              widget.chapterExists ? Icons.update_rounded : Icons.auto_fix_high,
              size: 18,
            ),
            label: Text(widget.chapterExists ? 'Régénérer' : 'Générer'),
            onPressed: () {
              if (!canProceed()) return;
              Navigator.of(context).pop();
              widget.onGenerate(
                mode: _mode,
                sousThemeKeys: keys(),
                customPrompt: _promptCtrl.text.trim(),
                isUpdate: widget.chapterExists,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              elevation: 3,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 4 – AUTOBIOGRAPHIE DIALOG (refonte complète)
// ═══════════════════════════════════════════════════════════════════════════

class AutobiographieDialog extends StatefulWidget {
  const AutobiographieDialog({Key? key}) : super(key: key);
  @override
  State<AutobiographieDialog> createState() => _AutobiographieDialogState();
}

class _AutobiographieDialogState extends State<AutobiographieDialog> {
  // ── Firebase ─────────────────────────────────────────────────────────────
  final _db = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  // ── État général ──────────────────────────────────────────────────────────
  bool _isFullScreen = false;
  bool _isLoadingChapters = true;
  bool _isLoadingCategories = true;
  bool _isLoadingUpdates = true;
  bool _isLoadingVisibility = true;
  bool _isAutobiographiePublic = true;
  bool _showThemesView = false;

  // ── Chapitres ─────────────────────────────────────────────────────────────
  Map<int, Map<String, dynamic>> _chaptersData = {};
  int? _generatingChapter;
  int? _completingChapter;
  int? _rewritingChapter;

  // ── Diff en attente (Accepter / Refuser) ──────────────────────────────────
  // clé = numéro de chapitre
  Map<int, _ChapterDiff> _pendingDiffs = {};

  // ── Edition manuelle ──────────────────────────────────────────────────────
  Map<int, bool> _editModes = {};
  Map<int, TextEditingController> _editControllers = {};
  // Images insérées en édition manuelle : liste d'URLs (Firebase Storage ou réseau)
  Map<int, List<String>> _editImages = {};

  // ── Sélection de texte ────────────────────────────────────────────────────
  Map<int, String> _selectedTextByChapter = {};

  // ── Thèmes biographiques ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _availableCategories = [];
  Map<String, String> _categoryNames = {};
  Map<String, bool> _themeHasUpdates = {};
  Map<String, bool> _sousThemeHasUpdates = {};
  Map<String, List<Map<String, dynamic>>> _sousThemesParTheme = {};

  // ── VIP ───────────────────────────────────────────────────────────────────
  bool _isVip = false;
  bool _canUpdate = false;
  DateTime? _lastAutobioUpdate;

  // ═════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    if (_user != null)
      _init();
    else
      setState(() {
        _isLoadingChapters = false;
        _isLoadingCategories = false;
        _isLoadingUpdates = false;
        _isLoadingVisibility = false;
      });
  }

  @override
  void dispose() {
    for (final c in _editControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await Future.wait([_loadVipData(), _loadVisibility()]);
    await _loadCategories();
    await Future.wait([_loadChapters(), _checkThemesForUpdates()]);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CHARGEMENT
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _loadVipData() async {
    if (_user == null) return;
    try {
      final doc = await _db.collection('users').doc(_user!.uid).get();
      final data = doc.data() ?? {};
      if (!mounted) return;
      setState(() {
        _isVip = data['isVip'] ?? false;
        final ts = data['lastAutobiographyUpdate'] as Timestamp?;
        _lastAutobioUpdate = ts?.toDate();
        _canUpdate =
            _isVip ||
            _lastAutobioUpdate == null ||
            DateTime.now().difference(_lastAutobioUpdate!).inDays >=
                _kNonVipAutobiographyCooldownDays;
      });
    } catch (e) {
      debugPrint('[AUTOBIO] _loadVipData erreur: $e');
    }
  }

  Future<void> _loadVisibility() async {
    if (_user == null) return;
    try {
      final doc = await _db.collection('users').doc(_user!.uid).get();
      if (!mounted) return;
      setState(() {
        _isAutobiographiePublic = doc.data()?['isAutobiographiePublic'] ?? true;
        _isLoadingVisibility = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingVisibility = false);
    }
  }

  Future<void> _toggleVisibility(bool v) async {
    if (_user == null) return;
    setState(() => _isAutobiographiePublic = v);
    try {
      await _db.collection('users').doc(_user!.uid).set({
        'isAutobiographiePublic': v,
      }, SetOptions(merge: true));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Visibilité mise à jour.'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _loadCategories() async {
    if (_user == null) return;
    try {
      final snap =
          await _db
              .collection('users')
              .doc(_user!.uid)
              .collection('themes_biographiques')
              .get();
      final cats = <Map<String, dynamic>>[];
      final stMap = <String, List<Map<String, dynamic>>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final nom = data['nom'] as String? ?? doc.id;
        _categoryNames[doc.id] = nom;
        cats.add({'id': doc.id, 'nom': nom});
        try {
          final stSnap = await doc.reference.collection('sous_themes').get();
          stMap[doc.id] =
              stSnap.docs
                  .map(
                    (st) => {
                      'id': st.id,
                      'nom': st.data()['nom'] as String? ?? st.id,
                    },
                  )
                  .toList();
        } catch (_) {
          stMap[doc.id] = [];
        }
      }
      if (mounted)
        setState(() {
          _availableCategories = cats;
          _sousThemesParTheme = stMap;
          _isLoadingCategories = false;
        });
    } catch (e) {
      debugPrint('[AUTOBIO] _loadCategories erreur: $e');
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _checkThemesForUpdates() async {
    if (_user == null || _availableCategories.isEmpty) {
      if (mounted) setState(() => _isLoadingUpdates = false);
      return;
    }
    final themeUpd = <String, bool>{};
    final stUpd = <String, bool>{};
    for (final cat in _availableCategories) {
      final themeId = cat['id'] as String;
      bool hasNew = false;
      try {
        final stSnap =
            await _db
                .collection('users')
                .doc(_user!.uid)
                .collection('themes_biographiques')
                .doc(themeId)
                .collection('sous_themes')
                .get();
        for (final st in stSnap.docs) {
          final extraits =
              await st.reference
                  .collection('extraits')
                  .where('lastAnalyzedAutobiographie', isEqualTo: null)
                  .limit(1)
                  .get();
          final has = extraits.docs.isNotEmpty;
          stUpd['$themeId||${st.id}'] = has;
          if (has) hasNew = true;
        }
      } catch (_) {}
      themeUpd[themeId] = hasNew;
    }
    if (mounted)
      setState(() {
        _themeHasUpdates = themeUpd;
        _sousThemeHasUpdates = stUpd;
        _isLoadingUpdates = false;
      });
  }

  Future<void> _loadChapters() async {
    if (_user == null) return;
    try {
      final snap =
          await _db
              .collection('users')
              .doc(_user!.uid)
              .collection('chapters')
              .get();
      final loaded = <int, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data.containsKey('number')) loaded[data['number'] as int] = data;
      }
      if (mounted)
        setState(() {
          _chaptersData = loaded;
          _isLoadingChapters = false;
        });
    } catch (e) {
      debugPrint('[AUTOBIO] _loadChapters erreur: $e');
      if (mounted) setState(() => _isLoadingChapters = false);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SÉLECTION IA DES SOUS-THÈMES
  // ═════════════════════════════════════════════════════════════════════════

  Future<Set<String>?> _smartSelectSousThemes(String instruction) async {
    if (_sousThemesParTheme.isEmpty) return null;
    final lines = <String>[];
    _sousThemesParTheme.forEach((themeId, sousThemes) {
      final themeName = _categoryNames[themeId] ?? themeId;
      for (final st in sousThemes)
        lines.add('"$themeId||${st['id']}": "$themeName > ${st['nom']}"');
    });
    if (lines.isEmpty) return null;
    try {
      final resp = await http.post(
        Uri.parse(_kApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': await resolveAiModel(isVip: _isVip),
          'max_tokens': 400,
          'messages': [
            {
              'role': 'system',
              'content':
                  'Réponds UNIQUEMENT avec du JSON valide. Format: {"ids": ["themeId1||sousThemeId1", ...]}',
            },
            {
              'role': 'user',
              'content':
                  'Instruction: "$instruction"\n\nThèmes:\n${lines.join('\n')}\n\nSélectionne les plus pertinents. Réponds: {"ids": [...]}',
            },
          ],
        }),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final raw = (data['choices'][0]['message']['content'] as String).trim();
        Map<String, dynamic>? parsed;
        try {
          parsed = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          final m = RegExp(r'\{[\s\S]*\}', dotAll: true).firstMatch(raw);
          if (m != null)
            try {
              parsed = jsonDecode(m.group(0)!) as Map<String, dynamic>;
            } catch (_) {}
        }
        if (parsed != null && parsed['ids'] is List) {
          final ids =
              (parsed['ids'] as List)
                  .cast<String>()
                  .where((k) => k.contains('||'))
                  .toSet();
          if (ids.isNotEmpty) return ids;
        }
      }
    } catch (e) {
      debugPrint('[AUTOBIO] _smartSelectSousThemes erreur: $e');
    }
    return null;
  }

  Future<Set<String>?> _resolveEffectiveKeys({
    required _ContentMode mode,
    required Set<String> sousThemeKeys,
    required String customPrompt,
  }) async {
    switch (mode) {
      case _ContentMode.allThemes:
        return null;
      case _ContentMode.specificThemes:
        return sousThemeKeys.isEmpty ? null : sousThemeKeys;
      case _ContentMode.custom:
        if (customPrompt.isEmpty) return null;
        return await _smartSelectSousThemes(customPrompt);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RÉCUPÉRATION DES ÉLÉMENTS
  // ═════════════════════════════════════════════════════════════════════════

  Future<_FetchResult> _fetchElements({
    required Set<String>? effectiveKeys,
    required bool onlyNew,
  }) async {
    if (_user == null) return _FetchResult([], []);
    final elements = <Map<String, dynamic>>[];
    final refs = <DocumentReference>[];
    Map<String, Set<String>>? themeFilter;
    if (effectiveKeys != null) {
      themeFilter = {};
      for (final key in effectiveKeys) {
        final parts = key.split('||');
        if (parts.length == 2) (themeFilter[parts[0]] ??= {}).add(parts[1]);
      }
    }
    final themesRef = _db
        .collection('users')
        .doc(_user!.uid)
        .collection('themes_biographiques');
    final List<DocumentSnapshot> themeDocs;
    if (themeFilter == null) {
      themeDocs = (await themesRef.get()).docs;
    } else {
      final futures =
          themeFilter.keys.map((id) => themesRef.doc(id).get()).toList();
      themeDocs = (await Future.wait(futures)).where((d) => d.exists).toList();
    }
    for (final themeDoc in themeDocs) {
      final themeData = themeDoc.data() as Map<String, dynamic>? ?? {};
      final themeNom = themeData['nom'] as String? ?? themeDoc.id;
      final allowedSousThemes = themeFilter?[themeDoc.id];
      final stSnap = await themeDoc.reference.collection('sous_themes').get();
      for (final stDoc in stSnap.docs) {
        if (allowedSousThemes != null && !allowedSousThemes.contains(stDoc.id))
          continue;
        final stData = stDoc.data() as Map<String, dynamic>? ?? {};
        final stNom = stData['nom'] as String? ?? stDoc.id;
        Query q = stDoc.reference.collection('extraits');
        if (onlyNew) q = q.where('lastAnalyzedAutobiographie', isEqualTo: null);
        final extraitsSnap = await q.get();
        for (final extraitDoc in extraitsSnap.docs) {
          final data = extraitDoc.data() as Map<String, dynamic>? ?? {};
          final texte = data['texte'] as String? ?? '';
          if (texte.isEmpty) continue;
          elements.add({
            'texte': texte,
            'label': '[$themeNom — $stNom]',
            'date':
                data['date'] is Timestamp
                    ? (data['date'] as Timestamp).toDate()
                    : DateTime.now(),
          });
          refs.add(extraitDoc.reference);
        }
      }
    }
    if (effectiveKeys == null) {
      try {
        final souvenirSnap =
            await _db
                .collection('souvenirs')
                .where('userId', isEqualTo: _user!.uid)
                .get();
        for (final doc in souvenirSnap.docs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final texte = data['texte'] as String? ?? '';
          if (texte.isEmpty) continue;
          String qualLabel;
          switch (data['qualite'] as String? ?? '') {
            case 'SouvenirQualite.nostalgie':
              qualLabel = 'Nostalgie';
              break;
            case 'SouvenirQualite.jamaisOublie':
              qualLabel = 'Jamais oublié';
              break;
            case 'SouvenirQualite.bonheur':
              qualLabel = 'Bonheur';
              break;
            default:
              qualLabel = 'Souvenir';
          }
          elements.add({
            'texte': texte,
            'label': '[Souvenir — $qualLabel]',
            'date':
                data['date'] is Timestamp
                    ? (data['date'] as Timestamp).toDate()
                    : DateTime.now(),
          });
        }
      } catch (e) {
        debugPrint('[AUTOBIO] Souvenirs erreur: $e');
      }
    }
    elements.sort(
      (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
    );
    return _FetchResult(elements, refs);
  }

  String _formatElementsForPrompt(List<Map<String, dynamic>> elements) {
    return elements
        .map((e) {
          final dateStr = DateFormat(
            'dd/MM/yyyy',
          ).format(e['date'] as DateTime);
          return '- [$dateStr] ${e['texte']} ${e['label']}';
        })
        .join('\n');
  }

  // ═════════════════════════════════════════════════════════════════════════
  // APPEL API – TEXTE PUR (pas de balises image)
  // ═════════════════════════════════════════════════════════════════════════

  Future<String> _callGenerationApi({
    required int chapterNumber,
    required String formattedElements,
    required String previousChapterContent,
    String? existingContent,
    required String customPrompt,
  }) async {
    final isUpdate = existingContent != null && existingContent.isNotEmpty;
    final customSection =
        customPrompt.isNotEmpty
            ? '\n\n**INSTRUCTION SPÉCIFIQUE (PRIORITÉ ABSOLUE) :**\n"$customPrompt"\nTu DOIS obéir à cette instruction.'
            : '';
    final existingSection =
        isUpdate
            ? '\n\n**Version actuelle du Chapitre $chapterNumber :**\n$existingContent'
            : '';

    final prompt = '''
Tu es un écrivain et biographe talentueux de langue maternelle FRANÇAISE.
Rédige un chapitre d\'autobiographie de manière engageante, fluide et émotive, à la première personne ("je").
 
**IL EST IMPÉRATIF QUE TA RÉPONSE SOIT EXCLUSIVEMENT EN FRANÇAIS.**
**Produis UNIQUEMENT du texte narratif. PAS de balises, PAS de marqueurs spéciaux, PAS d\'URLs.**
 
**Éléments de vie à intégrer :**
$formattedElements
 
**Contexte chapitre précédent (Chapitre ${chapterNumber - 1}) :**
${previousChapterContent.isEmpty ? "Premier chapitre." : previousChapterContent}
$existingSection$customSection
 
**Instructions :**
- **Tâche :** ${isUpdate ? "Mets à jour et enrichis ce chapitre avec les nouveaux éléments." : "Écris"} le **Chapitre $chapterNumber**.
- **Style :** Narratif, personnel, à la première personne ("je"). Cohérent avec le contexte précédent.
- **Format :** Produis uniquement le texte du chapitre, sans titre ni commentaire. Texte pur uniquement.
''';

    final resp = await http.post(
      Uri.parse(_kApiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $DEEPSEEK_API_KEY',
      },
      body: jsonEncode({
        'model': await resolveAiModel(isVip: _isVip),
        'max_tokens': 4000,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      }),
    );

    if (resp.statusCode != 200)
      throw Exception('Erreur API ${resp.statusCode}: ${resp.body}');
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    return (data['choices'][0]['message']['content'] as String).trim();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ACTION : GÉNÉRER / RÉGÉNÉRER
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _generateChapter({
    required int chapterNumber,
    required _ContentMode mode,
    required Set<String> sousThemeKeys,
    required String customPrompt,
    required bool isUpdate,
  }) async {
    if (_user == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _generatingChapter = chapterNumber;
      _pendingDiffs.remove(chapterNumber);
    });
    try {
      final effectiveKeys = await _resolveEffectiveKeys(
        mode: mode,
        sousThemeKeys: sousThemeKeys,
        customPrompt: customPrompt,
      );
      final fetchResult = await _fetchElements(
        effectiveKeys: effectiveKeys,
        onlyNew: isUpdate,
      );
      if (!mounted) return;
      if (fetchResult.elements.isEmpty && customPrompt.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isUpdate ? 'Aucun nouvel élément.' : 'Aucun élément trouvé.',
            ),
          ),
        );
        setState(() => _generatingChapter = null);
        return;
      }
      final formattedElements = _formatElementsForPrompt(fetchResult.elements);
      final previousContent =
          _chaptersData[chapterNumber - 1]?['content'] as String? ?? '';
      final existingContent =
          isUpdate
              ? (_chaptersData[chapterNumber]?['content'] as String?)
              : null;
      final newContent = await _callGenerationApi(
        chapterNumber: chapterNumber,
        formattedElements: formattedElements,
        previousChapterContent: previousContent,
        existingContent: existingContent,
        customPrompt: customPrompt,
      );
      if (!mounted) return;
      // Régénération → pas de diff, on enregistre directement
      final chapterDoc = {
        'number': chapterNumber,
        'content': newContent,
        'themesUsed': effectiveKeys?.toList() ?? ['all'],
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      await _db
          .collection('users')
          .doc(_user!.uid)
          .collection('chapters')
          .doc('chapter_$chapterNumber')
          .set(chapterDoc, SetOptions(merge: true));
      if (fetchResult.refs.isNotEmpty) {
        final batch = _db.batch();
        for (final ref in fetchResult.refs)
          batch.update(ref, {'lastAnalyzedAutobiographie': Timestamp.now()});
        await batch.commit();
      }
      if (!_isVip) {
        await _db.collection('users').doc(_user!.uid).set({
          'lastAutobiographyUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await _loadVipData();
      }
      if (mounted) {
        setState(
          () =>
              _chaptersData[chapterNumber] = {
                ...chapterDoc,
                'lastUpdated': Timestamp.now(),
              },
        );
        _checkThemesForUpdates();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Chapitre $chapterNumber ${isUpdate ? "mis à jour" : "généré"} !',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        messenger.showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _generatingChapter = null);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ACTION : COMPLÉTER (ajout de texte, proposé avant acceptation)
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _completeChapter({
    required int chapterNumber,
    required _ContentMode mode,
    required Set<String> sousThemeKeys,
    required String customPrompt,
  }) async {
    if (_user == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _completingChapter = chapterNumber;
      _pendingDiffs.remove(chapterNumber);
    });

    try {
      final existingContent =
          _chaptersData[chapterNumber]?['content'] as String? ?? '';
      final effectiveKeys = await _resolveEffectiveKeys(
        mode: mode,
        sousThemeKeys: sousThemeKeys,
        customPrompt: customPrompt,
      );
      final fetchResult = await _fetchElements(
        effectiveKeys: effectiveKeys,
        onlyNew: false,
      );
      final instrPart =
          customPrompt.isNotEmpty
              ? '\n\n**INSTRUCTION SPÉCIFIQUE :**\n"$customPrompt"'
              : '';
      final elemCtx =
          fetchResult.elements.isNotEmpty
              ? '\n\n**Éléments à intégrer :**\n${_formatElementsForPrompt(fetchResult.elements)}'
              : '';

      final prompt = '''
Tu es un écrivain biographe.

Voici le Chapitre $chapterNumber actuel :
"""
$existingContent
"""

**MISSION :** Écris un ajout de 2 à 5 paragraphes en FRANÇAIS, à la première personne ("je").
Tu dois LIRE le chapitre actuel et CHOISIR le meilleur endroit chronologique ou thématique pour insérer cet ajout (ça peut être au milieu, entre deux paragraphes, ou à la toute fin).
$elemCtx$instrPart

RÉPONDS STRICTEMENT AVEC CE FORMAT EXACT (utilise bien les balises) :

[ANCRAGE]
Copie-colle ici EXACTEMENT 5 à 10 mots du texte original juste APRÈS lesquels je dois insérer le nouveau texte. Ne change AUCUNE lettre, AUCUNE ponctuation.
⚠️ RÈGLE ABSOLUE : Cet ancrage DOIT se terminer par un point (.), un point d'exclamation (!) ou un point d'interrogation (?). Ne coupe JAMAIS une phrase en plein milieu.
(Si tu veux que l'ajout se fasse tout à la fin du chapitre, écris simplement "FIN").
[NOUVEAU_TEXTE]
(Rédige ton nouveau texte ici, sans guillemets ni commentaires).
''';

      debugPrint('⏳ Envoi de la requête à l\'IA...');

      final resp = await http.post(
        Uri.parse(_kApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': await resolveAiModel(isVip: _isVip),
          'max_tokens': 2000,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      if (resp.statusCode != 200)
        throw Exception('Erreur API ${resp.statusCode}');
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final raw = (data['choices'][0]['message']['content'] as String).trim();

      debugPrint('\n========== LOGS IA ==========');
      debugPrint('📝 RÉPONSE BRUTE DE L\'IA :\n$raw\n');

      String anchor = "FIN";
      String newText = raw;

      if (raw.contains('[ANCRAGE]') && raw.contains('[NOUVEAU_TEXTE]')) {
        final startAnchor = raw.indexOf('[ANCRAGE]') + '[ANCRAGE]'.length;
        final endAnchor = raw.indexOf('[NOUVEAU_TEXTE]');
        final startText = endAnchor + '[NOUVEAU_TEXTE]'.length;

        // On nettoie l'ancrage au cas où l'IA a mis des sauts de ligne dedans
        anchor =
            raw.substring(startAnchor, endAnchor).replaceAll('\n', ' ').trim();
        newText = raw.substring(startText).trim();
      }

      debugPrint('🎯 ANCRAGE EXTRAIT : "$anchor"');

      // ─── FONCTION DE RECHERCHE TOLÉRANTE (FUZZY MATCH) ───
      int findInsertionIndex(String text, String searchAnchor) {
        if (searchAnchor == 'FIN') return text.length;

        String cleanAnchor = searchAnchor.trim();
        if (text.contains(cleanAnchor))
          return text.indexOf(cleanAnchor) + cleanAnchor.length;

        // Si la phrase exacte n'est pas trouvée (ex: l'IA a ajouté un mot au début),
        // on coupe l'ancrage mot par mot en partant du début, et on cherche la fin.
        List<String> words = cleanAnchor.split(RegExp(r'\s+'));

        // On exige au moins 3 mots correspondants pour éviter de couper n'importe où
        for (int i = 0; i <= words.length - 3; i++) {
          String subAnchor = words.sublist(i).join(' ');

          // Recherche exacte du morceau
          if (text.contains(subAnchor))
            return text.indexOf(subAnchor) + subAnchor.length;

          // Recherche en forçant la première lettre en minuscule
          String lower = subAnchor[0].toLowerCase() + subAnchor.substring(1);
          if (text.contains(lower)) return text.indexOf(lower) + lower.length;

          // Recherche en forçant la première lettre en majuscule
          String upper = subAnchor[0].toUpperCase() + subAnchor.substring(1);
          if (text.contains(upper)) return text.indexOf(upper) + upper.length;
        }

        return -1; // Vraiment introuvable
      }
      // ────────────────────────────────────────────────────────

      if (newText.isEmpty) throw Exception("L'IA n'a généré aucun texte.");

      String newContent;
      int insertPos =
          existingContent.isEmpty
              ? 0
              : findInsertionIndex(existingContent, anchor);

      debugPrint('🔎 INDEX D\'INSERTION TROUVÉ : $insertPos');
      debugPrint('=============================\n');

      if (insertPos == -1) {
        debugPrint(
          '⚠️ ATTENTION : L\'ancrage n\'a pas été trouvé du tout. Fallback -> ajout à la fin.',
        );
        insertPos = existingContent.length;
        newContent =
            existingContent.isEmpty ? newText : '$existingContent\n\n$newText';
      } else if (insertPos == existingContent.length) {
        debugPrint('✅ Ajout à la fin demandé ou calculé.');
        newContent =
            existingContent.isEmpty ? newText : '$existingContent\n\n$newText';
      } else {
        debugPrint(
          '✅ SUCCÈS : Ancrage trouvé ! Découpage du texte en plein milieu...',
        );
        final before = existingContent.substring(0, insertPos).trimRight();
        final after = existingContent.substring(insertPos).trimLeft();

        // On insère le nouveau texte au milieu proprement
        newContent = '$before\n\n$newText\n\n$after';
      }

      if (mounted)
        setState(() {
          _pendingDiffs[chapterNumber] = _ChapterDiff(
            originalContent: existingContent,
            newContent: newContent,
            insertOffset: insertPos,
            insertedText: newText,
          );
        });
    } catch (e) {
      if (mounted)
        messenger.showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _completingChapter = null);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ACTION : RÉÉCRIRE UN PASSAGE SÉLECTIONNÉ
  // ═════════════════════════════════════════════════════════════════════════

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<void> _rewriteSelection({
    required int chapterNumber,
    required String selectedText,
    required _ContentMode mode,
    required Set<String> sousThemeKeys,
    required String customPrompt,
  }) async {
    if (_user == null) return;
    setState(() {
      _rewritingChapter = chapterNumber;
      _pendingDiffs.remove(chapterNumber);
    });

    // MODIFICATION : J'ai supprimé le showDialog(...) bloquant qui prenait toute la page

    try {
      final existingContent =
          _chaptersData[chapterNumber]?['content'] as String? ?? '';
      final rawIdx = existingContent.indexOf(selectedText);
      if (rawIdx == -1)
        throw Exception('Passage introuvable. Veuillez resélectionner.');

      final effectiveKeys = await _resolveEffectiveKeys(
        mode: mode,
        sousThemeKeys: sousThemeKeys,
        customPrompt: customPrompt,
      );
      final fetchResult = await _fetchElements(
        effectiveKeys: effectiveKeys,
        onlyNew: false,
      );
      final elemCtx =
          fetchResult.elements.isNotEmpty
              ? '\n\n**Éléments de vie à intégrer :**\n${_formatElementsForPrompt(fetchResult.elements)}'
              : '';
      final instrLine =
          customPrompt.isNotEmpty
              ? '\n\n**INSTRUCTION SPÉCIFIQUE :**\n"$customPrompt"'
              : '';

      final ctxStart = (rawIdx - 300).clamp(0, existingContent.length);
      final ctxEnd = (rawIdx + selectedText.length + 300).clamp(
        0,
        existingContent.length,
      );
      final ctxBefore = existingContent.substring(ctxStart, rawIdx).trim();
      final ctxAfter =
          existingContent
              .substring(rawIdx + selectedText.length, ctxEnd)
              .trim();

      final systemMsg =
          'Tu es un écrivain biographe en français. Réécris UNIQUEMENT le passage indiqué, à la première personne ("je"), en FRANÇAIS. Produis un texte NOUVEAU et ENRICHI. Réponds UNIQUEMENT avec le nouveau texte réécrit. Texte pur, pas de balises.';
      final userMsg =
          'Réécris et enrichis ce passage en FRANÇAIS :\n"$selectedText"\n\nContexte avant :\n$ctxBefore\n\nContexte après :\n$ctxAfter\n\nRédige UNIQUEMENT la réécriture.$elemCtx$instrLine';

      String? replacement;
      final temps = [0.4, 0.7, 1.0];
      for (int attempt = 0; attempt < temps.length; attempt++) {
        final resp = await http.post(
          Uri.parse(_kApiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $DEEPSEEK_API_KEY',
          },
          body: jsonEncode({
            'model': await resolveAiModel(isVip: _isVip),
            'max_tokens': 2000,
            'temperature': temps[attempt],
            'messages': [
              {'role': 'system', 'content': systemMsg},
              {'role': 'user', 'content': userMsg},
            ],
          }),
        );
        if (resp.statusCode != 200)
          throw Exception('Erreur API ${resp.statusCode}');
        final respData = jsonDecode(utf8.decode(resp.bodyBytes));
        final candidate =
            (respData['choices'][0]['message']['content'] as String).trim();
        final tooShort =
            candidate.length <
            (selectedText.length * 0.1).round().clamp(20, 80);
        final isCopy = _norm(candidate) == _norm(selectedText);
        if (!tooShort && !isCopy) {
          replacement = candidate;
          break;
        }
      }
      if (replacement == null)
        throw Exception('Réécriture invalide après 3 tentatives.');

      final newContent =
          existingContent.substring(0, rawIdx) +
          replacement +
          existingContent.substring(rawIdx + selectedText.length);

      if (mounted) {
        setState(() {
          _pendingDiffs[chapterNumber] = _ChapterDiff(
            originalContent: existingContent,
            newContent: newContent,
            replacedText: selectedText,
            replacementText: replacement!,
          );
          _selectedTextByChapter.remove(chapterNumber);
        });
        // MODIFICATION : J'ai retiré le Navigator.pop() car il n'y a plus de dialog à fermer
      }
    } catch (e) {
      if (mounted) {
        // MODIFICATION : J'ai retiré le Navigator.pop() ici aussi
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _rewritingChapter = null);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ACCEPTER / REFUSER LE DIFF
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _acceptDiff(int chapterNumber) async {
    final diff = _pendingDiffs[chapterNumber];
    if (diff == null || _user == null) return;
    try {
      await _db
          .collection('users')
          .doc(_user!.uid)
          .collection('chapters')
          .doc('chapter_$chapterNumber')
          .set({
            'content': diff.newContent,
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (!_isVip) {
        await _db.collection('users').doc(_user!.uid).set({
          'lastAutobiographyUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await _loadVipData();
      }
      if (mounted) {
        setState(() {
          _chaptersData[chapterNumber] = {
            ...(_chaptersData[chapterNumber] ?? {}),
            'content': diff.newContent,
          };
          _pendingDiffs.remove(chapterNumber);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Modification acceptée !'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
    }
  }

  void _rejectDiff(int chapterNumber) {
    setState(() => _pendingDiffs.remove(chapterNumber));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Modification annulée.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // OUVERTURE DU DIALOG DE SÉLECTION DE THÈMES
  // ═════════════════════════════════════════════════════════════════════════

  void _openThemeDialog(int chapterNumber, {String? selectedText}) {
    showDialog(
      context: context,
      builder:
          (ctx) => _ThemeSelectionDialog(
            chapterNumber: chapterNumber,
            chapterExists: _chaptersData.containsKey(chapterNumber),
            isDarkMode: Theme.of(context).brightness == Brightness.dark,
            availableCategories: _availableCategories,
            themeHasUpdates: _themeHasUpdates,
            sousThemesParTheme: _sousThemesParTheme,
            sousThemeHasUpdates: _sousThemeHasUpdates,
            selectedText: selectedText,
            messenger: ScaffoldMessenger.of(context),
            onGenerate:
                ({
                  required mode,
                  required sousThemeKeys,
                  required customPrompt,
                  required isUpdate,
                }) => _generateChapter(
                  chapterNumber: chapterNumber,
                  mode: mode,
                  sousThemeKeys: sousThemeKeys,
                  customPrompt: customPrompt,
                  isUpdate: isUpdate,
                ),
            onComplete:
                ({
                  required mode,
                  required sousThemeKeys,
                  required customPrompt,
                }) => _completeChapter(
                  chapterNumber: chapterNumber,
                  mode: mode,
                  sousThemeKeys: sousThemeKeys,
                  customPrompt: customPrompt,
                ),
            onRewrite:
                ({
                  required selectedText,
                  required mode,
                  required sousThemeKeys,
                  required customPrompt,
                }) => _rewriteSelection(
                  chapterNumber: chapterNumber,
                  selectedText: selectedText,
                  mode: mode,
                  sousThemeKeys: sousThemeKeys,
                  customPrompt: customPrompt,
                ),
          ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // INSERTION DE TAG IMAGE AU CURSEUR
  // ═════════════════════════════════════════════════════════════════════════

  void _insertImageTagInText(int chapterNumber, String url) {
    final controller = _editControllers[chapterNumber];
    if (controller == null) return;

    final tag = '\n\n[IMAGE:$url]\n\n';
    final text = controller.text;
    final selection = controller.selection;

    if (selection.isValid && selection.start >= 0) {
      // Insère la balise là où se trouve le curseur
      final newText = text.replaceRange(selection.start, selection.end, tag);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + tag.length,
        ),
      );
    } else {
      // Si le curseur n'est pas placé, on ajoute à la fin
      controller.text = text + tag;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // UPLOAD D'IMAGE (édition manuelle)
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _pickAndUploadImage(int chapterNumber) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Galerie'),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Appareil photo'),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud),
                  title: const Text('Depuis Firebase (souvenirs/journées)'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickFirebaseImage(chapterNumber);
                  },
                ),
              ],
            ),
          ),
    );
    if (source == null) return;
    final XFile? file = await picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (file == null) return;
    try {
      final ref = FirebaseStorage.instance.ref().child(
        'autobio_images/${_user!.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ref.putFile(File(file.path));
      final url = await ref.getDownloadURL();
      _insertImageTagInText(chapterNumber, url);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _pickFirebaseImage(int chapterNumber) async {
    if (_user == null) return;
    // Récupérer toutes les URLs photos des journées et souvenirs de l'utilisateur
    final List<String> allUrls = [];
    try {
      final jSnap =
          await _db
              .collection('journees')
              .where('userId', isEqualTo: _user!.uid)
              .get();
      for (final doc in jSnap.docs) {
        final urls = doc.data()['photoUrls'];
        if (urls is List) allUrls.addAll(List<String>.from(urls));
      }
      final sSnap =
          await _db
              .collection('souvenirs')
              .where('userId', isEqualTo: _user!.uid)
              .get();
      for (final doc in sSnap.docs) {
        final urls = doc.data()['photoUrls'];
        if (urls is List) allUrls.addAll(List<String>.from(urls));
      }
    } catch (_) {}

    if (!mounted) return;
    if (allUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune photo trouvée dans Firebase.')),
      );
      return;
    }

    final String? selected = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Choisir une photo'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: allUrls.length,
                itemBuilder:
                    (_, i) => GestureDetector(
                      onTap: () => Navigator.pop(ctx, allUrls[i]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          allUrls[i],
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => const Icon(Icons.broken_image),
                        ),
                      ),
                    ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
            ],
          ),
    );
    if (selected != null && mounted) {
      _insertImageTagInText(chapterNumber, selected);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD PRINCIPAL
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;

    return Dialog(
      shape:
          _isFullScreen
              ? const RoundedRectangleBorder()
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      backgroundColor: Colors.transparent,
      insetPadding:
          _isFullScreen
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth:
              _isFullScreen
                  ? MediaQuery.of(context).size.width
                  : MediaQuery.of(context).size.width * 0.9,
          maxHeight:
              _isFullScreen
                  ? MediaQuery.of(context).size.height
                  : MediaQuery.of(context).size.height * 0.85,
        ),
        padding:
            _isFullScreen
                ? const EdgeInsets.symmetric(horizontal: 20, vertical: 16)
                : const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius:
              _isFullScreen ? BorderRadius.zero : BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildHeader(isDark),
            Divider(
              height: 24,
              color: isDark ? Colors.blue.shade700 : Colors.blueAccent,
            ),
            Expanded(
              child:
                  (_isLoadingChapters || _isLoadingCategories)
                      ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue,
                          ),
                        ),
                      )
                      : (_showThemesView
                          ? _buildThemesView(isDark)
                          : _buildChapterList(isDark)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark) {
    final tc = isDark ? Colors.blue.shade300 : Colors.blue;
    final ic = isDark ? Colors.blue.shade400 : Colors.blue[700];
    final closeColor = isDark ? Colors.red.shade300 : Colors.redAccent;
    final secondary = isDark ? Colors.grey[400] : Colors.grey;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.auto_stories, color: ic, size: 28),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Mon Autobiographie',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: tc,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                _isFullScreen ? Icons.close_fullscreen : Icons.open_in_full,
                color: ic,
              ),
              onPressed: () => setState(() => _isFullScreen = !_isFullScreen),
            ),
            IconButton(
              icon: Icon(Icons.close, color: closeColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _isLoadingVisibility
            ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
            : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Privé',
                  style: TextStyle(
                    color: _isAutobiographiePublic ? secondary : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: _isAutobiographiePublic,
                  onChanged: _toggleVisibility,
                  activeColor: Colors.green,
                  inactiveThumbColor: Colors.red,
                ),
                Text(
                  'Public',
                  style: TextStyle(
                    color: _isAutobiographiePublic ? Colors.green : secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _viewTab(
              Icons.auto_stories,
              'Chapitres',
              !_showThemesView,
              isDark,
              () => setState(() => _showThemesView = false),
            ),
            const SizedBox(width: 8),
            _viewTab(
              Icons.account_tree,
              'Thèmes',
              _showThemesView,
              isDark,
              () => setState(() => _showThemesView = true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _viewTab(
    IconData icon,
    String label,
    bool selected,
    bool isDark,
    VoidCallback onTap,
  ) {
    final sel = isDark ? Colors.blue.shade300 : Colors.blue;
    final unsel = isDark ? Colors.grey.shade600 : Colors.grey.shade400;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color:
              selected
                  ? (isDark
                      ? Colors.blue.shade900.withOpacity(0.4)
                      : Colors.blue.shade50)
                  : Colors.transparent,
          border: Border.all(color: selected ? sel : unsel),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? sel : unsel),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? sel : unsel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Vue thèmes ────────────────────────────────────────────────────────────

  Widget _buildThemesView(bool isDark) {
    if (_availableCategories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 56,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              'Aucun thème biographique',
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Écris des journées pour que l'IA crée\nautomatiquement ton arborescence.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    final titleColor = isDark ? Colors.blue.shade300 : Colors.blue;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final cardColor = isDark ? Colors.grey[800] : Colors.white;

    return ListView.builder(
      itemCount: _availableCategories.length,
      itemBuilder: (context, i) {
        final theme = _availableCategories[i];
        final themeId = theme['id'] as String;
        final themeNom = theme['nom'] as String;
        final sousThemes = _sousThemesParTheme[themeId] ?? [];
        final hasUpdates = _themeHasUpdates[themeId] ?? false;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: cardColor,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.withOpacity(0.15),
              radius: 18,
              child: Text(
                themeNom.isNotEmpty ? themeNom[0].toUpperCase() : '?',
                style: TextStyle(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    themeNom,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (hasUpdates)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Nouveau',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              '${sousThemes.length} sous-thème${sousThemes.length != 1 ? 's' : ''}',
              style: TextStyle(color: subtitleColor, fontSize: 12),
            ),
            childrenPadding: const EdgeInsets.only(
              left: 16,
              right: 8,
              bottom: 8,
            ),
            children:
                sousThemes.isEmpty
                    ? [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'Aucun sous-thème',
                          style: TextStyle(
                            color: subtitleColor,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ]
                    : sousThemes.map((st) {
                      final stKey = '$themeId||${st['id']}';
                      final stHasUpd = _sousThemeHasUpdates[stKey] ?? false;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.label_outline,
                          size: 16,
                          color: Colors.blue.shade300,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                st['nom'] as String,
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark
                                          ? Colors.grey[300]
                                          : Colors.grey[800],
                                ),
                              ),
                            ),
                            if (stHasUpd)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade400,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Nouveau',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                      );
                    }).toList(),
          ),
        );
      },
    );
  }

  // ── Vue chapitres ─────────────────────────────────────────────────────────

  Widget _buildChapterList(bool isDark) {
    final chapterCount =
        _chaptersData.keys.isNotEmpty
            ? (_chaptersData.keys.reduce((a, b) => a > b ? a : b)) + 1
            : 1;
    return ListView.builder(
      itemCount: chapterCount,
      itemBuilder: (_, i) => _buildChapterCard(i + 1, isDark),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CARTE DE CHAPITRE
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildChapterCard(int num, bool isDark) {
    final data = _chaptersData[num];
    final chapterExists = data != null;
    final content = data?['content'] as String? ?? '';
    final isGenerating = _generatingChapter == num;
    final isCompleting = _completingChapter == num;
    final isRewriting = _rewritingChapter == num;
    final isBusy = isGenerating || isCompleting || isRewriting;
    final isEditMode = _editModes[num] == true;
    final selectedText = _selectedTextByChapter[num];
    final themesUsed = data?['themesUsed'] as List<dynamic>?;
    final pendingDiff = _pendingDiffs[num];
    final hasPending = pendingDiff != null;

    final titleColor = isDark ? Colors.blue.shade300 : Colors.blue;
    final textColor = isDark ? Colors.grey[300] : Colors.grey[800];
    final italicColor = isDark ? Colors.grey[500] : Colors.grey[600];
    final chipBg = isDark ? Colors.blue.shade900 : Colors.lightBlue.shade100;
    final chipTc = isDark ? Colors.white70 : Colors.black87;

    final cardColor =
        _isFullScreen
            ? Colors.transparent
            : (isDark ? Colors.grey[800] : Colors.white);
    final cardElevation = _isFullScreen ? 0.0 : 4.0;
    final cardMargin =
        _isFullScreen ? EdgeInsets.zero : const EdgeInsets.only(bottom: 20);
    final paddingVal =
        _isFullScreen
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 8)
            : const EdgeInsets.all(20.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: cardMargin,
          elevation: cardElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: cardColor,
          child: Padding(
            padding: paddingVal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Titre + actions ──
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chapitre $num',
                        style: TextStyle(
                          fontSize: _isFullScreen ? 24 : 20,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                      ),
                    ),
                    if (chapterExists) ...[
                      IconButton(
                        icon: Icon(
                          isEditMode ? Icons.check_circle : Icons.edit,
                          color: isEditMode ? Colors.green : titleColor,
                          size: 22,
                        ),
                        tooltip:
                            isEditMode ? 'Sauvegarder' : 'Éditer manuellement',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          if (isEditMode) {
                            final newText =
                                _editControllers[num]?.text ?? content;
                            try {
                              await _db
                                  .collection('users')
                                  .doc(_user!.uid)
                                  .collection('chapters')
                                  .doc('chapter_$num')
                                  .update({'content': newText});
                              if (mounted) {
                                setState(() {
                                  _chaptersData[num] = {
                                    ..._chaptersData[num]!,
                                    'content': newText,
                                  };
                                  _editModes[num] = false;
                                  _editControllers[num]?.dispose();
                                  _editControllers.remove(num);
                                  _editImages.remove(num);
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Chapitre $num sauvegardé !'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Erreur : $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                            }
                          } else {
                            _editControllers[num] = TextEditingController(
                              text: content,
                            );
                            setState(() => _editModes[num] = true);
                          }
                        },
                      ),
                      if (isEditMode)
                        IconButton(
                          icon: const Icon(
                            Icons.cancel,
                            color: Colors.red,
                            size: 22,
                          ),
                          tooltip: 'Annuler',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            _editControllers[num]?.dispose();
                            _editControllers.remove(num);
                            setState(() {
                              _editModes[num] = false;
                              _editImages.remove(num);
                            });
                          },
                        ),
                      if (!isEditMode)
                        IconButton(
                          icon: Icon(
                            Icons.visibility,
                            color: titleColor,
                            size: 26,
                          ),
                          tooltip: 'Lire le chapitre',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showFullScreen(num, isDark),
                        ),
                    ],
                  ],
                ),

                const SizedBox(height: 12),

                // ── Chips thèmes ──
                if (themesUsed != null && themesUsed.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children:
                        themesUsed.contains('all')
                            ? [
                              Chip(
                                label: Text(
                                  'Tous les thèmes',
                                  style: TextStyle(color: chipTc),
                                ),
                                backgroundColor: chipBg,
                              ),
                            ]
                            : themesUsed
                                .map(
                                  (id) => Chip(
                                    label: Text(
                                      _categoryNames[id as String] ?? id,
                                      style: TextStyle(color: chipTc),
                                    ),
                                    backgroundColor: chipBg,
                                  ),
                                )
                                .toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                // ══════════════════════════════════════════════════════════════════
                // ZONE PRINCIPALE : loading / edit / diff / lecture
                // ══════════════════════════════════════════════════════════════════
                if (isBusy)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isGenerating
                                ? 'Génération en cours…'
                                : isCompleting
                                ? 'Complétion en cours…'
                                : 'Réécriture en cours…',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (isEditMode)
                  _buildEditModeWidget(num, isDark, textColor)
                else if (hasPending)
                  _buildDiffWidget(num, pendingDiff!, isDark, textColor)
                else if (chapterExists)
                  _buildReadWidget(num, content, isDark, textColor)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        "Ce chapitre n'a pas encore été généré.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: italicColor,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),

                // ── Bandeau sélection ──
                if (selectedText != null &&
                    !isEditMode &&
                    chapterExists &&
                    !hasPending) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.text_fields,
                          color: Colors.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sélection : "${selectedText.length > 60 ? '${selectedText.substring(0, 60)}…' : selectedText}"',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark
                                      ? Colors.amber.shade200
                                      : Colors.amber.shade800,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color:
                                isDark
                                    ? Colors.amber.shade200
                                    : Colors.amber.shade700,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed:
                              () => setState(
                                () => _selectedTextByChapter.remove(num),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Bouton principal ──
                if (!hasPending)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Tooltip(
                        message:
                            !_canUpdate && _lastAutobioUpdate != null
                                ? 'Disponible dans ${_kNonVipAutobiographyCooldownDays - DateTime.now().difference(_lastAutobioUpdate!).inDays} jour(s)'
                                : '',
                        child: ElevatedButton.icon(
                          icon: Icon(
                            chapterExists
                                ? Icons.edit_note
                                : Icons.auto_fix_high,
                          ),
                          label: Text(chapterExists ? 'Thèmes' : 'Générer'),
                          onPressed:
                              (isBusy || !_canUpdate)
                                  ? null
                                  : () => _openThemeDialog(
                                    num,
                                    selectedText: selectedText,
                                  ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            elevation: 5,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (_isFullScreen)
          Divider(
            height: 32,
            color: isDark ? Colors.grey[800] : Colors.grey[300],
          ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // WIDGET : MODE LECTURE (texte sélectionnable)
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildReadWidget(
    int num,
    String content,
    bool isDark,
    Color? textColor,
  ) {
    // On cherche toutes les balises [IMAGE:url]
    final RegExp imgRegExp = RegExp(r'\[IMAGE:(.*?)\]');
    final matches = imgRegExp.allMatches(content);

    // S'il n'y a pas d'image, on affiche le texte normalement
    if (matches.isEmpty) {
      return SelectableText(
        content,
        style: TextStyle(height: 1.6, fontSize: 15, color: textColor),
        onSelectionChanged: (sel, _) {
          if (sel.start == -1 || sel.end == -1) return;
          final s = content.substring(
            sel.start.clamp(0, content.length),
            sel.end.clamp(0, content.length),
          );
          setState(() {
            if (s.isNotEmpty)
              _selectedTextByChapter[num] = s;
            else
              _selectedTextByChapter.remove(num);
          });
        },
      );
    }

    // S'il y a des images, on construit une colonne avec du texte, puis l'image, puis du texte...
    List<Widget> children = [];
    int lastIndex = 0;

    for (final match in matches) {
      // 1. Le texte AVANT l'image
      final textBefore = content.substring(lastIndex, match.start).trim();
      if (textBefore.isNotEmpty) {
        children.add(
          SelectableText(
            textBefore,
            style: TextStyle(height: 1.6, fontSize: 15, color: textColor),
            onSelectionChanged: (sel, _) {
              if (sel.start == -1 || sel.end == -1) return;
              final s = textBefore.substring(
                sel.start.clamp(0, textBefore.length),
                sel.end.clamp(0, textBefore.length),
              );
              setState(() {
                if (s.isNotEmpty)
                  _selectedTextByChapter[num] = s;
                else
                  _selectedTextByChapter.remove(num);
              });
            },
          ),
        );
        children.add(const SizedBox(height: 16));
      }

      // 2. L'image en elle-même
      final url = match.group(1);
      if (url != null && url.isNotEmpty) {
        children.add(
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) => Container(
                    width: double.infinity,
                    height: 150,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
            ),
          ),
        );
        children.add(const SizedBox(height: 16));
      }
      lastIndex = match.end;
    }

    // 3. Le texte restant APRÈS la dernière image
    final textAfter = content.substring(lastIndex).trim();
    if (textAfter.isNotEmpty) {
      children.add(
        SelectableText(
          textAfter,
          style: TextStyle(height: 1.6, fontSize: 15, color: textColor),
          onSelectionChanged: (sel, _) {
            if (sel.start == -1 || sel.end == -1) return;
            final s = textAfter.substring(
              sel.start.clamp(0, textAfter.length),
              sel.end.clamp(0, textAfter.length),
            );
            setState(() {
              if (s.isNotEmpty)
                _selectedTextByChapter[num] = s;
              else
                _selectedTextByChapter.remove(num);
            });
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // WIDGET : MODE ÉDITION MANUELLE (avec galerie d'images)
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildEditModeWidget(int num, bool isDark, Color? textColor) {
    final images = _editImages[num] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _editControllers[num],
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: TextStyle(fontSize: 15, height: 1.6, color: textColor),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            hintText: 'Éditez votre chapitre…',
          ),
        ),
        const SizedBox(height: 12),
        // Galerie d'images insérées
        if (images.isNotEmpty) ...[
          Text(
            'Images insérées :',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.blue.shade300 : Colors.blue,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              itemBuilder: (_, i) {
                return Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          images[i],
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => Container(
                                width: 90,
                                height: 90,
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image),
                              ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 8,
                      child: GestureDetector(
                        onTap:
                            () => setState(
                              () => (_editImages[num] ??= []).removeAt(i),
                            ),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          icon: const Icon(Icons.add_photo_alternate),
          label: const Text('Ajouter une image'),
          onPressed: () => _pickAndUploadImage(num),
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? Colors.blue.shade300 : Colors.blue,
            side: BorderSide(
              color: isDark ? Colors.blue.shade300 : Colors.blue,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        if (images.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '💡 Les images sont sauvegardées. Pour les intégrer dans le texte, copiez leur URL et insérez-la manuellement dans le texte si besoin.',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // WIDGET : AFFICHAGE DU DIFF (rouge = supprimé, jaune = ajouté)
  // + boutons Accepter / Refuser
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildDiffWidget(
    int num,
    _ChapterDiff diff,
    bool isDark,
    Color? textColor,
  ) {
    final isComplete = diff.insertedText.isNotEmpty; // mode complétion
    final isRewrite = diff.replacedText.isNotEmpty; // mode réécriture

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Titre du diff ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (isDark ? Colors.blue.shade900 : Colors.blue.shade50)
                .withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade300.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.preview, color: Colors.blue.shade400, size: 18),
              const SizedBox(width: 8),
              Text(
                isComplete
                    ? 'Aperçu de la complétion'
                    : 'Aperçu de la réécriture',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Légende ──
        Row(
          children: [
            _legendChip(
              'Supprimé',
              const Color(0xFFFF4444),
              const Color(0x22FF4444),
            ),
            const SizedBox(width: 8),
            _legendChip(
              'Ajouté',
              const Color(0xFFE6A817),
              const Color(0x22E6A817),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Contenu avec diff ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
            ),
          ),
          child: _buildDiffRichText(
            diff,
            isComplete,
            isRewrite,
            isDark,
            textColor,
          ),
        ),

        const SizedBox(height: 16),

        // ── Boutons Accepter / Refuser ──
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Accepter'),
                onPressed: () => _acceptDiff(num),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Refuser'),
                onPressed: () => _rejectDiff(num),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _legendChip(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffRichText(
    _ChapterDiff diff,
    bool isComplete,
    bool isRewrite,
    bool isDark,
    Color? textColor,
  ) {
    final spans = <InlineSpan>[];
    final baseStyle = TextStyle(height: 1.65, fontSize: 15, color: textColor);

    if (isComplete) {
      // ── Mode complétion : Couper le texte original à l'endroit exact de l'ancrage ──
      final int offset = diff.insertOffset ?? diff.originalContent.length;

      // Sécuriser l'offset pour éviter un crash si l'index est hors limites
      final safeOffset = offset.clamp(0, diff.originalContent.length);

      final before = diff.originalContent.substring(0, safeOffset);
      final after = diff.originalContent.substring(safeOffset);

      // 1. Afficher le texte AVANT l'insertion
      if (before.isNotEmpty) {
        spans.add(TextSpan(text: before, style: baseStyle));
      }

      // 2. Afficher le NOUVEAU texte en JAUNE
      if (diff.insertedText.isNotEmpty) {
        // Ajouter un saut de ligne propre seulement s'il y a du texte avant
        if (before.isNotEmpty && !before.endsWith('\n'))
          spans.add(TextSpan(text: '\n\n', style: baseStyle));

        spans.add(
          TextSpan(
            text: diff.insertedText,
            style: baseStyle.copyWith(
              backgroundColor: const Color(0x55E6A817),
              color: isDark ? Colors.amber.shade100 : Colors.brown.shade800,
            ),
          ),
        );

        // Ajouter un saut de ligne propre s'il y a du texte après
        if (after.isNotEmpty && !after.startsWith('\n'))
          spans.add(TextSpan(text: '\n\n', style: baseStyle));
      }

      // 3. Afficher le texte APRÈS l'insertion
      if (after.isNotEmpty) {
        spans.add(TextSpan(text: after, style: baseStyle));
      }
    } else if (isRewrite) {
      // ── Mode réécriture : rechercher le passage supprimé et afficher rouge+jaune ──
      final original = diff.originalContent;
      final removedText = diff.replacedText;
      final replacedWith = diff.replacementText;
      final idx = original.indexOf(removedText);

      if (idx != -1) {
        if (idx > 0)
          spans.add(
            TextSpan(text: original.substring(0, idx), style: baseStyle),
          );
        spans.add(
          TextSpan(
            text: removedText,
            style: baseStyle.copyWith(
              backgroundColor: const Color(0x33FF4444),
              color: const Color(0xFFFF4444),
              decoration: TextDecoration.lineThrough,
              decorationColor: const Color(0xFFFF4444),
            ),
          ),
        );
        spans.add(TextSpan(text: '\n', style: baseStyle));
        spans.add(
          TextSpan(
            text: replacedWith,
            style: baseStyle.copyWith(
              backgroundColor: const Color(0x55E6A817),
              color: isDark ? Colors.amber.shade100 : Colors.brown.shade800,
            ),
          ),
        );
        final afterStart = idx + removedText.length;
        if (afterStart < original.length)
          spans.add(
            TextSpan(text: original.substring(afterStart), style: baseStyle),
          );
      } else {
        spans.add(
          TextSpan(
            text: diff.newContent,
            style: baseStyle.copyWith(backgroundColor: const Color(0x55E6A817)),
          ),
        );
      }
    } else {
      spans.add(TextSpan(text: diff.newContent, style: baseStyle));
    }

    return RichText(text: TextSpan(children: spans));
  }

  // ── Plein écran ───────────────────────────────────────────────────────────

  // ── Plein écran ───────────────────────────────────────────────────────────

  void _showFullScreen(int initialChapterNum, bool isDark) {
    final chapters = _chaptersData.keys.toList()..sort();
    final initialIndex = chapters.indexOf(initialChapterNum);
    if (initialIndex == -1) return;

    // 👇 MODIFICATION ICI : On utilise Navigator.push au lieu de showDialog
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (ctx) => _ChapterReaderScreen(
              initialIndex: initialIndex,
              chapters: chapters,
              chaptersData: _chaptersData,
              isDark: isDark,
              buildReadWidget: _buildReadWidget,
            ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 6 – MODE LECTURE IMMERSIVE (AVEC SWIPE)
// ═══════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════
// SECTION 6 – MODE LECTURE IMMERSIVE (AVEC SWIPE HORIZONTAL)
// ═══════════════════════════════════════════════════════════════════════════

class _ChapterReaderScreen extends StatefulWidget {
  final int initialIndex;
  final List<int> chapters;
  final Map<int, Map<String, dynamic>> chaptersData;
  final bool isDark;
  final Widget Function(int, String, bool, Color?) buildReadWidget;

  const _ChapterReaderScreen({
    Key? key,
    required this.initialIndex,
    required this.chapters,
    required this.chaptersData,
    required this.isDark,
    required this.buildReadWidget,
  }) : super(key: key);

  @override
  State<_ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<_ChapterReaderScreen> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 👇 Utilisation d'un Scaffold pour un vrai mode plein écran
    return Scaffold(
      backgroundColor: widget.isDark ? Colors.grey[900] : Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.chapters.length,
              // 👇 MODIFICATION ICI : On passe en horizontal pour ne plus bloquer le scroll du texte
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final num = widget.chapters[index];
                final content =
                    widget.chaptersData[num]?['content'] as String? ?? '';
                final textColor =
                    widget.isDark ? Colors.grey[300] : Colors.grey[800];

                return Column(
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      'Chapitre $num',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: widget.isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(
                          left: 28,
                          right: 28,
                          bottom: 76,
                        ),
                        child: widget.buildReadWidget(
                          num,
                          content,
                          widget.isDark,
                          textColor,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, size: 28),
                color: widget.isDark ? Colors.white54 : Colors.black54,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            if (widget.chapters.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.keyboard_arrow_left_rounded,
                      size: 18,
                      color: widget.isDark ? Colors.white30 : Colors.black26,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Glissez pour changer de chapitre',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isDark ? Colors.white30 : Colors.black26,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_right_rounded,
                      size: 18,
                      color: widget.isDark ? Colors.white30 : Colors.black26,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 5 – CLASSE DE DONNÉES INTERNE
// ═══════════════════════════════════════════════════════════════════════════

class _FetchResult {
  final List<Map<String, dynamic>> elements;
  final List<DocumentReference> refs;
  const _FetchResult(this.elements, this.refs);
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 2 – DIALOG DE SÉLECTION DE THÈME (refonte complète)
// ═══════════════════════════════════════════════════════════════════════════

class MovingContentCard extends StatefulWidget {
  final dynamic data;
  final String design;
  final String color;
  final String animationType;
  final String size;
  final VoidCallback onSendToBack;
  final VoidCallback onReplaceRequest;
  final BoxConstraints parentConstraints;
  final Function(BuildContext context, dynamic data) contentBuilder;
  final VoidCallback onLongPress;
  final VoidCallback? onTap;

  const MovingContentCard({
    super.key,
    required this.data,
    required this.design,
    required this.color,
    required this.animationType,
    required this.size,
    required this.onSendToBack,
    required this.onReplaceRequest,
    required this.parentConstraints,
    required this.contentBuilder,
    required this.onLongPress,
    this.onTap,
  });

  @override
  _MovingContentCardState createState() => _MovingContentCardState();
}

class _MovingContentCardState extends State<MovingContentCard>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // --- Contrôleurs d'animation ---
  late AnimationController _moveController;
  late AnimationController _effectController;
  late Animation<double> _effectAnimation;

  // --- État du mouvement ---
  double _positionX = 0.0, _positionY = 0.0;
  double _velocityX = 0.0, _velocityY = 0.0;

  // --- Dimensions (calculées) ---
  Size _parentSize = Size.zero;
  Size _cardActualSize = Size.zero;
  late double _cardWidth; // Largeur de base définie par le widget
  final GlobalKey _cardKey = GlobalKey();

  // --- État de l'animation ---
  int _collisionCount = 0;
  final Random _random = Random();
  String _animationSpeed = 'normal';
  bool _isStaticMode = false;

  // Pour l'animation "flottant"
  double _floatOffsetX = 0.0;
  double _floatOffsetY = 0.0;

  // Pour l'animation "changer"
  Timer? _fadeTimer;
  bool _isFading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _setBaseCardSize();

    // Initialisation des contrôleurs
    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    );
    _effectController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _effectAnimation = Tween<double>(
      begin: 0,
      end: 0,
    ).animate(_effectController);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateDimensionsAndInitialize();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // On résout la vraie taille du PNG dès qu'on a le contexte
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant MovingContentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.size != oldWidget.size) {
      _setBaseCardSize();
    }
    // Si l'image change, on recalcule ses dimensions exactes
    if (widget.design != oldWidget.design ||
        widget.color != oldWidget.color ||
        widget.size != oldWidget.size) {
      _resolveImageSize();
    }
    if (widget.animationType != oldWidget.animationType) {
      _initializeAnimations();
    }
  }

  void _resolveImageSize() {
    final imageProvider = AssetImage(
      _getImagePath(widget.design, widget.color),
    );
    final config = createLocalImageConfiguration(context);
    imageProvider
        .resolve(config)
        .addListener(
          ImageStreamListener((ImageInfo info, bool _) {
            if (mounted) {
              final double aspect = info.image.width / info.image.height;
              setState(() {
                // On définit la taille exacte de l'image basée sur son vrai ratio
                _cardActualSize = Size(_cardWidth, _cardWidth / aspect);
              });
            }
          }),
        );
  }

  // =========================================================================
  // --- 1. GESTION DES DIMENSIONS ET DE L'INITIALISATION ---
  // =========================================================================

  void _updateDimensionsAndInitialize() async {
    if (!mounted) return;

    _parentSize = widget.parentConstraints.biggest;

    // Fallback de sécurité si l'image met du temps à se résoudre
    if (_cardActualSize == Size.zero) {
      _cardActualSize = Size(_cardWidth, _cardWidth);
    }

    _setRandomInitialPosition();
    await _loadAnimationSettings();
    _initializeAnimations();

    _moveController.addListener(_tick);
  }

  void _setBaseCardSize() {
    const double baseSize = 250.0;
    switch (widget.size) {
      case 'tres_petit':
        _cardWidth = baseSize * 0.7;
        break;
      case 'petit':
        _cardWidth = baseSize * 0.85;
        break;
      case 'gros':
        _cardWidth = baseSize * 1.1;
        break;
      default:
        _cardWidth = baseSize;
    }
  }

  Future<void> _loadAnimationSettings() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _animationSpeed = prefs.getString('animationSpeed') ?? 'normal';
    } catch (e) {
      print('Erreur de chargement des paramètres d\'animation : $e');
    }
  }

  void _initializeAnimations() {
    _moveController.duration = _getSpeedDuration();
    _effectController.stop();
    _fadeTimer?.cancel();
    _isStaticMode = false;

    _effectController.removeListener(_updateFloatOffset);

    switch (widget.animationType) {
      case 'rotation':
        _effectController.duration = _getEffectDuration();
        _effectAnimation = Tween<double>(
          begin: 0,
          end: 2 * math.pi,
        ).animate(_effectController);
        _effectController.repeat(reverse: true);
        break;
      case 'pulsation':
        _effectController.duration = _getEffectDuration();
        _effectAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
          CurvedAnimation(parent: _effectController, curve: Curves.easeInOut),
        );
        _effectController.repeat(reverse: true);
        break;
      case 'flottant':
        _effectController.duration = _getEffectDuration();
        _effectAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
          CurvedAnimation(parent: _effectController, curve: Curves.linear),
        );
        _effectController.addListener(_updateFloatOffset);
        _effectController.repeat();
        break;
      case 'changer':
        _isStaticMode = true;
        _effectAnimation = Tween<double>(
          begin: 1.0,
          end: 1.0,
        ).animate(_effectController);
        _scheduleRandomFade();
        break;
      case 'rebondissant':
      default:
        _effectAnimation = Tween<double>(
          begin: 0,
          end: 0,
        ).animate(_effectController);
    }

    if (!_isStaticMode) {
      if (!_moveController.isAnimating) {
        _moveController.repeat();
      }
    } else {
      _moveController.stop();
    }
  }

  // =========================================================================
  // --- 2. BOUCLE D'ANIMATION PRINCIPALE ET LOGIQUE DE DÉPLACEMENT ---
  // =========================================================================

  void _tick() {
    if (!mounted || _isStaticMode || _parentSize == Size.zero) return;

    final double nextX = _positionX + _velocityX;
    final double nextY = _positionY + _velocityY;

    final Map<String, double> result = _handleBoundaryCollisions(nextX, nextY);

    setState(() {
      _positionX = result['x']!;
      _positionY = result['y']!;
      _velocityX = result['vx']!;
      _velocityY = result['vy']!;
    });
  }

  // =========================================================================
  // --- 3. GESTION DES COLLISIONS AVEC LES BORDS ---
  // =========================================================================

  Map<String, double> _handleBoundaryCollisions(
    double proposedX,
    double proposedY,
  ) {
    double correctedX = proposedX;
    double correctedY = proposedY;
    double newVx = _velocityX;
    double newVy = _velocityY;
    bool hasCollided = false;

    final cardWidth = _getEffectiveWidth();
    final cardHeight = _getEffectiveHeight();
    final isFloating = widget.animationType == 'flottant';
    final currentFloatOffsetX = isFloating ? _floatOffsetX : 0.0;
    final currentFloatOffsetY = isFloating ? _floatOffsetY : 0.0;

    if (cardHeight <= 0) {
      return {'x': correctedX, 'y': correctedY, 'vx': newVx, 'vy': newVy};
    }

    final effectiveLeft = proposedX + currentFloatOffsetX;
    final effectiveRight = effectiveLeft + cardWidth;
    final effectiveTop = proposedY + currentFloatOffsetY;
    final effectiveBottom = effectiveTop + cardHeight;

    if (effectiveLeft < 0) {
      correctedX = -currentFloatOffsetX;
      newVx = _velocityX.abs();
      hasCollided = true;
    } else if (effectiveRight > _parentSize.width) {
      correctedX = _parentSize.width - cardWidth - currentFloatOffsetX;
      newVx = -_velocityX.abs();
      hasCollided = true;
    }

    if (effectiveTop < 0) {
      correctedY = -currentFloatOffsetY;
      newVy = _velocityY.abs();
      hasCollided = true;
    } else if (effectiveBottom > _parentSize.height) {
      correctedY = _parentSize.height - cardHeight - currentFloatOffsetY;
      newVy = -_velocityY.abs();
      hasCollided = true;
    }

    if (hasCollided) {
      _handleCollisionEvent();
    }

    return {'x': correctedX, 'y': correctedY, 'vx': newVx, 'vy': newVy};
  }

  void _updateFloatOffset() {
    if (mounted) {
      setState(() {
        _floatOffsetX = math.sin(_effectAnimation.value) * 15;
        _floatOffsetY = math.cos(_effectAnimation.value * 2) * 10;
      });
    }
  }

  void _setRandomInitialPosition() {
    if (_parentSize == Size.zero) return;
    final double cardW =
        _cardActualSize.width > 0 ? _cardActualSize.width : _cardWidth;
    final double cardH =
        _cardActualSize.height > 0 ? _cardActualSize.height : _cardWidth;

    final double margin = widget.animationType == 'flottant' ? 20 : 5;
    final double availableWidth = _parentSize.width - cardW - (2 * margin);
    final double availableHeight = _parentSize.height - cardH - (2 * margin);

    if (availableWidth > 0 && availableHeight > 0) {
      _positionX = margin + _random.nextDouble() * availableWidth;
      _positionY = margin + _random.nextDouble() * availableHeight;
    }

    _velocityX = (_random.nextDouble() - 0.5) * 3.5;
    _velocityY = (_random.nextDouble() - 0.5) * 3.5;
    if (_velocityX.abs() < 1.0) _velocityX = _velocityX.sign * 1.0;
    if (_velocityY.abs() < 1.0) _velocityY = _velocityY.sign * 1.0;
  }

  void _handleCollisionEvent() {
    widget.onSendToBack();
    _collisionCount++;
    if (_collisionCount >= 3) {
      widget.onReplaceRequest();
      _collisionCount = 0;
    }
  }

  Duration _getSpeedDuration() {
    switch (_animationSpeed) {
      case 'lent':
        return const Duration(milliseconds: 80);
      case 'rapide':
        return const Duration(milliseconds: 30);
      default:
        return const Duration(milliseconds: 50);
    }
  }

  Duration _getEffectDuration() {
    switch (_animationSpeed) {
      case 'lent':
        return const Duration(milliseconds: 3000);
      case 'rapide':
        return const Duration(milliseconds: 1000);
      default:
        return const Duration(milliseconds: 2000);
    }
  }

  double _getEffectiveWidth() {
    final baseWidth =
        _cardActualSize.width > 0 ? _cardActualSize.width : _cardWidth;
    if (widget.animationType == 'pulsation' && _effectController.isAnimating) {
      return baseWidth * _effectAnimation.value;
    }
    return baseWidth;
  }

  double _getEffectiveHeight() {
    final baseHeight =
        _cardActualSize.height > 0 ? _cardActualSize.height : _cardWidth;
    if (widget.animationType == 'pulsation' && _effectController.isAnimating) {
      return baseHeight * _effectAnimation.value;
    }
    return baseHeight;
  }

  void _scheduleRandomFade() {
    if (widget.animationType != 'changer') return;
    _fadeTimer?.cancel();
    final delaySeconds = 5 + _random.nextInt(10);
    _fadeTimer = Timer(Duration(seconds: delaySeconds), _startFadeAnimation);
  }

  void _startFadeAnimation() {
    if (!mounted || _isFading || widget.animationType != 'changer') return;
    _isFading = true;
    _effectController.duration = const Duration(milliseconds: 800);
    _effectAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _effectController, curve: Curves.easeInOut),
    );
    _effectController.forward(from: 0).whenComplete(() {
      if (mounted) {
        _setRandomInitialPosition();
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && widget.animationType == 'changer') {
            _effectAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: _effectController,
                curve: Curves.easeInOut,
              ),
            );
            _effectController.forward(from: 0).whenComplete(() {
              _isFading = false;
              _scheduleRandomFade();
            });
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AnimatedBuilder(
      animation: Listenable.merge([_moveController, _effectController]),
      builder: (context, child) {
        Widget transformedChild;
        double finalLeft = _positionX;
        double finalTop = _positionY;

        switch (widget.animationType) {
          case 'rotation':
            transformedChild = Transform.rotate(
              angle: _effectAnimation.value,
              child: child,
            );
            break;
          case 'pulsation':
            transformedChild = Transform.scale(
              scale: _effectAnimation.value,
              alignment: Alignment.center,
              child: child,
            );
            break;
          case 'flottant':
            finalLeft += _floatOffsetX;
            finalTop += _floatOffsetY;
            transformedChild = child!;
            break;
          case 'changer':
            transformedChild = Opacity(
              opacity: _effectAnimation.value,
              child: child,
            );
            break;
          default:
            transformedChild = child!;
        }

        return Positioned(
          left: finalLeft,
          top: finalTop,
          child: transformedChild,
        );
      },
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        onTap:
            widget.onTap == null
                ? null
                : () async {
                  _effectController.stop();
                  _moveController.stop();
                  widget.onTap!();
                  if (mounted) _initializeAnimations();
                },
        child: Stack(
          key: _cardKey,
          alignment: Alignment.center,
          children: [
            Image.asset(
              _getImagePath(widget.design, widget.color),
              width: _cardWidth,
              // La hauteur n'est plus forcée ici pour respecter le vrai ratio de l'image.
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: _cardWidth,
                  height: _cardWidth,
                  color: Colors.grey.shade200,
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.grey.shade400,
                    size: 40,
                  ),
                );
              },
            ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(_cardWidth / 6),
                child: widget.contentBuilder(context, widget.data),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getImagePath(String design, String color) {
    final safeDesign = design.isNotEmpty ? design : 'carrer';
    final safeColor = color.isNotEmpty ? color : 'bleu';
    return 'assets/${safeDesign}_${safeColor}.png';
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _moveController.removeListener(_tick);
    _moveController.dispose();
    _effectController.removeListener(_updateFloatOffset);
    _effectController.dispose();
    super.dispose();
  }
}

class _BlinkingDots extends StatefulWidget {
  const _BlinkingDots({Key? key}) : super(key: key);
  @override
  _BlinkingDotsState createState() => _BlinkingDotsState();
}

class _BlinkingDotsState extends State<_BlinkingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder:
          (context, child) => Opacity(
            opacity: _controller.value,
            child: const Text(
              '...',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // ... Le reste de HomePageState reste inchangé ...
  TabController? _tabController;
  List<JourneeModel> _myJournees = [];
  List<SouvenirModel> _mySouvenirs = [];
  ValueNotifier<String> journeeFilterNotifier = ValueNotifier<String>('tout');
  ValueNotifier<String> souvenirFilterNotifier = ValueNotifier<String>('tout');
  bool _isFullScreen = false;
  List<JourneeModel> _displayedJournees = [];
  List<JourneeModel> _filteredJournees = [];
  List<SouvenirModel> _displayedSouvenirs = [];
  List<SouvenirModel> _filteredSouvenirs = [];
  late Future<String> _cardSizeFuture;
  final ValueNotifier<String> _tabTitleNotifier = ValueNotifier<String>(
    'Mes Journées',
  );
  List<JourneeModel> _friendsJournees = [];
  List<JourneeModel> _globalJournees = [];
  List<SouvenirModel> _souvenirs = [];
  List<String> _friendIds = [];
  final _firestore = FirebaseFirestore.instance;
  DateTime _today = DateTime.now();
  bool _isLoading = false;
  ValueNotifier<Brightness> appBrightnessNotifier = ValueNotifier<Brightness>(
    Brightness.light,
  );

  late PageController _verticalMainPageController;
  late PageController _journeePageController;
  StreamSubscription<QuerySnapshot>? _myJourneesSubscription;
  StreamSubscription<QuerySnapshot>? _friendsJourneesSubscription;
  StreamSubscription<QuerySnapshot>? _globalJourneesSubscription;
  StreamSubscription<QuerySnapshot>? _mySouvenirsSubscription;
  Map<String, double> _journeeZOrders = {};
  Map<String, double> _souvenirZOrders = {};
  TextEditingController _controller = TextEditingController();
  List<String> _motsCles = [];
  int? _note;
  bool _isNoteObtained = false;
  static const int _maxDisplayedCards = 100;

  // Futures pour la personnalisation
  late Future<String> _journeeCardDesignFuture;
  late Future<String> _souvenirCardDesignFuture;
  late Future<String> _journeeCardAnimationFuture;
  late Future<String> _souvenirCardAnimationFuture;

  // AJOUT : Futures pour les couleurs
  late Future<String> _journeeCardColorFuture;
  late Future<String> _souvenirCardColorFuture;
  // Nouveaux futures pour forcer les couleurs globales
  late Future<bool> _forceGlobalJourneeColorFuture;
  late Future<bool> _forceGlobalSouvenirColorFuture;
  int _friendRequestCount = 0;
  StreamSubscription<QuerySnapshot>? _friendRequestsSubscription;

  // --- NOUVELLES VARIABLES D'ÉTAT POUR L'ONGLET MONDIAL ---
  bool _shareInGlobalFeed = false;
  String _globalFilter = 'mon_pays'; // Options: 'mon_pays' ou 'tous_les_pays'
  String? _currentUserCountry;
  bool _isLoadingGlobalPrefs = true;
  // --- FIN DES NOUVELLES VARIABLES ---

  @override
  bool get wantKeepAlive => true;
  bool _isVip = false;
  Map<String, Map<String, dynamic>> _userCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _verticalMainPageController = PageController(initialPage: 0);
    _journeePageController = PageController(viewportFraction: 0.85);
    _scheduleMidnightUpdate();
    _loadAppBrightness();
    _loadGlobalPreferences(); // <-- NOUVEL APPEL
    _setupRealtimeListeners();
    _listenToFriendRequests();

    _cardSizeFuture = _getCardSizeFromPreferences();

    journeeFilterNotifier.addListener(_updateDisplayedJournees);
    souvenirFilterNotifier.addListener(_updateDisplayedSouvenirs);
    _loadVipStatus();

    // Charger toutes les préférences de personnalisation
    _journeeCardDesignFuture = _getPreference('journeeCardDesign', 'carrer');
    _souvenirCardDesignFuture = _getPreference('cardDesign', 'carrer');
    _journeeCardAnimationFuture = _getPreference(
      'journeeAnimation',
      'rebondissant',
    );
    _souvenirCardAnimationFuture = _getPreference(
      'cardAnimation',
      'rebondissant',
    );
    // AJOUT : Chargement des préférences de couleur
    _journeeCardColorFuture = _getPreference('journeeCardColor', 'bleu');
    _souvenirCardColorFuture = _getPreference('cardColor', 'bleu');
    // Initialisation des switches pour forcer les couleurs
    _forceGlobalJourneeColorFuture = _getPreferenceBool(
      'forceGlobalJourneeColor',
      false,
    );
    _forceGlobalSouvenirColorFuture = _getPreferenceBool(
      'forceGlobalSouvenirColor',
      false,
    );

    // Lancer la petite animation de "slide" après l'initialisation de la vue
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSwipeHint();
    });
  }

  void _showSwipeHint() async {
    await Future.delayed(
      const Duration(milliseconds: 800),
    ); // Attend un peu le chargement initial
    if (!mounted || !_verticalMainPageController.hasClients) return;

    // Glisse légèrement vers le bas (100 pixels)
    await _verticalMainPageController.animateTo(
      100.0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
    );

    if (!mounted || !_verticalMainPageController.hasClients) return;

    // Revient à la position initiale
    await _verticalMainPageController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeIn,
    );
  }

  Future<bool> _getPreferenceBool(String key, bool defaultValue) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? defaultValue;
  }

  Future<void> _loadVipStatus() async {
    final data = await getUserSubscriptionData();
    if (mounted) {
      setState(() {
        _isVip = data['isVip'];
      });
    }
  }

  // --- NOUVELLE MÉTHODE POUR CHARGER LES PRÉFÉRENCES MONDIALES ---
  Future<void> _loadGlobalPreferences() async {
    setState(() => _isLoadingGlobalPrefs = true);
    final prefs = await SharedPreferences.getInstance();
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();
        if (userDoc.exists) {
          // IMPORTANT: Suppose que le document utilisateur a un champ 'country'.
          // Exemple: 'FR' pour la France. Ce champ est généralement défini lors de l'inscription par numéro de téléphone.
          _currentUserCountry = userDoc.data()?['country'];
        }
      } catch (e) {
        print("Erreur de récupération du pays de l'utilisateur: $e");
      }
    }

    if (mounted) {
      setState(() {
        _shareInGlobalFeed = prefs.getBool('shareInGlobalFeed') ?? false;
        _isLoadingGlobalPrefs = false;
      });
    }
  }

  void _listenToFriendRequests() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // On s'assure de ne pas avoir de listener fantôme
    _friendRequestsSubscription?.cancel();

    _friendRequestsSubscription = _firestore
        .collection('friend_requests')
        .where('receiverId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                _friendRequestCount = snapshot.docs.length;
              });
            }
          },
          onError: (e) {
            print('Erreur lors de l\'écoute des demandes d\'amis: $e');
          },
        );
  }

  Future<String> _getCardSizeFromPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('cardSize') ?? 'normal';
  }

  Future<String> _getPreference(String key, String defaultValue) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? defaultValue;
  }

  Future<Map<String, dynamic>> _getUserData(String userId) async {
    if (_userCache.containsKey(userId)) {
      return _userCache[userId]!;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _userCache[userId] = userData;
          });
        }
        return userData;
      }
    } catch (e) {
      print("Erreur de récupération des données utilisateur pour $userId: $e");
    }
    return {'username': 'Utilisateur Inconnu'};
  }

  // Dans la classe HomePageState de votre fichier home_page.dart

  void _updateDisplayedJournees() {
    setState(() {
      _filteredJournees = _filterJournees(
        _myJournees,
        journeeFilterNotifier.value,
      );

      // --- ON CRÉE UNE COPIE ET ON LA MÉLANGE ICI ---
      List<JourneeModel> listeMelangee = List.from(_filteredJournees);
      listeMelangee.shuffle();
      // ----------------------------------------------

      _displayedJournees = listeMelangee.take(_maxDisplayedCards).toList();

      _journeeZOrders.clear();
      for (var i = 0; i < _displayedJournees.length; i++) {
        final journee = _displayedJournees[i];
        if (journee.id != null) {
          _journeeZOrders[journee.id!] = i.toDouble();
        }
      }
    });
  }

  void _updateDisplayedSouvenirs() {
    setState(() {
      _filteredSouvenirs = _filterSouvenirs(
        _mySouvenirs,
        souvenirFilterNotifier.value,
      );

      // --- ON CRÉE UNE COPIE ET ON LA MÉLANGE ICI ---
      List<SouvenirModel> listeMelangee = List.from(_filteredSouvenirs);
      listeMelangee.shuffle();
      // ----------------------------------------------

      _displayedSouvenirs = listeMelangee.take(_maxDisplayedCards).toList();

      _souvenirZOrders.clear();
      for (var i = 0; i < _displayedSouvenirs.length; i++) {
        final souvenir = _displayedSouvenirs[i];
        if (souvenir.id != null) {
          _souvenirZOrders[souvenir.id!] = i.toDouble();
        }
      }
    });
  }

  void _setupRealtimeListeners() {
    if (!mounted) return;

    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _myJourneesSubscription = _firestore
        .collection('journees')
        .where('userId', isEqualTo: currentUser.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                _myJournees =
                    snapshot.docs
                        .map((doc) => JourneeModel.fromFirestore(doc))
                        .toList();
                _isLoading = false;
                _updateDisplayedJournees();
              });
            }
          },
          onError: (e) {
            print('Erreur lors de l\'écoute des journées: $e');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        );

    _loadFriends().then((_) {
      if (_friendIds.isNotEmpty) {
        final _fNow = DateTime.now();
        final _fStartOfToday = DateTime(_fNow.year, _fNow.month, _fNow.day);
        final _fEndOfToday = _fStartOfToday.add(const Duration(days: 1));
        _friendsJourneesSubscription = _firestore
            .collection('journees')
            .where('userId', whereIn: _friendIds)
            .where('estPublic', isEqualTo: true)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(_fStartOfToday),
            )
            .where('date', isLessThan: Timestamp.fromDate(_fEndOfToday))
            .orderBy('date', descending: true)
            .limit(50)
            .snapshots()
            .listen(
              (snapshot) {
                if (mounted) {
                  setState(() {
                    _friendsJournees =
                        snapshot.docs
                            .map((doc) => JourneeModel.fromFirestore(doc))
                            .toList();
                  });
                }
              },
              onError: (e) {
                print('Erreur lors de l\'écoute des journées des amis: $e');
              },
            );
      }
    });

    // Remplacé par une méthode dynamique pour permettre le filtrage
    _setupGlobalJourneesListener();

    _mySouvenirsSubscription = _firestore
        .collection('souvenirs')
        .where('userId', isEqualTo: currentUser.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                _mySouvenirs =
                    snapshot.docs
                        .map((doc) => SouvenirModel.fromFirestore(doc))
                        .toList();
                _updateDisplayedSouvenirs();
              });
            }
          },
          onError: (e) {
            print('Erreur lors de l\'écoute des souvenirs: $e');
          },
        );
  }

  // --- NOUVELLE MÉTHODE POUR LE LISTENER DYNAMIQUE MONDIAL ---
  void _setupGlobalJourneesListener() {
    if (!mounted) return;

    _globalJourneesSubscription?.cancel();

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    Query query = _firestore
        .collection('journees')
        .where('estPublic', isEqualTo: true)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
        .where('date', isLessThan: Timestamp.fromDate(endOfToday));

    _globalJourneesSubscription = query.snapshots().listen(
      (snapshot) {
        if (mounted) {
          List<JourneeModel> fetchedJournees =
              snapshot.docs
                  .map((doc) => JourneeModel.fromFirestore(doc))
                  .toList();

          if (_globalFilter == 'mon_pays' &&
              _currentUserCountry != null &&
              _currentUserCountry!.isNotEmpty) {
            fetchedJournees =
                fetchedJournees
                    .where(
                      (journee) => journee.userCountry == _currentUserCountry,
                    )
                    .toList();
          }

          setState(() {
            _globalJournees = fetchedJournees;
          });
        }
      },
      onError: (e) {
        print('Erreur lors de l\'écoute des journées mondiales filtrées: $e');
      },
    );
  }

  void _scheduleMidnightUpdate() {
    if (!mounted) return;

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    Future.delayed(timeUntilMidnight, () {
      if (mounted) {
        setState(() {
          _today = tomorrow;
        });
        _scheduleMidnightUpdate();
      }
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _verticalMainPageController.dispose();
    _journeePageController.dispose();
    _friendRequestsSubscription?.cancel();
    _myJourneesSubscription?.cancel();
    _friendsJourneesSubscription?.cancel();
    _globalJourneesSubscription?.cancel();
    _mySouvenirsSubscription?.cancel();
    _controller.dispose();
    journeeFilterNotifier.removeListener(_updateDisplayedJournees);
    souvenirFilterNotifier.removeListener(_updateDisplayedSouvenirs);
    _tabTitleNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadAppBrightness() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? themeMode = prefs.getString('themeMode');

      Brightness loadedBrightness = Brightness.light;
      if (themeMode == 'dark') {
        loadedBrightness = Brightness.dark;
      } else if (themeMode == 'light') {
        loadedBrightness = Brightness.light;
      } else {
        loadedBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
      }

      if (mounted) {
        appBrightnessNotifier.value = loadedBrightness;
      }
    } catch (e) {
      print('Erreur de chargement de la couleur de fond : $e');
    }
  }

  Future<void> _loadFriends() async {
    if (!mounted) return;

    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      QuerySnapshot friendsSnapshot =
          await _firestore
              .collection('friends')
              .where('users', arrayContains: currentUser.uid)
              .get();

      if (mounted) {
        setState(() {
          _friendIds =
              friendsSnapshot.docs.map((doc) {
                List<String> users = List<String>.from(doc['users']);
                return users.firstWhere((id) => id != currentUser.uid);
              }).toList();
        });
      }
    } catch (e) {
      print('Error loading friends: $e');
    }
  }

  Future<bool> _hasPostedJourneeOnDate(DateTime date) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    final querySnapshot =
        await _firestore
            .collection('journees')
            .where('userId', isEqualTo: currentUser.uid)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get();

    return querySnapshot.docs.isNotEmpty;
  }

  Future<void> _showConseilsDialog(JourneeModel journee) async {
    // 1. Vérifier si les conseils existent déjà dans Firestore pour éviter de régénérer
    if (journee.id != null) {
      try {
        DocumentSnapshot doc =
            await FirebaseFirestore.instance
                .collection('journees')
                .doc(journee.id)
                .get();
        if (doc.exists) {
          Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
          if (data != null &&
              data.containsKey('conseilsIA') &&
              data['conseilsIA'] is List) {
            List<String> savedConseils = List<String>.from(data['conseilsIA']);
            if (savedConseils.isNotEmpty) {
              _afficherPopupConseils(savedConseils);
              return; // On arrête ici, pas besoin d'appeler l'API !
            }
          }
        }
      } catch (e) {
        print("Erreur lors de la vérification du cache des conseils: $e");
      }
    }

    // 2. Si aucun conseil n'est sauvegardé, on affiche le loader et on appelle l'IA
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      const url = 'https://api.deepinfra.com/v1/openai/chat/completions';
      String texteAnalyse =
          journee.texte1 ?? journee.commentaire ?? 'Aucun détail fourni.';

      String prompt = '''
Tu es un coach de vie bienveillant et un psychologue expert. 
Lis attentivement le récit de la journée suivante.

Récit :
"$texteAnalyse"

Génère EXACTEMENT 3 conseils courts, personnalisés, constructifs et réconfortants basés EXCLUSIVEMENT sur ce récit. 
Ne donne pas de conseils génériques hors contexte. Formule les conseils directement à la deuxième personne ("Tu", "Pense à...").

IMPORTANT: Tu DOIS renvoyer UNIQUEMENT un objet JSON valide.
Format attendu:
{
  "conseils": [
    "Premier conseil ici.",
    "Deuxième conseil ici.",
    "Troisième conseil ici."
  ]
}
''';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': await resolveAiModel(isVip: _isVip),
          'max_tokens': 300,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      Navigator.pop(context); // Fermer le loader

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        String content = responseData['choices'][0]['message']['content'];

        // --- NETTOYAGE ROBUSTE ---
        // Supprimer les balises de réflexion de l'IA (ex: <think> ... </think> ou <thought> ... </thought>)
        content = content.replaceAll(
          RegExp(r'<think>[\s\S]*?<\/think>', dotAll: true),
          '',
        );
        content = content.replaceAll(
          RegExp(r'<thought>[\s\S]*?<\/thought>', dotAll: true),
          '',
        );

        // Enlever les balises markdown (```json)
        content =
            content
                .replaceAll(
                  RegExp(r'^```(?:json)?\s*|\s*```$', multiLine: true),
                  '',
                )
                .trim();

        // Extraire uniquement l'objet JSON
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
        if (jsonMatch != null) {
          content = jsonMatch.group(0)!;
        }

        List<String> conseilsList = [];
        try {
          final parsed = jsonDecode(content);
          if (parsed['conseils'] is List) {
            conseilsList = List<String>.from(parsed['conseils']);
          } else {
            conseilsList = [content]; // Fallback si le format est étrange
          }
        } catch (e) {
          // En cas d'échec total du JSON, on affiche le contenu nettoyé
          conseilsList = [content];
        }

        // 3. Sauvegarder les conseils générés dans Firebase pour ne pas rappeler l'IA la prochaine fois
        if (journee.id != null && conseilsList.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('journees')
              .doc(journee.id)
              .update({'conseilsIA': conseilsList});
        }

        _afficherPopupConseils(conseilsList);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de générer les conseils')),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Fermer loader
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur inattendue de génération IA')),
      );
    }
  }

  // --- SOUS-MÉTHODE POUR AFFICHER LE POPUP ---
  void _afficherPopupConseils(List<String> conseilsList) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.psychology, color: Colors.blue.shade700),
                const SizedBox(width: 10),
                const Text(
                  'Conseils IA',
                  style: TextStyle(color: Colors.blue, fontSize: 18),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: conseilsList.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      radius: 12,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    title: Text(
                      conseilsList[index],
                      style: const TextStyle(fontSize: 14),
                    ),
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
            ],
          ),
    );
  }

  void _showReactionsDetailsDialog(JourneeModel journee) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = appBrightnessNotifier.value == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          title: Text(
            'Réactions',
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: journee.reactions.keys.length,
              itemBuilder: (context, index) {
                String emoji = journee.reactions.keys.elementAt(index);
                List<String> users = journee.reactions[emoji] ?? [];
                return ListTile(
                  leading: Text(emoji, style: const TextStyle(fontSize: 24)),
                  title: Text(
                    '${users.length} personne(s)',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  void _sendJourneeToBack(JourneeModel journee) {
    if (journee.id == null || _journeeZOrders.isEmpty) return;
    final minZ = _journeeZOrders.values.reduce((a, b) => a < b ? a : b);

    setState(() {
      _journeeZOrders[journee.id!] = minZ - 1;
    });
  }

  void _replaceJournee(JourneeModel oldJournee) {
    if (_filteredJournees.length <= _maxDisplayedCards) return;

    final displayedIds = _displayedJournees.map((j) => j.id).toSet();
    final availableToDisplay =
        _filteredJournees.where((j) => !displayedIds.contains(j.id)).toList();

    if (availableToDisplay.isNotEmpty) {
      setState(() {
        final indexToReplace = _displayedJournees.indexOf(oldJournee);
        if (indexToReplace != -1) {
          _displayedJournees[indexToReplace] = availableToDisplay.first;
        }
      });
    }
  }

  void _sendSouvenirToBack(SouvenirModel souvenir) {
    if (souvenir.id == null || _souvenirZOrders.isEmpty) return;
    final minZ = _souvenirZOrders.values.reduce((a, b) => a < b ? a : b);
    setState(() {
      _souvenirZOrders[souvenir.id!] = minZ - 1;
    });
  }

  void _replaceSouvenir(SouvenirModel oldSouvenir) {
    if (_filteredSouvenirs.length <= _maxDisplayedCards) return;

    final displayedIds = _displayedSouvenirs.map((s) => s.id).toSet();
    final availableToDisplay =
        _filteredSouvenirs.where((s) => !displayedIds.contains(s.id)).toList();

    if (availableToDisplay.isNotEmpty) {
      setState(() {
        final indexToReplace = _displayedSouvenirs.indexOf(oldSouvenir);
        if (indexToReplace != -1) {
          _displayedSouvenirs[indexToReplace] = availableToDisplay.first;
        }
      });
    }
  }

  void _toggleGlobalSharing(bool value) async {
    if (!mounted) return;

    setState(() {
      _shareInGlobalFeed = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shareInGlobalFeed', value);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // On recherche la journée postée AUJOURD'HUI par l'utilisateur
    final todayStart = DateTime(_today.year, _today.month, _today.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final querySnapshot =
        await _firestore
            .collection('journees')
            .where('userId', isEqualTo: currentUser.uid)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(todayEnd))
            .limit(1)
            .get();

    // Si une journée existe pour aujourd'hui, on la met à jour
    if (querySnapshot.docs.isNotEmpty) {
      final docId = querySnapshot.docs.first.id;

      // On prépare les données à mettre à jour
      final Map<String, dynamic> updateData = {'estPublic': value};

      // --- C'EST LA PARTIE CRUCIALE ---
      // Si l'utilisateur active le partage ET que son pays est connu...
      if (value &&
          _currentUserCountry != null &&
          _currentUserCountry!.isNotEmpty) {
        // ...on ajoute le pays de l'utilisateur au document de la journée.
        updateData['userCountry'] = _currentUserCountry!;
      } else if (!value) {
        // Optionnel mais propre : si l'utilisateur rend sa journée privée,
        // on peut retirer le champ 'userCountry'
        updateData['userCountry'] = FieldValue.delete();
      }
      // --- FIN DE LA PARTIE CRUCIALE ---

      await _firestore.collection('journees').doc(docId).update(updateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Votre journée est maintenant visible dans le fil mondial.'
                  : 'Votre journée n\'est plus visible dans le fil mondial.',
            ),
            backgroundColor: value ? Colors.green : Colors.orange,
          ),
        );
      }
    } else {
      // Si aucune journée n'a été postée aujourd'hui
      if (value && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Postez votre journée d\'aujourd\'hui pour qu\'elle apparaisse dans le fil mondial.',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }

  void _onGlobalFilterChanged(String newFilter) {
    if (_globalFilter == newFilter) return;
    setState(() {
      _globalFilter = newFilter;
    });
    _setupGlobalJourneesListener();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    bool hasPostedToday = _hasPostedToday();

    return DefaultTabController(
      length: 3,
      child: ValueListenableBuilder<Brightness>(
        valueListenable: appBrightnessNotifier,
        builder: (context, currentBrightness, child) {
          final isDarkMode = currentBrightness == Brightness.dark;
          final textColor = isDarkMode ? Colors.white : Colors.white;
          final appBarColor = isDarkMode ? Colors.black : Colors.blue.shade700;
          final iconColor = isDarkMode ? Colors.white : Colors.white;

          return Scaffold(
            backgroundColor: isDarkMode ? Colors.black : Colors.white,
            appBar: AppBar(
              backgroundColor: appBarColor,
              // --- MODIFICATION COMMENCE ICI ---
              leading: Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.group_add, color: iconColor),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddFriendsPage(),
                        ),
                      );
                    },
                  ),
                  if (_friendRequestCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          _friendRequestCount > 5
                              ? '5+'
                              : _friendRequestCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              // --- MODIFICATION TERMINE ICI ---
              title: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(3.14159),
                    child: IconButton(
                      icon: Icon(
                        Icons.auto_stories,
                        color:
                            isDarkMode ? Colors.white : Colors.amber.shade300,
                        size: 28,
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => const AutobiographieDialog(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Daytalia',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontSize: 24,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _showNiveauDeVieDialog();
                    },
                    child: Icon(
                      Icons.favorite,
                      color: isDarkMode ? Colors.white : Colors.red.shade300,
                      size: 28,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.person, color: iconColor),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfilePage(),
                      ),
                    );
                    if (mounted) {
                      _loadVipStatus();
                      // Recharger les préférences après retour de la page profil
                      setState(() {
                        _journeeCardDesignFuture = _getPreference(
                          'journeeCardDesign',
                          'carrer',
                        );
                        _souvenirCardDesignFuture = _getPreference(
                          'cardDesign',
                          'carrer',
                        );
                        _journeeCardAnimationFuture = _getPreference(
                          'journeeAnimation',
                          'rebondissant',
                        );
                        _souvenirCardAnimationFuture = _getPreference(
                          'cardAnimation',
                          'rebondissant',
                        );
                        _cardSizeFuture = _getCardSizeFromPreferences();
                        // AJOUT : Recharger la couleur
                        _journeeCardColorFuture = _getPreference(
                          'journeeCardColor',
                          'bleu',
                        );
                        _souvenirCardColorFuture = _getPreference(
                          'cardColor',
                          'bleu',
                        );
                      });
                    }
                  },
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: iconColor,
                labelColor: textColor,
                unselectedLabelColor:
                    isDarkMode ? Colors.grey : Colors.blue.shade200,
                tabs: [
                  ValueListenableBuilder<String>(
                    valueListenable: _tabTitleNotifier,
                    builder: (context, tabTitle, _) {
                      return Tab(text: tabTitle);
                    },
                  ),
                  const Tab(text: 'Amis'),
                  const Tab(text: 'Mondial'),
                ],
                onTap: (index) {
                  if (index == 0) {
                  } else {
                    if (_verticalMainPageController.hasClients &&
                        _verticalMainPageController.page == 1) {
                      _verticalMainPageController.jumpToPage(0);
                      _tabTitleNotifier.value = 'Mes Journées';
                    }
                  }
                },
              ),
            ),
            body: TabBarView(
              controller: _tabController,
              children: [
                PageView(
                  controller: _verticalMainPageController,
                  onPageChanged: (index) {
                    if (index == 0) {
                      _tabTitleNotifier.value = 'Mes Journées';
                    } else if (index == 1) {
                      _tabTitleNotifier.value = 'Mes Souvenirs';
                    }
                  },
                  scrollDirection: Axis.vertical,
                  children: [
                    _buildMyJourneesTab(hasPostedToday),
                    _buildMySouvenirsTab(),
                  ],
                ),
                _buildFriendsJourneesTab(hasPostedToday),
                _buildGlobalJourneesTab(hasPostedToday),
              ],
            ),
          );
        },
      ),
    );
  }

  // Dans la classe HomePageState de home_page.dart
  Widget _buildMyJourneesTab(bool hasPostedToday) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // --- 1. CONTENU PRINCIPAL ---
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            // ANCIENNE VERSION : La liste s'affiche directement sans cadre autour
            else if (hasPostedToday)
              ValueListenableBuilder<String>(
                valueListenable: journeeFilterNotifier,
                builder: (context, filter, _) {
                  final journeesAffichees =
                      _myJournees.where((j) {
                        final isToday =
                            j.date.year == _today.year &&
                            j.date.month == _today.month &&
                            j.date.day == _today.day;
                        return j.note != null || isToday;
                      }).toList();

                  return _buildJourneeList(
                    journeesAffichees,
                    'Mes Journées',
                    showRepublishButton: false,
                    hasUserPostedToday: hasPostedToday,
                  );
                },
              )
            // CAS 2 : Cartes flottantes si rien n'est posté
            else if (_displayedJournees.isNotEmpty)
              _buildFloatingCards(constraints)
            // CAS 3 : Message vide
            else
              _buildEmptyMessage(
                "Aucune journée à afficher. \nCréez-en une pour commencer !",
              ),

            // --- 2. BOUTON FILTRE (En haut à droite) ---
            if (!hasPostedToday)
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  icon: Icon(
                    Icons.filter_list,
                    color:
                        appBrightnessNotifier.value == Brightness.dark
                            ? Colors.white
                            : Colors.blue.shade700,
                  ),
                  onPressed:
                      () => _showJourneeFilterDialog(journeeFilterNotifier),
                ),
              ),

            // --- 3. BOUTON SIMILAIRES (En haut à gauche) ---
            if (hasPostedToday)
              Positioned(
                top: 12,
                left: 12,
                child: _buildSimilarButton(context),
              ),
          ],
        );
      },
    );
  }

  // Séparation de la logique de contenu pour plus de lisibilité
  Widget _buildMainContent(
    bool hasPostedToday,
    BoxConstraints constraints,
    Color bgColor,
  ) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (hasPostedToday) {
      // Vue en Liste
      return ValueListenableBuilder<String>(
        valueListenable: journeeFilterNotifier,
        builder: (context, filter, _) {
          final journeesAffichees =
              _myJournees.where((j) {
                final isToday =
                    j.date.year == _today.year &&
                    j.date.month == _today.month &&
                    j.date.day == _today.day;
                return j.note != null || isToday;
              }).toList();

          return Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth:
                    _isFullScreen
                        ? constraints.maxWidth
                        : constraints.maxWidth * 0.9,
                maxHeight:
                    _isFullScreen
                        ? constraints.maxHeight
                        : constraints.maxHeight * 0.85,
              ),
              padding:
                  _isFullScreen
                      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 18)
                      : const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(_isFullScreen ? 18 : 16),
              ),
              child: _buildJourneeList(
                journeesAffichees,
                'Mes Journées',
                showRepublishButton: false,
                hasUserPostedToday: hasPostedToday,
              ),
            ),
          );
        },
      );
    } else if (_displayedJournees.isNotEmpty) {
      // Vue en Cartes Flottantes (Futures imbriqués)
      return _buildFloatingCards(constraints);
    } else {
      // Message Vide
      return _buildEmptyMessage(
        "Aucune journée à afficher. \nCréez-en une pour commencer !",
      );
    }
  }

  Widget _buildSimilarButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_isVip) {
          final todayJournee =
              _myJournees
                  .where(
                    (j) =>
                        j.date.year == _today.year &&
                        j.date.month == _today.month &&
                        j.date.day == _today.day,
                  )
                  .firstOrNull;

          if (todayJournee != null && todayJournee.note != null) {
            _showSimilarJourneesDialog();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Confirmez votre journée d\'abord pour activer la recherche de similaires.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          showVipPromotionPopup(context, "Journées Similaires");
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: _isVip ? Colors.blue.shade100 : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (_isVip ? Colors.blue : Colors.grey).withOpacity(0.2),
              blurRadius: 5,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isVip ? Icons.compare_arrows : Icons.lock,
              color: _isVip ? Colors.blue.shade700 : Colors.grey.shade600,
              size: 13,
            ),
            const SizedBox(width: 4),
            Text(
              'Similaires',
              style: TextStyle(
                color: _isVip ? Colors.blue.shade700 : Colors.grey.shade600,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper pour gérer la cascade de FutureBuilder des cartes
  Widget _buildFloatingCards(BoxConstraints constraints) {
    return FutureBuilder<String>(
      future: _cardSizeFuture,
      builder: (context, sizeSnapshot) {
        if (!sizeSnapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        return FutureBuilder<String>(
          future: _journeeCardDesignFuture,
          builder: (context, designSnapshot) {
            if (!designSnapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            return FutureBuilder<String>(
              future: _journeeCardAnimationFuture,
              builder: (context, animationSnapshot) {
                if (!animationSnapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                return FutureBuilder<String>(
                  future: _journeeCardColorFuture,
                  builder: (context, colorSnapshot) {
                    if (!colorSnapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    return FutureBuilder<bool>(
                      future: _forceGlobalJourneeColorFuture,
                      builder: (context, forceSnapshot) {
                        if (!forceSnapshot.hasData)
                          return const Center(
                            child: CircularProgressIndicator(),
                          );

                        final sortedJournees = List<JourneeModel>.from(
                          _displayedJournees,
                        )..sort(
                          (a, b) => (_journeeZOrders[a.id] ?? 0.0).compareTo(
                            _journeeZOrders[b.id] ?? 0.0,
                          ),
                        );

                        return Stack(
                          children:
                              sortedJournees.map((journee) {
                                final actualColor =
                                    (forceSnapshot.data! ||
                                            journee.cardColor == null)
                                        ? colorSnapshot.data!
                                        : journee.cardColor!;
                                return MovingContentCard(
                                  key: ValueKey(journee.id),
                                  data: journee,
                                  design: designSnapshot.data!,
                                  color: actualColor,
                                  animationType: animationSnapshot.data!,
                                  size: sizeSnapshot.data!,
                                  onSendToBack:
                                      () => _sendJourneeToBack(journee),
                                  onReplaceRequest:
                                      () => _replaceJournee(journee),
                                  parentConstraints: constraints,
                                  contentBuilder:
                                      (ctx, data) => _buildJourneeCardContent(
                                        data as JourneeModel,
                                      ),
                                  onLongPress: () {},
                                  onTap:
                                      () => _showJourneeDetailDialog(journee),
                                );
                              }).toList(),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMySouvenirsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_displayedSouvenirs.isNotEmpty)
              FutureBuilder<String>(
                future: _cardSizeFuture,
                builder: (context, sizeSnapshot) {
                  if (!sizeSnapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final cardSize = sizeSnapshot.data!;

                  return FutureBuilder<String>(
                    future: _souvenirCardDesignFuture,
                    builder: (context, designSnapshot) {
                      if (!designSnapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final cardDesign = designSnapshot.data!;

                      return FutureBuilder<String>(
                        future: _souvenirCardAnimationFuture,
                        builder: (context, animationSnapshot) {
                          if (!animationSnapshot.hasData)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          final cardAnimation = animationSnapshot.data!;

                          return FutureBuilder<String>(
                            future: _souvenirCardColorFuture,
                            builder: (context, colorSnapshot) {
                              if (!colorSnapshot.hasData)
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              final globalCardColor = colorSnapshot.data!;

                              return FutureBuilder<bool>(
                                future: _forceGlobalSouvenirColorFuture,
                                builder: (context, forceSnapshot) {
                                  if (!forceSnapshot.hasData)
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  final forceGlobal = forceSnapshot.data!;

                                  final sortedSouvenirs = List<
                                    SouvenirModel
                                  >.from(_displayedSouvenirs)..sort((a, b) {
                                    final zA = _souvenirZOrders[a.id] ?? 0.0;
                                    final zB = _souvenirZOrders[b.id] ?? 0.0;
                                    return zA.compareTo(zB);
                                  });

                                  return Stack(
                                    children:
                                        sortedSouvenirs.map((souvenir) {
                                          final actualColor =
                                              (forceGlobal ||
                                                      souvenir.cardColor ==
                                                          null)
                                                  ? globalCardColor
                                                  : souvenir.cardColor!;
                                          return MovingContentCard(
                                            key: ValueKey(souvenir.id),
                                            data: souvenir,
                                            design: cardDesign,
                                            color: actualColor,
                                            animationType: cardAnimation,
                                            size: cardSize,
                                            onSendToBack:
                                                () => _sendSouvenirToBack(
                                                  souvenir,
                                                ),
                                            onReplaceRequest:
                                                () =>
                                                    _replaceSouvenir(souvenir),
                                            parentConstraints: constraints,
                                            contentBuilder:
                                                (ctx, data) =>
                                                    _buildSouvenirCardContent(
                                                      data as SouvenirModel,
                                                    ),
                                            onLongPress: () {},
                                            onTap:
                                                () => _showSouvenirDetailDialog(
                                                  souvenir,
                                                ),
                                          );
                                        }).toList(),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              )
            else
              _buildEmptyMessage("Vous n'avez aucun souvenir pour le moment."),

            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: Icon(
                  Icons.filter_list,
                  color:
                      appBrightnessNotifier.value == Brightness.dark
                          ? Colors.white
                          : Colors.blue.shade700,
                ),
                onPressed:
                    () => _showSouvenirFilterDialog(souvenirFilterNotifier),
              ),
            ),
          ],
        );
      },
    );
  }

  // Code corrigé
  String _getImagePath(String design, String color) {
    final safeDesign = design.isNotEmpty ? design : 'carrer';
    final safeColor = color.isNotEmpty ? color : 'bleu';
    // Correction : Ajoutez le chemin complet du dossier 'assets/'.
    return 'assets/${safeDesign}_${safeColor}.png';
  }

  // NOUVEAU : Widget pour construire le contenu d'une carte Journée
  Widget _buildJourneeCardContent(JourneeModel journee) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min, // Important pour le FittedBox
                children: [
                  if (journee.emoji != null)
                    Text(journee.emoji!, style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width:
                        150, // Permet le retour à la ligne avant le scaleDown
                    child: Text(
                      journee.texte1 ?? 'Aucune description',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (journee.note != null)
                    Text(
                      'Note: ${journee.note}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // NOUVEAU : Widget pour construire le contenu d'une carte Souvenir
  Widget _buildSouvenirCardContent(SouvenirModel souvenir) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      souvenir.texte,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _getQualiteColor(
                        souvenir.qualite,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _getQualiteLabel(souvenir.qualite),
                      style: TextStyle(
                        fontSize: 10,
                        color: _getQualiteColor(souvenir.qualite),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFriendsJourneesTab(bool hasPostedToday) {
    return _buildJourneeList(
      _friendsJournees,
      'Journées de mes amis',
      showRepublishButton: true,
      hasUserPostedToday: hasPostedToday,
    );
  }

  // --- WIDGET POUR L'ONGLET MONDIAL (MODIFIÉ) ---
  Widget _buildGlobalJourneesTab(bool hasPostedToday) {
    if (_isLoadingGlobalPrefs) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Barre de contrôle compacte — visible uniquement quand le partage est actif
        if (_shareInGlobalFeed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Row(
              children: [
                ActionChip(
                  label: Text(
                    'Mon Pays',
                    style: TextStyle(
                      fontSize: 11,
                      color: _globalFilter == 'mon_pays' ? Colors.white : null,
                    ),
                  ),
                  backgroundColor:
                      _globalFilter == 'mon_pays' ? Colors.blue : null,
                  onPressed: () => _onGlobalFilterChanged('mon_pays'),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  label: Text(
                    'Tous les Pays',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          _globalFilter == 'tous_les_pays'
                              ? Colors.white
                              : null,
                    ),
                  ),
                  backgroundColor:
                      _globalFilter == 'tous_les_pays' ? Colors.blue : null,
                  onPressed: () => _onGlobalFilterChanged('tous_les_pays'),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _toggleGlobalSharing(false),
                  icon: const Icon(Icons.visibility_off, size: 13),
                  label: const Text(
                    'Désactiver',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildJourneeList(
                _globalJournees,
                'Journées mondiales',
                showRepublishButton: true,
                hasUserPostedToday: hasPostedToday,
              ),
              // Overlay flou + switch d'activation — clippé pour ne pas déborder sur la barre du haut
              if (!_shareInGlobalFeed)
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.15),
                      alignment: Alignment.center,
                      child: Card(
                        elevation: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 20,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.public,
                                size: 40,
                                color: Colors.blue,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Activez le partage pour voir les journées du monde entier.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              SwitchListTile(
                                title: const Text('Partager ma journée'),
                                value: _shareInGlobalFeed,
                                onChanged: _toggleGlobalSharing,
                                activeColor: Colors.blue,
                                secondary: const Icon(Icons.visibility),
                                dense: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<SouvenirModel> _filterSouvenirs(
    List<SouvenirModel> souvenirs,
    String filter,
  ) {
    return souvenirs.where((souvenir) {
      switch (filter) {
        case 'public':
          return souvenir.estPublic;
        case 'prive':
          return !souvenir.estPublic;
        case 'nostalgie':
          return souvenir.qualite == sm.SouvenirQualite.nostalgie;
        case 'bonheur':
          return souvenir.qualite == sm.SouvenirQualite.bonheur;
        case 'jamais_oublie':
          return souvenir.qualite == sm.SouvenirQualite.jamaisOublie;
        default:
          return true;
      }
    }).toList();
  }

  void _showSouvenirFilterDialog(ValueNotifier<String> filterNotifier) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Filtrer les souvenirs',
            style: TextStyle(color: Colors.blue),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFilterRadioListTile(filterNotifier, 'tout', 'Tous'),
                _buildFilterRadioListTile(filterNotifier, 'public', 'Public'),
                _buildFilterRadioListTile(filterNotifier, 'prive', 'Privé'),
                const Divider(),
                _buildFilterRadioListTile(
                  filterNotifier,
                  'nostalgie',
                  'Nostalgie',
                ),
                _buildFilterRadioListTile(filterNotifier, 'bonheur', 'Bonheur'),
                _buildFilterRadioListTile(
                  filterNotifier,
                  'jamais_oublie',
                  'Jamais oublié',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer', style: TextStyle(color: Colors.blue)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterRadioListTile(
    ValueNotifier<String> filterNotifier,
    String value,
    String title,
  ) {
    return ValueListenableBuilder<String>(
      valueListenable: filterNotifier,
      builder: (context, currentFilter, child) {
        return RadioListTile<String>(
          title: Text(title),
          value: value,
          groupValue: currentFilter,
          onChanged: (val) {
            if (val != null) {
              filterNotifier.value = val;
              Navigator.pop(context);
            }
          },
          activeColor: Colors.blue,
        );
      },
    );
  }

  Future<int> _calculateTruthPercentage() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return 0;

    try {
      final journeesSnapshot =
          await FirebaseFirestore.instance
              .collection('journees')
              .where('userId', isEqualTo: currentUser.uid)
              .get();

      final souvenirsSnapshot =
          await FirebaseFirestore.instance
              .collection('souvenirs')
              .where('userId', isEqualTo: currentUser.uid)
              .get();

      final journeesDates =
          journeesSnapshot.docs
              .map((doc) => (doc['date'] as Timestamp).toDate())
              .toList();

      final souvenirsDates =
          souvenirsSnapshot.docs
              .map((doc) => (doc['date'] as Timestamp).toDate())
              .toList();

      final Set<DateTime> uniquePostDates = {};

      for (final date in journeesDates) {
        uniquePostDates.add(DateTime(date.year, date.month, date.day));
      }

      for (final date in souvenirsDates) {
        uniquePostDates.add(DateTime(date.year, date.month, date.day));
      }

      final int activeDaysCount = uniquePostDates.length;

      final creationDate = currentUser.metadata.creationTime;
      if (creationDate == null) {
        return 0;
      }

      final int totalDaysSinceRegistration =
          DateTime.now().difference(creationDate.toLocal()).inDays + 1;

      if (totalDaysSinceRegistration <= 0) {
        return activeDaysCount > 0 ? 100 : 0;
      }

      final double reliabilityPercentage =
          (activeDaysCount / totalDaysSinceRegistration) * 100;

      return reliabilityPercentage.clamp(0, 100).round();
    } catch (e) {
      print('Erreur lors du calcul du pourcentage de fiabilité : $e');
      return 0;
    }
  }

  Future<void> _showNiveauDeVieDialog() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final userSubscriptionData = await getUserSubscriptionData();
      final isVip = userSubscriptionData['isVip'];
      final lastIaUpdateTimestamp =
          userSubscriptionData['lastIaUpdate'] as Timestamp?;
      final lastIaUpdate = lastIaUpdateTimestamp?.toDate();

      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      bool isIAAnalysisActive = userData['isIAAnalysisActive'] ?? false;
      bool isTruthAdjustmentActive =
          userData['isTruthAdjustmentActive'] ?? false;

      int truthPercentage = await _calculateTruthPercentage();
      debugPrint(
        '[FIDELITE] Pourcentage de fiabilité calculé : $truthPercentage%',
      );

      int qualiteDeVieActuelle = userData['qualiteDeVieActuelle'] ?? 50;

      int adjustNoteWithTruth(int note, int truthPercentage) {
        int adjusted = (note * truthPercentage / 100).round();
        debugPrint(
          '[FIDELITE] Ajustement -> Note de base: $note, Fiabilité: $truthPercentage%, Résultat: $adjusted',
        );
        return adjusted;
      }

      Future<Map<String, dynamic>> analyseEmotionsEtSouvenirsParIA() async {
        final url = Uri.parse(
          'https://api.deepinfra.com/v1/openai/chat/completions',
        );
        if (currentUser == null)
          return {
            'qualiteDeVie': 50,
            'analyse': 'Utilisateur non trouvé.',
            'recommandations': [],
          };

        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();
        if (!userDoc.exists) {
          return {
            'qualiteDeVie': 50,
            'analyse': 'Profil utilisateur non trouvé.',
            'recommandations': [],
          };
        }

        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        List<Map<String, dynamic>> newLifeEvents = [];
        List<DocumentReference> elementsToUpdateRefs = [];

        final categoriesSnapshot =
            await _firestore
                .collection('users')
                .doc(currentUser.uid)
                .collection('categories_elements')
                .get();

        for (final categoryDoc in categoriesSnapshot.docs) {
          final categoryName = categoryDoc.data()['nom'] ?? 'Inconnue';
          final elementsSnapshot =
              await categoryDoc.reference
                  .collection('elements')
                  .where('lastAnalyzed', isEqualTo: null)
                  .get();

          for (final elementDoc in elementsSnapshot.docs) {
            final elementData = elementDoc.data();
            newLifeEvents.add({
              'category': categoryName,
              'text': elementData['texte'],
              'explanation': elementData['explication'],
              'date':
                  (elementData['date'] as Timestamp).toDate().toIso8601String(),
            });
            elementsToUpdateRefs.add(elementDoc.reference);
          }
        }

        if (newLifeEvents.isEmpty) {
          return {
            'qualiteDeVie': userData['iaQualiteDeVie'] ?? 50,
            'analyse':
                "Tous les éléments ont déjà été analysés. Votre note de vie reste inchangée.",
            'recommandations': userData['iaRecommendations'] ?? [],
          };
        }

        int previousQualityOfLife = userData['iaQualiteDeVie'] ?? 50;
        final memoriesData = {
          "Jamais Oublié": {
            "count": userData['jamaisOublieCount'] ?? 0,
            "averageNote": userData['jamaisOublieNote'] ?? 50,
          },
          "Bonheur": {
            "count": userData['bonheurCount'] ?? 0,
            "averageNote": userData['bonheurNote'] ?? 50,
          },
          "Nostalgie": {
            "count": userData['nostalgieCount'] ?? 0,
            "averageNote": userData['nostalgieNote'] ?? 50,
          },
        };

        try {
          final response = await http.post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $DEEPSEEK_API_KEY',
            },
            body: jsonEncode({
              'model': await resolveAiModel(isVip: _isVip),
              'max_tokens': 800,
              'messages': [
                {
                  'role': 'user',
                  'content': '''
                      Tu es un psychologue. Mets à jour la note de qualité de vie d'un utilisateur en te basant sur de NOUVEAUX événements.
                      Contexte :
                      1. Qualité de vie PRÉCÉDENTE : $previousQualityOfLife/100.
                      2. Souvenirs : ${jsonEncode(memoriesData)}.
                      3. NOUVEAUX événements : ${jsonEncode(newLifeEvents)}.
                      Instructions :
                      - Ajuste la qualité de vie PRÉCÉDENTE.
                      - Rédige une analyse concise.
                      - Propose 2 recommandations.
                      Réponds UNIQUEMENT au format JSON EXACT :
                      {
                        "qualiteDeVie": 0-100,
                        "analyse": "Texte.",
                        "recommandations": ["Rec 1", "Rec 2"]
                      }
                      ''',
                },
              ],
            }),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(utf8.decode(response.bodyBytes));
            final content = data['choices'][0]['message']['content'] as String;

            Map<String, dynamic>? parsedJson;
            try {
              final codeBlockMatch = RegExp(
                r'```(?:json)?\s*'
                r'([\s\S]*?)'
                r'\s*```',
              ).firstMatch(content);
              if (codeBlockMatch != null) {
                final block = codeBlockMatch.group(1)!.trim();
                parsedJson = jsonDecode(block) as Map<String, dynamic>;
              }
            } catch (_) {}

            if (parsedJson == null) {
              final jsonMatch = RegExp(
                r'\{[\s\S]*\}',
                dotAll: true,
              ).firstMatch(content);
              if (jsonMatch != null) {
                try {
                  parsedJson =
                      jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
                } catch (_) {
                  try {
                    final sanitized = jsonMatch
                        .group(0)!
                        .replaceAllMapped(RegExp(r'[\x00-\x1F]'), (m) => ' ');
                    parsedJson = jsonDecode(sanitized) as Map<String, dynamic>;
                  } catch (_) {}
                }
              }
            }

            if (parsedJson != null) {
              final int qualiteDeVieCalculee =
                  parsedJson['qualiteDeVie'] is int
                      ? parsedJson['qualiteDeVie']
                      : int.tryParse(parsedJson['qualiteDeVie'].toString()) ??
                          previousQualityOfLife;

              WriteBatch batch = _firestore.batch();
              for (final docRef in elementsToUpdateRefs) {
                batch.update(docRef, {'lastAnalyzed': Timestamp.now()});
              }
              await batch.commit();

              return {
                'qualiteDeVie': qualiteDeVieCalculee,
                'analyse': parsedJson['analyse'] ?? 'Analyse non disponible.',
                'recommandations': List<String>.from(
                  parsedJson['recommandations'] ?? [],
                ),
              };
            }
          }
          return {
            'qualiteDeVie': previousQualityOfLife,
            'analyse': 'Impossible de générer une analyse complète.',
            'recommandations': [],
          };
        } catch (e) {
          throw Exception('Erreur de connexion à l\'IA : $e');
        }
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final bgColor = isDark ? Colors.grey[900] : Colors.white;
          final textColor = isDark ? Colors.white : Colors.black87;

          return StatefulBuilder(
            builder: (context, setStateDialog) {
              bool isUpdatingIA = false;
              bool canUpdateIA = false;
              int remainingDays = 0;

              if (isVip) {
                canUpdateIA = true;
              } else {
                if (lastIaUpdate == null) {
                  canUpdateIA = true;
                } else {
                  remainingDays =
                      7 - DateTime.now().difference(lastIaUpdate).inDays;
                  canUpdateIA = remainingDays <= 0;
                }
              }

              int calculateDisplayQualiteDeVie() {
                int baseNote =
                    isIAAnalysisActive
                        ? (userData['iaQualiteDeVie'] ?? qualiteDeVieActuelle)
                        : qualiteDeVieActuelle;
                int finalNote =
                    isTruthAdjustmentActive
                        ? adjustNoteWithTruth(baseNote, truthPercentage)
                        : baseNote;

                debugPrint(
                  '[FIDELITE] UI MAJ -> Note de base (IA=$isIAAnalysisActive): $baseNote | Fidélité Active: $isTruthAdjustmentActive | Note Finale Affichée: $finalNote',
                );
                return finalNote;
              }

              int displayQualiteDeVie = calculateDisplayQualiteDeVie();
              String displayAnalyse =
                  isIAAnalysisActive
                      ? (userData['iaAnalyse'] ?? 'Analyse IA non disponible')
                      : _getQualiteDeVieMessage(displayQualiteDeVie);
              List<String> recommandations =
                  isIAAnalysisActive
                      ? List<String>.from(userData['iaRecommendations'] ?? [])
                      : [];

              Color couleur = _getQualiteDeVieColor(displayQualiteDeVie);

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: couleur.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- EN-TÊTE ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(Icons.favorite, color: couleur, size: 32),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: Colors.grey.shade500,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Votre Qualité de Vie',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // --- BARRE DE PROGRESSION & SCORE ---
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              height: 120,
                              width: 120,
                              child: CircularProgressIndicator(
                                value: displayQualiteDeVie / 100,
                                backgroundColor:
                                    isDark
                                        ? Colors.grey[800]
                                        : Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  couleur,
                                ),
                                strokeWidth: 12,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Column(
                              children: [
                                Text(
                                  '$displayQualiteDeVie',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: couleur,
                                    height: 1.0,
                                  ),
                                ),
                                Text(
                                  '/100',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // --- FIABILITÉ ---
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isDark
                                    ? Colors.grey[800]
                                    : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.verified_user_rounded,
                                color: Colors.blue.shade600,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Fiabilité des données : $truthPercentage%',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // --- ANALYSE IA ---
                        if (isIAAnalysisActive)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: couleur.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: couleur.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              displayAnalyse,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: textColor,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),

                        // --- RECOMMANDATIONS ---
                        if (recommandations.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Recommandations',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: textColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...recommandations
                              .map(
                                (rec) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: couleur,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          rec,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: textColor,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ],

                        const SizedBox(height: 32),

                        // --- BOUTON DE MISE À JOUR IA ---
                        if (isIAAnalysisActive)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  (isUpdatingIA || !canUpdateIA)
                                      ? null
                                      : () async {
                                        setStateDialog(
                                          () => isUpdatingIA = true,
                                        );
                                        try {
                                          final resultIA =
                                              await analyseEmotionsEtSouvenirsParIA();
                                          await FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(currentUser.uid)
                                              .update({
                                                'iaQualiteDeVie':
                                                    resultIA['qualiteDeVie'],
                                                'iaAnalyse':
                                                    resultIA['analyse'],
                                                'iaRecommendations':
                                                    resultIA['recommandations'],
                                                if (!isVip)
                                                  'lastIaAnalysisUpdate':
                                                      FieldValue.serverTimestamp(),
                                              });

                                          setStateDialog(() {
                                            userData['iaQualiteDeVie'] =
                                                resultIA['qualiteDeVie'];
                                            userData['iaAnalyse'] =
                                                resultIA['analyse'];
                                            userData['iaRecommendations'] =
                                                resultIA['recommandations'];
                                          });
                                        } catch (e) {
                                          if (context.mounted)
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text('Erreur: $e'),
                                              ),
                                            );
                                        } finally {
                                          if (context.mounted)
                                            setStateDialog(
                                              () => isUpdatingIA = false,
                                            );
                                        }
                                      },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: couleur,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child:
                                  isUpdatingIA
                                      ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                      : Text(
                                        !canUpdateIA
                                            ? "Disponible dans $remainingDays jour(s)"
                                            : "Mettre à jour l'analyse",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                            ),
                          ),

                        const SizedBox(height: 16),

                        // --- TOGGLES OPTIONS (Fidélité & IA) ---
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  setStateDialog(
                                    () =>
                                        isTruthAdjustmentActive =
                                            !isTruthAdjustmentActive,
                                  );
                                  debugPrint(
                                    '[FIDELITE] Clic sur le bouton Fidélité. Nouvel état dans la base de données : $isTruthAdjustmentActive',
                                  );
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(currentUser.uid)
                                      .update({
                                        'isTruthAdjustmentActive':
                                            isTruthAdjustmentActive,
                                      });
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  side: BorderSide(
                                    color:
                                        isTruthAdjustmentActive
                                            ? Colors.blue
                                            : Colors.grey.shade300,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  backgroundColor:
                                      isTruthAdjustmentActive
                                          ? Colors.blue.withOpacity(0.1)
                                          : Colors.transparent,
                                ),
                                child: Text(
                                  isTruthAdjustmentActive
                                      ? 'Fidélité ON'
                                      : 'Fidélité OFF',
                                  style: TextStyle(
                                    color:
                                        isTruthAdjustmentActive
                                            ? Colors.blue
                                            : Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  if (!isIAAnalysisActive) {
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder:
                                          (context) => const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                    );
                                    try {
                                      final resultIA =
                                          await analyseEmotionsEtSouvenirsParIA();
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(currentUser.uid)
                                          .update({
                                            'iaQualiteDeVie':
                                                resultIA['qualiteDeVie'],
                                            'iaAnalyse': resultIA['analyse'],
                                            'iaRecommendations':
                                                resultIA['recommandations'],
                                            'isIAAnalysisActive': true,
                                          });
                                      setStateDialog(() {
                                        isIAAnalysisActive = true;
                                        userData['iaQualiteDeVie'] =
                                            resultIA['qualiteDeVie'];
                                        userData['iaAnalyse'] =
                                            resultIA['analyse'];
                                        userData['iaRecommendations'] =
                                            resultIA['recommandations'];
                                      });
                                    } catch (e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Une erreur est survenue: $e',
                                          ),
                                        ),
                                      );
                                    } finally {
                                      Navigator.of(
                                        context,
                                      ).pop(); // Enlève le loader
                                    }
                                  } else {
                                    setStateDialog(
                                      () => isIAAnalysisActive = false,
                                    );
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(currentUser.uid)
                                        .update({'isIAAnalysisActive': false});
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  side: BorderSide(
                                    color:
                                        isIAAnalysisActive
                                            ? Colors.deepPurple
                                            : Colors.grey.shade300,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  backgroundColor:
                                      isIAAnalysisActive
                                          ? Colors.deepPurple.withOpacity(0.1)
                                          : Colors.transparent,
                                ),
                                child: Text(
                                  isIAAnalysisActive ? 'IA ON' : 'IA OFF',
                                  style: TextStyle(
                                    color:
                                        isIAAnalysisActive
                                            ? Colors.deepPurple
                                            : Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      print('Erreur lors de la récupération de la qualité de vie : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de récupérer votre niveau de vie'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getQualiteDeVieMessage(int qualiteDeVie) {
    if (qualiteDeVie < 20) {
      return "Votre qualité de vie est actuellement très basse. Il est important de prendre soin de vous, de vous entourer et de chercher du soutien.";
    } else if (qualiteDeVie < 40) {
      return "Votre qualité de vie peut être améliorée. Concentrez-vous sur des activités positives et prenez soin de votre bien-être mental et physique.";
    } else if (qualiteDeVie < 60) {
      return "Votre qualité de vie est moyenne. Il y a des opportunités d'amélioration et de croissance personnelle.";
    } else if (qualiteDeVie < 80) {
      return "Votre qualité de vie est bonne ! Continuez à maintenir un équilibre positif dans votre vie.";
    } else {
      return "Votre qualité de vie est excellente ! Continuez à cultiver les habitudes qui vous apportent du bonheur et de la satisfaction.";
    }
  }

  Color _getQualiteDeVieColor(int qualiteDeVie) {
    if (qualiteDeVie < 20) {
      return Colors.red.shade700;
    } else if (qualiteDeVie < 50) {
      return Colors.orange.shade700;
    } else if (qualiteDeVie < 80) {
      return Colors.green.shade500;
    } else {
      return Colors.green.shade700;
    }
  }

  Widget _buildJourneeCard(
    JourneeModel journee,
    String title, {
    bool showRepublishButton = false,
    required bool hasUserPostedToday,
  }) {
    bool isMyJournees = title == 'Mes Journées';
    final currentUser = FirebaseAuth.instance.currentUser;

    final bool isMentioned = (journee.mentionedUserIds ?? []).contains(
      currentUser?.uid,
    );
    final bool journeeHasHiddenText =
        (journee.hiddenTextFriends ?? []).isNotEmpty;
    final bool isHiddenFromMe = (journee.hiddenTextFriends ?? []).contains(
      currentUser?.uid,
    );
    bool shouldBlurText =
        !isMyJournees && (!hasUserPostedToday && !isMentioned);
    bool shouldShowPartialMask =
        !isMyJournees && journeeHasHiddenText && isHiddenFromMe;
    bool isToday =
        journee.date.year == _today.year &&
        journee.date.month == _today.month &&
        journee.date.day == _today.day;
    bool isLive = journee.note == null;
    final wordCount = _countWords(journee.texte1 ?? '');

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(journee.userId).get(),
      builder: (context, userSnapshot) {
        final isDark = appBrightnessNotifier.value == Brightness.dark;
        Map<String, dynamic> personalizationPreferences =
            (userSnapshot.data?.data()
                as Map<String, dynamic>?)?['personalizationPreferences'] ??
            {};

        bool forceGlobal =
            personalizationPreferences['forceGlobalJourneeColor'] ?? false;
        String colorPref =
            forceGlobal
                ? (personalizationPreferences['journeeCardColor'] ?? 'bleu')
                : (journee.cardColor ??
                    personalizationPreferences['journeeCardColor'] ??
                    'bleu');

        Color cardColor;
        switch (colorPref) {
          case 'noir':
            cardColor = isDark ? Colors.grey.shade900 : Colors.black87;
            break;
          case 'rouge':
            cardColor = isDark ? Colors.red.shade900 : Colors.red.shade400;
            break;
          case 'vert':
            cardColor = isDark ? Colors.green.shade900 : Colors.green.shade400;
            break;
          case 'orange':
            cardColor =
                isDark ? Colors.orange.shade900 : Colors.orange.shade400;
            break;
          case 'jaune':
            cardColor =
                isDark ? Colors.yellow.shade900 : Colors.yellow.shade600;
            break;
          case 'violet':
            cardColor =
                isDark ? Colors.purple.shade900 : Colors.purple.shade300;
            break;
          case 'rose':
            cardColor = isDark ? Colors.pink.shade900 : Colors.pink.shade300;
            break;
          case 'blanc':
            cardColor = isDark ? Colors.grey.shade300 : Colors.white;
            break;
          case 'bleu':
          default:
            cardColor = isDark ? Colors.blue.shade900 : Colors.blue.shade300;
            break;
        }

        final Color cardEndColor = isDark ? Colors.grey.shade900 : Colors.white;
        final Color mainTextColor =
            cardColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
        final Color secondaryTextColor = mainTextColor.withOpacity(0.7);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side:
                journee.isRepost
                    ? const BorderSide(color: Colors.grey, width: 2.0)
                    : BorderSide.none,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cardColor, cardEndColor],
              ),
              boxShadow: [
                BoxShadow(
                  color: cardColor.withOpacity(
                    0.6,
                  ), // Flou beaucoup plus visible !
                  spreadRadius: 4,
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                20.0,
                20.0,
                20.0,
                10.0,
              ), // Padding ajusté
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. EN-TÊTE FIXE
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (journee.isRepost)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Text(
                                  'De ${journee.repostedFromUserName ?? 'un ami'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: secondaryTextColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (isMyJournees)
                              Chip(
                                label: Text(
                                  journee.estPublic ? 'Public' : 'Privé',
                                  style: TextStyle(
                                    color:
                                        journee.estPublic
                                            ? Colors.green
                                            : Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                                backgroundColor:
                                    journee.estPublic
                                        ? Colors.green.shade50
                                        : Colors.red.shade50,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isMyJournees)
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: mainTextColor),
                          onSelected: (value) {
                            if (value == 'modifier')
                              _modifierJournee(journee);
                            else if (value == 'supprimer')
                              _supprimerJournee(journee);
                          },
                          itemBuilder:
                              (BuildContext context) => [
                                const PopupMenuItem(
                                  value: 'modifier',
                                  child: Text('Modifier'),
                                ),
                                const PopupMenuItem(
                                  value: 'supprimer',
                                  child: Text('Supprimer'),
                                ),
                              ],
                        ),
                    ],
                  ),
                  if ((title == 'Journées de mes amis' ||
                          title == 'Journées mondiales') &&
                      !hasUserPostedToday)
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12.0),
                                child: ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: 6,
                                    sigmaY: 6,
                                  ),
                                  child: Opacity(
                                    opacity: 0.45,
                                    child: Text(
                                      journee.texte1 ?? '',
                                      style: TextStyle(
                                        fontSize: _calculateFontSize(
                                          journee.texte1 ?? '',
                                        ),
                                        color: mainTextColor,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: mainTextColor.withOpacity(0.6),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  color: mainTextColor.withOpacity(0.1),
                                ),
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  'Postez votre journée pour voir le contenu complet des autres utilisateurs.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: mainTextColor,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(height: 10),

                  // 2. TEXTE & IMAGES (Qui peuvent scroller si c'est trop long)
                  if ((title == 'Journées de mes amis' ||
                          title == 'Journées mondiales') &&
                      !hasUserPostedToday)
                    const SizedBox.shrink()
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            shouldBlurText
                                ? ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: 5,
                                    sigmaY: 5,
                                  ),
                                  child: Text(
                                    journee.texte1 ?? '',
                                    style: TextStyle(
                                      fontSize: _calculateFontSize(
                                        journee.texte1 ?? '',
                                      ),
                                      color: mainTextColor,
                                      height: 1.5,
                                    ),
                                  ),
                                )
                                : isMyJournees
                                ? Text(
                                  journee.texte1 ?? '',
                                  style: TextStyle(
                                    fontSize: _calculateFontSize(
                                      journee.texte1 ?? '',
                                    ),
                                    color: mainTextColor,
                                    height: 1.5,
                                  ),
                                )
                                : shouldShowPartialMask &&
                                    !(journee.texte1Masked ?? '').contains('*')
                                ? ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: 5,
                                    sigmaY: 5,
                                  ),
                                  child: Text(
                                    journee.texte1 ?? '',
                                    style: TextStyle(
                                      fontSize: _calculateFontSize(
                                        journee.texte1 ?? '',
                                      ),
                                      color: mainTextColor,
                                      height: 1.5,
                                    ),
                                  ),
                                )
                                : _buildTextWithBlurredAsterisks(
                                  shouldShowPartialMask
                                      ? journee.texte1Masked!
                                      : (journee.texte1 ?? ''),
                                  style: TextStyle(
                                    fontSize: _calculateFontSize(
                                      journee.texte1 ?? '',
                                    ),
                                    color: mainTextColor,
                                    height: 1.5,
                                  ),
                                ),

                            if (!isMyJournees && isMentioned) ...[
                              const SizedBox(height: 10),
                              Center(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.repeat, size: 18),
                                  label: const Text('Republier cette journée'),
                                  onPressed: () => _republierJournee(journee),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            if (journee.photoUrls.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 80,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: journee.photoUrls.length,
                                  itemBuilder: (context, index) {
                                    final imageUrl = journee.photoUrls[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        right: 8.0,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          10.0,
                                        ),
                                        child: Image.network(
                                          imageUrl,
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (
                                            context,
                                            child,
                                            loadingProgress,
                                          ) {
                                            if (loadingProgress == null)
                                              return child;
                                            return Container(
                                              width: 80,
                                              height: 80,
                                              color: Colors.grey[200],
                                              child: const Center(
                                                child: CircularProgressIndicator(
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(Colors.blue),
                                                ),
                                              ),
                                            );
                                          },
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) {
                                            return Container(
                                              width: 80,
                                              height: 80,
                                              color: Colors.grey[200],
                                              child: const Icon(
                                                Icons.broken_image,
                                                color: Colors.grey,
                                                size: 40,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],

                            if (journee.commentaire != null &&
                                journee.commentaire!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  journee.commentaire!,
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: secondaryTextColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ),

                            if (isMyJournees && isToday && isLive) ...[
                              const SizedBox(height: 10),
                              Center(
                                child: ElevatedButton(
                                  onPressed:
                                      wordCount >= 4
                                          ? () => _confirmerJournee(journee)
                                          : () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (context) =>
                                                        JourneeEnDirectPage(
                                                          journeeToEdit:
                                                              journee,
                                                        ),
                                              ),
                                            );
                                          },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        wordCount >= 4
                                            ? Colors.green.shade600
                                            : Colors.orange.shade600,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    elevation: 3,
                                  ),
                                  child: Text(
                                    wordCount >= 4
                                        ? 'Confirmer ma journée'
                                        : 'Écrivez pour confirmer',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  // 3. BAS DE CARTE FIXE (Épinglé)
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (journee.emoji != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Text(
                            journee.emoji!,
                            style: const TextStyle(
                              fontSize: 24,
                            ), // Remis à sa place en bas
                          ),
                        ),
                      if (journee.note != null)
                        Text(
                          'Note: ${journee.note}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: secondaryTextColor,
                            fontSize: 14,
                          ),
                        ),
                      const Spacer(),
                      if (journee.reactions.isNotEmpty)
                        Builder(
                          builder: (context) {
                            int totalReactions = journee.reactions.values.fold(
                              0,
                              (sum, list) => sum + list.length,
                            );
                            // Prendre les 2 emojis les plus utilisés pour l'aperçu
                            var sortedReactions =
                                journee.reactions.entries.toList()..sort(
                                  (a, b) =>
                                      b.value.length.compareTo(a.value.length),
                                );
                            String topEmojis = sortedReactions
                                .take(2)
                                .map((e) => e.key)
                                .join('');

                            return InkWell(
                              onTap: () => _showReactionsDetailsDialog(journee),
                              borderRadius: BorderRadius.circular(15),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: mainTextColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      topEmojis,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      totalReactions.toString(),
                                      style: TextStyle(
                                        color: mainTextColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      const Spacer(),
                      if (!isMyJournees)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.add_reaction_outlined,
                            color: secondaryTextColor,
                          ),
                          tooltip: 'Réagir',
                          onPressed: () => _showReactionPicker(journee),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.chat_bubble_outline,
                          color: secondaryTextColor,
                        ),
                        tooltip: 'Commenter',
                        onPressed:
                            () => _showCommentsDialog(
                              journee,
                              isMyJournees: isMyJournees,
                            ),
                      ),
                      if (isMyJournees && journee.note != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            _isVip
                                ? Icons.lightbulb_outline
                                : Icons.lock_outline,
                            color:
                                _isVip
                                    ? Colors.amber.shade400
                                    : secondaryTextColor,
                          ),
                          onPressed: () {
                            if (_isVip) {
                              _showConseilsDialog(journee);
                            } else {
                              showVipPromotionPopup(
                                context,
                                "Conseils de l'IA",
                              );
                            }
                          },
                          tooltip:
                              _isVip
                                  ? 'Voir les conseils de l\'IA'
                                  : 'Fonctionnalité VIP',
                        ),
                      ],
                    ],
                  ),

                  // 4. SOUVENIRS ASSOCIÉS FIXES (Épinglés)
                  _AssociatedMemoriesWidget(
                    journee: journee,
                    souvenirs: _getSouvenirsForJournee(journee),
                    showRepublishButton: showRepublishButton,
                    hasUserPostedToday: hasUserPostedToday,
                    buildSouvenirCard: _buildSouvenirCard,
                    mainTextColor: mainTextColor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildJourneeList(
    List<JourneeModel> journees,
    String title, {
    bool showRepublishButton = false,
    required bool hasUserPostedToday,
  }) {
    final currentUser = FirebaseAuth.instance.currentUser;

    final List<JourneeModel> filteredJournees =
        journees.where((journee) {
          final isOwner = journee.userId == currentUser?.uid;
          if ((title == 'Journées de mes amis' ||
                  title == 'Journées mondiales') &&
              isOwner) {
            return false;
          }
          return true;
        }).toList();

    final sortedJournees = List<JourneeModel>.from(filteredJournees)
      ..sort((a, b) => b.date.compareTo(a.date));

    final displayItems = sortedJournees.take(50).toList();

    if (displayItems.isEmpty) {
      return _buildEmptyMessage('Aucune journée disponible pour le moment.');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 90.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PageView.builder(
              controller: _journeePageController,
              itemCount: displayItems.length,
              itemBuilder: (context, index) {
                final journee = displayItems[index];
                final isMyJournees = title == 'Mes Journées';
                final isOwner = journee.userId == currentUser?.uid;

                return Column(
                  children: [
                    FutureBuilder<Map<String, dynamic>>(
                      future: _getUserData(journee.userId ?? ''),
                      builder: (context, userSnapshot) {
                        String username;
                        Widget trailingWidget;

                        if (userSnapshot.connectionState ==
                                ConnectionState.waiting &&
                            !userSnapshot.hasData) {
                          username = '';
                          trailingWidget = const _BlinkingDots();
                        } else {
                          final userData =
                              userSnapshot.data ??
                              {'username': 'Utilisateur Inconnu'};
                          username =
                              userData['username'] ?? 'Utilisateur Inconnu';
                          trailingWidget =
                              !isMyJournees
                                  ? PopupMenuButton<String>(
                                    icon: const Icon(
                                      Icons.more_vert,
                                      color: Colors.blueGrey,
                                    ),
                                    onSelected: (value) {
                                      if (value == 'signaler') {
                                        _signalerJournee(journee);
                                      }
                                    },
                                    // --- MODIFICATION ---
                                    // Le itemBuilder ne retourne plus que l'option "Signaler"
                                    itemBuilder: (BuildContext context) {
                                      return [
                                        const PopupMenuItem(
                                          value: 'signaler',
                                          child: Text('Signaler'),
                                        ),
                                      ];
                                    },
                                    // --- FIN DE LA MODIFICATION ---
                                  )
                                  : const SizedBox.shrink();
                        }

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(
                            16.0,
                            10.0,
                            4.0,
                            5.0,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child:
                                    isMyJournees
                                        ? Center(
                                          child: Text(
                                            _formatDate(journee.date),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                        )
                                        : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder:
                                                        (context) =>
                                                            ProfileUserPage(
                                                              userId:
                                                                  journee
                                                                      .userId ??
                                                                  '',
                                                            ),
                                                  ),
                                                );
                                              },
                                              child: Text(
                                                '@$username',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _formatDate(journee.date),
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                              ),
                              trailingWidget,
                            ],
                          ),
                        );
                      },
                    ),
                    Expanded(
                      child: _buildJourneeCard(
                        journee,
                        title,
                        showRepublishButton: showRepublishButton,
                        hasUserPostedToday: hasUserPostedToday,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showReactionPicker(JourneeModel journee) {
    final List<String> reactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16.0),
            padding: const EdgeInsets.symmetric(
              vertical: 20.0,
              horizontal: 16.0,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25.0),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 20.0,
              runSpacing: 10.0,
              children:
                  reactions.map((emoji) {
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _handleReaction(journee, emoji);
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _republierJournee(JourneeModel journee) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JourneePage(journeeToRepublish: journee),
      ),
    );
  }

  void _republierSouvenir(JourneeModel journee) async {
    final tempSouvenir = SouvenirModel(
      texte: journee.texte1 ?? journee.commentaire ?? 'Souvenir de ma journée',
      date: journee.date,
      estPublic: journee.estPublic,
      qualite: sm.SouvenirQualite.nostalgie,
      noteQualite: int.tryParse(journee.note?.split('/').first ?? '50') ?? 50,
      photoUrls: journee.photoUrls,
      userId: journee.userId!,
      isRepost: true,
      repostedFromUserId: journee.userId,
      repostedFromUserName: await _getUsernameById(journee.userId!),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SouvenirPage(souvenirToRepublish: tempSouvenir),
      ),
    );
  }

  Future<String?> _getUsernameById(String userId) async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(userId).get();
      return userDoc['username'];
    } catch (e) {
      print(
        'Erreur lors de la récupération du nom d\'utilisateur pour $userId: $e',
      );
      return null;
    }
  }

  int _countWords(String text) {
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
  }

  Future<void> _confirmerJournee(JourneeModel journee) async {
    if (journee.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur : Journée non valide')),
      );
      return;
    }
    if (!mounted) return;
    final bool? wasModified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => JourneePage(journeeToEdit: journee),
      ),
    );
    if (wasModified == true && mounted) setState(() {});
  }

  Future<void> _obtenirNote(String texte) async {
    if (texte.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Aucun texte à évaluer')));
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String iaPreference = prefs.getString('iaPreference') ?? 'ressenti';

    String prompt;
    if (iaPreference == 'ressenti') {
      prompt =
          'Analyse ce texte et donne une note sur 100 basée sur le ressenti global de la journée. Réponds uniquement avec un nombre entier entre 0 et 100 suivi de "/100", par exemple "75/100". Texte : $texte';
    } else {
      prompt =
          'Analyse ce texte et donne une note sur 100 basée sur la qualité globale des événements de la journée. Réponds uniquement avec un nombre entier entre 0 et 100 suivi de "/100", par exemple "75/100". Texte : $texte';
    }

    const url = 'https://api.deepinfra.com/v1/openai/chat/completions';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': await resolveAiModel(isVip: _isVip),
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 50,
        }),
      );

      print('Réponse brute _obtenirNote: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data.containsKey('choices') &&
            data['choices'] is List &&
            data['choices'].isNotEmpty) {
          final noteText =
              data['choices'][0]['message']['content']?.toString() ?? '';

          if (noteText.isEmpty) {
            print('Contenu vide dans choices');
            setState(() {
              _note = 50;
              _isNoteObtained = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Réponse vide de l\'API pour la note.'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }

          final standardMatch = RegExp(r'(\d+)/100').firstMatch(noteText);
          if (standardMatch != null) {
            _note = int.parse(standardMatch.group(1)!);
          } else {
            final numberMatch = RegExp(r'(\d+)').firstMatch(noteText);
            if (numberMatch != null) {
              final extractedNumber = int.parse(numberMatch.group(1)!);
              _note = extractedNumber.clamp(0, 100);
            } else {
              _note = 50;
            }
          }
          setState(() {
            _isNoteObtained = true;
          });

          _motsCles = await _extraireMotsCles(texte);
          setState(() {});

          await _enregistrerElementsInteressants(texte);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Note obtenue : $_note/100'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          print('Structure de réponse invalide : $data');
          setState(() {
            _note = 50;
            _isNoteObtained = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La réponse de l\'API ne contient pas de contenu valide.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        print('Erreur API : ${response.statusCode} - ${response.body}');
        setState(() {
          _note = -1;
          _isNoteObtained = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors de l\'obtention de la note : ${response.statusCode}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Erreur de connexion _obtenirNote : $e');
      setState(() {
        _note = -1;
        _isNoteObtained = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur de connexion : $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String normaliserId(String texte) {
    final Map<String, String> accentsMap = {
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ñ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'À': 'a',
      'Á': 'a',
      'Â': 'a',
      'Ã': 'a',
      'Ä': 'a',
      'Ç': 'c',
      'È': 'e',
      'É': 'e',
      'Ê': 'e',
      'Ë': 'e',
      'Ì': 'i',
      'Í': 'i',
      'Î': 'i',
      'Ï': 'i',
      'Ñ': 'n',
      'Ò': 'o',
      'Ó': 'o',
      'Ô': 'o',
      'Õ': 'o',
      'Ö': 'o',
      'Ù': 'u',
      'Ú': 'u',
      'Û': 'u',
      'Ü': 'u',
      'Ý': 'y',
    };

    String result = texte.toLowerCase();
    accentsMap.forEach((accent, normal) {
      result = result.replaceAll(accent, normal);
    });
    result = result.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    result = result.trim().replaceAll(RegExp(r'\s+'), '_');

    if (result.isEmpty) {
      result = 'categorie_${DateTime.now().millisecondsSinceEpoch}';
    }
    return result;
  }

  Future<void> _enregistrerElementsInteressants(String texte) async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vous devez être connecté')));
      return;
    }
    if (DEEPSEEK_API_KEY == 'VOTRE_CLÉ_API_DEEPSEEK') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Clé API DeepSeek non configurée pour la catégorisation.',
          ),
        ),
      );
      return;
    }

    print('Début de l\'analyse pour catégorisation...');
    print('Texte à analyser: $texte');

    const url = 'https://api.deepinfra.com/v1/openai/chat/completions';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': await resolveAiModel(isVip: _isVip),
          'messages': [
            {
              'role': 'user',
              'content':
                  '''Analyse ce texte et extrais les éléments intéressants qui pourraient être expliqués dans une biographie.
          Pour chaque élément, détermine une catégorie thématique générale (comme "amis", "travail", "famille", "loisirs", "santé", "voyage", "éducation", "événements").
          Utilise uniquement des mots simples et des catégories générales.
          Réponds STRICTEMENT au format JSON suivant, sans aucun texte supplémentaire, ni préambule, ni postface. Assure-toi que la liste 'elements' est toujours présente, même vide:
          {
            "elements": [
              {
                "texte": "texte intéressant",
                "explication": "explication de l'élément",
                "categorie": "catégorie thématique"
              }
            ]
          }

          Texte à analyser : $texte''',
            },
          ],
          'max_tokens': 500,
        }),
      );

      print('Statut de la réponse: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String elementsText =
            data['choices']?[0]['message']['content']?.toString() ?? '';

        print('Réponse brute: $elementsText');

        Map<String, dynamic>? parsedElements;
        try {
          elementsText = elementsText.trim();
          elementsText = elementsText.replaceAll(
            RegExp(r'^```json\s*|\s*```$'),
            '',
          );
          parsedElements = jsonDecode(elementsText);
          print('JSON parsé avec succès');
        } catch (jsonError) {
          print('Erreur lors du parse JSON direct: $jsonError');
          final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(elementsText);
          if (jsonMatch != null) {
            try {
              String matchedJson = jsonMatch.group(0)!;
              print('JSON extrait par regex: $matchedJson');
              parsedElements = jsonDecode(matchedJson);
              print('JSON récupéré via regex');
            } catch (e) {
              print('Échec de la récupération via regex: $e');
            }
          }
        }

        if (parsedElements != null && parsedElements.containsKey('elements')) {
          List<dynamic> elements =
              parsedElements['elements'] is List
                  ? parsedElements['elements']
                  : [];
          print('Éléments trouvés: ${elements.length}');

          if (elements.isNotEmpty) {
            final categoriesSnapshot =
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser.uid)
                    .collection('categories_elements')
                    .get();

            Map<String, String> categoriesExistantes = {};
            for (var doc in categoriesSnapshot.docs) {
              String nomCategorie = doc.data()['nom'].toString();
              categoriesExistantes[normaliserId(nomCategorie)] = doc.id;
              categoriesExistantes[nomCategorie.toLowerCase()] = doc.id;
            }

            print(
              'Catégories existantes: ${categoriesExistantes.keys.join(", ")}',
            );
            int elementsTraites = 0;

            for (var element in elements) {
              if (element is! Map<String, dynamic> ||
                  !element.containsKey('texte') ||
                  !element.containsKey('explication') ||
                  !element.containsKey('categorie')) {
                print(
                  'Élément incomplet ou format incorrect, ignoré: $element',
                );
                continue;
              }

              String texteElement = element['texte'] ?? '';
              String explication = element['explication'] ?? '';
              String categorieNom = element['categorie'] ?? '';

              if (texteElement.isEmpty || categorieNom.isEmpty) {
                print('Élément avec texte ou catégorie vide, ignoré');
                continue;
              }

              String categorieNormalisee = normaliserId(categorieNom);
              print(
                'Traitement de l\'élément: "$texteElement" (Catégorie: "$categorieNom", normalisée: "$categorieNormalisee")',
              );

              String categorieId;
              if (categoriesExistantes.containsKey(categorieNormalisee)) {
                categorieId = categoriesExistantes[categorieNormalisee]!;
                print(
                  'Catégorie existante trouvée via ID normalisé: $categorieId',
                );
              } else if (categoriesExistantes.containsKey(
                categorieNom.toLowerCase(),
              )) {
                categorieId = categoriesExistantes[categorieNom.toLowerCase()]!;
                print(
                  'Catégorie existante trouvée via nom exact: $categorieId',
                );
              } else {
                String docId = normaliserId(categorieNom);
                if (docId.isEmpty) {
                  docId = 'categorie_${DateTime.now().millisecondsSinceEpoch}';
                }

                try {
                  final newCategorieRef = FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUser.uid)
                      .collection('categories_elements')
                      .doc(docId);

                  await newCategorieRef.set({
                    'nom': categorieNom,
                    'createdAt': Timestamp.now(),
                  });

                  categorieId = docId;
                  categoriesExistantes[categorieNormalisee] = categorieId;
                  categoriesExistantes[categorieNom.toLowerCase()] =
                      categorieId;
                  print(
                    'Nouvelle catégorie créée: $categorieNom (ID: $categorieId)',
                  );
                } catch (e) {
                  print('Erreur lors de la création de la catégorie: $e');
                  continue;
                }
              }

              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser.uid)
                    .collection('categories_elements')
                    .doc(categorieId)
                    .collection('elements')
                    .add({
                      'texte': texteElement,
                      'explication': explication,
                      'date': Timestamp.now(),
                      'isRepost': false,
                      'repostedFromUserId': null,
                      'repostedFromUserName': null,
                    });

                elementsTraites++;
                print('Élément ajouté à la catégorie: $categorieId');
              } catch (e) {
                print('Erreur lors de l\'ajout de l\'élément: $e');
              }
            }

            if (elementsTraites > 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '$elementsTraites éléments intéressants classifiés et enregistrés',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Aucun élément n\'a pu être enregistré'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } else {
            print('Aucun élément trouvé dans le JSON');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Aucun élément intéressant identifié dans le texte',
                ),
                backgroundColor: Colors.blue,
              ),
            );
          }
        } else {
          print('Format JSON invalide ou clé "elements" non trouvée');
          print('Contenu parsé: $parsedElements');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Erreur lors de l\'analyse du texte : Format de réponse IA inattendu.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        print('Erreur API: ${response.statusCode} - ${response.reasonPhrase}');
        print('Body: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur API: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print(
        'Erreur globale lors de l\'enregistrement des éléments intéressants : $e',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<List<String>> _extraireMotsCles(String texte) async {
    if (DEEPSEEK_API_KEY == 'VOTRE_CLÉ_API_DEEPSEEK') {
      print("ERREUR : Clé API DeepSeek non configurée pour les mots-clés.");
      return ['default1', 'default2', 'default3', 'default4', 'default5'];
    }
    const url = 'https://api.deepinfra.com/v1/openai/chat/completions';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $DEEPSEEK_API_KEY',
        },
        body: jsonEncode({
          'model': await resolveAiModel(isVip: _isVip),
          'messages': [
            {
              'role': 'user',
              'content':
                  '''Analyse ce texte et extrais exactement 5 mots-clés qui résument les thèmes principaux de la journée. Réponds uniquement avec une liste JSON de 5 mots, sans texte supplémentaire, ni préambule, ni postface. Assure-toi que la liste 'mots_cles' est toujours présente, même vide si aucun mot-clé n'est pertinent:
                {
                  "mots_cles": ["mot1", "mot2", "mot3", "mot4", "mot5"]
                }
                Texte à analyser : $texte''',
            },
          ],
          'max_tokens': 100,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content =
            data['choices']?[0]['message']['content']?.toString() ?? '';

        if (content.isEmpty) {
          print('Contenu vide dans la réponse des mots-clés');
          return ['default1', 'default2', 'default3', 'default4', 'default5'];
        }

        content = content.trim().replaceAll(RegExp(r'^```json\s*|\s*```$'), '');

        try {
          final motsClesParsed = jsonDecode(content);
          if (motsClesParsed.containsKey('mots_cles') &&
              motsClesParsed['mots_cles'] is List) {
            List<String> extracted = List<String>.from(
              motsClesParsed['mots_cles'],
            );
            if (extracted.length > 5) {
              return extracted.sublist(0, 5);
            } else if (extracted.length < 5) {
              while (extracted.length < 5) {
                extracted.add('defaut${extracted.length + 1}');
              }
            }
            return extracted;
          } else {
            print('Format de réponse invalide pour mots-clés: $content');
            return ['default1', 'default2', 'default3', 'default4', 'default5'];
          }
        } catch (e) {
          print(
            'Erreur de parsing JSON pour mots-clés : $e, contenu : $content',
          );
          return ['default1', 'default2', 'default3', 'default4', 'default3'];
        }
      } else {
        print('Erreur API DeepSeek pour mots-clés : ${response.statusCode}');
        return ['erreur1', 'erreur2', 'erreur3', 'erreur4', 'erreur5'];
      }
    } catch (e) {
      print('Erreur lors de l\'extraction des mots-clés : $e');
      return ['erreur1', 'erreur2', 'erreur3', 'erreur4', 'erreur5'];
    }
  }

  double _calculateFontSize(String text) {
    if (text.length < 50) {
      return 18.0;
    } else if (text.length < 100) {
      return 16.0;
    } else if (text.length < 200) {
      return 15.0;
    } else {
      return 14.0;
    }
  }

  Future<void> _handleReaction(
    JourneeModel journee,
    String selectedEmoji,
  ) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || journee.id == null) return;

    bool isNewReaction = false;

    try {
      final journeeRef = _firestore.collection('journees').doc(journee.id);

      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(journeeRef);
        if (!docSnapshot.exists)
          throw Exception("Le document de la journée n'existe pas.");

        final data = docSnapshot.data() ?? {};
        Map<String, List<String>> currentReactions = {};
        if (data['reactions'] is Map) {
          (data['reactions'] as Map<String, dynamic>).forEach((emoji, users) {
            if (users is List) {
              currentReactions[emoji] = List<String>.from(users);
            }
          });
        }

        String? existingEmoji;
        currentReactions.forEach((emoji, users) {
          if (users.contains(userId)) existingEmoji = emoji;
        });

        if (existingEmoji != null) {
          // L'utilisateur a déjà réagi
          currentReactions[existingEmoji]?.remove(userId);
          if (currentReactions[existingEmoji]?.isEmpty ?? false) {
            currentReactions.remove(existingEmoji);
          }
          if (existingEmoji != selectedEmoji) {
            // Changer de réaction
            currentReactions.update(
              selectedEmoji,
              (v) => [...v, userId],
              ifAbsent: () => [userId],
            );
            isNewReaction = true;
          }
          // Si même emoji : suppression (toggle off)
        } else {
          // Nouvelle réaction
          currentReactions.update(
            selectedEmoji,
            (v) => [...v, userId],
            ifAbsent: () => [userId],
          );
          isNewReaction = true;
        }

        transaction.update(journeeRef, {'reactions': currentReactions});
      });

      // Notifier seulement si c'est une nouvelle réaction (pas une suppression)
      if (isNewReaction) {
        final currentUserDoc =
            await _firestore.collection('users').doc(userId).get();
        final username = currentUserDoc.data()?['username'] ?? 'Quelqu\'un';
        NotificationService.notifyOwnerOnInteraction(
          journeeId: journee.id!,
          interactorName: username,
          action: "réagi à",
        );
      }
    } catch (e) {
      print('Erreur lors de la gestion de la réaction: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la réaction: $e')),
        );
      }
    }
  }

  List<SouvenirModel> _getSouvenirsForJournee(JourneeModel journee) {
    try {
      final journeeDate = DateTime(
        journee.date.year,
        journee.date.month,
        journee.date.day,
      );
      return _mySouvenirs.where((souvenir) {
        final souvenirDate = DateTime(
          souvenir.date.year,
          souvenir.date.month,
          souvenir.date.day,
        );
        return souvenirDate.isAtSameMomentAs(journeeDate);
      }).toList();
    } catch (e) {
      print(
        'Erreur lors de la récupération des souvenirs pour la journée : $e',
      );
      return [];
    }
  }

  void _showSouvenirDetailDialog(SouvenirModel souvenir) {
    final bool isMySouvenir =
        souvenir.userId == FirebaseAuth.instance.currentUser?.uid;
    final isDark = appBrightnessNotifier.value == Brightness.dark;

    final Map<SouvenirQualite, Map<String, dynamic>> qualiteInfo = {
      SouvenirQualite.nostalgie: {
        'label': 'Nostalgie',
        'icon': Icons.history,
        'color': Colors.purple,
      },
      SouvenirQualite.jamaisOublie: {
        'label': 'Jamais oublié',
        'icon': Icons.favorite,
        'color': Colors.red,
      },
      SouvenirQualite.bonheur: {
        'label': 'Bonheur',
        'icon': Icons.wb_sunny_rounded,
        'color': Colors.orange,
      },
    };
    final qInfo = qualiteInfo[souvenir.qualite]!;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.90, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14.0, sigmaY: 14.0),
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.85,
                      maxWidth: MediaQuery.of(context).size.width,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade900 : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Header ──
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${souvenir.date.day.toString().padLeft(2, '0')}'
                                    '/${souvenir.date.month.toString().padLeft(2, '0')}'
                                    '/${souvenir.date.year}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          isDark
                                              ? Colors.white
                                              : Colors.black87,
                                    ),
                                  ),
                                ),
                                if (isMySouvenir)
                                  IconButton(
                                    tooltip: 'Modifier',
                                    icon: Icon(
                                      Icons.edit_outlined,
                                      color:
                                          isDark
                                              ? Colors.blue.shade300
                                              : Colors.blue,
                                    ),
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      _modifierSouvenir(souvenir);
                                    },
                                  ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color:
                                        isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                ),
                              ],
                            ),
                          ),
                          // ── Content ──
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                10,
                                20,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Qualité badge
                                  Row(
                                    children: [
                                      Icon(
                                        qInfo['icon'] as IconData,
                                        color: qInfo['color'] as Color,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        qInfo['label'] as String,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: qInfo['color'] as Color,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    souvenir.texte,
                                    style: TextStyle(
                                      fontSize: 15,
                                      height: 1.65,
                                      color:
                                          isDark
                                              ? Colors.grey.shade100
                                              : Colors.black87,
                                    ),
                                  ),

                                  if (souvenir.photoUrls.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      height: 120,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: souvenir.photoUrls.length,
                                        itemBuilder:
                                            (_, i) => Padding(
                                              padding: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.network(
                                                  souvenir.photoUrls[i],
                                                  width: 120,
                                                  height: 120,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _modifierSouvenir(SouvenirModel souvenir) async {
    bool canModify = await _canModify('souvenirs', souvenir.id);

    if (!mounted) return;

    if (canModify) {
      final bool? wasModified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => SouvenirPage(souvenirToEdit: souvenir),
        ),
      );

      if (wasModified == true) {
        await _firestore.collection('souvenirs').doc(souvenir.id).set({
          'dateDerniereModif': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vous avez déjà modifié ce souvenir aujourd\'hui.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Future<bool> _canModify(String collection, String? docId) async {
    if (docId == null) return false;

    final docRef = _firestore.collection(collection).doc(docId);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) return true;

    final data = docSnapshot.data();
    final lastModifiedTimestamp = data?['dateDerniereModif'] as Timestamp?;

    if (lastModifiedTimestamp == null) {
      return true;
    }

    final lastModifiedDate = lastModifiedTimestamp.toDate();
    final now = DateTime.now();

    if (!_isSameDay(lastModifiedDate, now)) {
      return true;
    }

    return false;
  }

  void _showJourneeDetailDialog(JourneeModel journee) {
    final bool isMyJournee =
        journee.userId == FirebaseAuth.instance.currentUser?.uid;
    final isDark = appBrightnessNotifier.value == Brightness.dark;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.90, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14.0, sigmaY: 14.0),
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.85,
                      maxWidth: MediaQuery.of(context).size.width,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade900 : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Header ──
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${journee.date.day.toString().padLeft(2, '0')}/'
                                    '${journee.date.month.toString().padLeft(2, '0')}/'
                                    '${journee.date.year}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          isDark
                                              ? Colors.white
                                              : Colors.black87,
                                    ),
                                  ),
                                ),
                                if (isMyJournee)
                                  IconButton(
                                    tooltip: 'Modifier',
                                    icon: Icon(
                                      Icons.edit_outlined,
                                      color:
                                          isDark
                                              ? Colors.blue.shade300
                                              : Colors.blue,
                                    ),
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      _modifierJournee(journee);
                                    },
                                  ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color:
                                        isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                ),
                              ],
                            ),
                          ),
                          // ── Content ──
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                10,
                                20,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (journee.emoji != null) ...[
                                    Text(
                                      journee.emoji!,
                                      style: const TextStyle(fontSize: 36),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Text(
                                    journee.texte1 ?? '',
                                    style: TextStyle(
                                      fontSize: 15,
                                      height: 1.65,
                                      color:
                                          isDark
                                              ? Colors.grey.shade100
                                              : Colors.black87,
                                    ),
                                  ),
                                  if (journee.note != null) ...[
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          color: Colors.amber,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Note : ${journee.note}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blueGrey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (journee.photoUrls.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      height: 120,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: journee.photoUrls.length,
                                        itemBuilder:
                                            (_, i) => Padding(
                                              padding: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.network(
                                                  journee.photoUrls[i],
                                                  width: 120,
                                                  height: 120,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                      ),
                                    ),
                                  ],
                                  if ((journee.motsCles ?? []).isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children:
                                          (journee.motsCles ?? [])
                                              .map(
                                                (k) => Chip(
                                                  label: Text(
                                                    k,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: EdgeInsets.zero,
                                                ),
                                              )
                                              .toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _modifierJournee(JourneeModel journee) async {
    bool canModify = await _canModify('journees', journee.id);

    if (!mounted) return;

    if (canModify) {
      final bool? wasModified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => JourneePage(journeeToEdit: journee),
        ),
      );

      if (wasModified == true) {
        await _firestore.collection('journees').doc(journee.id).set({
          'dateDerniereModif': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vous avez déjà modifié cette journée aujourd\'hui.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _signalerJournee(JourneeModel journee) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Journée de ${journee.userId} signalée.')),
    );
  }

  Widget _buildTextWithBlurredAsterisks(String text, {TextStyle? style}) {
    List<TextSpan> spans = [];
    final regex = RegExp(r'\*');

    int start = 0;
    for (Match match in regex.allMatches(text)) {
      if (start < match.start) {
        spans.add(
          TextSpan(text: text.substring(start, match.start), style: style),
        );
      }
      spans.add(
        TextSpan(
          text: '*',
          style: (style ?? const TextStyle()).copyWith(
            color: Colors.transparent,
            shadows: [
              Shadow(
                blurRadius: 10.0,
                color: (style?.color ?? Colors.black).withValues(alpha: 0.9),
                offset: const Offset(0, 0),
              ),
            ],
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }

    return RichText(
      text: TextSpan(
        style:
            style ??
            const TextStyle(fontSize: 18, height: 1.5, color: Colors.black),
        children: spans,
      ),
    );
  }

  Widget _buildSouvenirCard(
    SouvenirModel souvenir, {
    bool showRepublishButton = false,
    required bool hasUserPostedToday,
  }) {
    return FutureBuilder<DocumentSnapshot>(
      future:
          _firestore
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser?.uid)
              .get(),
      builder: (context, userSnapshot) {
        final isDark = appBrightnessNotifier.value == Brightness.dark;
        Map<String, dynamic> personalizationPreferences =
            (userSnapshot.data?.data()
                as Map<String, dynamic>?)?['personalizationPreferences'] ??
            {};

        bool forceGlobal =
            personalizationPreferences['forceGlobalSouvenirColor'] ?? false;
        String colorPref =
            forceGlobal
                ? (personalizationPreferences['cardColor'] ?? 'bleu')
                : (souvenir.cardColor ??
                    personalizationPreferences['cardColor'] ??
                    'bleu');

        Color cardColor;
        switch (colorPref) {
          case 'noir':
            cardColor = isDark ? Colors.grey.shade900 : Colors.black87;
            break;
          case 'rouge':
            cardColor = isDark ? Colors.red.shade900 : Colors.red.shade300;
            break;
          case 'vert':
            cardColor = isDark ? Colors.green.shade900 : Colors.green.shade300;
            break;
          case 'orange':
            cardColor =
                isDark ? Colors.orange.shade900 : Colors.orange.shade300;
            break;
          case 'jaune':
            cardColor =
                isDark ? Colors.yellow.shade900 : Colors.yellow.shade600;
            break;
          case 'violet':
            cardColor =
                isDark ? Colors.purple.shade900 : Colors.purple.shade300;
            break;
          case 'rose':
            cardColor = isDark ? Colors.pink.shade900 : Colors.pink.shade300;
            break;
          case 'blanc':
            cardColor = isDark ? Colors.grey.shade300 : Colors.white;
            break;
          case 'bleu':
          default:
            cardColor = isDark ? Colors.blue.shade900 : Colors.blue.shade300;
            break;
        }

        final Color cardEndColor = isDark ? Colors.grey.shade900 : Colors.white;
        final Color mainTextColor =
            cardColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
        final Color secondaryTextColor = mainTextColor.withOpacity(0.7);

        return GestureDetector(
          onTap: () => _showSouvenirDetailDialog(souvenir),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side:
                  souvenir.isRepost
                      ? const BorderSide(color: Colors.grey, width: 2.0)
                      : BorderSide.none,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cardColor, cardEndColor],
                ),
                boxShadow: [
                  BoxShadow(
                    color: cardColor.withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (souvenir.isRepost)
                      Text(
                        'De ${souvenir.repostedFromUserName ?? 'un ami'}',
                        style: TextStyle(
                          fontSize: 10,
                          color: secondaryTextColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    if (souvenir.photoUrls.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10.0),
                        child: Image.network(
                          souvenir.photoUrls.first,
                          height: 42,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 42,
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 42,
                              color: Colors.grey[200],
                              child: const Icon(
                                Icons.broken_image,
                                size: 22,
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      souvenir.texte,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: mainTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: souvenir.photoUrls.isNotEmpty ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getQualiteColor(
                                    souvenir.qualite,
                                  ).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _getQualiteLabel(souvenir.qualite),
                                  style: TextStyle(
                                    color: _getQualiteColor(souvenir.qualite),
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      souvenir.estPublic
                                          ? Colors.green.shade50
                                          : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  souvenir.estPublic ? 'Public' : 'Privé',
                                  style: TextStyle(
                                    color:
                                        souvenir.estPublic
                                            ? Colors.green
                                            : Colors.red,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _getQualiteLabel(sm.SouvenirQualite qualite) {
    switch (qualite) {
      case sm.SouvenirQualite.nostalgie:
        return "Nostalgie";
      case sm.SouvenirQualite.jamaisOublie:
        return "Jamais Oublié";
      case sm.SouvenirQualite.bonheur:
        return "Bonheur";
    }
  }

  Color _getQualiteColor(sm.SouvenirQualite qualite) {
    switch (qualite) {
      case sm.SouvenirQualite.nostalgie:
        return Colors.purple;
      case sm.SouvenirQualite.jamaisOublie:
        return Colors.blue;
      case sm.SouvenirQualite.bonheur:
        return Colors.green;
    }
  }

  Future<void> _supprimerSouvenir(SouvenirModel souvenir) async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();

      int qualiteDeVieActuelle =
          userDoc.exists
              ? (userDoc.data()
                      as Map<String, dynamic>)['qualiteDeVieActuelle'] ??
                  50
              : 50;

      int nouvelleQualiteDeVie =
          ((qualiteDeVieActuelle * 2 - souvenir.noteQualite) / 3).round();
      nouvelleQualiteDeVie = nouvelleQualiteDeVie.clamp(0, 100);

      await FirebaseFirestore.instance
          .collection('souvenirs')
          .doc(souvenir.id)
          .delete();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({'qualiteDeVieActuelle': nouvelleQualiteDeVie});

      setState(() {
        _souvenirs.remove(souvenir);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Souvenir supprimé avec succès')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression : $e')),
      );
    }
  }

  bool _hasPostedToday() {
    return _myJournees.any(
      (journee) =>
          journee.date.year == _today.year &&
          journee.date.month == _today.month &&
          journee.date.day == _today.day,
    );
  }

  bool _hasPostedTodayWithComment() {
    return _myJournees.any(
      (journee) =>
          journee.date.year == _today.year &&
          journee.date.month == _today.month &&
          journee.date.day == _today.day &&
          journee.commentaire != null &&
          journee.commentaire!.isNotEmpty,
    );
  }

  Future<double> _calculateSimilarity(String text1, String text2) async {
    if (DEEPSEEK_API_KEY == 'VOTRE_CLÉ_API_DEEPSEEK') return 0.0;
    const String url = 'https://api.deepinfra.com/v1/openai/chat/completions';

    if (text1.trim().isEmpty || text2.trim().isEmpty) return 0.0;

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $DEEPSEEK_API_KEY',
            },
            body: jsonEncode({
              'model': await resolveAiModel(isVip: _isVip),
              'messages': [
                {
                  'role': 'user',
                  'content':
                      '''Compare les deux textes suivants et donne un pourcentage de similarité basé sur leur contenu, leur ton et leurs thèmes principaux.
              Tu DOIS répondre STRICTEMENT et UNIQUEMENT avec un objet JSON valide contenant une seule clé "similarite" avec un nombre entier entre 0 et 100. Ne mets AUCUN texte avant ou après.
              Exemple de réponse attendue: {"similarite": 75}

              Texte 1: $text1
              Texte 2: $text2''',
                },
              ],
              'max_tokens': 50,
            }),
          )
          .timeout(
            const Duration(seconds: 15),
          ); // <-- TIMEOUT AJOUTÉ (15 sec max)

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content =
            data['choices']?[0]['message']['content']?.toString().trim() ?? '';

        if (content.isEmpty) return 0.0;

        // Nettoyage au cas où l'IA rajoute des balises Markdown (ex: ```json ... ```)
        content =
            content.replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$'), '').trim();

        try {
          final parsed = jsonDecode(content);
          if (parsed is Map && parsed.containsKey('similarite')) {
            return (parsed['similarite'] as num).toDouble();
          }
        } catch (e) {
          print(
            'Erreur parsing JSON similarité: $e. Fallback Regex sur le contenu: $content',
          );
          // Sécurité supplémentaire : Fallback avec Regex si l'IA n'a pas respecté le JSON
          final match = RegExp(r'"similarite"\s*:\s*(\d+)').firstMatch(content);
          if (match != null && match.group(1) != null) {
            return double.parse(match.group(1)!);
          }
        }
        return 0.0;
      } else {
        print(
          'Erreur API DeepSeek pour similarité: ${response.statusCode} - ${response.body}',
        );
        return 0.0;
      }
    } on TimeoutException {
      print('Erreur : Timeout lors du calcul de similarité (API trop longue).');
      return 0.0;
    } catch (e, stacktrace) {
      print('Erreur lors du calcul de la similarité : $e\n$stacktrace');
      return 0.0;
    }
  }

  Future<Map<JourneeModel, double>> _findSimilarJournees(
    JourneeModel todayJournee, {
    DateTime? searchAfter,
  }) async {
    print('--- DÉBUT DE LA RECHERCHE DE JOURNÉES SIMILAIRES ---');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || todayJournee.id == null) return {};

    final todayDocSnapshot =
        await _firestore.collection('journees').doc(todayJournee.id).get();
    if (!todayDocSnapshot.exists) return {};

    final todayData = todayDocSnapshot.data() as Map<String, dynamic>? ?? {};
    final keywordsList =
        todayData['motsCles'] is List ? List.from(todayData['motsCles']) : [];
    final todayKeywords =
        keywordsList.map((k) => k.toString().toLowerCase()).toSet();
    final todayText = todayJournee.texte1 ?? todayJournee.commentaire ?? '';

    // Gestion propre de l'absence de mots-clés
    if (todayKeywords.isEmpty) {
      print('[FIN] La journée n\'a pas encore de mots-clés.');
      throw Exception(
        'L\'IA est encore en train d\'analyser les mots-clés de cette journée. Veuillez réessayer dans quelques instants.',
      );
    }

    final allJourneesQuery =
        await _firestore
            .collection('journees')
            .where('userId', isEqualTo: user.uid)
            .get();

    // 1. PHASE DE PRÉ-FILTRAGE LOCAL (Ultra rapide, gratuit)
    List<JourneeModel> candidates = [];

    for (var doc in allJourneesQuery.docs) {
      if (doc.id == todayJournee.id) continue;

      final journee = JourneeModel.fromFirestore(doc);
      final journeeData = doc.data() as Map<String, dynamic>? ?? {};
      final otherKeywordsList =
          journeeData['motsCles'] is List
              ? List.from(journeeData['motsCles'])
              : [];
      final journeeKeywords =
          otherKeywordsList.map((k) => k.toString().toLowerCase()).toSet();

      final journeeText = journee.texte1 ?? journee.commentaire ?? '';

      if (journeeText.isNotEmpty) {
        final hasCommonKeyword = todayKeywords.any(
          (keyword) => journeeKeywords.contains(keyword),
        );
        if (hasCommonKeyword) {
          candidates.add(journee);
        }
      }
    }

    if (candidates.isEmpty) {
      print(
        '[FIN] Aucune journée n\'a de mots-clés en commun avec aujourd\'hui.',
      );
      return {};
    }

    print(
      '\n[API] Lancement des calculs IA pour ${candidates.length} candidats...',
    );

    // 2. PHASE D'APPEL IA PAR LOTS (BATCH) POUR ÉVITER LE RATE LIMIT (Erreur 429)
    List<MapEntry<JourneeModel, double>> finalResults = [];
    const int chunkSize =
        5; // On ne lance que 5 requêtes IA en même temps maximum.

    for (int i = 0; i < candidates.length; i += chunkSize) {
      int end =
          (i + chunkSize < candidates.length)
              ? i + chunkSize
              : candidates.length;
      List<JourneeModel> chunk = candidates.sublist(i, end);

      print(
        ' -> Traitement du lot ${i ~/ chunkSize + 1} (${chunk.length} requêtes)...',
      );

      // Création des futures pour ce lot
      var futures = chunk.map((journee) async {
        final journeeText = journee.texte1 ?? journee.commentaire ?? '';
        double similarity = await _calculateSimilarity(todayText, journeeText);
        return MapEntry(journee, similarity);
      });

      // On attend que les 5 requêtes de ce lot soient terminées avant de passer au lot suivant
      var chunkResults = await Future.wait(futures);

      // On filtre directement ceux qui dépassent le seuil (30%)
      finalResults.addAll(chunkResults.where((entry) => entry.value > 30));
    }

    // 3. TRI PAR POURCENTAGE LE PLUS ÉLEVÉ
    finalResults.sort((a, b) => b.value.compareTo(a.value));

    print(
      '--- FIN DE LA RECHERCHE (${finalResults.length} résultats > 30%) ---',
    );
    return Map.fromEntries(finalResults);
  }

  void _showSimilarJourneesDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vous n'êtes pas connecté.")),
      );
      return;
    }

    final todayStart = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final todayEnd = todayStart.add(const Duration(days: 1));
    final todayQuery =
        await _firestore
            .collection('journees')
            .where('userId', isEqualTo: user.uid)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(todayEnd))
            .limit(1)
            .get();

    if (todayQuery.docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vous n'avez pas encore posté de journée aujourd'hui."),
        ),
      );
      return;
    }

    final todayJourneeDoc = todayQuery.docs.first;
    final todayJournee = JourneeModel.fromFirestore(todayJourneeDoc);

    // Affichage du loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            backgroundColor: Colors.white,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                SizedBox(height: 16),
                Text(
                  "Recherche de journées similaires...",
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Cela peut prendre quelques secondes.",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
    );

    Map<JourneeModel, double> similarJournees = {};
    String? errorMessage;

    try {
      similarJournees = await _findSimilarJournees(todayJournee);
    } catch (e) {
      // Nettoyage du message d'erreur si c'est notre Exception personnalisée
      errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (mounted) {
        Navigator.pop(context); // Fermer la boite de chargement
      }
    }

    if (!mounted) return;

    // Si on a attrapé une erreur (ex: Pas encore de mots clés)
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.orange),
      );
      return;
    }

    if (similarJournees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aucune journée similaire trouvée (basé sur les mots-clés et l\'IA).',
          ),
          backgroundColor: Colors.blue,
        ),
      );
      return;
    }

    // Mise en cache des résultats
    await FirebaseFirestore.instance
        .collection('journees')
        .doc(todayJourneeDoc.id)
        .set({
          'similarJourneesCache': similarJournees.map(
            (key, value) => MapEntry(key.id!, value),
          ),
          'lastSimilaritySearchDate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    // Affichage de la pop-up avec les résultats
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Vos Journées Similaires',
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Journée d'aujourd'hui :",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blueGrey,
                    ),
                  ),
                  Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      title: Text(
                        DateFormat(
                          'dd MMMM yyyy',
                          'fr_FR',
                        ).format(todayJournee.date),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        todayJournee.texte1 ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const Divider(height: 24, thickness: 1),
                  const Text(
                    "Journées similaires trouvées :",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: similarJournees.length,
                    separatorBuilder:
                        (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = similarJournees.entries.elementAt(index);
                      final journee = entry.key;
                      final similarity = entry.value;
                      final color = _getPercentageColor(similarity);

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: color.withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat(
                                  'dd MMMM yyyy',
                                  'fr_FR',
                                ).format(journee.date),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                journee.texte1 ?? '...',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: similarity / 100,
                                      backgroundColor: color.withOpacity(0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        color,
                                      ),
                                      minHeight: 6,
                                      borderRadius: BorderRadius.circular(
                                        10,
                                      ), // Optionnel, esthétique
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${similarity.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Fermer',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<SouvenirModel>> _getSouvenirsForUser(String userId) async {
    try {
      final snapshot =
          await _firestore
              .collection('souvenirs')
              .where('userId', isEqualTo: userId)
              .where('estPublic', isEqualTo: true)
              .get();

      return snapshot.docs
          .map((doc) => SouvenirModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Erreur lors de la récupération des souvenirs: $e');
      return [];
    }
  }

  Color _getPercentageColor(double percentage) {
    if (percentage > 80) return Colors.green.shade700;
    if (percentage > 60) return Colors.green.shade500;
    if (percentage > 40) return Colors.orange.shade500;
    if (percentage > 20) return Colors.red.shade500;
    return Colors.red.shade700;
  }

  void _showJourneeFilterDialog(ValueNotifier<String> filterNotifier) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Filtrer mes journées',
            style: TextStyle(color: Colors.blue),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildJourneeFilterOption(
                  filterNotifier,
                  'tout',
                  'Toutes les journées',
                ),
                const Divider(),
                _buildJourneeFilterOption(
                  filterNotifier,
                  'note_plus_80',
                  'Note > 80%',
                ),
                _buildJourneeFilterOption(
                  filterNotifier,
                  'note_50_80',
                  'Note 50%-80%',
                ),
                _buildJourneeFilterOption(
                  filterNotifier,
                  'note_moins_50',
                  'Note < 50%',
                ),
                _buildJourneeFilterOption(
                  filterNotifier,
                  'note_moins_30',
                  'Note < 30%',
                ),
                const Divider(),
                _buildJourneeFilterOption(
                  filterNotifier,
                  'avec_emoji',
                  'Avec emoji',
                ),
                _buildJourneeFilterOption(
                  filterNotifier,
                  'sans_emoji',
                  'Sans emoji',
                ),
                _buildJourneeFilterOption(
                  filterNotifier,
                  'avec_commentaire',
                  'Avec commentaire',
                ),
                _buildJourneeFilterOption(
                  filterNotifier,
                  'sans_commentaire',
                  'Sans commentaire',
                ),
                const Divider(),
                _buildJourneeFilterOption(
                  filterNotifier,
                  'public',
                  'Publiques',
                ),
                _buildJourneeFilterOption(filterNotifier, 'prive', 'Privées'),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Annuler', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildJourneeFilterOption(
    ValueNotifier<String> filterNotifier,
    String filterValue,
    String label,
  ) {
    return ValueListenableBuilder<String>(
      valueListenable: filterNotifier,
      builder: (context, currentFilter, child) {
        return RadioListTile<String>(
          title: Text(label),
          value: filterValue,
          groupValue: currentFilter,
          onChanged: (String? value) {
            if (value != null) {
              filterNotifier.value = value;
              Navigator.of(context).pop();
            }
          },
          activeColor: Colors.blue,
        );
      },
    );
  }

  List<JourneeModel> _filterJournees(
    List<JourneeModel> journees,
    String filter,
  ) {
    return journees.where((journee) {
      if (filter == 'tout') return true;

      int? note;
      try {
        if (journee.note != null && journee.note!.contains('/')) {
          note = int.tryParse(journee.note!.split('/').first);
        }
      } catch (e) {
        print('Erreur conversion note: $e');
        note = null;
      }

      switch (filter) {
        case 'note_plus_80':
          return (note ?? 0) > 80;
        case 'note_50_80':
          return (note ?? 0) >= 50 && (note ?? 0) <= 80;
        case 'note_moins_50':
          return (note ?? 0) < 50;
        case 'note_moins_30':
          return (note ?? 0) < 30;
        case 'avec_emoji':
          return journee.emoji != null && journee.emoji!.isNotEmpty;
        case 'sans_emoji':
          return journee.emoji == null || journee.emoji!.isEmpty;
        case 'avec_commentaire':
          return journee.commentaire != null && journee.commentaire!.isNotEmpty;
        case 'sans_commentaire':
          return journee.commentaire == null || journee.commentaire!.isEmpty;
        case 'public':
          return journee.estPublic;
        case 'prive':
          return !journee.estPublic;
        default:
          return true;
      }
    }).toList();
  }

  bool _isDifferentDate(DateTime date1, DateTime date2) {
    return date1.year != date2.year ||
        date1.month != date2.month ||
        date1.day != date2.day;
  }

  Widget _buildEmptyMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.book_outlined, size: 100, color: Colors.grey),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${_getWeekday(date.weekday)} ${date.day} ${_getMonth(date.month)} ${date.year}';
  }

  String _getWeekday(int weekday) {
    switch (weekday) {
      case 1:
        return 'Lundi';
      case 2:
        return 'Mardi';
      case 3:
        return 'Mercredi';
      case 4:
        return 'Jeudi';
      case 5:
        return 'Vendredi';
      case 6:
        return 'Samedi';
      case 7:
        return 'Dimanche';
      default:
        return '';
    }
  }

  String _getMonth(int month) {
    switch (month) {
      case 1:
        return 'Janvier';
      case 2:
        return 'Février';
      case 3:
        return 'Mars';
      case 4:
        return 'Avril';
      case 5:
        return 'Mai';
      case 6:
        return 'Juin';
      case 7:
        return 'Juillet';
      case 8:
        return 'Août';
      case 9:
        return 'Septembre';
      case 10:
        return 'Octobre';
      case 11:
        return 'Novembre';
      case 12:
        return 'Décembre';
      default:
        return '';
    }
  }

  Future<void> _supprimerJournee(JourneeModel journee) async {
    if (journee.id == null) return;

    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();

      int qualiteDeVieActuelle =
          userDoc.exists
              ? (userDoc.data()
                      as Map<String, dynamic>)['qualiteDeVieActuelle'] ??
                  50
              : 50;

      int noteJournee = 50;
      if (journee.note != null && journee.note!.contains('/')) {
        try {
          noteJournee = int.parse(journee.note!.split('/').first);
        } catch (e) {
          noteJournee = 50;
        }
      }

      int nouvelleQualiteDeVie =
          ((qualiteDeVieActuelle * 2 - noteJournee) / 3).round();
      nouvelleQualiteDeVie = nouvelleQualiteDeVie.clamp(0, 100);

      await FirebaseFirestore.instance
          .collection('journees')
          .doc(journee.id)
          .delete();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({'qualiteDeVieActuelle': nouvelleQualiteDeVie});

      setState(() {
        _myJournees.remove(journee);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Journée supprimée avec succès')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression : $e')),
      );
    }
  }

  void _showCommentsDialog(JourneeModel journee, {required bool isMyJournees}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: CommentsSection(
              journeeId: journee.id!,
              isMyJournees: isMyJournees,
            ),
          ),
        );
      },
    );
  }

  void _showPopupCardSouvenir(
    BuildContext context,
    SouvenirModel souvenir,
    String design,
    String color,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        final bool isSpecialShape = [
          'coeur',
          'etoile',
          'rond',
        ].contains(design);
        final double paddingValue = isSpecialShape ? 50.0 : 40.0;
        // No need for qualiteAsString here, use souvenir.qualite directly

        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Material(
            color: Colors.transparent,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Center(
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: GestureDetector(
                    onTap:
                        () {}, // Empêche la propagation du tap vers le parent
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.65,
                      height: MediaQuery.of(context).size.width * 0.65,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: Image.asset(
                              _getImagePath(design, color),
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (context, error, stackTrace) => Container(
                                    color: Colors.white,
                                    child: const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                    ),
                                  ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(paddingValue),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (souvenir.isRepost)
                                    Text(
                                      'Republié de ${souvenir.repostedFromUserName ?? 'un ami'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  Text(
                                    souvenir.texte,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: <Shadow>[
                                        Shadow(
                                          offset: Offset(1.5, 1.5),
                                          blurRadius: 3.0,
                                          color: Colors.black87,
                                        ),
                                        Shadow(
                                          offset: Offset(-1.5, -1.5),
                                          blurRadius: 3.0,
                                          color: Colors.black87,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (souvenir.photoUrls.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        souvenir.photoUrls.first,
                                        height: 100,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Chip(
                                    label: Text(
                                      _getQualiteLabel(souvenir.qualite),
                                      style: TextStyle(
                                        color: _getQualiteColor(
                                          souvenir.qualite,
                                        ), // Use souvenir.qualite directly
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    backgroundColor: _getQualiteColor(
                                      souvenir.qualite,
                                    ).withOpacity(
                                      0.15,
                                    ), // Use souvenir.qualite directly
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Note: ${souvenir.noteQualite}/100',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPopupCardJournee(
    BuildContext context,
    JourneeModel journee,
    String design,
    String color,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        final bool isSpecialShape = [
          'coeur',
          'etoile',
          'rond',
        ].contains(design);
        final double paddingValue = isSpecialShape ? 50.0 : 40.0;

        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Material(
            color: Colors.transparent,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Center(
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: GestureDetector(
                    onTap:
                        () {}, // Empêche la propagation du tap vers le parent
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.65,
                      height: MediaQuery.of(context).size.width * 0.65,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: Image.asset(
                              _getImagePath(design, color),
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (context, error, stackTrace) => Container(
                                    color: Colors.white,
                                    child: const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                    ),
                                  ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(paddingValue),
                            child: SingleChildScrollView(
                              child: StatefulBuilder(
                                builder: (
                                  BuildContext context,
                                  StateSetter setDialogState,
                                ) {
                                  bool isSearching = false;
                                  String? searchError;
                                  List<MapEntry<JourneeModel, double>>?
                                  displayedSimilarities;
                                  DateTime? lastSearchDate;
                                  bool hasResultsInCache = false;

                                  // ✅ Chargement du cache Firestore
                                  Future<void> loadCache() async {
                                    if (journee.id == null) return;
                                    final doc =
                                        await FirebaseFirestore.instance
                                            .collection('journees')
                                            .doc(journee.id)
                                            .get();
                                    if (!doc.exists) return;

                                    final data = doc.data();
                                    final cache =
                                        data?['similarJourneesCache']
                                            as Map<String, dynamic>?;
                                    final lastSearchTimestamp =
                                        data?['lastSimilaritySearchDate']
                                            as Timestamp?;

                                    if (lastSearchTimestamp != null) {
                                      lastSearchDate =
                                          lastSearchTimestamp.toDate();
                                    }

                                    if (cache != null && cache.isNotEmpty) {
                                      hasResultsInCache = true;
                                      final futures =
                                          cache.entries.map((entry) async {
                                            final journeeDoc =
                                                await FirebaseFirestore.instance
                                                    .collection('journees')
                                                    .doc(entry.key)
                                                    .get();
                                            if (journeeDoc.exists) {
                                              return MapEntry(
                                                JourneeModel.fromFirestore(
                                                  journeeDoc,
                                                ),
                                                (entry.value as num).toDouble(),
                                              );
                                            }
                                            return null;
                                          }).toList();

                                      final results =
                                          (await Future.wait(futures))
                                              .whereType<
                                                MapEntry<JourneeModel, double>
                                              >()
                                              .toList();
                                      results.sort(
                                        (a, b) => b.value.compareTo(a.value),
                                      );
                                      displayedSimilarities = results;
                                    }
                                  }

                                  // ✅ Lancer une recherche / mise à jour
                                  Future<void> handleSearch() async {
                                    setDialogState(() {
                                      isSearching = true;
                                      searchError = null;
                                    });

                                    try {
                                      final results =
                                          await _findSimilarJournees(
                                            journee,
                                            searchAfter: lastSearchDate,
                                          );

                                      await FirebaseFirestore.instance
                                          .collection('journees')
                                          .doc(journee.id)
                                          .set({
                                            'similarJourneesCache': results.map(
                                              (key, value) =>
                                                  MapEntry(key.id!, value),
                                            ),
                                            'lastSimilaritySearchDate':
                                                FieldValue.serverTimestamp(),
                                          }, SetOptions(merge: true));

                                      setDialogState(() {
                                        displayedSimilarities =
                                            results.entries.toList();
                                        hasResultsInCache = results.isNotEmpty;
                                        lastSearchDate = DateTime.now();
                                      });
                                    } catch (e) {
                                      setDialogState(() {
                                        searchError =
                                            "Erreur : ${e.toString()}";
                                      });
                                    } finally {
                                      setDialogState(() {
                                        isSearching = false;
                                      });
                                    }
                                  }

                                  // ✅ Affichage via FutureBuilder
                                  return FutureBuilder(
                                    future: loadCache(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }

                                      return Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            journee.emoji ?? '🤔',
                                            style: const TextStyle(
                                              fontSize: 40,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            journee.texte1 ?? 'Aucun texte',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              shadows: <Shadow>[
                                                Shadow(
                                                  offset: Offset(1.5, 1.5),
                                                  blurRadius: 3.0,
                                                  color: Colors.black87,
                                                ),
                                                Shadow(
                                                  offset: Offset(-1.5, -1.5),
                                                  blurRadius: 3.0,
                                                  color: Colors.black87,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          // Removed the Chip displaying 'Qualité'
                                          Text(
                                            'Note: ${journee.note ?? 'N/A'}/100', // Display journee.note instead
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.black87,
                                            ),
                                          ),

                                          const SizedBox(height: 20),
                                          const Divider(color: Colors.white70),

                                          // 🔍 Affichage des résultats similaires
                                          if (searchError != null)
                                            Text(
                                              searchError!,
                                              style: const TextStyle(
                                                color: Colors.red,
                                              ),
                                            )
                                          else if (displayedSimilarities !=
                                                  null &&
                                              displayedSimilarities!.isNotEmpty)
                                            Column(
                                              children: [
                                                const Text(
                                                  'Journées similaires :',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                ...displayedSimilarities!.map((
                                                  entry,
                                                ) {
                                                  return Card(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.85,
                                                        ),
                                                    margin:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 4,
                                                        ),
                                                    child: ListTile(
                                                      title: Text(
                                                        DateFormat(
                                                          'd MMMM yyyy',
                                                        ).format(
                                                          entry.key.date,
                                                        ),
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      subtitle: Text(
                                                        entry.key.texte1 ?? '',
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),
                                                      trailing: Text(
                                                        '${entry.value.toStringAsFixed(0)}%',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ],
                                            )
                                          else if (lastSearchDate != null &&
                                              !hasResultsInCache)
                                            const Text(
                                              "Aucune journée similaire trouvée.",
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),

                                          const SizedBox(height: 12),

                                          // 🔘 Bouton de recherche
                                          isSearching
                                              ? const CircularProgressIndicator()
                                              : ElevatedButton.icon(
                                                icon: Icon(
                                                  hasResultsInCache
                                                      ? Icons.sync
                                                      : Icons.search,
                                                  color: Colors.white,
                                                ),
                                                label: Text(
                                                  hasResultsInCache
                                                      ? 'Mettre à jour'
                                                      : 'Rechercher des journées similaires',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.blueAccent,
                                                ),
                                                onPressed: handleSearch,
                                              ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CommentsSection extends StatefulWidget {
  final String journeeId;
  final bool isMyJournees;

  const CommentsSection({
    Key? key,
    required this.journeeId,
    required this.isMyJournees,
  }) : super(key: key);

  @override
  _CommentsSectionState createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? currentUser = FirebaseAuth.instance.currentUser;
  bool _isPosting = false;

  Future<void> _postComment() async {
    if (_commentController.text.trim().isEmpty ||
        currentUser == null ||
        _isPosting)
      return;
    setState(() => _isPosting = true);
    try {
      final userDoc =
          await _firestore.collection('users').doc(currentUser!.uid).get();
      final username = userDoc.data()?['username'] ?? 'Utilisateur anonyme';
      await _firestore
          .collection('journees')
          .doc(widget.journeeId)
          .collection('comments')
          .add({
            'text': _commentController.text.trim(),
            'userId': currentUser!.uid,
            'username': username,
            'timestamp': FieldValue.serverTimestamp(),
          });
      NotificationService.notifyOwnerOnInteraction(
        journeeId: widget.journeeId,
        interactorName: username,
        action: "commenté",
      );
      if (mounted) {
        _commentController.clear();
        FocusScope.of(context).unfocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'envoi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await _firestore
          .collection('journees')
          .doc(widget.journeeId)
          .collection('comments')
          .doc(commentId)
          .delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la suppression: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _reportComment(String commentId) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Commentaire signalé à la modération.'),
        backgroundColor: Colors.orange,
      ),
    );
    // Optionnel : Enregistrer le signalement dans Firestore
    // _firestore.collection('reports').add({...});
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.grey[900] : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Container(
      color: bgColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.blue.shade50,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.blue.shade100,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Commentaires',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.blue.shade300 : Colors.blue,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  _firestore
                      .collection('journees')
                      .doc(widget.journeeId)
                      .collection('comments')
                      .orderBy('timestamp', descending: false)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Erreur de chargement.',
                      style: TextStyle(color: textColor),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color:
                              isDark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Aucun commentaire pour le moment.',
                          style: TextStyle(color: subtitleColor),
                        ),
                      ],
                    ),
                  );
                }
                final comments = snapshot.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    final data = comment.data() as Map<String, dynamic>;
                    final timestamp = data['timestamp'] as Timestamp?;
                    final date = timestamp?.toDate();
                    final isMyComment = data['userId'] == currentUser?.uid;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            isDark
                                ? Colors.blue.shade900
                                : Colors.blue.shade100,
                        child: Text(
                          ((data['username'] as String?) ?? 'A')[0]
                              .toUpperCase(),
                          style: TextStyle(
                            color:
                                isDark
                                    ? Colors.blue.shade300
                                    : Colors.blue.shade700,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            data['username'] ?? 'Anonyme',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: textColor,
                              fontSize: 14,
                            ),
                          ),
                          if (isMyComment) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Moi',
                                style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      isDark
                                          ? Colors.blue.shade300
                                          : Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        data['text'] ?? '',
                        style: TextStyle(color: textColor, fontSize: 14),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (date != null)
                            Text(
                              DateFormat('dd/MM HH:mm').format(date),
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 11,
                              ),
                            ),
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              size: 18,
                              color: subtitleColor,
                            ),
                            onSelected: (value) {
                              if (value == 'delete') _deleteComment(comment.id);
                              if (value == 'report') _reportComment(comment.id);
                            },
                            itemBuilder:
                                (BuildContext context) => [
                                  if (isMyComment || widget.isMyJournees)
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        'Supprimer',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  if (!isMyComment)
                                    const PopupMenuItem(
                                      value: 'report',
                                      child: Text('Signaler'),
                                    ),
                                ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.grey.shade50,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Ajouter un commentaire...',
                        hintStyle: TextStyle(color: subtitleColor),
                        filled: true,
                        fillColor: isDark ? Colors.grey[800] : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _postComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _isPosting
                      ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : IconButton(
                        icon: const Icon(Icons.send_rounded),
                        color: Colors.blue,
                        onPressed: _postComment,
                        tooltip: 'Envoyer',
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssociatedMemoriesWidget extends StatefulWidget {
  final JourneeModel journee;
  final List<SouvenirModel> souvenirs;
  final bool showRepublishButton;
  final bool hasUserPostedToday;
  final Widget Function(
    SouvenirModel, {
    bool showRepublishButton,
    required bool hasUserPostedToday,
  })
  buildSouvenirCard;
  final Color mainTextColor;

  const _AssociatedMemoriesWidget({
    Key? key,
    required this.journee,
    required this.souvenirs,
    required this.showRepublishButton,
    required this.hasUserPostedToday,
    required this.buildSouvenirCard,
    required this.mainTextColor,
  }) : super(key: key);

  @override
  State<_AssociatedMemoriesWidget> createState() =>
      _AssociatedMemoriesWidgetState();
}

class _AssociatedMemoriesWidgetState extends State<_AssociatedMemoriesWidget> {
  bool _isVisible = false;

  @override
  Widget build(BuildContext context) {
    if (widget.souvenirs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize:
          MainAxisSize.min, // S'assure qu'il ne prend que la place nécessaire
      children: [
        Center(
          child: SizedBox(
            height: 30, // Réduit la hauteur du bouton pour gagner de la place
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                _isVisible
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: widget.mainTextColor.withOpacity(0.8),
                size: 28,
              ),
              onPressed: () {
                setState(() {
                  _isVisible = !_isVisible;
                });
              },
            ),
          ),
        ),
        if (_isVisible)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(color: widget.mainTextColor.withOpacity(0.3), height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  'Souvenirs associés :',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.mainTextColor,
                    fontSize: 14,
                  ),
                ),
              ),
              SizedBox(
                height: 120, // Hauteur fixe pour éviter l'overflow
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.souvenirs.length,
                  itemBuilder: (context, index) {
                    return Container(
                      width: 200,
                      margin: const EdgeInsets.only(right: 10.0),
                      child: widget.buildSouvenirCard(
                        widget.souvenirs[index],
                        showRepublishButton: widget.showRepublishButton,
                        hasUserPostedToday: widget.hasUserPostedToday,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }
}
