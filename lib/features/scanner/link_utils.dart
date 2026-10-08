/// Returns a launchable web [Uri] when [text] is a single http(s) link
/// (a bare "www." address is treated as https), otherwise null.
Uri? linkUri(String text) {
  final value = text.trim();
  if (value.isEmpty || value.contains(RegExp(r'\s'))) return null;
  final withScheme = value.toLowerCase().startsWith('www.')
      ? 'https://$value'
      : value;
  final uri = Uri.tryParse(withScheme);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}
