import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:project2proposal/screens/settings_screen.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'constants.dart' as app_colors;
import 'screens/proposal_generation_screen.dart';
import 'models/proposal_details.dart';
// import 'package:appwrite/appwrite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Client client = Client();
  // client.
  //   setProject('67b2c34b0023fa9dbd30')
  //   .setEndpoint('https://project2proposal.krishaay.dev');
  
  final GetStorage storage = GetStorage();
  storage.getKeys();
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://7823527942b2ea9afb0978678fca6e1c@o4508941739098112.ingest.us.sentry.io/4508971879366656';
      // Adds request headers and IP for users,
      // visit: https://docs.sentry.io/platforms/dart/data-management/data-collected/ for more info
      options.sendDefaultPii = true;
    },
    appRunner: () => runApp(
      SentryWidget(
        child: ProposalApp(),
      ),
    ),
  );
  // runApp(const ProposalApp());
}

class ProposalApp extends StatelessWidget {
  const ProposalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proposal Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: app_colors.background,
        appBarTheme: AppBarTheme(
          backgroundColor: app_colors.accent,
          foregroundColor: Colors.white,
          titleTextStyle: app_colors.martianMonoTextStyle.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: app_colors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: app_colors.martianMonoTextStyle,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: app_colors.accent,
          hintStyle: app_colors.martianMonoTextStyle.copyWith(
            color: app_colors.neutral,
          ),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: app_colors.neutral),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: app_colors.neutral),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: app_colors.primary, width: 2),
          ),
        ),
        textTheme: TextTheme(
          bodyLarge: app_colors.martianMonoTextStyle,
          bodyMedium: app_colors.martianMonoTextStyle,
          titleLarge: app_colors.martianMonoTextStyle,
          labelLarge: app_colors.martianMonoTextStyle,
        ),
      ),
      home: const ProjectDetailsScreen(),
    );
  }
}

class ProjectDetailsScreen extends StatefulWidget {
  const ProjectDetailsScreen({super.key});

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen> {
  final TextEditingController _projectDetailsController = TextEditingController();

  @override
  void dispose() {
    _projectDetailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Details'),
        actions: [
          IconButton(
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (context) => const SettingsDialog(),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _projectDetailsController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Enter project details...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  children: [
                    
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 200,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HardwareLinksScreen(
                                projectDetails: _projectDetailsController.text,
                              ),
                            ),
                          );
                        },
                        child: const Text('Next'),
                      ),
                    ),
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

class HardwareLinksScreen extends StatefulWidget {
  final String projectDetails;

  const HardwareLinksScreen({
    super.key,
    required this.projectDetails,
  });

  @override
  State<HardwareLinksScreen> createState() => _HardwareLinksScreenState();
}

class _HardwareLinksScreenState extends State<HardwareLinksScreen> {
  final TextEditingController _hardwareLinksController = TextEditingController();

  @override
  void dispose() {
    _hardwareLinksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Material'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _hardwareLinksController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Paste purchase links (one per line)...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: SizedBox(
                  width: 200,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReviewScreen(
                            projectDetails: widget.projectDetails,
                            hardwareLinks: _hardwareLinksController.text,
                          ),
                        ),
                      );
                    },
                    child: const Text('Next'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReviewScreen extends StatelessWidget {
  final String projectDetails;
  final String hardwareLinks;

  const ReviewScreen({
    super.key,
    required this.projectDetails,
    required this.hardwareLinks,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Details:',
                      style: app_colors.martianMonoTextStyle.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      projectDetails,
                      style: app_colors.martianMonoTextStyle,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Hardware Links:',
                      style: app_colors.martianMonoTextStyle.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hardwareLinks,
                      style: app_colors.martianMonoTextStyle,
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: SizedBox(
                width: 200,
                child: ElevatedButton(
                  onPressed: () {
                    final proposalDetails = ProposalDetails.fromForm(
                      projectDescription: projectDetails,
                      hardwareLinksText: hardwareLinks,
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProposalGenerationScreen(
                          proposalDetails: proposalDetails,
                        ),
                      ),
                    );
                  },
                  child: const Text('Generate Proposal'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
