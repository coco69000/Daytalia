import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'inscription_page.dart';

class OnboardingTutorialPage extends StatefulWidget {
  final bool showAuthActions;

  const OnboardingTutorialPage({
    super.key,
    this.showAuthActions = false,
  });

  @override
  State<OnboardingTutorialPage> createState() => _OnboardingTutorialPageState();
}

class _OnboardingTutorialPageState extends State<OnboardingTutorialPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_TutorialStep> _steps = const [
    _TutorialStep(
      title: 'Bienvenue dans Daytalia',
      description:
          'Votre espace pour écrire vos journées, garder vos souvenirs et suivre votre évolution au fil du temps.',
      icon: Icons.auto_stories_outlined,
      accentColor: Color(0xFF4F8CFF),
    ),
    _TutorialStep(
      title: 'Racontez vos journées',
      description:
          'Notez ce que vous vivez dans l’éditeur. Vous pouvez ajouter du texte, des photos, une note et même une version en direct.',
      icon: Icons.edit_note_outlined,
      accentColor: Color(0xFFFFA24B),
    ),
    _TutorialStep(
      title: 'Classez vos souvenirs',
      description:
          'Transformez vos moments forts en souvenirs, épinglez-les, puis retrouvez-les facilement depuis Memories.',
      icon: Icons.favorite_border,
      accentColor: Color(0xFFFF6B8B),
    ),
    _TutorialStep(
      title: 'Écrivez votre autobiographie automatiquement',
      description:
          'Daytalia peut transformer vos journées, souvenirs et notes en autobiographie automatiquement pour créer un récit plus complet de votre vie.',
      icon: Icons.auto_stories,
      accentColor: Color(0xFF8B6CFF),
    ),
    _TutorialStep(
      title: 'Ajoutez vos amis et partagez',
      description:
          'Vous pouvez ajouter des amis, partager vos journées et vos souvenirs, et choisir ce que vous rendez visible selon vos préférences.',
      icon: Icons.group_add_outlined,
      accentColor: Color(0xFF35C28B),
    ),
    _TutorialStep(
      title: 'Personnalisez l’app',
      description:
          'Dans les paramètres, changez le thème, les cartes, l’IA et relancez ce tutoriel quand vous voulez.',
      icon: Icons.tune_outlined,
      accentColor: Color(0xFF4F8CFF),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('introTutorialCompleted', true);
    if (!mounted) return;
    if (widget.showAuthActions) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InscriptionPage()),
        (_) => false,
      );
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _skipTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('introTutorialCompleted', true);
    if (!mounted) return;
    if (widget.showAuthActions) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InscriptionPage()),
        (_) => false,
      );
    } else {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _goToSignIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('introTutorialCompleted', true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const InscriptionPage()),
      (_) => false,
    );
  }

  Future<void> _goToRecoverAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('introTutorialCompleted', true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const InscriptionPage(
          initialFlow: AuthFlow.changeNumber_EnterOld,
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDarkMode
            ? const LinearGradient(
              colors: [Color(0xFF0F1116), Color(0xFF171B26), Color(0xFF0F1116)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
            : const LinearGradient(
              colors: [Color(0xFFF6F9FF), Color(0xFFFFFFFF), Color(0xFFEAF2FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: background),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Découvrir Daytalia',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _skipTutorial,
                      child: Text(
                        'Passer',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Quelques écrans pour comprendre les fonctions principales.',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _steps.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final step = _steps[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: _TutorialCard(
                          step: step,
                          isDarkMode: isDarkMode,
                          pageNumber: index + 1,
                          totalPages: _steps.length,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_steps.length, (index) {
                    final isActive = index == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color:
                            isActive
                                ? _steps[_currentPage].accentColor
                                : (isDarkMode
                                    ? Colors.white24
                                    : Colors.black12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 18),
                if (_currentPage == _steps.length - 1 && widget.showAuthActions)
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 14,
                            ),
                            backgroundColor: _steps[_currentPage].accentColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _goToSignIn,
                          child: const Text('Se connecter avec mon numéro'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 14,
                            ),
                            side: BorderSide(color: _steps[_currentPage].accentColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _goToRecoverAccount,
                          child: const Text('Récupérer mon compte avec un numéro'),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      if (_currentPage > 0)
                        TextButton(
                          onPressed: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                          },
                          child: Text(
                            'Retour',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 72),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 14,
                          ),
                          backgroundColor: _steps[_currentPage].accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          if (_currentPage == _steps.length - 1) {
                            _completeTutorial();
                          } else {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        child: Text(
                          _currentPage == _steps.length - 1
                              ? 'Commencer'
                              : 'Suivant',
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
  }
}

class _TutorialStep {
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;

  const _TutorialStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
  });
}

class _TutorialCard extends StatelessWidget {
  final _TutorialStep step;
  final bool isDarkMode;
  final int pageNumber;
  final int totalPages;

  const _TutorialCard({
    required this.step,
    required this.isDarkMode,
    required this.pageNumber,
    required this.totalPages,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDarkMode ? const Color(0xFF1A2030) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final mutedColor = isDarkMode ? Colors.white70 : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: step.accentColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color:
                isDarkMode
                    ? Colors.black45
                    : step.accentColor.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: step.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$pageNumber/$totalPages',
                  style: TextStyle(
                    color: step.accentColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: step.accentColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(step.icon, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 24),
            Text(
              step.title,
              style: TextStyle(
                color: textColor,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              step.description,
              style: TextStyle(color: mutedColor, fontSize: 16, height: 1.45),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color:
                    isDarkMode
                        ? Colors.white.withValues(alpha: 0.04)
                        : step.accentColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _buildHintFor(step.title),
                style: TextStyle(color: mutedColor, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildHintFor(String title) {
    if (title.contains('Bienvenue')) {
      return 'Vous pouvez revenir ici plus tard depuis les paramètres si vous voulez revoir les écrans.';
    }
    if (title.contains('journées')) {
      return 'Essayez de démarrer par une journée simple : une phrase suffit pour commencer.';
    }
    if (title.contains('souvenirs')) {
      return 'Les souvenirs servent à conserver les moments importants et à les retrouver facilement.';
    }
    if (title.contains('autobiographie')) {
      return 'L’option autobiographie automatique s’appuie sur ce que vous écrivez pour construire un récit plus long et plus cohérent.';
    }
    if (title.contains('amis')) {
      return 'Ajoutez des amis pour partager ce que vous voulez montrer, tout en gardant le contrôle sur votre confidentialité.';
    }
    return 'Les paramètres servent aussi à relancer le tutoriel ou à demander un redémarrage après certains changements.';
  }
}
