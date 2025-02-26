class Prompts {
  // Title generation prompt
  static String title(String projectDescription) => 
    'Write a title for the project based on the description provided. Only respond with the title and nothing else.: $projectDescription';

  // Abstract generation prompt
  static String abstract(String projectDescription) => 
    'Write a brief abstract within 200 words for the project based on the description provided. Only respond with the abstract and nothing else.: $projectDescription';

  // Motivation/Origin generation prompt
  static String motivation(String projectDescription) => 
    'Write about the origin of the project based on the description provided. Only respond with the origin and nothing else.: $projectDescription';

  // Problem statement generation prompt
  static String problemStatement(String projectDescription) => 
    'Write a problem statement in 1-2 sentences based on the description provided. Only respond with the problem statement and nothing else.: $projectDescription';

  // Hypothesis generation prompt
  static String hypothesis(String projectDescription) => 
    'Write a hypothesis based on the description provided. Only respond with the hypothesis and nothing else.: $projectDescription';

  // Objectives generation prompt
  static String objectives(String projectDescription) => 
    'Write objectives based on the description provided. Only respond with the objectives and nothing else.: $projectDescription';

  // Methodology generation prompt
  static String methodology(String projectDescription) => 
    'Write a detailed methodology based on the description provided. Only respond with the methodology and nothing else.: $projectDescription';

  // Outcomes generation prompt
  static String outcomes(String projectDescription) => 
    'Write the final goal for the project in 1-2 sentences at the most based on the description provided. Only respond with the final goal and nothing else.: $projectDescription';

  // Timeline generation prompt
  static String timeline(String projectDescription) => 
    'Write a timeline for the project based on the description provided. Only respond with the timeline and nothing else.: $projectDescription';

  // References generation prompt
  static String references(String title, String abstract, String problemStatement) => 
    'Find relevant academic references for a research project with the following details:\n\nTitle: $title\n\nAbstract: $abstract\n\nProblem Statement: $problemStatement\n\nProvide 5-7 relevant academic references in a numbered list.';
} 