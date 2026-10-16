/// Ten commonly used Indian languages, shown in their native scripts.
class AppLanguage {
  const AppLanguage(this.code, this.nativeName, this.englishName);

  final String code;
  final String nativeName;
  final String englishName;

  String get label => code == 'en' ? englishName : '$nativeName · $englishName';
}

const appLanguages = <AppLanguage>[
  AppLanguage('en', 'English', 'English'),
  AppLanguage('hi', 'हिन्दी', 'Hindi'),
  AppLanguage('te', 'తెలుగు', 'Telugu'),
  AppLanguage('ta', 'தமிழ்', 'Tamil'),
  AppLanguage('kn', 'ಕನ್ನಡ', 'Kannada'),
  AppLanguage('ml', 'മലയാളം', 'Malayalam'),
  AppLanguage('bn', 'বাংলা', 'Bengali'),
  AppLanguage('mr', 'मराठी', 'Marathi'),
  AppLanguage('gu', 'ગુજરાતી', 'Gujarati'),
  AppLanguage('pa', 'ਪੰਜਾਬੀ', 'Punjabi'),
];

AppLanguage languageFor(String code) => appLanguages.firstWhere(
      (language) => language.code == code,
      orElse: () => appLanguages.first,
    );
