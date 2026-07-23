import '../../data/models/scripture_model.dart';

const List<Translation> availableTranslations = [
  Translation(code: 'KJV', name: 'King James Version', shortName: 'KJV'),
  Translation(code: 'NIV', name: 'New International Version', shortName: 'NIV'),
  Translation(code: 'ESV', name: 'English Standard Version', shortName: 'ESV'),
  Translation(code: 'NLT', name: 'New Living Translation', shortName: 'NLT'),
  Translation(code: 'NKJV', name: 'New King James Version', shortName: 'NKJV'),
];

final Map<String, Map<String, ScripturePassage>> mockScriptureDB = {
  'KJV': {
    'John 3:16': ScripturePassage(
      reference: 'John 3:16',
      translation: 'KJV',
      book: 'John',
      chapter: 3,
      verseStart: 16,
      verseEnd: 16,
      verses: [
        ScriptureVerse(
          verseNumber: 16,
          text:
              'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.',
        ),
      ],
    ),
    'John 3:16-17': ScripturePassage(
      reference: 'John 3:16-17',
      translation: 'KJV',
      book: 'John',
      chapter: 3,
      verseStart: 16,
      verseEnd: 17,
      verses: [
        ScriptureVerse(
          verseNumber: 16,
          text:
              'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.',
        ),
        ScriptureVerse(
          verseNumber: 17,
          text:
              'For God sent not his Son into the world to condemn the world; but that the world through him might be saved.',
        ),
      ],
    ),
    'Romans 5:1': ScripturePassage(
      reference: 'Romans 5:1',
      translation: 'KJV',
      book: 'Romans',
      chapter: 5,
      verseStart: 1,
      verseEnd: 1,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text:
              'Therefore being justified by faith, we have peace with God through our Lord Jesus Christ.',
        ),
      ],
    ),
    'Romans 5:1-5': ScripturePassage(
      reference: 'Romans 5:1-5',
      translation: 'KJV',
      book: 'Romans',
      chapter: 5,
      verseStart: 1,
      verseEnd: 5,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text:
              'Therefore being justified by faith, we have peace with God through our Lord Jesus Christ.',
        ),
        ScriptureVerse(
          verseNumber: 2,
          text:
              'By whom also we have access by faith into this grace wherein we stand, and rejoice in hope of the glory of God.',
        ),
        ScriptureVerse(
          verseNumber: 3,
          text:
              'And not only so, but we glory in tribulations also: knowing that tribulation worketh patience.',
        ),
        ScriptureVerse(
          verseNumber: 4,
          text: 'And patience, experience; and experience, hope.',
        ),
        ScriptureVerse(
          verseNumber: 5,
          text:
              'And hope maketh not ashamed; because the love of God is shed abroad in our hearts by the Holy Ghost which is given unto us.',
        ),
      ],
    ),
    'Philippians 4:13': ScripturePassage(
      reference: 'Philippians 4:13',
      translation: 'KJV',
      book: 'Philippians',
      chapter: 4,
      verseStart: 13,
      verseEnd: 13,
      verses: [
        ScriptureVerse(
          verseNumber: 13,
          text: 'I can do all things through Christ which strengtheneth me.',
        ),
      ],
    ),
    'Isaiah 40:31': ScripturePassage(
      reference: 'Isaiah 40:31',
      translation: 'KJV',
      book: 'Isaiah',
      chapter: 40,
      verseStart: 31,
      verseEnd: 31,
      verses: [
        ScriptureVerse(
          verseNumber: 31,
          text:
              'But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint.',
        ),
      ],
    ),
    'Psalm 23:1': ScripturePassage(
      reference: 'Psalm 23:1',
      translation: 'KJV',
      book: 'Psalm',
      chapter: 23,
      verseStart: 1,
      verseEnd: 1,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text: 'The LORD is my shepherd; I shall not want.',
        ),
      ],
    ),
    'Psalm 23:1-6': ScripturePassage(
      reference: 'Psalm 23:1-6',
      translation: 'KJV',
      book: 'Psalm',
      chapter: 23,
      verseStart: 1,
      verseEnd: 6,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text: 'The LORD is my shepherd; I shall not want.',
        ),
        ScriptureVerse(
          verseNumber: 2,
          text:
              'He maketh me to lie down in green pastures: he leadeth me beside the still waters.',
        ),
        ScriptureVerse(
          verseNumber: 3,
          text:
              'He restoreth my soul: he leadeth me in the paths of righteousness for his name\'s sake.',
        ),
        ScriptureVerse(
          verseNumber: 4,
          text:
              'Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff they comfort me.',
        ),
        ScriptureVerse(
          verseNumber: 5,
          text:
              'Thou preparest a table before me in the presence of mine enemies: thou anointest my head with oil; my cup runneth over.',
        ),
        ScriptureVerse(
          verseNumber: 6,
          text:
              'Surely goodness and mercy shall follow me all the days of my life: and I will dwell in the house of the LORD for ever.',
        ),
      ],
    ),
    'Jeremiah 29:11': ScripturePassage(
      reference: 'Jeremiah 29:11',
      translation: 'KJV',
      book: 'Jeremiah',
      chapter: 29,
      verseStart: 11,
      verseEnd: 11,
      verses: [
        ScriptureVerse(
          verseNumber: 11,
          text:
              'For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end.',
        ),
      ],
    ),
    'Hebrews 11:1': ScripturePassage(
      reference: 'Hebrews 11:1',
      translation: 'KJV',
      book: 'Hebrews',
      chapter: 11,
      verseStart: 1,
      verseEnd: 1,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text:
              'Now faith is the substance of things hoped for, the evidence of things not seen.',
        ),
      ],
    ),
    'Ephesians 2:8-9': ScripturePassage(
      reference: 'Ephesians 2:8-9',
      translation: 'KJV',
      book: 'Ephesians',
      chapter: 2,
      verseStart: 8,
      verseEnd: 9,
      verses: [
        ScriptureVerse(
          verseNumber: 8,
          text:
              'For by grace are ye saved through faith; and that not of yourselves: it is the gift of God.',
        ),
        ScriptureVerse(
          verseNumber: 9,
          text: 'Not of works, lest any man should boast.',
        ),
      ],
    ),
    'Genesis 1:1': ScripturePassage(
      reference: 'Genesis 1:1',
      translation: 'KJV',
      book: 'Genesis',
      chapter: 1,
      verseStart: 1,
      verseEnd: 1,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text: 'In the beginning God created the heaven and the earth.',
        ),
      ],
    ),
    'Proverbs 3:5-6': ScripturePassage(
      reference: 'Proverbs 3:5-6',
      translation: 'KJV',
      book: 'Proverbs',
      chapter: 3,
      verseStart: 5,
      verseEnd: 6,
      verses: [
        ScriptureVerse(
          verseNumber: 5,
          text:
              'Trust in the LORD with all thine heart; and lean not unto thine own understanding.',
        ),
        ScriptureVerse(
          verseNumber: 6,
          text:
              'In all thy ways acknowledge him, and he shall direct thy paths.',
        ),
      ],
    ),
  },
  'NIV': {
    'John 3:16': ScripturePassage(
      reference: 'John 3:16',
      translation: 'NIV',
      book: 'John',
      chapter: 3,
      verseStart: 16,
      verseEnd: 16,
      verses: [
        ScriptureVerse(
          verseNumber: 16,
          text:
              'For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.',
        ),
      ],
    ),
    'Romans 5:1': ScripturePassage(
      reference: 'Romans 5:1',
      translation: 'NIV',
      book: 'Romans',
      chapter: 5,
      verseStart: 1,
      verseEnd: 1,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text:
              'Therefore, since we have been justified through faith, we have peace with God through our Lord Jesus Christ.',
        ),
      ],
    ),
    'Romans 5:1-5': ScripturePassage(
      reference: 'Romans 5:1-5',
      translation: 'NIV',
      book: 'Romans',
      chapter: 5,
      verseStart: 1,
      verseEnd: 5,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text:
              'Therefore, since we have been justified through faith, we have peace with God through our Lord Jesus Christ.',
        ),
        ScriptureVerse(
          verseNumber: 2,
          text:
              'through whom we have gained access by faith into this grace in which we now stand. And we boast in the hope of the glory of God.',
        ),
        ScriptureVerse(
          verseNumber: 3,
          text:
              'Not only so, but we also glory in our sufferings, because we know that suffering produces perseverance;',
        ),
        ScriptureVerse(
          verseNumber: 4,
          text: 'perseverance, character; and character, hope.',
        ),
        ScriptureVerse(
          verseNumber: 5,
          text:
              'And hope does not put us to shame, because God\'s love has been poured out into our hearts through the Holy Spirit, who has been given to us.',
        ),
      ],
    ),
    'Philippians 4:13': ScripturePassage(
      reference: 'Philippians 4:13',
      translation: 'NIV',
      book: 'Philippians',
      chapter: 4,
      verseStart: 13,
      verseEnd: 13,
      verses: [
        ScriptureVerse(
          verseNumber: 13,
          text: 'I can do all this through him who gives me strength.',
        ),
      ],
    ),
    'Jeremiah 29:11': ScripturePassage(
      reference: 'Jeremiah 29:11',
      translation: 'NIV',
      book: 'Jeremiah',
      chapter: 29,
      verseStart: 11,
      verseEnd: 11,
      verses: [
        ScriptureVerse(
          verseNumber: 11,
          text:
              'For I know the plans I have for you, declares the LORD, plans to prosper you and not to harm you, plans to give you hope and a future.',
        ),
      ],
    ),
    'Proverbs 3:5-6': ScripturePassage(
      reference: 'Proverbs 3:5-6',
      translation: 'NIV',
      book: 'Proverbs',
      chapter: 3,
      verseStart: 5,
      verseEnd: 6,
      verses: [
        ScriptureVerse(
          verseNumber: 5,
          text:
              'Trust in the LORD with all your heart and lean not on your own understanding.',
        ),
        ScriptureVerse(
          verseNumber: 6,
          text:
              'in all your ways submit to him, and he will make your paths straight.',
        ),
      ],
    ),
    'Isaiah 40:31': ScripturePassage(
      reference: 'Isaiah 40:31',
      translation: 'NIV',
      book: 'Isaiah',
      chapter: 40,
      verseStart: 31,
      verseEnd: 31,
      verses: [
        ScriptureVerse(
          verseNumber: 31,
          text:
              'but those who hope in the LORD will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.',
        ),
      ],
    ),
    'Hebrews 11:1': ScripturePassage(
      reference: 'Hebrews 11:1',
      translation: 'NIV',
      book: 'Hebrews',
      chapter: 11,
      verseStart: 1,
      verseEnd: 1,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text:
              'Now faith is confidence in what we hope for and assurance about what we do not see.',
        ),
      ],
    ),
    'Ephesians 2:8-9': ScripturePassage(
      reference: 'Ephesians 2:8-9',
      translation: 'NIV',
      book: 'Ephesians',
      chapter: 2,
      verseStart: 8,
      verseEnd: 9,
      verses: [
        ScriptureVerse(
          verseNumber: 8,
          text:
              'For it is by grace you have been saved, through faith — and this is not from yourselves, it is the gift of God —',
        ),
        ScriptureVerse(
          verseNumber: 9,
          text: 'not by works, so that no one can boast.',
        ),
      ],
    ),
    'Genesis 1:1': ScripturePassage(
      reference: 'Genesis 1:1',
      translation: 'NIV',
      book: 'Genesis',
      chapter: 1,
      verseStart: 1,
      verseEnd: 1,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text: 'In the beginning God created the heavens and the earth.',
        ),
      ],
    ),
  },
  'ESV': {
    'John 3:16': ScripturePassage(
      reference: 'John 3:16',
      translation: 'ESV',
      book: 'John',
      chapter: 3,
      verseStart: 16,
      verseEnd: 16,
      verses: [
        ScriptureVerse(
          verseNumber: 16,
          text:
              'For God so loved the world, that he gave his only Son, that whoever believes in him should not perish but have eternal life.',
        ),
      ],
    ),
    'Romans 5:1': ScripturePassage(
      reference: 'Romans 5:1',
      translation: 'ESV',
      book: 'Romans',
      chapter: 5,
      verseStart: 1,
      verseEnd: 1,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text:
              'Therefore, since we have been justified by faith, we have peace with God through our Lord Jesus Christ.',
        ),
      ],
    ),
    'Philippians 4:13': ScripturePassage(
      reference: 'Philippians 4:13',
      translation: 'ESV',
      book: 'Philippians',
      chapter: 4,
      verseStart: 13,
      verseEnd: 13,
      verses: [
        ScriptureVerse(
          verseNumber: 13,
          text: 'I can do all things through him who strengthens me.',
        ),
      ],
    ),
    'Jeremiah 29:11': ScripturePassage(
      reference: 'Jeremiah 29:11',
      translation: 'ESV',
      book: 'Jeremiah',
      chapter: 29,
      verseStart: 11,
      verseEnd: 11,
      verses: [
        ScriptureVerse(
          verseNumber: 11,
          text:
              'For I know the plans I have for you, declares the LORD, plans for welfare and not for evil, to give you a future and a hope.',
        ),
      ],
    ),
    'Hebrews 11:1': ScripturePassage(
      reference: 'Hebrews 11:1',
      translation: 'ESV',
      book: 'Hebrews',
      chapter: 11,
      verseStart: 1,
      verseEnd: 1,
      verses: [
        ScriptureVerse(
          verseNumber: 1,
          text:
              'Now faith is the assurance of things hoped for, the conviction of things not seen.',
        ),
      ],
    ),
    'Isaiah 40:31': ScripturePassage(
      reference: 'Isaiah 40:31',
      translation: 'ESV',
      book: 'Isaiah',
      chapter: 40,
      verseStart: 31,
      verseEnd: 31,
      verses: [
        ScriptureVerse(
          verseNumber: 31,
          text:
              'but they who wait for the LORD shall renew their strength; they shall mount up with wings like eagles; they shall run and not be weary; they shall walk and not faint.',
        ),
      ],
    ),
  },
};

ScripturePassage? lookupScripture(String ref, String translation) {
  final translationData = mockScriptureDB[translation];
  if (translationData == null) return null;
  return translationData[ref];
}

List<String> getAvailableTranslationsForRef(String ref) {
  return mockScriptureDB.entries
      .where((e) => e.value.containsKey(ref))
      .map((e) => e.key)
      .toList();
}
