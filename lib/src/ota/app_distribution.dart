/// Store builds delegate updates to their distributor and make no automatic
/// requests to the direct-download manifest or Shorebird service.
class AppDistribution {
  const AppDistribution({
    this.channel = const String.fromEnvironment('APP_DISTRIBUTION_CHANNEL'),
    this.listingUrl = const String.fromEnvironment('APP_STORE_LISTING_URL'),
  });

  final String channel;
  final String listingUrl;
  bool get managedByStore => channel == 'fdroid' || channel == 'play';
  String get storeName => channel == 'fdroid' ? 'F-Droid' : 'Google Play';
  Uri? get storeUri {
    final value = Uri.tryParse(listingUrl);
    return value?.scheme == 'https' && value!.host.isNotEmpty ? value : null;
  }
}
