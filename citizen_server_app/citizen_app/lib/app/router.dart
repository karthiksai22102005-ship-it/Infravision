import 'package:flutter/material.dart';

import '../features/assistant/assistant_screen.dart';
import '../features/camera/camera_screen.dart';
import '../features/camera/detection_overlay_screen.dart';
import '../features/camera/photos_screen.dart';
import '../features/complaint_details/details_screen.dart';
import '../features/complaint_submission/category_screen.dart';
import '../features/complaint_submission/review_screen.dart';
import '../features/complaint_submission/success_screen.dart';
import '../features/dashboard/home_screen.dart';
import '../features/location/location_screen.dart';
import '../features/nearby_issues/nearby_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/auth_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/reports/reports_screen.dart';

/// Central route table. Detail screens take the complaint reference as argument.
Route<dynamic> onGenerateRoute(RouteSettings s) {
  final Widget page = switch (s.name) {
    '/splash' => const SplashScreen(),
    '/auth' => const AuthScreen(),
    '/home' => const HomeScreen(),
    '/category' => const CategoryScreen(),
    '/location' => const LocationScreen(),
    '/camera' => const CameraScreen(),
    '/photos' => const PhotosScreen(),
    '/detection_review' =>
      DetectionOverlayScreen(imagePath: s.arguments as String),
    '/review' => const ReviewScreen(),
    '/success' => const SuccessScreen(),
    '/reports' => const ReportsScreen(),
    '/details' => DetailsScreen(reference: s.arguments as String),
    '/nearby' => const NearbyScreen(),
    '/notifications' => const NotificationsScreen(),
    '/profile' => const ProfileScreen(),
    '/assistant' => const AssistantScreen(),
    _ => const SplashScreen(),
  };
  return MaterialPageRoute(builder: (_) => page, settings: s);
}
