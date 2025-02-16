import 'package:flutter/material.dart';
import '../constants.dart' as app_colors;
import 'package:get_storage/get_storage.dart';

enum CitationStyle {
  mla,
  apa,
  harvard,
}

enum AIProvider {
  openai,
  ollama,
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _serpAPIController = TextEditingController();
  final TextEditingController _browserlessAPIController = TextEditingController();
  final TextEditingController _openAIController = TextEditingController();
  final GetStorage storage = GetStorage();
  late CitationStyle _selectedStyle;
  late AIProvider _selectedAIProvider;

  @override
  void initState() {
    super.initState();
    _serpAPIController.text = storage.read('SERP_API_KEY') ?? '';
    _browserlessAPIController.text = storage.read('BROWSERLESS_API_KEY') ?? '';
    _openAIController.text = storage.read('OPENAI_API_KEY') ?? '';
    _selectedStyle = CitationStyle.values.firstWhere(
      (style) => style.name == (storage.read('CITATION_STYLE') ?? 'apa'),
      orElse: () => CitationStyle.apa,
    );
    _selectedAIProvider = AIProvider.values.firstWhere(
      (provider) => provider.name == (storage.read('AI_PROVIDER') ?? 'ollama'),
      orElse: () => AIProvider.ollama,
    );
  }

  @override
  void dispose() {
    _serpAPIController.dispose();
    _browserlessAPIController.dispose();
    _openAIController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'API Keys',
              style: app_colors.martianMonoTextStyle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: app_colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _serpAPIController,
              style: app_colors.martianMonoTextStyle,
              decoration: InputDecoration(
                labelText: 'Serp API Key',
                hintText: 'Enter your Serp API key',
                labelStyle: app_colors.martianMonoTextStyle.copyWith(
                  color: app_colors.primary,
                ),
              ),
              obscureText: false,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _browserlessAPIController,
              style: app_colors.martianMonoTextStyle,
              decoration: InputDecoration(
                labelText: 'Browserless API Key',
                hintText: 'Enter your Browserless API key',
                labelStyle: app_colors.martianMonoTextStyle.copyWith(
                  color: app_colors.primary,
                ),
              ),
              obscureText: false,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _openAIController,
              style: app_colors.martianMonoTextStyle,
              decoration: InputDecoration(
                labelText: 'OpenAI API Key',
                hintText: 'Enter your OpenAI API key',
                labelStyle: app_colors.martianMonoTextStyle.copyWith(
                  color: app_colors.primary,
                ),
              ),
              obscureText: false,
            ),
            const SizedBox(height: 24),
            Text(
              'AI Provider',
              style: app_colors.martianMonoTextStyle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: app_colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Radio<AIProvider>(
                  value: AIProvider.ollama,
                  groupValue: _selectedAIProvider,
                  fillColor: MaterialStateProperty.resolveWith(
                    (states) => states.contains(MaterialState.selected)
                        ? app_colors.primary
                        : app_colors.neutral,
                  ),
                  onChanged: (AIProvider? value) {
                    if (value != null) {
                      setState(() {
                        _selectedAIProvider = value;
                      });
                    }
                  },
                ),
                Text(
                  'Ollama',
                  style: app_colors.martianMonoTextStyle.copyWith(
                    color: _selectedAIProvider == AIProvider.ollama 
                        ? app_colors.primary 
                        : app_colors.neutral,
                  ),
                ),
                const SizedBox(width: 24),
                Radio<AIProvider>(
                  value: AIProvider.openai,
                  groupValue: _selectedAIProvider,
                  fillColor: MaterialStateProperty.resolveWith(
                    (states) => states.contains(MaterialState.selected)
                        ? app_colors.primary
                        : app_colors.neutral,
                  ),
                  onChanged: (AIProvider? value) {
                    if (value != null) {
                      setState(() {
                        _selectedAIProvider = value;
                      });
                    }
                  },
                ),
                Text(
                  'OpenAI',
                  style: app_colors.martianMonoTextStyle.copyWith(
                    color: _selectedAIProvider == AIProvider.openai 
                        ? app_colors.primary 
                        : app_colors.neutral,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Citation Style',
              style: app_colors.martianMonoTextStyle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: app_colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Radio<CitationStyle>(
                      value: CitationStyle.apa,
                      groupValue: _selectedStyle,
                      fillColor: MaterialStateProperty.resolveWith(
                        (states) => states.contains(MaterialState.selected)
                            ? app_colors.primary
                            : app_colors.neutral,
                      ),
                      onChanged: (CitationStyle? value) {
                        if (value != null) {
                          setState(() {
                            _selectedStyle = value;
                          });
                        }
                      },
                    ),
                    Text(
                      'APA',
                      style: app_colors.martianMonoTextStyle.copyWith(
                        color: _selectedStyle == CitationStyle.apa 
                            ? app_colors.primary 
                            : app_colors.neutral,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Radio<CitationStyle>(
                      value: CitationStyle.mla,
                      groupValue: _selectedStyle,
                      fillColor: MaterialStateProperty.resolveWith(
                        (states) => states.contains(MaterialState.selected)
                            ? app_colors.primary
                            : app_colors.neutral,
                      ),
                      onChanged: (CitationStyle? value) {
                        if (value != null) {
                          setState(() {
                            _selectedStyle = value;
                          });
                        }
                      },
                    ),
                    Text(
                      'MLA',
                      style: app_colors.martianMonoTextStyle.copyWith(
                        color: _selectedStyle == CitationStyle.mla 
                            ? app_colors.primary 
                            : app_colors.neutral,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Radio<CitationStyle>(
                      value: CitationStyle.harvard,
                      groupValue: _selectedStyle,
                      fillColor: MaterialStateProperty.resolveWith(
                        (states) => states.contains(MaterialState.selected)
                            ? app_colors.primary
                            : app_colors.neutral,
                      ),
                      onChanged: (CitationStyle? value) {
                        if (value != null) {
                          setState(() {
                            _selectedStyle = value;
                          });
                        }
                      },
                    ),
                    Text(
                      'Harvard',
                      style: app_colors.martianMonoTextStyle.copyWith(
                        color: _selectedStyle == CitationStyle.harvard 
                            ? app_colors.primary 
                            : app_colors.neutral,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Center(
              child: SizedBox(
                width: 200,
                child: ElevatedButton(
                  onPressed: () async {
                    await storage.write('SERP_API_KEY', _serpAPIController.text);
                    await storage.write('BROWSERLESS_API_KEY', _browserlessAPIController.text);
                    await storage.write('OPENAI_API_KEY', _openAIController.text);
                    await storage.write('CITATION_STYLE', _selectedStyle.name);
                    await storage.write('AI_PROVIDER', _selectedAIProvider.name);
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}