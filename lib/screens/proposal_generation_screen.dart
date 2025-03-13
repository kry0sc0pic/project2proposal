import 'dart:io' show Platform, Directory, File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';

import 'package:dart_openai/dart_openai.dart';
import 'package:dio/dio.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project2proposal/screens/settings_screen.dart';
import 'package:sanitize_filename/sanitize_filename.dart';
import '../constants.dart' as app_colors;
import '../models/proposal_details.dart';
import '../utils/prompts.dart';
import 'package:process_run/shell.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'dart:async';

// Helper to check if platform supports Ollama
bool get _platformSupportsOllama {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

// Helper to check if device is mobile
bool get _isMobileDevice {
  if (kIsWeb) {
    // For web, check window width
    return false; // We'll handle this in the build method with MediaQuery
  }
  return Platform.isAndroid || Platform.isIOS;
}

class GenerationStep {
  final String title;
  final Future<void> Function() execute;
  final List<String> dependencies;
  String? feedback;
  bool requiresUserAction;
  String? userActionMessage;
  DateTime? startTime;
  Duration? duration;
  bool isRunning = false;
  bool isComplete = false;

  GenerationStep({
    required this.title,
    required this.execute,
    this.dependencies = const [],
    this.feedback,
    this.requiresUserAction = false,
    this.userActionMessage,
  });

  String get durationText {
    if (startTime == null) return '';
    final duration = this.duration ?? DateTime.now().difference(startTime ?? DateTime.now());
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
    'motivation': '',
    'researchProblem': '',
    'hypothesis': '',
    'objectives': '',
    'methodology': '',
    'studyEndPoints': '',
    'budget': <Map<String,dynamic>> [],
    'timeline': '',
    'references': [],
  };
  final OllamaClient ollamaClient = OllamaClient();
  late final List<GenerationStep> steps;
  Set<int> _collapsedSteps = {};  // Add this to track collapsed states
  Timer? _durationTimer;
  bool _isCancelled = false;
  Set<int> _completedSteps = {};
  Map<String, Completer<void>> _stepCompletions = {};
  Set<String> _runningSteps = {};
  DateTime? _generationStartTime;
  Duration? _totalGenerationTime;

  @override
  void initState() {
    super.initState();
   
    _checkSettings();
    _initializeSteps();
    
    // Initialize collapsed steps based on device type
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCollapsedState();
    });
    
    _startGeneration();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  String citationKey(String style) {
    switch(style) {
      case 'apa':
        return 'APA';
      case 'modern-language-association-with-url':
        return 'MLA';
      case 'harvard':
        return 'harvard1';
      default:
        return 'apa';
    }
  }
final String base_url = 'https://md2pdf.krishaay.dev'; // 
// final String base_url = 'http://localhost:45767';
Future<  Map<String,dynamic>?> getProductData(String link,String bs_key) async {
    final String ep = "https://production-lon.browserless.io/chrome/bql";
    final Dio _dio = Dio();
    final Uri uri = Uri.parse(link);

     String host = uri.host;
    if(host == "") return null;
    if(host.startsWith('www.')){
      host = host.substring(4);
    }
    print(link);
    switch(host){
      
      case "robu.in":
        final Response r = await _dio.post(ep,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          }
        ),
        queryParameters: {
          'humanlike': 'true',
          'token': bs_key,
        },
        data: {
          'variables': null,
          'operationName': 'robuSearch',
          'query': 'mutation robuSearch {\n  goto(\n    url: \"https://robu.in/product/orange-ifr10440-200mah-lifepo4-battery/\"\n    waitUntil: firstContentfulPaint\n  ) {\n    status\n  }\n  productTitle: text(selector: \".product_title\") {\n    text\n  }\n  price: querySelectorAll(selector: \".woocommerce-Price-amount\") {\n    innerText\n  }\n}'
        },
        
        );
        print(r.data);
        print(r.statusCode);
        final Map<String,dynamic> data = (r.data as Map<String,dynamic>)['data'];
        final Map<String,dynamic> productData = {
          'name': data['productTitle']['text'],
          'price': data['price'][1]['innerText'],
        };
        return productData;
      

      case 'amazon.in':
        final Response r = await _dio.post(ep,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          }
        ),
        queryParameters: {
          'humanlike': 'true',
          'token': bs_key,
        },
        data: {
          'variables': null,
          'operationName': 'amazonSearch',
          'query': 'mutation amazonSearch {\n  goto(\n    url: \"$link"\n    waitUntil: firstContentfulPaint\n  ) {\n    status\n  }\n  name: text(selector: \".product-title-word-break\") {\n    text\n  }\n  price: text(selector: \".reinventPricePriceToPayMargin\") {\n    text\n  }\n}'
        },
        
        );
        print(r.data);
        print(r.statusCode);
        final Map<String,dynamic> data = (r.data as Map<String,dynamic>)['data'];
        final Map<String,dynamic> productData = {
          'name': data['name']['text'],
          'price': data['price']['text'],
        };
        return productData;
       default:
        return null;

    }
  }




  Future<String> _generateText(String prompt, {void Function(String)? onToken}) async {
    final GetStorage storage = GetStorage();
    final bool useOpenAI = storage.read('AI_PROVIDER') == 'openai';
    
    if (useOpenAI) {
      return _generateWithOpenAI(prompt, onToken: onToken);
    } else {
      return _generateWithOllama(prompt, onToken: onToken);
    }
  }

  Future<String> _generateWithOpenAI(String prompt, {void Function(String)? onToken}) async {
    final userMessage = OpenAIChatCompletionChoiceMessageModel(
      content: [
        OpenAIChatCompletionChoiceMessageContentItemModel.text(
          prompt,
        ),
      ],
      role: OpenAIChatMessageRole.user,
    );
    final completer = Completer<String>();
    String result = '';
    
    final chatStream = OpenAI.instance.chat.createStream(
      model: "gpt-3.5-turbo",
      messages: [
        userMessage,
      ],
      seed: 423,
    );
    
    chatStream.listen(
      (streamChatCompletion) {
        final content = streamChatCompletion.choices.first.delta.content;
        if (content != null && content.isNotEmpty) {
          if(content.first!.text != null) {
          
            result += content.first!.text ?? '';
          
          if(onToken != null) {
            onToken(result);
          }
           } else {
                  }
        }
      },
      onDone: () {
        completer.complete(result);
      },
      onError: (error) {
        print('Error: $error'); 
        completer.completeError(error);
      },
    );
    
    return completer.future;
  }
  Future<String> _generateWithOllama(String prompt, {void Function(String)? onToken}) async {
    String result = '';
    final stream = ollamaClient.generateCompletionStream(
      request: GenerateCompletionRequest(
        model: 'phi4:14b',
        prompt: prompt,
      ),
    );
    
    await for (final res in stream) {
      result += res.response ?? '';
      if (onToken != null) {
        onToken(result);
      }
    }
    return result;
  }

  // Helper method to get the correct step index
  int getStepIndex(String stepName) {
    return steps.indexWhere((step) => step.title == stepName);
  }

  String _getTotalDuration() {
    if (_totalGenerationTime != null) {
      final minutes = _totalGenerationTime!.inMinutes;
      final seconds = _totalGenerationTime!.inSeconds % 60;
      return '$minutes min $seconds sec';
    }
    
    Duration totalDuration = Duration.zero;
    for (var step in steps) {
      if (step.duration != null) {
        totalDuration += step.duration!;
      }
    }
    
    final minutes = totalDuration.inMinutes;
    final seconds = totalDuration.inSeconds % 60;
    return '$minutes min $seconds sec';
  }

  void _initializeSteps() {
    final GetStorage storage = GetStorage();
    final bool enableReferences = storage.read('ENABLE_REFERENCES') ?? false;
    final bool enableBudget = storage.read('ENABLE_BUDGET') ?? false;
    final bool useOpenAI = !_platformSupportsOllama || storage.read('AI_PROVIDER') == 'openai';
    final String serpAPIKey = storage.read('SERP_API_KEY') ?? '';
    final String browserlessAPIKey = storage.read('BROWSERLESS_API_KEY') ?? '';
    final String openAIKey = storage.read('OPENAI_API_KEY') ?? '';
    
    if(useOpenAI) {
      OpenAI.apiKey = storage.read('OPENAI_API_KEY');
    }
    
    steps = [
      if (!useOpenAI) GenerationStep(
        title: 'Installing Ollama',
        dependencies: [],
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
              steps[getStepIndex('Installing Ollama')].feedback = 'Started Ollama';
            });
            
          } else {
            final Directory tempDir = await getTemporaryDirectory();
          if(Platform.isWindows) {
            final shell = Shell(workingDirectory: tempDir.path);
            final Dio dio = Dio();
            print('Downloading Ollama in ${tempDir.path}');
            setState(() {
              steps[getStepIndex('Installing Ollama')].feedback = 'Downloading Ollama: 0%';
            });
            await dio.downloadUri(Uri.parse('https://ollama.com/download/OllamaSetup.exe'), tempDir.path+'/OllamaSetup.exe',onReceiveProgress: (count, total) => {
              setState(() {
                steps[getStepIndex('Installing Ollama')].feedback = 'Downloading Ollama: ${((count / total) * 100).toStringAsFixed(2)}%';
              })
            },);
            setState(() {
              steps[getStepIndex('Installing Ollama')].feedback = 'Downloaded Ollama.\nRunning Ollama Setup';
            });
            shell.run('${tempDir.path}\\OllamaSetup.exe');
            
          } else if(Platform.isLinux) {
           final Dio dio = Dio();
            print('Downloading Ollama in ${tempDir.path}');
            final shell = Shell(workingDirectory: tempDir.path);
            await dio.downloadUri(Uri.parse('https://ollama.com/install.sh'), tempDir.path+'/ollama.sh',onReceiveProgress: (count, total) => {
              setState(() {
                steps[0].feedback = 'Downloading Ollama: ${((count / total) * 100).toStringAsFixed(2)}%';
              })
            },);
            await shell.run('chmod +x ollama.sh');
            await shell.run('pkexec ./ollama.sh');
            await shell.run('rm ollama.sh');
          } else if(Platform.isMacOS) {
            
            final Dio dio = Dio();
            final Shell shell = Shell(workingDirectory: tempDir.path);
            final ollamaFile = File('/Applications/Ollama.app');
            print(ollamaFile.path);
            if(ollamaFile.existsSync()) {
              setState(() {
                steps[getStepIndex('Installing Ollama')].feedback = 'Ollama.app found but not on path.\nOpening App...';
              });
              try {
                Shell().run('open /Applications/Ollama.app',);
              } catch (e) {
                print(e);
              }
              return;
            }
            

            setState(() {
              steps[getStepIndex('Installing Ollama')].feedback = 'Downloading Ollama: 0%';
            });
            await dio.downloadUri(Uri.parse('https://ollama.com/download/Ollama-darwin.zip'), tempDir.path+'/Ollama-darwin.zip',onReceiveProgress: (count, total) => {
              setState(() {
                steps[getStepIndex('Installing Ollama')].feedback = 'Downloading Ollama: ${((count / total) * 100).toStringAsFixed(2)}%';
              })
            },);
            setState(() {
              steps[getStepIndex('Installing Ollama')].feedback = 'Downloaded Ollama\nExtracting Ollama...';
            });
            await shell.run('unzip Ollama-darwin.zip');
            setState(() {
              steps[getStepIndex('Installing Ollama')].feedback = steps[getStepIndex('Installing Ollama')].feedback! + 'Done.\nCopying to /Applications. Please allow permissions when prompted';
            });
            await shell.run('mv Ollama.app /Applications/Ollama.app');
            await shell.run('rm Ollama-darwin.zip');
            await shell.run('open /Applications/Ollama.app --hide');
          }
          setState(() {
            steps[getStepIndex('Installing Ollama')].feedback = 'Installed Ollama';
          });
          try {
            Shell().run('open /Applications/Ollama.app',);
          } catch (e) {
            print(e);
          }
          await Future.delayed(Duration(seconds: 3),);
          }
          
          
        },
      ),
      if (!useOpenAI) GenerationStep(
        title: 'Downloading Model',
        dependencies: ['Installing Ollama'],
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
                      steps[getStepIndex('Downloading Model')].feedback = 'Pulling Manifest';
                    });
                    break;
                  
                  case PullModelStatus.downloadingDigestname:
                    setState(() {
                      steps[getStepIndex('Downloading Model')].feedback = 'Downloading Digestname';
                    });
                    break;
                  
                  case PullModelStatus.verifyingSha256Digest:
                    setState(() {
                      steps[getStepIndex('Downloading Model')].feedback = 'Verifying Sha256 Digest';
                    });
                    break;
                  
                  case PullModelStatus.writingManifest:
                    setState(() {
                      steps[getStepIndex('Downloading Model')].feedback = 'Writing Manifest';
                    });
                    break;
                  
                  case PullModelStatus.removingAnyUnusedLayers:
                    setState(() {
                      steps[getStepIndex('Downloading Model')].feedback = 'Removing Any Unused Layers';
                    });
                    break;
                  
                  case PullModelStatus.success:
                    setState(() {
                      steps[getStepIndex('Downloading Model')].feedback = 'Model downloaded';
                    });
                    break;

                  case null:
                    if(res.completed != null && res.total != null) {
                      setState(() {
                        steps[getStepIndex('Downloading Model')].feedback = 'Downloading Model: ${((res.completed! / res.total!) * 100).toStringAsFixed(2)}%';
                      });
                    }
                    break;
                }
              }
              
            
            
          } else {
            print('model already downloaded');
            steps[getStepIndex('Downloading Model')].feedback = 'Model already downloaded';
          }
        },
      ),
      if (!useOpenAI) GenerationStep(
        title: 'Loading Model',
        dependencies: ['Downloading Model'],
        execute: () async {
          ollamaClient.generateCompletion(request: GenerateCompletionRequest(model: 'phi4:14b', prompt: 'what is the first whole number. only reply with the number'));
          setState(() {
            steps[getStepIndex('Loading Model')].feedback = 'Model loaded';
          });
        },
      ),
      GenerationStep(
        title: 'Title',
        dependencies: !useOpenAI ? ['Loading Model'] : [],
        execute: () async {
          proposalData['title'] = await _generateText(
            Prompts.title(widget.proposalDetails.projectDescription),
            onToken: (result) {
              setState(() {
                steps[getStepIndex('Title')].feedback = result;
              });
            }
          );

          proposalData['title'] = proposalData['title'].contains('---') ? proposalData['title'].split('---')[0].toString().trim() : proposalData['title'];
          setState(() {
            steps[getStepIndex('Title')].feedback = proposalData['title'];
          });
        }
      ),
      GenerationStep(
        title: 'Abstract',
        dependencies: !useOpenAI ? ['Loading Model'] : [],
        execute: () async {
          proposalData['abstract'] = await _generateText(
            Prompts.abstract(widget.proposalDetails.projectDescription),
            onToken: (result) {
              setState(() {
                steps[getStepIndex('Abstract')].feedback = result;
              });
            }
          );
        }
      ),
      GenerationStep(
        title: 'Motivation',
        dependencies: !useOpenAI ? ['Loading Model'] : [],
        execute: () async {
          print('Generating motivation');
          proposalData['motivation'] = await _generateText(
            Prompts.motivation(widget.proposalDetails.projectDescription),
            onToken: (result) {
              setState(() {
                steps[getStepIndex('Motivation')].feedback = result;
              });
            }
          );
        }
      ),
      GenerationStep(
        title: 'Problem Statement',
        dependencies: !useOpenAI ? ['Loading Model'] : [],
        execute: () async {
          print('Generating Problem Statement');
          proposalData['researchProblem'] = await _generateText(
            Prompts.problemStatement(widget.proposalDetails.projectDescription),
            onToken: (result) {
              setState(() {
                steps[getStepIndex('Problem Statement')].feedback = result;
              });
            }
          );
        }
      ),
       GenerationStep(
        title: 'Research Hypothesis',
        dependencies: !useOpenAI ? ['Loading Model'] : [],
        execute: () async {
          print('Generating Research Hypothesis');
          proposalData['hypothesis'] = await _generateText(
            'Write a hypothesis based on the description provided. Only respond with the hypothesis and nothing else.: ${widget.proposalDetails.projectDescription}',
            onToken: (result) {
              setState(() {
                steps[getStepIndex('Research Hypothesis')].feedback = result;
              });
            }
          );
        }
      ),
      GenerationStep(
        title: 'Objectives',
        dependencies: !useOpenAI ? ['Loading Model'] : [],
        execute: () async {
          print('Generating Objectives');
          proposalData['objectives'] = await _generateText(
            'Write objectives based on the description provided. Only respond with the objectives and nothing else.: ${widget.proposalDetails.projectDescription}',
            onToken: (result) {
              setState(() {
                steps[getStepIndex('Objectives')].feedback = result;
              });
            }
          );
        }
      ),
      //TODO: integrate diagram generation at some point
       GenerationStep(
        title: 'Methodology',
        dependencies: !useOpenAI ? ['Loading Model'] : [],
        execute: () async {
          print('Generating methodology');
          proposalData['methodology'] = await _generateText(
            'Write a detailed methodology based on the description provided. Only respond with the methodology and nothing else.: ${widget.proposalDetails.projectDescription}',
            onToken: (result) {
              setState(() {
                steps[getStepIndex('Methodology')].feedback = result;
              });
            }
          );
        }
      ),
       GenerationStep(
        title: 'Outcomes',
        dependencies: !useOpenAI ? ['Loading Model'] : [],
        execute: () async {
          print('Generating outcomes');
          proposalData['studyEndPoints'] = await _generateText(
            'Write the final goal for the project in 1-2 sentences at the most based on the description provided. Only respond with the final goal and nothing else.: ${widget.proposalDetails.projectDescription}',
            onToken: (result) {
              setState(() {
                steps[getStepIndex('Outcomes')].feedback = result;
              });
            }
          );
        }
      ),      
      GenerationStep(
        title: 'Timeline',
        dependencies: !useOpenAI ? ['Loading Model'] : [],
        execute: () async {
          print('Generating timeline');
          proposalData['timeline'] = await _generateText(
            'Write a timeline for the project based on the description provided. Only respond with the timeline and nothing else.: ${widget.proposalDetails.projectDescription}',
            onToken: (result) {
              setState(() {
                steps[getStepIndex('Timeline')].feedback = result;
              });
            }
          );
        }
      ),
      if (enableReferences) GenerationStep(
        title: 'Finding References',
        dependencies: ['Title', 'Abstract', 'Problem Statement'],
        execute: () async {
          final GetStorage storage = GetStorage();
          final String openAIKey = storage.read('OPENAI_API_KEY') ?? '';
          final String serpAPIKey = storage.read('SERP_API_KEY') ?? '';
          
          // Check if required API keys are available
          if (openAIKey.isEmpty || serpAPIKey.isEmpty) {
            setState(() {
              steps[getStepIndex('Finding References')].feedback = 
                'Skipped. SERP API Key or OpenAI Key is not set';
            });
            return;
          }
          
          print('Finding references');
          final String citationStyle = storage.read('CITATION_STYLE') ?? 'apa';
          
          print("SERP KEY: $serpAPIKey");
          if(serpAPIKey == null) {
            setState(() {
              steps[getStepIndex('Finding References')].feedback = 'Skipping references as SERP API Key is not set';
            });
            return;
          }
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt:  'Write a query term to find relevant patents in the google patents search syntax for the given methodolgy and abstract. Don\'t make the search the term very specific & keep it general to find results. Only respond with the query term in the search syntax and nothing else: \nAbstract: ${proposalData['abstract']}\nMethodology: ${proposalData['methodology']}'));
          String searchQuery = '';
          await for (final res in titleStream) {
            searchQuery += res.response ?? '';
            setState(() {
              steps[getStepIndex('Finding References')].feedback = "Search Term: $searchQuery\n";
            });
          }
          searchQuery = searchQuery.replaceAll('`', '');
          setState(() {
            steps[getStepIndex('Finding References')].feedback = 'Search Term: "$searchQuery"\n';
          });
          if(searchQuery.contains('---')){
            searchQuery = searchQuery.split('---')[0];
          }
          if(searchQuery.contains('\n\n')){
            searchQuery = searchQuery.split('\n\n')[0];
          }
          searchQuery = searchQuery.trim();
          setState(() {
            steps[getStepIndex('Finding References')].feedback = 'Search Term: "$searchQuery"\n';
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
              steps[getStepIndex('Finding References')].feedback = (steps[getStepIndex('Finding References')].feedback ?? '') + '\nSearch didn\'t return any results. Proceeding..';
            });
            return;
          }
          final results = data['organic_results'] as List<dynamic>;
          setState(() {
            steps[getStepIndex('Finding References')].feedback = (steps[getStepIndex('Finding References')].feedback ?? '') + '\nSearch returned ${results.length} results';
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
            final Response citationResponse = await dio.get("https://api.citeas.org/product/${result['link']}",queryParameters: {
              'email': 'project2proposal@krishaay.dev',
            });
            final citationData = citationResponse.data as Map<String, dynamic>;
            final citations = citationData['citations'] as List<dynamic>;
            for(final citation in citations) {
              if(citation['style_shortname'] == citationStyle) {
                result['citation'] = citation['citation'];
                result['citation_style'] = citation['style'];
                break;
              }
            } 
            if (result['citation'] == null) {
              result['citation'] = citations[0]['citation'];
              result['citation_style'] = citations[0]['style'];
            }
            setState(() {
              steps[getStepIndex('Finding References')].feedback = (steps[getStepIndex('Finding References')].feedback ?? '') + '\n\n' + result['citation'];
            });
            
          }

          proposalData['references'] = resultsFiltered;
         
        },
      ),
      if (enableBudget) GenerationStep(
        title: 'Budget',
        dependencies: !useOpenAI ? ['Loading Model'] : [],
        execute: () async {
          final GetStorage storage = GetStorage();
          final String browserlessAPIKey = storage.read('BROWSERLESS_API_KEY') ?? '';
          
          // Check if required API keys are available
          if (browserlessAPIKey.isEmpty) {
            setState(() {
              steps[getStepIndex('Budget')].feedback = 
                'Budget generation skipped. Missing Browserless API key. Please add it in settings.';
            });
            return;
          }
          
          print('Generating budget');
          final List<String> budgetLinks = widget.proposalDetails.hardwareLinks;
          final Dio dio = Dio();
          
          final List<String> toBeScrapedWithAI = [];
          for(final link in budgetLinks) {
            final productData = await getProductData(link,browserlessAPIKey);
            if(productData == null) {
              toBeScrapedWithAI.add(link);
              continue;
            }
            proposalData['budget'].add(productData);
            setState(() {
              steps[getStepIndex('Budget')].feedback = (steps[getStepIndex('Budget')].feedback ?? '') + '\n\n\nTitle: ${productData['name']}\nPrice: ${productData['price']}';
            });
          }
          if (toBeScrapedWithAI.isEmpty) {
            return;
          }
          setState(() {
            steps[getStepIndex('Budget')].feedback = (steps[getStepIndex('Budget')].feedback ?? '') + '\nScraping Pending Links:\n${toBeScrapedWithAI.join('\n')}';
          });

          try {
            // Start scraping task
            final Response r = await dio.postUri(
              Uri.parse('$base_url/scrape_info'),
              data: {'links': toBeScrapedWithAI,
              'openAIKey': storage.read('OPENAI_API_KEY'),
              'browserless_token': browserlessAPIKey,
              },
            );
            
            if (r.statusCode != 200) {
              setState(() {
                steps[getStepIndex('Budget')].feedback = (steps[getStepIndex('Budget')].feedback ?? '') + '\n\nError starting scraping task';
              });
              return;
            }
            
            final String taskId = (r.data as Map<String, dynamic>)['task_id'];
            
            // Poll for results
            while (true) {
              final Response statusResponse = await dio.getUri(
                Uri.parse('$base_url/scrape_status/$taskId'),
                options: Options(
                validateStatus: (status) {
                  return status == 200 || status == 404;
                },)
              );
              
              if (statusResponse.statusCode == 404) {
                setState(() {
                  steps[getStepIndex('Budget')].feedback = (steps[getStepIndex('Budget')].feedback ?? '') + '\n\nTask not found';
                });
                break;
              }
              
              final Map<String, dynamic> status = statusResponse.data;
              
              if (status['status'] == 'in_progress') {
                // Wait before next poll
                await Future.delayed(Duration(seconds: 3));
                continue;
              }
              
              if (status['status'] == 'complete') {
                final List<dynamic> results = status['results'];
                for (final result in results) {
                  proposalData['budget'].add(result);
                  setState(() {
                    steps[getStepIndex('Budget')].feedback = (steps[getStepIndex('Budget')].feedback ?? '') + 
                      '\n\n\nTitle: ${result['name']}\nPrice: ${result['price']}';
                  });
                }
                break;
              } 
              
              if (status['status'] == 'error') {
                setState(() {
                  steps[getStepIndex('Budget')].feedback = (steps[getStepIndex('Budget')].feedback ?? '') + 
                    '\n\nError scraping: ${status['error']}';
                });
                break;
              }
            }
          } catch (e) {
            setState(() {
              steps[getStepIndex('Budget')].feedback = (steps[getStepIndex('Budget')].feedback ?? '') + '\n\nError: $e';
            });
          }
        }),
      GenerationStep(
        title: 'Saving PDF',
        dependencies: [
          'Title', 'Abstract', 'Motivation', 'Problem Statement', 
          'Research Hypothesis', 'Objectives', 'Methodology', 'Outcomes', 'Timeline',
          if (enableReferences) 'Finding References',
          if (enableBudget) 'Budget'
        ],
        execute: () async {
          steps[getStepIndex('Saving PDF')].feedback = 'PDFs can take up to a minute to generate depending on server status. Please be patient.';
          final String markdownContent = 
          '''
# Title
${proposalData['title']}
# Abstract
${proposalData['abstract']}
# Motivation
${proposalData['motivation']}
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
${enableBudget ? '''
# Budget
| Name | Price | 
| --- | --- | 
${proposalData['budget'].map((e) => '| ${e['name']} | ${e['price']} |').join('\n')}
''' : ''}
# Timeline
${proposalData['timeline']}
${enableReferences ? '''
# References
${proposalData['references'].map((e) => e['citation']).join('\n\n')}
''' : ''}
''';      

          try{
            final dio = Dio();
          final Response response = await dio.post('https://kry0sc0pic--project2proposal-convert-md-to-pdf.modal.run',data: {
            'markdown' : markdownContent,
          },options: Options(
            responseType: ResponseType.bytes
          ));
          String santizedTitle = sanitizeFilename(proposalData['title']);

          final String sPath = await FileSaver.instance.saveAs(name: santizedTitle, ext: 'pdf', mimeType: MimeType.pdf,
          bytes: Uint8List.fromList(response.data as List<int>),
          dioClient: dio,

          ) ?? '';

          // final savePath = '${downloadsDirectory!.path}/$santizedTitle';
          // File(savePath).writeAsBytesSync(response.data as List<int>);
          steps[getStepIndex('Saving PDF')].feedback = 'Saved to downloads folder: $santizedTitle.pdf';
          // steps[getStepIndex('Saving PDF')+1].feedback = sPath;
          
          } catch (e) {
            throw e;
          }

          


          // print(markdownContent);
          // final baseFont = await rootBundle.load("assets/DMSans-Regular.ttf"); 
          // final boldFont = await rootBundle.load("assets/DMSans-Bold.ttf");
          // final italicFont = await rootBundle.load("assets/DMSans-Italic.ttf");
          // final boldItalicFont = await rootBundle.load("assets/DMSans-BoldItalic.ttf");
          // final mdpdf.ThemeData t = mdpdf.ThemeData.withFont(
          //   base: mdpdf.Font.ttf(baseFont),
          //   bold: mdpdf.Font.ttf(boldFont),
          //   boldItalic: mdpdf.Font.ttf(boldItalicFont),
          //   italic: mdpdf.Font.ttf(italicFont),


        
          // );
          // final htmlContent = md.markdownToHtml(markdownContent,extensionSet: md.ExtensionSet.commonMark);
          // final List<mdpdf.Widget> mdWidgets = await mdpdf.HTMLToPdf().convert(htmlContent);
          // final htmlPDF = mdpdf.Document(theme: t,author: "Project2Proposal",title: "Proposal",);
          // htmlPDF.addPage(mdpdf.MultiPage(pageFormat: mdpdf.PdfPageFormat.a4,build: (context) => mdWidgets));
          // final pdfPath = '${downloadsDirectory!.path}/proposal.pdf';
          // File(pdfPath).writeAsBytes(await htmlPDF.save());
          
        },
      ),
      // GenerationStep(
      //   title: 'Proposal Complete',
      //   dependencies: ['Export to PDF'],
      //   execute: () async {
      //     final String pdfPath = steps[getStepIndex('Export to PDF')+1].feedback!;
          
      //     final String totalTime = _getTotalDuration();
          
      //     setState(() {
      //       steps[getStepIndex('Proposal Complete')].feedback = 
      //         'Your proposal is ready! You can find it at: $pdfPath\n\n' +
      //         'Total generation time: $totalTime' +
      //         (_totalGenerationTime != null ? ' (wall clock)' : ' (sum of steps)');
      //     });
          
      //     if(pdfPath.isNotEmpty){
      //       OpenFile.open(pdfPath);
      //     }
          
      //   },
      // ),
    ].where((step) => step != null).toList(); // Remove null steps
    
    _stepErrors = List.filled(steps.length, '');
  }

  void _cancelGeneration() {
    setState(() {
      _isCancelled = true;
      _isProcessing = false;
      if (_generationStartTime != null) {
        _totalGenerationTime = DateTime.now().difference(_generationStartTime!);
      }
    });
    _durationTimer?.cancel();
  }

  Future<void> _startGeneration() async {
    if (_isProcessing) return;
    _isProcessing = true;
    _isCancelled = false;
    _generationStartTime = DateTime.now();
    
    final GetStorage storage = GetStorage();
    final bool useParallel = storage.read('GENERATION_MODE') == 'parallel';
    final bool useOpenAI = !_platformSupportsOllama || storage.read('AI_PROVIDER') == 'openai';
    
    if (useOpenAI || useParallel) {
      await _startParallelGeneration();
    } else {
      await _startSequentialGeneration();
    }
    
    if (_generationStartTime != null) {
      _totalGenerationTime = DateTime.now().difference(_generationStartTime!);
    }
    _isProcessing = false;
  }
  
  Future<void> _startParallelGeneration() async {
    // Initialize completers for each step
    _stepCompletions = {
      for (var step in steps) step.title: Completer<void>()
    };
    
    // Start all steps that have no dependencies
    for (int i = 0; i < steps.length; i++) {
      if (steps[i].dependencies.isEmpty && !steps[i].requiresUserAction) {
        _executeStep(i);
      }
    }
    
    // Wait for all steps to complete
    try {
      await Future.wait(_stepCompletions.values.map((c) => c.future));
      _durationTimer?.cancel();
      setState(() {
        _currentStep = steps.length - 1;
        if (_generationStartTime != null) {
          _totalGenerationTime = DateTime.now().difference(_generationStartTime!);
        }
      });
    } catch (e) {
      print('Error in parallel execution: $e');
    }
  }
  
  Future<void> _startSequentialGeneration() async {
    _currentStep = 0;
    
    for (int i = 0; i < steps.length; i++) {
      if (_isCancelled) break;
      
      setState(() {
        _currentStep = i;
        steps[i].startTime = DateTime.now();
      });
      
      if (_durationTimer == null || !_durationTimer!.isActive) {
        _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
      
      try {
        if (steps[i].requiresUserAction) {
          setState(() {
            _waitingForUser = true;
          });
          return; // Will be continued by user action
        }
        
        await steps[i].execute();
        
        setState(() {
          steps[i].duration = DateTime.now().difference(steps[i].startTime!);
          steps[i].isComplete = true;
          _completedSteps.add(i);
        });
      } catch (e) {
        setState(() {
          _stepErrors[i] = e.toString();
        });
        break;
      }
    }
    
    _durationTimer?.cancel();
  }

  Future<void> _executeStep(int index) async {
    if (!mounted || _isCancelled) return;
    
    final step = steps[index];
    
    // Check if all dependencies are complete
    for (final dep in step.dependencies) {
      if (!_stepCompletions[dep]!.isCompleted) {
        // Wait for dependency to complete
        await _stepCompletions[dep]!.future;
      }
    }
   
    
    // Check if step is already complete or running
    if (step.isComplete || step.isRunning) {
      return;
    }
    
    // Start executing this step

    setState(() {
      step.isRunning = true;
      step.startTime = DateTime.now();
      _runningSteps.add(step.title);
    });
    
    // Start timer to update duration

    if (_durationTimer == null || !_durationTimer!.isActive) {
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    
    try {
      if (step.requiresUserAction) {
        setState(() {
          _waitingForUser = true;
          _currentStep = index;
        });
        return; // Will be continued by user action
      }
      
      await step.execute();
      
      setState(() {
        step.duration = DateTime.now().difference(step.startTime ?? DateTime.now());
        step.isRunning = false;
        step.isComplete = true;
        _completedSteps.add(index);
        _runningSteps.remove(step.title);
      });
      
  
      // Mark this step as complete
      if (!_stepCompletions[step.title]!.isCompleted) {
        _stepCompletions[step.title]!.complete();
      }
      

      // Start any steps that depend on this one
      for (int i = 0; i < steps.length; i++) {

        if (steps[i].dependencies.contains(step.title) && !steps[i].isRunning && !steps[i].isComplete) {
          // Check if all dependencies are now complete
          bool canStart = true;
          for (final dep in steps[i].dependencies) {
            if(!_stepCompletions.containsKey(dep)) {
              print('${dep} not found');
              canStart = false;
              break;
            }
            if (!_stepCompletions[dep]!.isCompleted) {
              canStart = false;
              break;
            }
          }
          
          if (canStart) {
   
            _executeStep(i);
          }
        }
      }
    } catch (e) {


      setState(() {
        _stepErrors[index] = e.toString();
        step.isRunning = false;
        _runningSteps.remove(step.title);
      });
      if (!_stepCompletions[step.title]!.isCompleted) {
        _stepCompletions[step.title]!.completeError(e);
      }
    }
  }

  void continueExecution() {
    if (_waitingForUser) {
      _waitingForUser = false;
      final GetStorage storage = GetStorage();
      final bool useParallel = storage.read('GENERATION_MODE') == 'parallel';
      final bool useOpenAI = !_platformSupportsOllama || storage.read('AI_PROVIDER') == 'openai';
      
      if (useOpenAI || useParallel) {
        final int index = _currentStep;
        final step = steps[index];
        
        step.execute().then((_) {
          setState(() {
            step.duration = DateTime.now().difference(step.startTime!);
            step.isRunning = false;
            step.isComplete = true;
            _completedSteps.add(index);
            _runningSteps.remove(step.title);
          });
          
          // Mark this step as complete
          if (!_stepCompletions[step.title]!.isCompleted) {
            _stepCompletions[step.title]!.complete();
          }
          
          // Start any steps that depend on this one
          for (int i = 0; i < steps.length; i++) {
            if (steps[i].dependencies.contains(step.title) && 
                !steps[i].isRunning && 
                !steps[i].isComplete) {
              // Check if all dependencies are now complete
              bool canStart = true;
              for (final dep in steps[i].dependencies) {
                if (!_stepCompletions[dep]!.isCompleted) {
                  canStart = false;
                  break;
                }
              }
              
              if (canStart) {
                _executeStep(i);
              }
            }
          }
        }).catchError((e) {
          setState(() {
            _stepErrors[_currentStep] = e.toString();
            step.isRunning = false;
            _runningSteps.remove(step.title);
          });
          if (!_stepCompletions[step.title]!.isCompleted) {
            _stepCompletions[step.title]!.completeError(e);
          }
        });
      } else {
        // Sequential mode
        steps[_currentStep].execute().then((_) {
          setState(() {
            steps[_currentStep].duration = DateTime.now().difference(steps[_currentStep].startTime!);
            steps[_currentStep].isComplete = true;
            _completedSteps.add(_currentStep);
          });
          _startSequentialGeneration(); // Continue with next steps
        }).catchError((e) {
          setState(() {
            _stepErrors[_currentStep] = e.toString();
          });
        });
      }
    }
  }

  StepState _getStepState(int step) {
    if (_stepErrors[step].isNotEmpty) {
      return StepState.error;
    }
    if (steps[step].isComplete) {
      return StepState.complete;
    }
    if (steps[step].isRunning) {
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

  void _checkSettings() async {
    final GetStorage storage = GetStorage();
    final bool hasOpenAIKey = storage.read('OPENAI_API_KEY') != null;
    final bool hasSerpAPIKey = storage.read('SERP_API_KEY') != null;
    final bool hasBrowserlessKey = storage.read('BROWSERLESS_API_KEY') != null;
    final bool enableReferences = storage.read('ENABLE_REFERENCES') ?? false;
    final bool enableBudget = storage.read('ENABLE_BUDGET') ?? false;

    bool showSettingsWarning = false;
    List<String> missingKeys = [];
    
    // Check if OpenAI key is needed (required for both references and budget)
    if (!hasOpenAIKey && (enableReferences || enableBudget)) {
      showSettingsWarning = true;
      missingKeys.add('OpenAI API key');
    }
    
    // Check if SERP API key is needed
    if (!hasSerpAPIKey && enableReferences) {
      showSettingsWarning = true;
      missingKeys.add('SERP API key');
    }
    
    // Check if Browserless key is needed
    if (!hasBrowserlessKey && enableBudget) {
      showSettingsWarning = true;
      missingKeys.add('Browserless API key');
    }

    if (showSettingsWarning && missingKeys.isNotEmpty) {
      final bool openSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: app_colors.background,
          title: Text(
            'Missing API Keys',
            style: app_colors.martianMonoTextStyle.copyWith(
              color: app_colors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The following API keys are missing:',
                style: app_colors.martianMonoTextStyle,
              ),
              const SizedBox(height: 8),
              ...missingKeys.map((key) => Padding(
                padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
                child: Text(
                  '• $key',
                  style: app_colors.martianMonoTextStyle,
                ),
              )),
              const SizedBox(height: 8),
              Text(
                'Some features will be skipped. Would you like to add these keys now?',
                style: app_colors.martianMonoTextStyle,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Continue without keys',
                style: app_colors.martianMonoTextStyle.copyWith(
                  color: app_colors.neutral,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Open Settings',
                style: app_colors.martianMonoTextStyle.copyWith(
                  color: app_colors.primary,
                ),
              ),
            ),
          ],
        ),
      ) ?? false;
      
      if (openSettings) {
        await showDialog(
          context: context,
          builder: (context) => const SettingsDialog(),
        );
      }
    }
  }

  void _initializeCollapsedState() {
    final bool shouldCollapseByDefault = _isMobileDevice || 
        (kIsWeb && MediaQuery.of(context).size.width < 600);
    
    if (shouldCollapseByDefault) {
      setState(() {
        // Collapse all steps except the first one
        _collapsedSteps = Set.from(
          List.generate(steps.length, (index) => index)
            ..remove(0) // Keep the first step expanded
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // For web, check screen width to determine if it's a mobile view
    final bool isMobileView = _isMobileDevice || 
        (kIsWeb && MediaQuery.of(context).size.width < 600);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Building Proposal'),
        automaticallyImplyLeading: _currentStep == steps.length - 1 || _isCancelled,
        leading: (_currentStep == steps.length - 1 || _isCancelled) 
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.of(context).pop();
              },
              tooltip: 'Create New Proposal',
            )
          : null,
        actions: [
          if (_isProcessing)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel Generation',
              onPressed: _cancelGeneration,
            ),
          // Add a button to expand/collapse all sections
          if (isMobileView)
            IconButton(
              icon: Icon(_collapsedSteps.length > steps.length / 2 
                ? Icons.unfold_more 
                : Icons.unfold_less),
              tooltip: _collapsedSteps.length > steps.length / 2 
                ? 'Expand All' 
                : 'Collapse All',
              onPressed: () {
                setState(() {
                  if (_collapsedSteps.length > steps.length / 2) {
                    // More than half are collapsed, so expand all
                    _collapsedSteps.clear();
                  } else {
                    // Less than half are collapsed, so collapse all
                    _collapsedSteps = Set.from(
                      List.generate(steps.length, (index) => index)
                    );
                  }
                });
              },
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
                        if ((_currentStep == steps.length - 1 || _isCancelled) && 
                            _completedSteps.contains(index) &&
                            index != steps.length - 1) // Don't show for final step
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Regenerate this section',
                            onPressed: () => _executeStep(index),
                            iconSize: 20,
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