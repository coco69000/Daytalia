// lib/main.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'home_page.dart';
import 'memories_page.dart';
import 'journee_page.dart';
import 'souvenir_page.dart';
import 'JourneeEnDirectPage_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'inscription_page.dart';
import 'onboarding_tutorial_page.dart';
import 'theme_manager.dart';

class RestartWidget extends StatefulWidget {
  final Widget child;

  const RestartWidget({super.key, required this.child});

  static Future<void> restartApp(BuildContext context) async {
    final state = context.findAncestorStateOfType<_RestartWidgetState>();
    await state?._restartApp();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _childKey = UniqueKey();
  static const MethodChannel _restartChannel = MethodChannel(
    'daytalia/app_restart',
  );

  Future<void> _restartApp() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _restartChannel.invokeMethod<void>('restartApp');
        return;
      } catch (e) {
        debugPrint('Impossible de relancer l’application via Android: $e');
      }
    }

    setState(() {
      _childKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _childKey, child: widget.child);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error at startup: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error at startup: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  try {
    await initializeDateFormatting('fr_FR', null);
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Charger le thème AVANT runApp pour éviter le flash
    await _loadInitialAppBrightness();

    runApp(const RestartWidget(child: MyApp()));
  } catch (e, stack) {
    debugPrint('Fatal startup error: $e');
    debugPrintStack(stackTrace: stack);
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _StartupErrorPage(error: e.toString()),
      ),
    );
  }
}

Future<void> _loadInitialAppBrightness() async {
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? themeMode = prefs.getString('themeMode');
    Brightness loadedBrightness;
    if (themeMode == 'dark') {
      loadedBrightness = Brightness.dark;
    } else if (themeMode == 'light') {
      loadedBrightness = Brightness.light;
    } else {
      // Par défaut sombre si aucune préférence
      loadedBrightness = Brightness.dark;
    }
    appBrightnessNotifier.value = loadedBrightness;
  } catch (e) {
    print('Erreur de chargement du thème initial : $e');
    appBrightnessNotifier.value = Brightness.dark;
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Message en arrière-plan reçu : ${message.notification?.title}');
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(initializePushServices());
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Brightness>(
      valueListenable: appBrightnessNotifier,
      builder: (context, brightness, child) {
        final isDarkMode = brightness == Brightness.dark;
        return MaterialApp(
          title: 'Daytalia',
          theme: isDarkMode ? ThemeData.dark() : ThemeData.light(),
          home: const AuthWrapper(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

Future<void> initializePushServices() async {
  try {
    OneSignal.initialize('83c44506-2022-4432-a8fe-004e4406416e');
    OneSignal.Notifications.requestPermission(true);
  } catch (e, stack) {
    debugPrint('Erreur OneSignal au démarrage: $e');
    debugPrintStack(stackTrace: stack);
  }
}

class _StartupErrorPage extends StatelessWidget {
  final String error;

  const _StartupErrorPage({required this.error});

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final background = isDark ? const Color(0xFF0F1116) : const Color(0xFFF6F9FF);
    final cardBackground = isDark ? const Color(0xFF1A2030) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardBackground,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade400, size: 52),
                    const SizedBox(height: 16),
                    Text(
                      'Daytalia n’a pas pu démarrer',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Une erreur est survenue pendant l’initialisation. Vérifie la configuration Firebase iOS et les permissions du projet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      error,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black45,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Utiliser le thème déjà chargé pour l'écran de chargement
    final isDark = appBrightnessNotifier.value == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final spinnerColor = isDark ? Colors.white : Colors.blue;

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // Écran de chargement stylisé (pendant vérification auth)
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: bgColor,
            body: Center(child: CircularProgressIndicator(color: spinnerColor)),
          );
        }

        if (authSnapshot.hasData) {
          return FutureBuilder<DocumentSnapshot>(
            future:
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(authSnapshot.data!.uid)
                    .get(),
            builder: (context, userDocSnapshot) {
              // Écran de chargement stylisé (pendant vérification profil)
              if (userDocSnapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  backgroundColor: bgColor,
                  body: Center(
                    child: CircularProgressIndicator(color: spinnerColor),
                  ),
                );
              }

              if (!userDocSnapshot.hasData || !userDocSnapshot.data!.exists) {
                return const InscriptionPage();
              }

              final userData =
                  userDocSnapshot.data!.data() as Map<String, dynamic>? ?? {};
              final bool accountBlocked =
                  userData['accountBlocked'] == true ||
                  userData['recoveryStatus'] == 'pending';

              if (accountBlocked) {
                return AccountBlockedPage(
                  userId: authSnapshot.data!.uid,
                );
              }

              return const AppInitializer(child: HomeBarrePage());
            },
          );
        }

        return FutureBuilder<SharedPreferences>(
          future: SharedPreferences.getInstance(),
          builder: (context, prefsSnapshot) {
            if (prefsSnapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                backgroundColor: bgColor,
                body: Center(
                  child: CircularProgressIndicator(color: spinnerColor),
                ),
              );
            }

            final prefs = prefsSnapshot.data;
            final hasCompletedTutorial =
                prefs?.getBool('introTutorialCompleted') ?? false;

            if (!hasCompletedTutorial) {
              return const OnboardingTutorialPage(showAuthActions: true);
            }

            return const InscriptionPage();
          },
        );
      },
    );
  }
}

