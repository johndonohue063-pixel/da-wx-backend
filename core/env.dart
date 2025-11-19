const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://da-wx-backend.onrender.com'
);

Uri api(String path, [Map<String,String>? q]) {
  final base = Uri.parse(kApiBase);
  return base.replace(path: path, queryParameters: q);
}
