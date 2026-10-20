import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/ios_glass.dart';

/// Legal information is bundled so reading it never requires a network request.
class LegalPage extends StatefulWidget {
  const LegalPage({super.key, required this.title, required this.asset});
  final String title;
  final String asset;
  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  late final Future<String> content = rootBundle.loadString(widget.asset);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AdaptiveNavigationBar(
          platform: Theme.of(context).platform, title: widget.title),
      body: FutureBuilder<String>(
          future: content,
          builder: (context, snapshot) => snapshot.hasData
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(snapshot.data!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.6)))
              : Center(
                  child: snapshot.hasError
                      ? const Text('暂时无法载入，请稍后重试。')
                      : const CircularProgressIndicator())));
}
