# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

class OllamaLlmService
  class ResponseError < StandardError; end

  Result = Struct.new(
    :response,
    :context,
    :context_provided,
    :created_at,
    :done,
    :done_reason,
    :total_duration,
    :load_duration,
    :prompt_eval_count,
    :prompt_eval_duration,
    :eval_count,
    :eval_duration,
    keyword_init: true
  ) do
    def self.from_json(data, context_provided: false)
      new(
        response: data["response"].to_s,
        context: data["context"],
        context_provided: context_provided,
        created_at: data["created_at"].to_s,
        done: data["done"] || false,
        done_reason: data["done_reason"],
        total_duration: data["total_duration"] || 0,
        load_duration: data["load_duration"] || 0,
        prompt_eval_count: data["prompt_eval_count"] || 0,
        prompt_eval_duration: data["prompt_eval_duration"] || 0,
        eval_count: data["eval_count"] || 0,
        eval_duration: data["eval_duration"] || 0
      )
    end

    def valid?
      response.present?
    end

    def json_attr(attr_name)
      return nil if attr_name.blank?

      raw = response.to_s
      return nil unless raw.include?("{") && raw.include?("}") && raw.include?(":")

      cleaned = raw.gsub("```", "").strip
      cleaned = cleaned.delete_prefix("json").strip if cleaned.start_with?("json")
      json = JSON.parse(cleaned)
      return nil unless json.is_a?(Hash)

      return json[attr_name] if json.key?(attr_name)

      fuzzy_key = json.keys.find { |key| similar_key?(attr_name, key) }
      fuzzy_key ? json[fuzzy_key] : nil
    rescue JSON::ParserError
      nil
    end

    private

    def similar_key?(left, right)
      normalize_key(left) == normalize_key(right)
    end

    def normalize_key(value)
      value.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end
  end

  ENDPOINT = ENV.fetch("OLLAMA_ENDPOINT", "http://localhost:11434/api/generate")
  TAGS_ENDPOINT = ENV.fetch("OLLAMA_TAGS_ENDPOINT", "http://localhost:11434/api/tags")
  DEFAULT_MODEL = ENV.fetch("OLLAMA_MODEL", "deepseek-r1:14b")
  DEFAULT_TIMEOUT = 180
  DEFAULT_SYSTEM_PROMPT_DROP_RATE = 0.9
  CHECK_INTERVAL = 0.1
  FAILURE_THRESHOLD = 3
  DEFAULT_STATE = "local"
  PROMPT_RESPONSE_HISTORY_MAX_ITEMS = 200

  @failure_counts = Hash.new(0)
  @failure_lock = Mutex.new

  class << self
    attr_reader :failure_counts, :failure_lock

    def failure_count_for_state(state_key)
      failure_lock.synchronize { failure_counts[state_key.to_s] }
    end

    def increment_failure_count_for_state(state_key)
      failure_lock.synchronize do
        key = state_key.to_s
        failure_counts[key] += 1
      end
    end

    def reset_failure_count_for_state(state_key)
      failure_lock.synchronize { failure_counts[state_key.to_s] = 0 }
    end

    def failing_for_state?(state_key)
      failure_count_for_state(state_key) >= FAILURE_THRESHOLD
    end

    def available_models(timeout: 5)
      uri = URI.parse(tags_endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = timeout
      http.read_timeout = timeout
      req = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(req)
      return [] unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      extract_model_names(payload)
    rescue StandardError => e
      Rails.logger.warn("Unable to fetch Ollama model list: #{e.message}")
      []
    end

    private

    def tags_endpoint
      explicit = TAGS_ENDPOINT.to_s
      return explicit if explicit.present?

      ENDPOINT.to_s.sub(%r{/api/generate\z}, "/api/tags")
    end

    def extract_model_names(payload)
      models = Array(payload["models"])
      names = models.map { |item| item["name"].to_s }.reject(&:blank?)
      names.uniq.sort
    end
  end

  def initialize(model_name: DEFAULT_MODEL, run_context: nil, state_key: nil, track_prompts_and_responses: false)
    @model_name = model_name
    @run_context = run_context
    @state_key = state_key || DEFAULT_STATE
    @track_prompts_and_responses = !!track_prompts_and_responses
    @prompt_response_history = []
    @prompt_response_lock = Mutex.new
    @prompt_response_history_file = Rails.root.join("tmp", "llm_prompt_response_history_#{sanitize_state_key(@state_key)}.json")
    @cancelled = false
    @result = nil
    @exception = nil
    @thread = nil
  end

  def ask(query, json_key: nil, timeout: DEFAULT_TIMEOUT, context: nil, system_prompt: nil, system_prompt_drop_rate: DEFAULT_SYSTEM_PROMPT_DROP_RATE)
    if json_key.present?
      generate_json_get_value(
        query,
        json_key,
        timeout: timeout,
        context: context,
        system_prompt: system_prompt,
        system_prompt_drop_rate: system_prompt_drop_rate
      )
    else
      generate_response_async(
        query,
        timeout: timeout,
        context: context,
        system_prompt: system_prompt,
        system_prompt_drop_rate: system_prompt_drop_rate
      )
    end
  end

  def generate_response(query, timeout: DEFAULT_TIMEOUT, context: nil, system_prompt: nil, system_prompt_drop_rate: DEFAULT_SYSTEM_PROMPT_DROP_RATE)
    sanitized_query = sanitize_query(query)
    effective_timeout = timeout_for_model(timeout)
    payload = {
      model: @model_name,
      prompt: sanitized_query,
      stream: false
    }
    payload[:context] = context if context.present?
    if system_prompt.present? && rand > system_prompt_drop_rate.to_f
      payload[:system] = system_prompt
    end

    response_json = post_json(payload, timeout: effective_timeout)
    result = Result.from_json(response_json, context_provided: context.present?)
    result.response = clean_response_for_models(result.response)

    track_prompt_response(
      prompt: sanitized_query,
      response: result.response,
      context_provided: context.present?,
      system_prompt_included: payload.key?(:system)
    )

    raise ResponseError, "LLM response is invalid" unless result.valid?

    reset_failure_count
    result
  rescue StandardError => e
    increment_failure_count
    raise ResponseError, "Failed to generate LLM response: #{e.message}"
  end

  def generate_response_async(query, timeout: DEFAULT_TIMEOUT, context: nil, system_prompt: nil, system_prompt_drop_rate: DEFAULT_SYSTEM_PROMPT_DROP_RATE)
    @cancelled = false
    @result = nil
    @exception = nil
    @thread = Thread.new do
      begin
        generated = generate_response(
          query,
          timeout: timeout,
          context: context,
          system_prompt: system_prompt,
          system_prompt_drop_rate: system_prompt_drop_rate
        )
        @result = generated unless @cancelled
      rescue StandardError => e
        @exception = e
      end
    end

    while @thread&.alive?
      if @run_context&.respond_to?(:should_skip?) && @run_context.should_skip
        cancel_generation
        return nil
      end
      sleep(CHECK_INTERVAL)
    end

    raise @exception if @exception

    @result
  ensure
    @thread = nil
  end

  def generate_json_get_value(query, json_key, timeout: DEFAULT_TIMEOUT, context: nil, system_prompt: nil, system_prompt_drop_rate: DEFAULT_SYSTEM_PROMPT_DROP_RATE)
    result = generate_response_async(
      query,
      timeout: timeout,
      context: context,
      system_prompt: system_prompt,
      system_prompt_drop_rate: system_prompt_drop_rate
    )
    raise ResponseError, "Failed to generate LLM response - result is nil" if result.nil?

    result.json_attr(json_key)
  end

  def get_failure_count
    self.class.failure_count_for_state(@state_key)
  end

  def increment_failure_count
    self.class.increment_failure_count_for_state(@state_key)
  end

  def reset_failure_count
    self.class.reset_failure_count_for_state(@state_key)
  end

  def failing?
    self.class.failing_for_state?(@state_key)
  end

  def llm_penalty
    1.0 / (1.0 + Math.log2(1.0 + get_failure_count))
  end

  def cancel_generation
    @cancelled = true
    return unless @thread&.alive?

    @thread.join(1.0)
    @thread = nil
  end

  private

  def post_json(payload, timeout:)
    uri = URI.parse(ENDPOINT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = timeout
    http.read_timeout = timeout
    req = Net::HTTP::Post.new(uri.request_uri, { "Content-Type" => "application/json" })
    req.body = payload.to_json
    response = http.request(req)
    raise ResponseError, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def track_prompt_response(prompt:, response:, context_provided:, system_prompt_included:)
    return unless @track_prompts_and_responses

    entry = {
      timestamp: Time.current.to_f,
      model: @model_name,
      prompt: prompt,
      response: response,
      context_provided: !!context_provided,
      system_prompt_included: !!system_prompt_included
    }

    @prompt_response_lock.synchronize do
      @prompt_response_history << entry
      @prompt_response_history = @prompt_response_history.last(PROMPT_RESPONSE_HISTORY_MAX_ITEMS)
      persist_prompt_response_history
    end
  end

  def persist_prompt_response_history
    payload = {
      model: @model_name,
      state_key: @state_key,
      updated_at: Time.current.to_f,
      max_items: PROMPT_RESPONSE_HISTORY_MAX_ITEMS,
      items: @prompt_response_history
    }
    File.write(@prompt_response_history_file, JSON.pretty_generate(payload))
  rescue StandardError => e
    Rails.logger.warn("Failed to persist LLM prompt/response history: #{e.message}")
  end

  def sanitize_state_key(value)
    value.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")
  end

  def thinking_model?
    @model_name.to_s.start_with?("deepseek-r1")
  end

  def clean_response_for_models(text)
    response_text = text.to_s
    if thinking_model?
      if response_text.strip.start_with?("<think>") && response_text.include?("</think>")
        response_text = response_text[(response_text.rindex("</think>") + "</think>".length)..].to_s.strip
      end
      response_text = response_text.gsub("<think>", "").gsub("</think>", "").strip
    end

    if response_text.strip.start_with?("Final Answer:")
      response_text = response_text.sub(/\AFinal Answer:\s*/m, "")
    end

    invalid_pattern = "---\n\n**Note:** The assistant's response is cut off due to the user stopping the interaction.\n\n---"
    if response_text.include?(invalid_pattern)
      return "" if response_text.strip == invalid_pattern

      response_text = response_text.gsub(invalid_pattern, "").strip
    end
    response_text
  end

  def sanitize_query(query)
    query.to_s
  end

  def timeout_for_model(timeout)
    return [timeout.to_i, 300].max if thinking_model?

    timeout.to_i
  end
end
