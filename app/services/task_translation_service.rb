# frozen_string_literal: true

# Translates a Task's title and description into a target language via the
# already-configured Ollama LLM. Ollama has no native structured-output/
# function-calling mode here (see OllamaLlmService) - the JSON contract is
# enforced by prompting for it and parsing the response, mirroring the
# pattern already used by TaskInsightsChatService for its tool-call envelope.
class TaskTranslationService
  class TranslationError < StandardError; end

  SYSTEM_PROMPT = <<~PROMPT
    You translate short project-management task text. Reply with ONLY a
    single JSON object shaped exactly like {"title": "...", "description": "..."} -
    no markdown code fences, no commentary, no extra keys. Preserve the
    original meaning and tone, and preserve any Markdown formatting already
    present in the description. Do not translate proper nouns, code
    snippets, or URLs.
  PROMPT

  def self.call(task:, target_language:, model_name:)
    new(task: task, target_language: target_language, model_name: model_name).call
  end

  def initialize(task:, target_language:, model_name:)
    @task = task
    @target_language = target_language.to_s
    @model_name = model_name
  end

  def call
    raise TranslationError, "No target language configured" if @target_language.blank?
    raise TranslationError, "No LLM model available" if @model_name.blank?

    llm = OllamaLlmService.new(model_name: @model_name, state_key: "translate")
    result = llm.generate_response(prompt, system_prompt: SYSTEM_PROMPT)

    translated_title = result.json_attr("title").to_s.strip
    translated_description = result.json_attr("description").to_s.strip
    raise TranslationError, "LLM response did not include a translated title" if translated_title.blank?

    { title: translated_title, description: translated_description }
  rescue OllamaLlmService::ResponseError => e
    raise TranslationError, e.message
  end

  private

  def prompt
    <<~PROMPT
      Translate the following task title and description into #{@target_language}.

      Title: #{@task.title}
      Description: #{@task.description.presence || "(none)"}

      Respond with only the JSON object described in your instructions.
    PROMPT
  end
end
