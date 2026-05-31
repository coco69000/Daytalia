import 'package:flutter/material.dart';

// Initialiser avec Light comme défaut, sera mis à jour dans _loadInitialAppBrightness()
// dans main.dart avec la préférence utilisateur ou le thème système
final ValueNotifier<Brightness> appBrightnessNotifier = 
    ValueNotifier<Brightness>(Brightness.light);