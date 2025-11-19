import "package:divergent_alliance/services/nws_client.dart";
Future<void> main() async {
  final w = await NwsClient.windForPoint(lat: 29.7752, lon: -95.3103, hours: 24);
  print("SMOKE Harris TX -> sustained=${w["max_sustained_mph"]} mph, gust=${w["max_gust_mph"]} mph, grid=${w["office"]}/${w["grid"]}");
}