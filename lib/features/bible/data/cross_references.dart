/// Curated cross-reference data. Each key is a normalized verse reference
/// ("Book Chapter:Verse"); the value is a list of related references with a
/// short note that surfaces in the UI.
///
/// Coverage is intentionally limited to ~50 frequently-preached verses —
/// the goal is "useful starting point for sermon prep", not exhaustive
/// concordance coverage. Expand as the app grows or wire to an external
/// dataset (e.g. OpenBible.info's public cross-reference corpus).
class CrossReference {
  final String reference;
  final String note;
  const CrossReference({required this.reference, required this.note});
}

/// Lookup cross-references for a verse. Falls back to chapter-level matches
/// (e.g. "John 3:16-17" → "John 3:16") and finally returns null.
List<CrossReference>? crossRefsFor(String reference) {
  final ref = reference.trim();
  final direct = _crossRefs[ref];
  if (direct != null) return direct;

  // Strip a range like "John 3:16-17" → "John 3:16" and retry.
  final dashIdx = ref.indexOf('-');
  if (dashIdx > 0) {
    final base = ref.substring(0, dashIdx).trim();
    final fallback = _crossRefs[base];
    if (fallback != null) return fallback;
  }

  return null;
}

const Map<String, List<CrossReference>> _crossRefs = {
  // ── John ─────────────────────────────────
  'John 1:1': [
    CrossReference(reference: 'Genesis 1:1', note: 'In the beginning God created'),
    CrossReference(reference: 'Hebrews 1:2', note: 'Through whom He made the worlds'),
    CrossReference(reference: 'Colossians 1:16', note: 'All things created by Him'),
    CrossReference(reference: 'Revelation 19:13', note: 'His name is The Word of God'),
  ],
  'John 3:16': [
    CrossReference(reference: 'Romans 5:8', note: 'God demonstrates His love'),
    CrossReference(reference: '1 John 4:9', note: 'God sent His only Son'),
    CrossReference(reference: 'Ephesians 2:8-9', note: 'Saved through faith, not works'),
    CrossReference(reference: 'Romans 6:23', note: 'Eternal life through Christ'),
  ],
  'John 10:10': [
    CrossReference(reference: 'John 14:6', note: 'I am the way, the truth, the life'),
    CrossReference(reference: 'Psalm 23:1', note: 'The Lord is my shepherd'),
    CrossReference(reference: 'Ezekiel 34:11', note: 'I myself will search for my sheep'),
  ],
  'John 14:6': [
    CrossReference(reference: 'Acts 4:12', note: 'No other name under heaven'),
    CrossReference(reference: '1 Timothy 2:5', note: 'One mediator between God and men'),
    CrossReference(reference: 'Hebrews 10:20', note: 'A new and living way'),
  ],
  'John 15:5': [
    CrossReference(reference: 'Philippians 4:13', note: 'I can do all things through Him'),
    CrossReference(reference: '2 Corinthians 12:9', note: 'My grace is sufficient'),
    CrossReference(reference: 'Galatians 2:20', note: 'Christ lives in me'),
  ],

  // ── Romans ───────────────────────────────
  'Romans 1:16': [
    CrossReference(reference: '1 Corinthians 1:18', note: 'The message of the cross is power'),
    CrossReference(reference: '2 Timothy 1:8', note: 'Do not be ashamed of the testimony'),
    CrossReference(reference: 'Mark 8:38', note: 'Whoever is ashamed of Me'),
  ],
  'Romans 5:1': [
    CrossReference(reference: 'Ephesians 2:8', note: 'By grace through faith'),
    CrossReference(reference: 'Galatians 2:16', note: 'Justified by faith in Christ'),
    CrossReference(reference: 'Philippians 4:7', note: 'Peace that surpasses understanding'),
  ],
  'Romans 6:23': [
    CrossReference(reference: 'Genesis 2:17', note: 'You shall surely die'),
    CrossReference(reference: 'James 1:15', note: 'Sin brings forth death'),
    CrossReference(reference: 'John 3:16', note: 'Eternal life through the Son'),
  ],
  'Romans 8:28': [
    CrossReference(reference: 'Genesis 50:20', note: 'What was meant for evil'),
    CrossReference(reference: 'Jeremiah 29:11', note: 'Plans to prosper you'),
    CrossReference(reference: 'Philippians 4:7', note: 'Peace that transcends'),
  ],
  'Romans 8:38-39': [
    CrossReference(reference: 'John 10:28', note: 'No one shall snatch them out'),
    CrossReference(reference: 'Psalm 139:7', note: 'Where can I flee from Your presence'),
    CrossReference(reference: 'Isaiah 49:15', note: 'I will not forget you'),
  ],
  'Romans 12:1': [
    CrossReference(reference: '1 Peter 2:5', note: 'A spiritual house, a holy priesthood'),
    CrossReference(reference: 'Hebrews 13:15', note: 'Sacrifice of praise to God'),
    CrossReference(reference: 'Philippians 2:17', note: 'Poured out as a drink offering'),
  ],
  'Romans 12:2': [
    CrossReference(reference: 'Ephesians 4:23', note: 'Renewed in the spirit of your mind'),
    CrossReference(reference: '2 Corinthians 5:17', note: 'New creation in Christ'),
    CrossReference(reference: 'Colossians 3:10', note: 'Renewed in knowledge'),
  ],

  // ── Philippians ──────────────────────────
  'Philippians 4:7': [
    CrossReference(reference: 'Isaiah 26:3', note: 'Perfect peace whose mind is stayed'),
    CrossReference(reference: 'John 14:27', note: 'Peace I leave with you'),
    CrossReference(reference: 'Colossians 3:15', note: 'Let the peace of Christ rule'),
  ],
  'Philippians 4:13': [
    CrossReference(reference: '2 Corinthians 12:9', note: 'Strength in weakness'),
    CrossReference(reference: 'Ephesians 6:10', note: 'Strong in the Lord'),
    CrossReference(reference: 'Isaiah 40:31', note: 'Renew their strength'),
  ],
  'Philippians 4:19': [
    CrossReference(reference: 'Matthew 6:33', note: 'Seek first the kingdom'),
    CrossReference(reference: 'Psalm 23:1', note: 'I shall not want'),
    CrossReference(reference: '2 Corinthians 9:8', note: 'God is able to make all grace abound'),
  ],

  // ── Psalms ───────────────────────────────
  'Psalm 23:1': [
    CrossReference(reference: 'John 10:11', note: 'I am the good shepherd'),
    CrossReference(reference: 'Isaiah 40:11', note: 'He tends His flock like a shepherd'),
    CrossReference(reference: 'Ezekiel 34:15', note: 'I myself will tend my sheep'),
  ],
  'Psalm 27:1': [
    CrossReference(reference: 'Isaiah 12:2', note: 'The Lord is my strength and song'),
    CrossReference(reference: '1 John 4:18', note: 'Perfect love casts out fear'),
    CrossReference(reference: 'Psalm 46:1', note: 'God is our refuge and strength'),
  ],
  'Psalm 37:4': [
    CrossReference(reference: 'Matthew 6:33', note: 'Seek first His kingdom'),
    CrossReference(reference: 'Isaiah 58:14', note: 'You shall delight yourself in the Lord'),
    CrossReference(reference: 'Psalm 73:25', note: 'Whom have I in heaven but You'),
  ],
  'Psalm 46:1': [
    CrossReference(reference: 'Deuteronomy 33:27', note: 'The eternal God is your refuge'),
    CrossReference(reference: 'Psalm 91:2', note: 'My refuge and my fortress'),
    CrossReference(reference: 'Isaiah 25:4', note: 'A refuge from the storm'),
  ],
  'Psalm 119:105': [
    CrossReference(reference: 'Proverbs 6:23', note: 'The commandment is a lamp'),
    CrossReference(reference: '2 Peter 1:19', note: 'A light shining in a dark place'),
    CrossReference(reference: 'Psalm 19:8', note: 'The commandment of the Lord is pure'),
  ],
  'Psalm 139:14': [
    CrossReference(reference: 'Genesis 1:27', note: 'God created man in His image'),
    CrossReference(reference: 'Jeremiah 1:5', note: 'Before I formed you I knew you'),
    CrossReference(reference: 'Ephesians 2:10', note: 'We are His workmanship'),
  ],

  // ── Proverbs ─────────────────────────────
  'Proverbs 3:5-6': [
    CrossReference(reference: 'Psalm 37:5', note: 'Commit your way to the Lord'),
    CrossReference(reference: 'Jeremiah 17:7', note: 'Blessed is the one who trusts'),
    CrossReference(reference: 'Isaiah 26:3', note: 'You will keep him in perfect peace'),
  ],

  // ── Isaiah ───────────────────────────────
  'Isaiah 40:31': [
    CrossReference(reference: 'Psalm 103:5', note: 'Renews your youth like the eagle'),
    CrossReference(reference: 'Habakkuk 3:19', note: 'He makes my feet like deer'),
    CrossReference(reference: '2 Corinthians 4:16', note: 'Inwardly renewed day by day'),
  ],
  'Isaiah 41:10': [
    CrossReference(reference: 'Deuteronomy 31:6', note: 'Be strong and courageous'),
    CrossReference(reference: 'Joshua 1:9', note: 'Be strong and of good courage'),
    CrossReference(reference: 'Psalm 27:1', note: 'Whom shall I fear'),
  ],
  'Isaiah 53:5': [
    CrossReference(reference: '1 Peter 2:24', note: 'By His wounds you have been healed'),
    CrossReference(reference: 'Romans 4:25', note: 'Delivered up for our trespasses'),
    CrossReference(reference: '2 Corinthians 5:21', note: 'Made Him to be sin for us'),
  ],

  // ── Jeremiah ─────────────────────────────
  'Jeremiah 29:11': [
    CrossReference(reference: 'Romans 8:28', note: 'All things work for good'),
    CrossReference(reference: 'Proverbs 23:18', note: 'Surely there is a future'),
    CrossReference(reference: 'Psalm 32:8', note: 'I will instruct and teach you'),
  ],

  // ── Matthew ──────────────────────────────
  'Matthew 5:16': [
    CrossReference(reference: '1 Peter 2:12', note: 'Live such good lives among the pagans'),
    CrossReference(reference: 'Philippians 2:15', note: 'Shine as lights in the world'),
    CrossReference(reference: 'Ephesians 5:8', note: 'Walk as children of light'),
  ],
  'Matthew 6:33': [
    CrossReference(reference: 'Luke 12:31', note: 'Seek His kingdom, these will be added'),
    CrossReference(reference: 'Psalm 37:4', note: 'Delight yourself in the Lord'),
    CrossReference(reference: '1 Kings 3:11-13', note: 'Solomon asked for wisdom first'),
  ],
  'Matthew 11:28': [
    CrossReference(reference: 'Jeremiah 6:16', note: 'Find rest for your souls'),
    CrossReference(reference: 'Hebrews 4:9-10', note: 'A Sabbath rest for the people of God'),
    CrossReference(reference: 'Isaiah 40:31', note: 'Renew their strength'),
  ],
  'Matthew 28:19-20': [
    CrossReference(reference: 'Mark 16:15', note: 'Preach the gospel to all creation'),
    CrossReference(reference: 'Acts 1:8', note: 'You will be my witnesses'),
    CrossReference(reference: 'Luke 24:47', note: 'Repentance and forgiveness'),
  ],

  // ── Acts ─────────────────────────────────
  'Acts 1:8': [
    CrossReference(reference: 'Luke 24:49', note: 'Stay until you are clothed with power'),
    CrossReference(reference: 'Matthew 28:19', note: 'Go and make disciples'),
    CrossReference(reference: 'John 14:26', note: 'The Helper will teach you'),
  ],

  // ── 1 Corinthians ────────────────────────
  '1 Corinthians 10:13': [
    CrossReference(reference: '2 Peter 2:9', note: 'The Lord knows how to rescue the godly'),
    CrossReference(reference: 'Hebrews 2:18', note: 'He is able to help those tempted'),
    CrossReference(reference: 'James 1:12', note: 'Blessed is the one who perseveres'),
  ],
  '1 Corinthians 13:4-7': [
    CrossReference(reference: 'Romans 12:9-10', note: 'Love must be sincere'),
    CrossReference(reference: '1 John 4:8', note: 'God is love'),
    CrossReference(reference: 'Galatians 5:22', note: 'The fruit of the Spirit'),
  ],

  // ── 2 Corinthians ────────────────────────
  '2 Corinthians 5:17': [
    CrossReference(reference: 'Galatians 6:15', note: 'A new creation'),
    CrossReference(reference: 'Ephesians 4:24', note: 'Put on the new self'),
    CrossReference(reference: 'Romans 6:4', note: 'Newness of life'),
  ],
  '2 Corinthians 12:9': [
    CrossReference(reference: 'Philippians 4:13', note: 'I can do all things'),
    CrossReference(reference: '2 Corinthians 4:7', note: 'Treasure in jars of clay'),
    CrossReference(reference: 'Isaiah 40:29', note: 'He gives strength to the weary'),
  ],

  // ── Galatians ────────────────────────────
  'Galatians 2:20': [
    CrossReference(reference: 'Romans 6:6', note: 'Our old self was crucified'),
    CrossReference(reference: 'Colossians 3:3', note: 'Your life is hidden with Christ'),
    CrossReference(reference: 'Philippians 1:21', note: 'For me to live is Christ'),
  ],
  'Galatians 5:22-23': [
    CrossReference(reference: 'Ephesians 5:9', note: 'The fruit of light'),
    CrossReference(reference: 'James 3:17', note: 'Wisdom from above'),
    CrossReference(reference: 'Colossians 3:12', note: 'Put on compassion, kindness'),
  ],

  // ── Ephesians ────────────────────────────
  'Ephesians 2:8': [
    CrossReference(reference: 'Romans 3:24', note: 'Justified freely by His grace'),
    CrossReference(reference: 'Titus 3:5', note: 'Not by works of righteousness'),
    CrossReference(reference: '2 Timothy 1:9', note: 'Saved according to His purpose'),
  ],
  'Ephesians 2:8-9': [
    CrossReference(reference: 'Romans 3:28', note: 'Justified by faith apart from works'),
    CrossReference(reference: 'Galatians 2:16', note: 'Not by the works of the Law'),
    CrossReference(reference: 'Titus 3:5', note: 'According to His mercy'),
  ],
  'Ephesians 6:10': [
    CrossReference(reference: '1 Corinthians 16:13', note: 'Stand firm in the faith'),
    CrossReference(reference: '2 Timothy 2:1', note: 'Be strong in the grace'),
    CrossReference(reference: 'Psalm 27:14', note: 'Be strong and take heart'),
  ],

  // ── Hebrews ──────────────────────────────
  'Hebrews 11:1': [
    CrossReference(reference: 'Romans 8:24-25', note: 'Hope that is seen is not hope'),
    CrossReference(reference: '2 Corinthians 5:7', note: 'We walk by faith, not by sight'),
    CrossReference(reference: 'Hebrews 11:6', note: 'Without faith it is impossible'),
  ],

  // ── James ────────────────────────────────
  'James 1:5': [
    CrossReference(reference: 'Proverbs 2:6', note: 'The Lord gives wisdom'),
    CrossReference(reference: '1 Kings 3:9', note: 'Give your servant an understanding heart'),
    CrossReference(reference: 'Matthew 7:7', note: 'Ask and it will be given to you'),
  ],

  // ── 1 Peter ──────────────────────────────
  '1 Peter 5:7': [
    CrossReference(reference: 'Psalm 55:22', note: 'Cast your burden on the Lord'),
    CrossReference(reference: 'Philippians 4:6-7', note: 'Do not be anxious about anything'),
    CrossReference(reference: 'Matthew 6:25', note: 'Do not worry about your life'),
  ],

  // ── 1 John ───────────────────────────────
  '1 John 1:9': [
    CrossReference(reference: 'Proverbs 28:13', note: 'Whoever conceals their sins'),
    CrossReference(reference: 'Psalm 32:5', note: 'I acknowledged my sin to You'),
    CrossReference(reference: 'James 5:16', note: 'Confess your sins to one another'),
  ],
  '1 John 4:19': [
    CrossReference(reference: 'John 15:16', note: 'You did not choose Me'),
    CrossReference(reference: 'Romans 5:8', note: 'While we were still sinners'),
    CrossReference(reference: 'Jeremiah 31:3', note: 'I have loved you with an everlasting love'),
  ],

  // ── Genesis ──────────────────────────────
  'Genesis 1:1': [
    CrossReference(reference: 'John 1:1', note: 'In the beginning was the Word'),
    CrossReference(reference: 'Hebrews 11:3', note: 'Worlds framed by the word of God'),
    CrossReference(reference: 'Psalm 33:6', note: 'By the word of the Lord the heavens'),
  ],

  // ── Joshua ───────────────────────────────
  'Joshua 1:9': [
    CrossReference(reference: 'Deuteronomy 31:6', note: 'Be strong and of good courage'),
    CrossReference(reference: 'Isaiah 41:10', note: 'Fear not, for I am with you'),
    CrossReference(reference: '2 Timothy 1:7', note: 'Spirit of power, love, and self-control'),
  ],

  // ── 2 Timothy ────────────────────────────
  '2 Timothy 1:7': [
    CrossReference(reference: 'Romans 8:15', note: 'Not a spirit of slavery to fear'),
    CrossReference(reference: '1 John 4:18', note: 'Perfect love casts out fear'),
    CrossReference(reference: 'Joshua 1:9', note: 'Be strong and courageous'),
  ],

  // ── Revelation ───────────────────────────
  'Revelation 21:4': [
    CrossReference(reference: 'Isaiah 25:8', note: 'He will swallow up death forever'),
    CrossReference(reference: 'Revelation 7:17', note: 'God will wipe away every tear'),
    CrossReference(reference: '1 Corinthians 15:54', note: 'Death is swallowed up in victory'),
  ],
};
