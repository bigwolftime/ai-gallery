import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/glass.dart';

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
      extendBodyBehindAppBar: true,
      appBar: GlassNavigationBar(title: widget.title),
      body: FutureBuilder<String>(
          future: content,
          builder: (context, snapshot) => snapshot.hasData
              ? SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      20,
                      MediaQuery.paddingOf(context).top +
                          GlassNavigationBar.height +
                          20,
                      20,
                      MediaQuery.paddingOf(context).bottom + 20),
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
