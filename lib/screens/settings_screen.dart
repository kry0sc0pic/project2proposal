import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import '../constants.dart' as app_colors;
import 'package:get_storage/get_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/extensions.dart';

enum CitationStyle {
  mla,
  apa,
  harvard,
}

enum AIProvider {
  openai,
  ollama,
}

enum GenerationMode {
  sequential,
  parallel,
}

// Helper to check if platform supports Ollama
bool get _platformSupportsOllama {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final TextEditingController _serpAPIController = TextEditingController();
  final TextEditingController _browserlessAPIController = TextEditingController();
  final TextEditingController _openAIController = TextEditingController();
  final GetStorage storage = GetStorage();
  late CitationStyle _selectedStyle;
  late AIProvider _selectedAIProvider;
  late GenerationMode _generationMode;
  bool _enableReferences = false;
  bool _enableBudget = false;

  void _saveSettings() async {
    await storage.write('SERP_API_KEY', _serpAPIController.text);
    await storage.write('BROWSERLESS_API_KEY', _browserlessAPIController.text);
    await storage.write('OPENAI_API_KEY', _openAIController.text);
    await storage.write('CITATION_STYLE', _selectedStyle.name);
    await storage.write('AI_PROVIDER', _selectedAIProvider.name);
    await storage.write('ENABLE_REFERENCES', _enableReferences);
    await storage.write('ENABLE_BUDGET', _enableBudget);
    await storage.write('GENERATION_MODE', _generationMode.name);
  }

  @override
  void initState() {
    super.initState();
    _serpAPIController.text = storage.read('SERP_API_KEY') ?? '';
    _browserlessAPIController.text = storage.read('BROWSERLESS_API_KEY') ?? '';
    _openAIController.text = storage.read('OPENAI_API_KEY') ?? '';
    _enableReferences = storage.read('ENABLE_REFERENCES') ?? false;
    _enableBudget = storage.read('ENABLE_BUDGET') ?? false;
    _selectedStyle = CitationStyle.values.firstWhere(
      (style) => style.name == (storage.read('CITATION_STYLE') ?? 'apa'),
      orElse: () => CitationStyle.apa,
    );
    if (!_platformSupportsOllama) {
      _selectedAIProvider = AIProvider.openai;
      storage.write('AI_PROVIDER', 'openai');
    } else {
      _selectedAIProvider = AIProvider.values.firstWhere(
        (provider) => provider.name == (storage.read('AI_PROVIDER') ?? 'openai'),
        orElse: () => AIProvider.openai,
      );
    }
    _generationMode = GenerationMode.values.firstWhere(
      (mode) => mode.name == (storage.read('GENERATION_MODE') ?? 'sequential'),
      orElse: () => GenerationMode.sequential,
    );

    _serpAPIController.addListener(_saveSettings);
    _browserlessAPIController.addListener(_saveSettings);
    _openAIController.addListener(_saveSettings);
  }

  @override
  void dispose() {
    _serpAPIController.removeListener(_saveSettings);
    _browserlessAPIController.removeListener(_saveSettings);
    _openAIController.removeListener(_saveSettings);
    _serpAPIController.dispose();
    _browserlessAPIController.dispose();
    _openAIController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: app_colors.background,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
               SizedBox.shrink(),
                // Text(
                //   'Settings',
                //   style: app_colors.martianMonoTextStyle.copyWith(
                //     fontSize: 20,
                //     fontWeight: FontWeight.bold,
                //     color: app_colors.primary,
                //   ),
                // ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Proposal Sections',
                      style: app_colors.martianMonoTextStyle.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: app_colors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: Text(
                        'Enable References',
                        style: app_colors.martianMonoTextStyle,
                      ),
                      value: _enableReferences,
                      activeColor: app_colors.primary,
                      onChanged: (bool value) {
                        setState(() {
                          _enableReferences = value;
                          _saveSettings();
                        });
                      },
                    ),
                    if (_enableReferences)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: TextField(
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
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'How do I get a SERP API key?',
                          style: app_colors.martianMonoTextStyle.copyWith(
                            fontSize: 12,
                            color: app_colors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ).paddingLeft(16).asButton(
                          onTap: () => launchUrl(Uri.parse('https://serpapi.com/manage-api-key')),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Citation Style',
                                style: app_colors.martianMonoTextStyle.copyWith(
                                  color: app_colors.primary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<CitationStyle>(
                                value: _selectedStyle,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: app_colors.neutral),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: app_colors.neutral),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: app_colors.primary),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                ),
                                style: app_colors.martianMonoTextStyle.copyWith(
                                  color: app_colors.primary,
                                ),
                                dropdownColor: app_colors.background,
                                items: [
                                  DropdownMenuItem(
                                    value: CitationStyle.apa,
                                    child: Text(
                                      'APA',
                                      style: app_colors.martianMonoTextStyle,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: CitationStyle.mla,
                                    child: Text(
                                      'MLA',
                                      style: app_colors.martianMonoTextStyle,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: CitationStyle.harvard,
                                    child: Text(
                                      'Harvard',
                                      style: app_colors.martianMonoTextStyle,
                                    ),
                                  ),
                                ],
                                onChanged: (CitationStyle? value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedStyle = value;
                                      _saveSettings();
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: Text(
                        'Enable Budget',
                        style: app_colors.martianMonoTextStyle,
                      ),
                      value: _enableBudget,
                      activeColor: app_colors.primary,
                      onChanged: (bool value) {
                        setState(() {
                          _enableBudget = value;
                          _saveSettings();
                        });
                      },
                    ),
                    if (_enableBudget)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: TextField(
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
                    ),
                    if (_enableBudget)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'How do I get a Browserless API key?',
                          style: app_colors.martianMonoTextStyle.copyWith(
                            fontSize: 12,
                            color: app_colors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ).paddingLeft(16).asButton(
                          onTap: () => launchUrl(Uri.parse('https://cloud.browserless.io/account/api-key')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'AI Provider',
                      style: app_colors.martianMonoTextStyle.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: app_colors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_platformSupportsOllama)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Using OpenAI for this platform',
                          style: app_colors.martianMonoTextStyle.copyWith(
                            color: app_colors.primary,
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
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
                                  _saveSettings();
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
                          const SizedBox(width: 24),
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
                                  _saveSettings();
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
                        ],
                      ),
                    if (_selectedAIProvider == AIProvider.openai)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                          const SizedBox(height: 4),
                          Text(
                            'How do I get an OpenAI API key?',
                            style: app_colors.martianMonoTextStyle.copyWith(
                              fontSize: 12,
                              color: app_colors.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ).asButton(
                            onTap: () => launchUrl(Uri.parse('https://platform.openai.com/api-keys')),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_platformSupportsOllama) ...[
                      Text(
                        'Experimental Features',
                        style: app_colors.martianMonoTextStyle.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: app_colors.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: Row(
                          children: [
                            Text(
                              'Parallel Generation (Ollama)',
                              style: app_colors.martianMonoTextStyle,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: app_colors.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Experimental',
                                style: app_colors.martianMonoTextStyle.copyWith(
                                  fontSize: 10,
                                  color: app_colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          'Generate multiple sections in parallel when using Ollama. May be unstable. OpenAI always uses parallel generation.',
                          style: app_colors.martianMonoTextStyle.copyWith(
                            fontSize: 12,
                            color: app_colors.neutral,
                          ),
                        ),
                       
                        value: _generationMode == GenerationMode.parallel,
                        activeColor: app_colors.primary,
                        onChanged: (bool value) {
                          setState(() {
                            _generationMode = value ? GenerationMode.parallel : GenerationMode.sequential;
                            _saveSettings();
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}