class ProposalDetails {
  final String projectDescription;
  final List<String> hardwareLinks;
  final String? openAIKey;
  final String? azureSpeechKey;

  ProposalDetails({
    required this.projectDescription,
    required this.hardwareLinks,
    this.openAIKey,
    this.azureSpeechKey,
  });

  // Convert hardware links string to List
  static List<String> parseHardwareLinks(String links) {
    return links
        .split('\n')
        .where((link) => link.trim().isNotEmpty)
        .map((link) => link.trim())
        .toList();
  }

  // Create from form data
  factory ProposalDetails.fromForm({
    required String projectDescription,
    required String hardwareLinksText,
    String? openAIKey,
    String? azureSpeechKey,
  }) {
    return ProposalDetails(
      projectDescription: projectDescription,
      hardwareLinks: parseHardwareLinks(hardwareLinksText),
      openAIKey: openAIKey,
      azureSpeechKey: azureSpeechKey,
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'projectDescription': projectDescription,
      'hardwareLinks': hardwareLinks,
      'openAIKey': openAIKey,
      'azureSpeechKey': azureSpeechKey,
    };
  }

  // Create from JSON
  factory ProposalDetails.fromJson(Map<String, dynamic> json) {
    return ProposalDetails(
      projectDescription: json['projectDescription'] as String,
      hardwareLinks: List<String>.from(json['hardwareLinks']),
      openAIKey: json['openAIKey'] as String?,
      azureSpeechKey: json['azureSpeechKey'] as String?,
    );
  }

  // Create a copy with optional new values
  ProposalDetails copyWith({
    String? projectDescription,
    List<String>? hardwareLinks,
    String? openAIKey,
    String? azureSpeechKey,
  }) {
    return ProposalDetails(
      projectDescription: projectDescription ?? this.projectDescription,
      hardwareLinks: hardwareLinks ?? this.hardwareLinks,
      openAIKey: openAIKey ?? this.openAIKey,
      azureSpeechKey: azureSpeechKey ?? this.azureSpeechKey,
    );
  }
} 