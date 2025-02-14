import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_storage/get_storage.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../constants.dart' as app_colors;
import '../models/proposal_details.dart';
import 'package:process_run/shell.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'dart:async';
import 'package:htmltopdfwidgets/htmltopdfwidgets.dart' as mdpdf;

class GenerationStep {
  final String title;
  final Future<void> Function() execute;
  String? feedback;
  bool requiresUserAction;
  String? userActionMessage;
  DateTime? startTime;
  Duration? duration;

  GenerationStep({
    required this.title,
    required this.execute,
    this.feedback,
    this.requiresUserAction = false,
    this.userActionMessage,
  });

  String get durationText {
    if (startTime == null) return '';
    final duration = this.duration ?? DateTime.now().difference(startTime!);
    return '${duration.inSeconds}s';
  }
}

class ProposalGenerationScreen extends StatefulWidget {
  final ProposalDetails proposalDetails;
  
  const ProposalGenerationScreen({
    super.key,
    required this.proposalDetails,
  });

  @override
  State<ProposalGenerationScreen> createState() => _ProposalGenerationScreenState();
}

class _ProposalGenerationScreenState extends State<ProposalGenerationScreen> {
  int _currentStep = 0;
  List<String> _stepErrors = [];
  bool _isProcessing = false;
  bool _waitingForUser = false;
  final Map<String,dynamic> proposalData = {
    'title': '',
    'abstract': '',
    'origin': '',
    'researchProblem': '',
    'hypothesis': '',
    'objectives': '',
    'methodology': '',
    'studyEndPoints': '',
    'budget': [],
    'timeline': '',
    'references': [],
  };
  final OllamaClient ollamaClient = OllamaClient();
  late final List<GenerationStep> steps;
  Set<int> _collapsedSteps = {};  // Add this to track collapsed states
  Timer? _durationTimer;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _initializeSteps();
    _startGeneration();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  void _initializeSteps() {
    steps = [
      GenerationStep(
        title: 'Installing Ollama',
        userActionMessage: 'Please allow system permissions when prompted',
        execute: () async {
          var ollamaExec = whichSync('ollama');
          if(ollamaExec != null) {
            final shell = Shell();
            try {
              shell.run('ollama serve',);
            } catch (e) {
              print(e);
            }
            await Future.delayed(Duration(seconds: 3),);
            setState(() {
            steps[0].feedback = 'Started Ollama';
          });
            
          } else {
            final Directory tempDir = await getTemporaryDirectory();
          if(Platform.isWindows) {
            final shell = Shell(workingDirectory: tempDir.path);
            print('Downloading Ollama in ${tempDir.path}');
            setState(() {
              steps[0].feedback = 'Downloading Ollama...';
            });
            await shell.run("powershell -c \"Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile 'OllamaSetup.exe'\"");
            setState(() {
              steps[0].feedback = 'Downloaded Ollama.\nRunning Ollama Setup';
            });
            await shell.run('OllamaSetup.exe');

          } else if(Platform.isLinux) {
            final shell = Shell(workingDirectory: '~');
            await shell.run('curl -fsSL https://ollama.com/install.sh | sh');
          } else if(Platform.isMacOS) {
            final shell = Shell(workingDirectory: tempDir.path);
            await shell.run('wget -o Ollama-darwin.zip https://ollama.com/download/Ollama-darwin.zip');
            await shell.run('unzip Ollama-darwin.zip');
            await shell.run('mv Ollama-darwin/Ollama.app /Applications');
          }
          setState(() {
            steps[0].feedback = 'Started Ollama';
          });
          try {
            Shell().run('ollama serve',);
          } catch (e) {
            print(e);
          }
          await Future.delayed(Duration(seconds: 3),);
          }
          
          
        },
      ),
      GenerationStep(
        title: 'Downloading Model',
        execute: () async {
          final res = await ollamaClient.listModels();
          print(res.models);
          final Model model = (res.models ?? []).firstWhere((element) => element.model == 'phi4:14b',orElse: () => Model(model: 'this-model-doesnt-exist'),);
          if (model.model == 'this-model-doesnt-exist') {
            print('downloading model');
            final dlStream = ollamaClient.pullModelStream(request: PullModelRequest(model: 'phi4:14b'));
            await for (final res in dlStream) {
              print("status: ${res.status} | c: ${res.completed} | t: ${res.total}");
              
                switch(res.status){
                  case PullModelStatus.pullingManifest:
                    setState(() {
                      steps[1].feedback = 'Pulling Manifest';
                    });
                    break;
                  
                  case PullModelStatus.downloadingDigestname:
                    setState(() {
                      steps[1].feedback = 'Downloading Digestname';
                    });
                    break;
                  
                  case PullModelStatus.verifyingSha256Digest:
                    setState(() {
                      steps[1].feedback = 'Verifying Sha256 Digest';
                    });
                    break;
                  
                  case PullModelStatus.writingManifest:
                    setState(() {
                      steps[1].feedback = 'Writing Manifest';
                    });
                    break;
                  
                  case PullModelStatus.removingAnyUnusedLayers:
                    setState(() {
                      steps[1].feedback = 'Removing Any Unused Layers';
                    });
                    break;
                  
                  case PullModelStatus.success:
                    setState(() {
                      steps[1].feedback = 'Model downloaded';
                    });
                    break;

                  case null:
                    if(res.completed != null && res.total != null) {
                      setState(() {
                        steps[1].feedback = 'Downloading Model: ${((res.completed! / res.total!) * 100).toStringAsFixed(2)}%';
                      });
                    }
                    break;
                }
              }
              
            
            
          } else {
            print('model already downloaded');
            steps[1].feedback = 'Model already downloaded';
          }
        },
      ),
      GenerationStep(
        title: 'Loading Model',
        execute: () async {
          ollamaClient.generateCompletion(request: GenerateCompletionRequest(model: 'phi4:14b', prompt: 'what is the first whole number. only reply with the number'));
          setState(() {
            steps[2].feedback = 'Model loaded';
          });
        },
      ),
   
     
      GenerationStep(
        title: 'Title',
        execute: () async {
          print('Generating title');
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt: 'Write a one-line title based on the description provided. Only respond with the title and nothing else.: ${widget.proposalDetails.projectDescription}'));
          await for (final res in titleStream) {
            proposalData['title'] += res.response ?? '';
            setState(() {
              steps[3].feedback = proposalData['title'];
            });
          }
          if(proposalData['title'].contains('---')){
            proposalData['title'] = proposalData['title'].split('---')[0];
            setState(() {
              steps[3].feedback = proposalData['title'];
            });
          }
        }
      ),
      GenerationStep(
        title: 'Abstract',
        execute: () async {
          print('Generating abstract');
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt: 'Write a 200-word abstract based on the description provided. Only respond with the abstract and nothing else.: ${widget.proposalDetails.projectDescription}'));
          await for (final res in titleStream) {
            proposalData['abstract'] += res.response ?? '';
            setState(() {
              steps[4].feedback = proposalData['abstract'];
            });
          }
        }
      ),
      GenerationStep(
        title: 'Motivation',
        execute: () async {
          print('Generating motivation');
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt: 'Write a brief motivation for the project in 2-3 sentences based on the description provided. Only respond with the motivation and nothing else. : ${widget.proposalDetails.projectDescription}'));
          await for (final res in titleStream) {
            proposalData['origin'] += res.response ?? '';
            setState(() {
              steps[5].feedback = proposalData['origin'];
            });
          }
        }
      ),
      GenerationStep(
        title: 'Problem Statement',
        execute: () async {
          print('Generating Problem Statement');
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt: 'Write a problem statement in 1-2 sentences based on the description provided. Only respond with the problem statement and nothing else. : ${widget.proposalDetails.projectDescription}'));
          await for (final res in titleStream) {
            proposalData['researchProblem'] += res.response ?? '';
            setState(() {
              steps[6].feedback = proposalData['researchProblem'];
            });
          }
        }
      ),
       GenerationStep(
        title: 'Research Hypothesis',
        execute: () async {
          print('Generating Research Hypothesis');
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt: 'Write a 1-2 line hypothesis of the result based on the description provided. Only respond with the hypothesis and nothing else. : ${widget.proposalDetails.projectDescription}'));
          await for (final res in titleStream) {
            proposalData['hypothesis'] += res.response ?? '';
            setState(() {
              steps[7].feedback = proposalData['hypothesis'];
            });
          }
        }
      ),
      GenerationStep(
        title: 'Objectives',
        execute: () async {
          print('Generating Objectives');
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt: 'Write a concise list of objectives (not more than 5) for the project each on a new line based on the description provided. Only respond with the numbered objectives and nothing else: ${widget.proposalDetails.projectDescription}'));
          await for (final res in titleStream) {
            proposalData['objectives'] += res.response ?? '';
            setState(() {
              steps[8].feedback = proposalData['objectives'];
            });
          }
        }
      ),
      //TODO: integrate diagram generation at some point
       GenerationStep(
        title: 'Methodology',
        execute: () async {
          print('Generating methodology');
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt: 'Write a detailed methodology for the project based on the description provided. Use multiple paragraphs as needed. Only respond with the methodology and nothing else.: ${widget.proposalDetails.projectDescription}'));
          await for (final res in titleStream) {
            proposalData['methodology'] += res.response ?? '';
            setState(() {
              steps[9].feedback = proposalData['methodology'];
            });
            
          }
          proposalData['methodology'] = proposalData['methodology'].replaceAll('### Methodology', '');
          setState(() {
              steps[9].feedback = proposalData['methodology'];
            });
        }
      ),
       GenerationStep(
        title: 'Outcomes',
        execute: () async {
          print('Generating outcomes');
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt:  'Write the final goal for the project in 1-2 sentences at the most based on the description provided. Only respond with the final goal and nothing else.: ${widget.proposalDetails.projectDescription}'));
          await for (final res in titleStream) {
            proposalData['studyEndPoints'] += res.response ?? '';
            setState(() {
              steps[10].feedback = proposalData['studyEndPoints'];
            });
          }
        }
      ),
      
      GenerationStep(
        title: 'Timeline',
        execute: () async {
          print('Generating timeline');
          final date = DateTime.now();
          
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt:  'Write a timeline for the project as a table with the task and the deadline for each task. Today is ${date.day}/${date.month}/${date.year}. Only respond with the table in mardown format and nothing else: ${widget.proposalDetails.projectDescription}'));
          await for (final res in titleStream) {
            proposalData['timeline'] += res.response ?? '';
            setState(() {
              steps[11].feedback = proposalData['timeline'];
            });
          }
          proposalData['timeline'] = proposalData['timeline'].replaceAll('```markdown','').split('```')[0];
          
          setState(() {
              steps[11].feedback = proposalData['timeline'];
          });
        }
      ),
      GenerationStep(
        title: 'Finding References',
        execute: () async {
          // Your proposal generation code here
          print('Finding references');
                    final GetStorage storage = GetStorage();
          final String? serpAPIKey = storage.read('SERP_API_KEY');
;
          
          print("SERP KEY: $serpAPIKey");
          if(serpAPIKey == null) {
            setState(() {
              steps[12].feedback = 'Skipping references as SERP API Key is not set';
            });
            return;
          }
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt:  'Write a query term to find relevant patents in the google patents search syntax for the given methodolgy and abstract. Don\'t make the search the term very specific & keep it general to find results. Only respond with the query term in the search syntax and nothing else: \nAbstract: ${proposalData['abstract']}\nMethodology: ${proposalData['methodology']}'));
          String searchQuery = '';
          await for (final res in titleStream) {
            searchQuery += res.response ?? '';
            setState(() {
              steps[12].feedback = "Search Term: $searchQuery\n";
            });
          }
          searchQuery = searchQuery.replaceAll('`', '');
          setState(() {
            steps[12].feedback = 'Search Term: "$searchQuery"\n';
          });
          if(searchQuery.contains('---')){
            searchQuery = searchQuery.split('---')[0];
          }
          setState(() {
            steps[12].feedback = 'Search Term: "$searchQuery"\n';
          });
          // load api key
          

          // search for references
          final Dio dio = Dio();
          final queryURL = "https://serpapi.com/search.json";
          final Response response = await dio.get(queryURL, queryParameters: {
            'api_key': serpAPIKey,
            'engine': 'google_patents',
            'q': searchQuery,
            'scholar': true,
            'page': 1,
            'dups': 'language',
            'num': 10,
          });

          final data = response.data as Map<String, dynamic>;
          if (data['organic_results'] == null) {
            setState(() {
              steps[12].feedback = (steps[12].feedback ?? '') + '\nSearch didn\'t return any results. Proceeding..';
            });
            return;
          }
          final results = data['organic_results'] as List<dynamic>;
          setState(() {
            steps[12].feedback = (steps[12].feedback ?? '') + '\nSearch returned ${results.length} results';
          });
          final resultsFiltered = [];
          for (final element in results) {
            resultsFiltered.add({
              'title': element['title'],
              'abstract': element['snippet'],
              'link': element.containsKey('patent_link') ? element['patent_link'] : element['scholar_link'],
              'citation': null,
              'citation_style': null,
            });
          }
          print(
            'getting citations'
          );
          for (final result in resultsFiltered) {
            if (result['link'] == null) {
              continue;
            }
            final Response cite_response = await dio.get("https://api.citeas.org/product/${result['link']}",queryParameters: {
              'email': 'project2proposal@krishaay.dev',
            });
            final cite_data = cite_response.data as Map<String, dynamic>;
            final citations = cite_data['citations'] as List<dynamic>;
            final cite_style = storage.read('CITATION_STYLE').toString().toLowerCase() == 'apa' ? 'apa' : 'modern-language-association-with-url';
            for(final citation in citations) {
              if(citation['style_shortname'] == cite_style) {
                result['citation'] = citation['citation'];
                result['citation_style'] = citation['style'];
                break;
              }
            } 
            if (result['citation'] == null) {
              result['citation'] = citations[0]['citation'];
              result['citation_style'] = citations[0]['style'];
            }
            
          }

          proposalData['references'] = resultsFiltered;
          setState(() {
            steps[13].feedback = (steps[14].feedback ?? '') + resultsFiltered.map((e) => e['citation']).join('\n\n\n');
          });
        },
      ),
      GenerationStep(
        title: 'Saving PDF File',
        execute: () async {
          final Directory? downloadsDirectory = await getDownloadsDirectory();
          final String markdownContent = 
          '''
# Title
${proposalData['title']}
# Abstract
${proposalData['abstract']}
# Origin
${proposalData['origin']}
# Problem Statement
${proposalData['researchProblem']}
# Hypothesis
${proposalData['hypothesis']}
# Objectives
${proposalData['objectives']}
# Methodology
${proposalData['methodology']}
# Study End Point
${proposalData['studyEndPoints']}
# Budget
yay
# Timeline
${proposalData['timeline']}
# References
${proposalData['references'].map((e) => e['citation']).join('\n')}
''';      
          final baseFont = await rootBundle.load("assets/DMSans-Regular.ttf"); 
          final boldFont = await rootBundle.load("assets/DMSans-Bold.ttf");
          final italicFont = await rootBundle.load("assets/DMSans-Italic.ttf");
          final boldItalicFont = await rootBundle.load("assets/DMSans-BoldItalic.ttf");
          final mdpdf.ThemeData t = mdpdf.ThemeData.withFont(
            base: mdpdf.Font.ttf(baseFont),
            bold: mdpdf.Font.ttf(boldFont),
            boldItalic: mdpdf.Font.ttf(boldItalicFont),
            italic: mdpdf.Font.ttf(italicFont),


        
          );
          final List<mdpdf.Widget> mdWidgets = await mdpdf.HTMLToPdf().convertMarkdown(markdownContent);
          final markdownPDF = mdpdf.Document(theme: t,author: "Project2Proposal",title: "Proposal",);
          markdownPDF.addPage(mdpdf.MultiPage(pageFormat: mdpdf.PdfPageFormat.a4,build: (context) => mdWidgets));
          final pdfPath = '${downloadsDirectory!.path}/proposal.pdf';
          File(pdfPath).writeAsBytes(await markdownPDF.save());
          steps[13].feedback = 'Saved to: $pdfPath';
        },
      ),
      GenerationStep(
        title: 'Proposal Complete',
        execute: () async {
          final Directory? downloadsDirectory = await getDownloadsDirectory();
          final pdfPath = '${downloadsDirectory!.path}/proposal.pdf';
          await OpenFile.open(pdfPath);
          steps[14].feedback = 'Opened PDF';
        },
      ),
    ];
    
    _stepErrors = List.filled(steps.length, '');
  }

  void _cancelGeneration() {
    setState(() {
      _isCancelled = true;
      _isProcessing = false;
      _durationTimer?.cancel();
      _stepErrors[_currentStep] = 'Generation cancelled';
    });
  }

  Future<void> _startGeneration() async {
    if (_isProcessing) return;
    _isProcessing = true;
    _isCancelled = false;

    for (int i = 0; i < steps.length - 1; i++) {
      if (!mounted || _isCancelled) return;
      
      setState(() {
        _currentStep = i;
        _waitingForUser = false;
        steps[i].startTime = DateTime.now();
      });

      // Start timer to update duration
      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });

      try {
        if (steps[i].requiresUserAction) {
          setState(() {
            _waitingForUser = true;
          });
          return;
        }
        
        await steps[i].execute();
        
        setState(() {
          steps[i].duration = DateTime.now().difference(steps[i].startTime!);
          if (i < steps.length - 2) {
            _currentStep = i + 1;
          }
        });
      } catch (e) {
        setState(() {
          _stepErrors[i] = e.toString();
        });
        _isProcessing = false;
        return;
      }
    }

    _durationTimer?.cancel();
    setState(() {
      _currentStep = steps.length - 1;
    });
    _isProcessing = false;
  }

  void continueExecution() {
    if (_waitingForUser) {
      _waitingForUser = false;
      steps[_currentStep].execute().then((_) {
        setState(() {
          // Refresh to show feedback
        });
        _startGeneration(); // Continue with next steps
      }).catchError((e) {
        setState(() {
          _stepErrors[_currentStep] = e.toString();
        });
      });
    }
  }

  StepState _getStepState(int step) {
    if (_stepErrors[step].isNotEmpty) {
      return StepState.error;
    }
    if (step < _currentStep || (step == steps.length - 1 && _currentStep == steps.length - 1)) {
      return StepState.complete;
    }
    if (step == _currentStep) {
      return StepState.editing;
    }
    return StepState.indexed;
  }

  void _toggleStepCollapse(int index) {
    setState(() {
      if (_collapsedSteps.contains(index)) {
        _collapsedSteps.remove(index);
      } else {
        _collapsedSteps.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Building Proposal'),
        automaticallyImplyLeading: false,
        actions: [
          if (_isProcessing)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel Generation',
              onPressed: _cancelGeneration,
            ),
        ],
      ),
      
      body: Column(
        children: [
          Expanded(
            child: Stepper(
              
              connectorThickness: 2,
              connectorColor: WidgetStateColor.fromMap({
                // WidgetState.disabled: app_colors.neutral,
                // WidgetState.selected: app_colors.primary,
                WidgetState.disabled: Colors.transparent,
                WidgetState.selected: Colors.transparent,
              }),
              stepIconBuilder: (stepIndex, stepState) {
                if(stepState == StepState.complete) {
                  return const Icon(Icons.check, size: 14,);
                } 
                
                if (stepState == StepState.editing) {
                  return SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: app_colors.primary,
                      strokeWidth: 2,
                    ),
                  );
                }

               


              },
              currentStep: _currentStep,
              controlsBuilder: (context, details) => Container(),
              steps: List.generate(
                steps.length,
                (index) => Step(
                  title: InkWell(
                    onTap: () => _toggleStepCollapse(index),
                    child: Row(
                      children: [
                        Text(
                          steps[index].title,
                          style: app_colors.martianMonoTextStyle,
                        ),
                        const SizedBox(width: 8),
                        if (steps[index].startTime != null)
                          Text(
                            steps[index].durationText,
                            style: app_colors.martianMonoTextStyle.copyWith(
                              fontSize: 12,
                              color: app_colors.primary,
                            ),
                          ),
                        const SizedBox(width: 8),
                        Icon(
                          _collapsedSteps.contains(index) 
                              ? Icons.expand_more 
                              : Icons.expand_less,
                          size: 20,
                          color: app_colors.primary,
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  subtitle: _collapsedSteps.contains(index)
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_stepErrors[index].isNotEmpty)
                              Text(
                                _stepErrors[index],
                                style: app_colors.martianMonoTextStyle.copyWith(
                                  color: Colors.red,
                                ),
                              ),
                            if (steps[index].feedback != null)
                              Text(
                                steps[index].feedback!,
                                style: app_colors.martianMonoTextStyle.copyWith(
                                  color: app_colors.neutral,
                                ),
                              ),
                            if (_waitingForUser && 
                                index == _currentStep && 
                                steps[index].userActionMessage != null)
                              Column(
                                children: [
                                  Text(
                                    steps[index].userActionMessage!,
                                    style: app_colors.martianMonoTextStyle.copyWith(
                                      color: app_colors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: continueExecution,
                                    child: const Text('Continue'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                  content: SizedBox(),
                  state: _getStepState(index),
                  stepStyle: StepStyle(
                    color: _getStepState(index) == StepState.error ? Colors.red : _getStepState(index) == StepState.complete ? app_colors.primary : app_colors.neutral,
                  ),
                  
                  isActive: index <= _currentStep,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 