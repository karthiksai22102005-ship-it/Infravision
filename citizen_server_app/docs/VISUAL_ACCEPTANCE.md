# Visual Acceptance (vs reference image)

Status key: Built = code written; NOT yet compared on a device. Nothing here is visually verified.

| # | Screen | File | Status | Likely gaps to polish |
|---|---|---|---|---|
| 1 | Splash + language | features/onboarding/splash_screen.dart | Built | Logo is an icon, not the road/globe artwork; no skyline background |
| 2 | Home dashboard | features/dashboard/home_screen.dart | Built | Tile counts/colors to tune |
| 3 | Category selection | features/complaint_submission/category_screen.dart | Built | Icons are Material approximations; description field added here |
| 4 | Location | features/location/location_screen.dart | Built | OSM tiles (reference uses Google-style map) |
| 5 | Camera | features/camera/camera_screen.dart | Built | Photo/Video toggle omitted (photo only) |
| 6 | Photo preview | features/camera/photos_screen.dart | Built | |
| 7 | Review & submit | features/complaint_submission/review_screen.dart | Built | Map thumbnail not shown |
| 8 | Success | features/complaint_submission/success_screen.dart | Built | Confetti omitted |
| 9 | My Reports | features/reports/reports_screen.dart | Built | Thumbnails not shown in list |
| 10 | Details + timeline | features/complaint_details/details_screen.dart | Built | Map tab not implemented |
| 11 | Nearby map | features/nearby_issues/nearby_screen.dart | Built | Bottom summary card is a tap sheet |
| 12 | Notifications + Profile | features/notifications, features/profile | Built | Updates/Alerts/Messages tabs not split |