class AccountBlockedPage extends StatefulWidget {
  final String userId;

  const AccountBlockedPage({super.key, required this.userId});

  @override
  State<AccountBlockedPage> createState() => _AccountBlockedPageState();
}

class _AccountBlockedPageState extends State<AccountBlockedPage> {
  bool _loading = false;

  Future<void> _refreshStatus() async {
    setState(() => _loading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final data = doc.data() ?? {};
      final bool stillBlocked =
          data['accountBlocked'] == true || data['recoveryStatus'] == 'pending';

      if (!mounted) return;
      if (!stillBlocked) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppInitializer(child: HomeBarrePage())),
          (_) => false,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bg = isDarkMode ? const Color(0xFF0F1116) : const Color(0xFFF6F9FF);
    final cardBg = isDarkMode ? const Color(0xFF1A2030) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.orange.shade400, Colors.red.shade400],
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.lock_outline, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Compte en attente de validation',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Votre demande de récupération a été enregistrée. Le compte sera débloqué dès que vous validez la demande dans Firebase.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _loading ? null : _refreshStatus,
                        child: _loading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Vérifier la validation'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppInitializer extends StatefulWidget {
  final Widget child;
  const AppInitializer({Key? key, required this.child}) : super(key: key);

  @override
  _AppInitializerState createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    _initOneSignalAndSavePlayerId();
  }

  Future<void> _initOneSignalAndSavePlayerId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String? playerId = OneSignal.User.pushSubscription.id;

    if (playerId != null && playerId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'oneSignalPlayerId': playerId,
        }, SetOptions(merge: true));
        print("--- OneSignal: Player ID $playerId enregistré pour ${user.uid}");
      } catch (e) {
        print(
          "--- ERREUR OneSignal: Impossible d'enregistrer le Player ID: $e",
        );
      }
    } else {
      OneSignal.User.pushSubscription.addObserver((state) {
        if (state.current.id != null && state.current.id!.isNotEmpty) {
          _initOneSignalAndSavePlayerId();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomeBarrePage extends StatefulWidget {
  const HomeBarrePage({super.key});

  @override
  _HomeBarrePageState createState() => _HomeBarrePageState();
}

class _HomeBarrePageState extends State<HomeBarrePage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late PageController _pageController;
  Key _homePageKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    if (page != 1) {
      setState(() {
        _selectedIndex = page;
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      _showAddOptionsDialog();
    } else {
      setState(() {
        _selectedIndex = index;
        _pageController.jumpToPage(index);
      });
    }
  }

  void _refreshHomePage() {
    setState(() {
      _homePageKey = UniqueKey();
    });
  }

  void _showAddOptionsDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (BuildContext context) {
        final isDarkMode = appBrightnessNotifier.value == Brightness.dark;
        final Color dialogBackgroundColor =
            isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
        final Color textColor = isDarkMode ? Colors.white : Colors.black;
        final Color buttonBackgroundColor =
            isDarkMode ? Colors.grey[800]! : Colors.blue.shade50;
        final Color buttonIconColor = isDarkMode ? Colors.white : Colors.blue;
        final Color buttonTextColor = isDarkMode ? Colors.white : Colors.blue;

        return Container(
          height: 250,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: dialogBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Que voulez-vous ajouter ?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: _buildOptionButton(
                      icon: Icons.calendar_today,
                      label: 'Raconter\nsa journée',
                      onTap: () {
                        Navigator.pop(context);
                        _navigateToRaconterJournee();
                      },
                      backgroundColor: buttonBackgroundColor,
                      iconColor: buttonIconColor,
                      textColor: buttonTextColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildOptionButton(
                      icon: Icons.memory,
                      label: 'Raconter\nun souvenir',
                      onTap: () {
                        Navigator.pop(context);
                        _navigateToRaconterSouvenir();
                      },
                      backgroundColor: buttonBackgroundColor,
                      iconColor: buttonIconColor,
                      textColor: buttonTextColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildOptionButton(
                      icon: Icons.live_tv,
                      label: 'Journée\nen direct',
                      onTap: () {
                        Navigator.pop(context);
                        _navigateToJourneeEnDirect();
                      },
                      backgroundColor: buttonBackgroundColor,
                      iconColor: buttonIconColor,
                      textColor: buttonTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToJourneeEnDirect() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const JourneeEnDirectPage()),
    );
    if (result == true && mounted) {
      _refreshHomePage();
    }
  }

  void _navigateToRaconterJournee() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const JourneePage()),
    );
  }

  void _navigateToRaconterSouvenir() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SouvenirPage()),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color iconColor,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        height: 130,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: iconColor),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Brightness>(
      valueListenable: appBrightnessNotifier,
      builder: (context, brightness, child) {
        final isDarkMode = brightness == Brightness.dark;
        final Color navbarBackgroundColor =
            isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
        final Color selectedItemColor = Colors.blue;
        final Color unselectedItemColor =
            isDarkMode ? Colors.grey[600]! : Colors.grey;
        final Color borderColor =
            isDarkMode ? Colors.grey.shade700 : Colors.transparent;

        return Scaffold(
          body: Stack(
            children: [
              PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  KeyedSubtree(key: _homePageKey, child: const HomePage()),
                  Container(color: isDarkMode ? Colors.black : Colors.white),
                  const KeyedSubtree(key: ValueKey(2), child: MemoriesPage()),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: navbarBackgroundColor,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: borderColor,
                            width: isDarkMode ? 1.0 : 0.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  isDarkMode
                                      ? Colors.black54
                                      : Colors.grey.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BottomNavigationBar(
                            backgroundColor: navbarBackgroundColor,
                            selectedItemColor: selectedItemColor,
                            unselectedItemColor: unselectedItemColor,
                            showUnselectedLabels: false,
                            items: const <BottomNavigationBarItem>[
                              BottomNavigationBarItem(
                                icon: Icon(Icons.home),
                                label: 'Accueil',
                              ),
                              BottomNavigationBarItem(
                                icon: Icon(Icons.add_circle),
                                label: 'Ajouter',
                              ),
                              BottomNavigationBarItem(
                                icon: Icon(Icons.person),
                                label: 'Memories',
                              ),
                            ],
                            currentIndex: _selectedIndex,
                            onTap: _onItemTapped,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
