
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'connexion_page.dart';
import 'home_page.dart';
import 'memories_page.dart';
import 'journee_page.dart';
import 'souvenir_page.dart';
import 'JourneeEnDirectPage_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:intl/date_symbol_data_local.dart';

final ValueNotifier<Brightness> appBrightnessNotifier = ValueNotifier<Brightness>(Brightness.light);

void main() async {
WidgetsFlutterBinding.ensureInitialized();
await initializeDateFormatting('fr_FR', null);
await Firebase.initializeApp(
options: DefaultFirebaseOptions.currentPlatform,
);

// OneSignal.Debug.setLogLevel(OSLogLevel.verbose); // Optionnel, pour le debug
OneSignal.initialize("83c44506-2022-4432-a8fe-004e4406416e");
OneSignal.Notifications.requestPermission(true);

FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
await _loadInitialAppBrightness();
runApp(const MyApp());
}

Future<void> _loadInitialAppBrightness() async {
try {
SharedPreferences prefs = await SharedPreferences.getInstance();
String? themeMode = prefs.getString('themeMode');
Brightness loadedBrightness = Brightness.light;
if (themeMode == 'dark') {
loadedBrightness = Brightness.dark;
} else if (themeMode == 'light') {
loadedBrightness = Brightness.light;
} else {
loadedBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
}
appBrightnessNotifier.value = loadedBrightness;
} catch (e) {
print('Erreur de chargement du thème initial : $e');
appBrightnessNotifier.value = Brightness.light;
}
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
print('Message en arrière-plan reçu : ${message.notification?.title}');
}

class MyApp extends StatelessWidget {
const MyApp({super.key});

@override
Widget build(BuildContext context) {
return ValueListenableBuilder<Brightness>(
valueListenable: appBrightnessNotifier,
builder: (context, brightness, child) {
final isDarkMode = brightness == Brightness.dark;
return MaterialApp(
title: 'Mon Application',
theme: isDarkMode ? ThemeData.dark() : ThemeData.light(),
home: const AuthWrapper(),
debugShowCheckedModeBanner: false,
);
},
);
}
}

class AuthWrapper extends StatelessWidget {
const AuthWrapper({super.key});

@override
Widget build(BuildContext context) {
return StreamBuilder<auth.User?>(
stream: FirebaseAuth.instance.authStateChanges(),
builder: (context, snapshot) {
if (snapshot.connectionState == ConnectionState.waiting) {
return const Scaffold(body: Center(child: CircularProgressIndicator()));
}
if (snapshot.hasData) {
// --- AMÉLIORATION : On initialise OneSignal ici
return AppInitializer(child: const SouvenirsEtJourneesApp());
}
return const ConnexionPage();
},
);
}
}

// --- AMÉLIORATION : Widget pour gérer l'initialisation après la connexion ---
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

    // Récupère l'ID de l'appareil (Player ID)
    final String? playerId = OneSignal.User.pushSubscription.id;

    if (playerId != null && playerId.isNotEmpty) {
      // Enregistre le Player ID dans Firestore pour cet utilisateur
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'oneSignalPlayerId': playerId}, SetOptions(merge: true));
        print("--- OneSignal: Player ID $playerId enregistré pour ${user.uid}");
      } catch (e) {
        print("--- ERREUR OneSignal: Impossible d'enregistrer le Player ID: $e");
      }
    } else {
      print("--- OneSignal: Player ID non encore disponible. L'utilisateur devra peut-être relancer l'app.");
      // OneSignal peut prendre un petit moment pour générer l'ID la première fois.
      // On peut écouter les changements pour l'obtenir plus tard.
      OneSignal.User.pushSubscription.addObserver((state) {
        if (state.current.id != null && state.current.id!.isNotEmpty) {
          _initOneSignalAndSavePlayerId(); // Réessaie d'enregistrer quand l'ID est disponible
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}


class SouvenirsEtJourneesApp extends StatelessWidget {
const SouvenirsEtJourneesApp({super.key});

@override
Widget build(BuildContext context) {
return ValueListenableBuilder<Brightness>(
valueListenable: appBrightnessNotifier,
builder: (context, brightness, child) {
final isDarkMode = brightness == Brightness.dark;
return MaterialApp(
title: 'Souvenirs et Journées',
theme: isDarkMode ? ThemeData.dark() : ThemeData.light(),
home: const HomeBarrePage(),
debugShowCheckedModeBanner: false,
);
},
);
}
}

class HomeBarrePage extends StatefulWidget {
const HomeBarrePage({super.key});

@override
_HomeBarrePageState createState() => _HomeBarrePageState();
}

class _HomeBarrePageState extends State<HomeBarrePage> with SingleTickerProviderStateMixin {
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
borderRadius: BorderRadius.vertical(
top: Radius.circular(25),
),
),
builder: (BuildContext context) {
final isDarkMode = appBrightnessNotifier.value == Brightness.dark;
final Color dialogBackgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
final Color textColor = isDarkMode ? Colors.white : Colors.black;
final Color buttonBackgroundColor = isDarkMode ? Colors.grey[800]! : Colors.blue.shade50;
final Color buttonIconColor = isDarkMode ? Colors.white : Colors.blue;
final Color buttonTextColor = isDarkMode ? Colors.white : Colors.blue;

return Container(
height: 250,
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
color: dialogBackgroundColor,
borderRadius: const BorderRadius.vertical(
top: Radius.circular(25),
),
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
      Expanded( // <-- AJOUTER ICI
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
      const SizedBox(width: 8), // Optionnel: pour ajouter un petit espace entre les boutons
      Expanded( // <-- AJOUTER ICI
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
      const SizedBox(width: 8), // Optionnel: pour ajouter un petit espace entre les boutons
      Expanded( // <-- AJOUTER ICI
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
  )
    ]
)
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
style: TextStyle(
color: textColor,
fontWeight: FontWeight.bold,
),
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
final Color navbarBackgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
final Color selectedItemColor = Colors.blue;
final Color unselectedItemColor = isDarkMode ? Colors.grey[600]! : Colors.grey;
final Color borderColor = isDarkMode ? Colors.grey.shade700 : Colors.transparent;

return Scaffold(
body: Stack(
children: [
PageView(
controller: _pageController,
onPageChanged: _onPageChanged,
physics: const NeverScrollableScrollPhysics(),
children: <Widget>[
KeyedSubtree(
key: _homePageKey,
child: const HomePage(),
),
Container(color: isDarkMode ? Colors.black : Colors.white),
const KeyedSubtree(
key: ValueKey(2),
child: MemoriesPage(),
),
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
padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
child: Container(
decoration: BoxDecoration(
color: navbarBackgroundColor,
borderRadius: BorderRadius.circular(30),
border: Border.all(color: borderColor, width: isDarkMode ? 1.0 : 0.0),
boxShadow: [
BoxShadow(
color: isDarkMode ? Colors.black54 : Colors.grey.withOpacity(0.3),
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