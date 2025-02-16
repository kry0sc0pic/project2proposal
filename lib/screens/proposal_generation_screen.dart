import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanitize_filename/sanitize_filename.dart';
import '../constants.dart' as app_colors;
import '../models/proposal_details.dart';
import 'package:process_run/shell.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'package:process_run/shell.dart';
import 'dart:async';
import 'dart:convert';

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
            final Dio dio = Dio();
            print('Downloading Ollama in ${tempDir.path}');
            setState(() {
              steps[0].feedback = 'Downloading Ollama: 0%';
            });
            await dio.downloadUri(Uri.parse('https://ollama.com/download/OllamaSetup.exe'), tempDir.path+'/OllamaSetup.exe',onReceiveProgress: (count, total) => {
              setState(() {
                steps[0].feedback = 'Downloading Ollama: ${((count / total) * 100).toStringAsFixed(2)}%';
              })
            },);
            setState(() {
              steps[0].feedback = 'Downloaded Ollama.\nRunning Ollama Setup';
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
                steps[0].feedback = 'Ollama.app found but not on path.\nOpening App...';
              });
              try {
                Shell().run('open /Applications/Ollama.app',);
              } catch (e) {
                print(e);
              }
              return;
            }
            

            setState(() {
              steps[0].feedback = 'Downloading Ollama: 0%';
            });
            await dio.downloadUri(Uri.parse('https://ollama.com/download/Ollama-darwin.zip'), tempDir.path+'/Ollama-darwin.zip',onReceiveProgress: (count, total) => {
              setState(() {
                steps[0].feedback = 'Downloading Ollama: ${((count / total) * 100).toStringAsFixed(2)}%';
              })
            },);
            setState(() {
              steps[0].feedback = 'Downloaded Ollama\nExtracting Ollama...';
            });
            await shell.run('unzip Ollama-darwin.zip');
            setState(() {
              steps[0].feedback = steps[0].feedback! + 'Done.\nCopying to /Applications. Please allow permissions when prompted';
            });
            await shell.run('mv Ollama.app /Applications/Ollama.app');
            await shell.run('rm Ollama-darwin.zip');
            await shell.run('open /Applications/Ollama.app --hide');
          }
          setState(() {
            steps[0].feedback = 'Installed Ollama';
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
          if(proposalData['title'].contains('\n\n')){
            proposalData['title'] = proposalData['title'].split('\n\n')[0];
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
          
          final titleStream = ollamaClient.generateCompletionStream(request: GenerateCompletionRequest(model: 'phi4:14b', prompt:  'Write a timeline for the project as a table with the task and the deadline for each task. Today is ${date.day}/${date.month}/${date.year}. Only respond with the table in markdown format and nothing else: ${widget.proposalDetails.projectDescription}'));
          await for (final res in titleStream) {
            proposalData['timeline'] += res.response ?? '';
            setState(() {
              steps[11].feedback = proposalData['timeline'];
            });
          }
          proposalData['timeline'] = proposalData['timeline'].replaceAll('```markdown\n','').split('\n```')[0];
          print(proposalData['timeline']);
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
          if(searchQuery.contains('\n\n')){
            searchQuery = searchQuery.split('\n\n')[0];
          }
          searchQuery = searchQuery.trim();
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
            final Response citationResponse = await dio.get("https://api.citeas.org/product/${result['link']}",queryParameters: {
              'email': 'project2proposal@krishaay.dev',
            });
            final citationData = citationResponse.data as Map<String, dynamic>;
            final citations = citationData['citations'] as List<dynamic>;
            final citationStyle = citationKey(storage.read('CITATION_STYLE').toString().toLowerCase());
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
              steps[12].feedback = (steps[12].feedback ?? '') + '\n\n' + result['citation'];
            });
            
          }

          proposalData['references'] = resultsFiltered;
         
        },
      ),
      GenerationStep(title: "Budget", execute: () async {
        final List<String> budgetLinks = widget.proposalDetails.hardwareLinks;
        final Dio dio = Dio();
        final GetStorage storage = GetStorage();
        final String? bs_key = storage.read('BROWSERLESS_API_KEY');
        if(bs_key == null) {
          setState(() {
            steps[13].feedback = 'Skipping budget as Browserless API Key is not set';
          });
          return;
        }
        final List<String> toBeScrapedWithAI = [];
        for(final link in budgetLinks) {
          final productData = await getProductData(link,bs_key);
          if(productData == null) {
            toBeScrapedWithAI.add(link);
            continue;
          }
          proposalData['budget'].add(productData);
          setState(() {
            steps[13].feedback = (steps[13].feedback ?? '') + '\n\n\nTitle: ${productData['name']}\nPrice: ${productData['price']}';
          });
        }
        if (toBeScrapedWithAI.isEmpty) {
          return;
        }
        setState(() {
          steps[13].feedback = (steps[13].feedback ?? '') + '\nScraping Pending Links:\n${toBeScrapedWithAI.join('\n')}';
        });

        try {
          // Start scraping task
          final Response r = await dio.postUri(
            Uri.parse('https://md2pdf.krishaay.dev/scrape_info'),
            data: {'links': toBeScrapedWithAI,
            'openAIKey': storage.read('OPENAI_API_KEY'),
            'browserless_token': bs_key,
            },
          );
          
          if (r.statusCode != 200) {
            setState(() {
              steps[13].feedback = (steps[13].feedback ?? '') + '\n\nError starting scraping task';
            });
            return;
          }
          
          final String taskId = (r.data as Map<String, dynamic>)['task_id'];
          
          // Poll for results
          while (true) {
            final Response statusResponse = await dio.getUri(
              Uri.parse('https://md2pdf.krishaay.dev/scrape_status/$taskId'),
              options: Options(
              validateStatus: (status) {
                return status == 200 || status == 404;
              },)
            );
            
            if (statusResponse.statusCode == 404) {
              setState(() {
                steps[13].feedback = (steps[13].feedback ?? '') + '\n\nTask not found';
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
                  steps[13].feedback = (steps[13].feedback ?? '') + 
                    '\n\n\nTitle: ${result['name']}\nPrice: ${result['price']}';
                });
              }
              break;
            }
            
            if (status['status'] == 'error') {
              setState(() {
                steps[13].feedback = (steps[13].feedback ?? '') + 
                  '\n\nError scraping: ${status['error']}';
              });
              break;
            }
          }
        } catch (e) {
          setState(() {
            steps[13].feedback = (steps[13].feedback ?? '') + '\n\nError: $e';
          });
        }
      }),
      GenerationStep(
        title: 'Export to PDF',
        execute: () async {
          final Directory? downloadsDirectory = await getDownloadsDirectory();
          steps[14].feedback = 'PDFs can take up to a minute to generate depending on server status. Please be patient.';
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
| Name | Price | 
| --- | --- | 
${proposalData['budget'].map((e) => '| ${e['name']} | ${e['price']} |').join('\n')}

# Timeline

${proposalData['timeline']}

# References
${proposalData['references'].map((e) => e['citation']).join('\n\n')}
''';      

          try{
            final dio = Dio();
          final Response response = await dio.post('https://md2pdf.krishaay.dev/md2pdf',data: {
            'markdown' : markdownContent,
          },options: Options(
            responseType: ResponseType.bytes
          ));
          String santizedTitle = sanitizeFilename(proposalData['title']+'.pdf');
          final savePath = '${downloadsDirectory!.path}/$santizedTitle';
          File(savePath).writeAsBytesSync(response.data as List<int>);
          steps[14].feedback = 'Saved to: $savePath';
          steps[15].feedback = savePath;
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
      GenerationStep(
        title: 'Proposal Complete',
        execute: () async {
          OpenFile.open(steps[15].feedback!,type: 'application/pdf');
          steps[15].feedback = 'Opened PDF';
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
          _completedSteps.add(i);
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

  Future<void> _rerunStep(int index) async {
    if (_isProcessing) return;
    
    setState(() {
      steps[index].feedback = null;
      steps[index].startTime = DateTime.now();
      _stepErrors[index] = '';
    });
    
    try {
      await steps[index].execute();
      setState(() {
        steps[index].duration = DateTime.now().difference(steps[index].startTime!);
      });
    } catch (e) {
      setState(() {
        _stepErrors[index] = e.toString();
      });
    }
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
                            onPressed: () => _rerunStep(index),
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