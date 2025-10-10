import 'package:flutter/material.dart';

/// Un ValueNotifier global pour gérer le mode sombre/clair de l'application.
/// Il est initialisé à `Brightness.light` par défaut.
final ValueNotifier<Brightness> appBrightnessNotifier = ValueNotifier<Brightness>(Brightness.light);