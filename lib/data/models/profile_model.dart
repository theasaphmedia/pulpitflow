class UserProfile {
  final String id;
  final String? fullName;
  final String ministryTitle;
  final String? churchName;
  final String? denomination;
  final String? city;
  final String? country;
  final String defaultTranslation;
  final String? bio;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    this.fullName,
    this.ministryTitle = 'Pastor',
    this.churchName,
    this.denomination,
    this.city,
    this.country,
    this.defaultTranslation = 'KJV',
    this.bio,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromSupabase(Map<String, dynamic> row) {
    return UserProfile(
      id: row['id'] as String,
      fullName: row['full_name'] as String?,
      ministryTitle: row['ministry_title'] as String? ?? 'Pastor',
      churchName: row['church_name'] as String?,
      denomination: row['denomination'] as String?,
      city: row['city'] as String?,
      country: row['country'] as String?,
      defaultTranslation: row['default_translation'] as String? ?? 'KJV',
      bio: row['bio'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Map<String, dynamic> toSupabase() => {
    'id': id,
    'full_name': fullName,
    'ministry_title': ministryTitle,
    'church_name': churchName,
    'denomination': denomination,
    'city': city,
    'country': country,
    'default_translation': defaultTranslation,
    'bio': bio,
    'updated_at': DateTime.now().toIso8601String(),
  };

  UserProfile copyWith({
    String? fullName,
    String? ministryTitle,
    String? churchName,
    String? denomination,
    String? city,
    String? country,
    String? defaultTranslation,
    String? bio,
  }) {
    return UserProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      ministryTitle: ministryTitle ?? this.ministryTitle,
      churchName: churchName ?? this.churchName,
      denomination: denomination ?? this.denomination,
      city: city ?? this.city,
      country: country ?? this.country,
      defaultTranslation: defaultTranslation ?? this.defaultTranslation,
      bio: bio ?? this.bio,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Display name — falls back to "Minister" if name not yet set.
  /// Title-cased regardless of how it was typed into the profile field —
  /// a name saved as "solomon stephen" (or "SOLOMON STEPHEN") reads as
  /// "Solomon Stephen" everywhere this getter is shown verbatim, which
  /// includes both the Home greeting and the Profile header.
  String get displayName {
    if (fullName?.isNotEmpty != true) return 'Minister';
    return fullName!
        .trim()
        .split(RegExp(r'\s+'))
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  /// Avatar initial.
  String get initial => displayName[0].toUpperCase();
}

// ── Ministry titles & church roles ───────────────────────────────────────────
const List<String> kMinistryTitles = [
  // Preachers & Ministers
  'Pastor',
  'Senior Pastor',
  'Associate Pastor',
  'Youth Pastor',
  'Children\'s Pastor',
  'Bishop',
  'Elder',
  'Deacon',
  'Reverend',
  'Evangelist',
  'Apostle',
  'Prophet',
  'Teacher',
  'Minister',
  'Chaplain',
  // Church Operations
  'Worship Leader',
  'Worship Pastor',
  'Projectionist',
  'Sound Engineer',
  'Church Administrator',
  'Media Director',
  'Other',
];

// ── Denominations ─────────────────────────────────────────────────────────────
const List<String> kDenominations = [
  'Non-denominational',
  'Baptist',
  'Pentecostal',
  'Charismatic',
  'Methodist',
  'Anglican / Episcopal',
  'Presbyterian',
  'Lutheran',
  'Reformed / Calvinist',
  'Catholic',
  'Orthodox',
  'Assemblies of God',
  'Church of God',
  'Seventh-day Adventist',
  'Church of Christ',
  'Wesleyan',
  'Nazarene',
  'Foursquare',
  'Other',
];
