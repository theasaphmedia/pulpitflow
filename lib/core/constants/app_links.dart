/// Public URLs for the deployed PulpitFlow web build.
///
/// Used by the "Share" action on the preacher's session-code card (see
/// preaching_screen.dart) to build a clickable join link — e.g.
/// `$kPulpitFlowWebUrl/projection?code=7N2RYT` — instead of making the
/// projectionist type a 6-character code read aloud over a phone call.
///
/// UPDATE THIS after the first Vercel deploy — it's a placeholder until
/// then. If a custom domain gets attached later, this is the only place
/// that needs to change.
const String kPulpitFlowWebUrl = 'https://pulpitflow.vercel.app';

/// Builds the shareable "connect a screen" link for a given session code.
String buildProjectionJoinLink(String code) =>
    '$kPulpitFlowWebUrl/projection?code=$code';
