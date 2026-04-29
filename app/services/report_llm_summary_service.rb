# frozen_string_literal: true

class ReportLlmSummaryService
  SYSTEM_PROMPT = <<~PROMPT
    You are an assistant that summarizes project analytics for a task management app.
    Be concise, actionable, and specific.
    Output plain text only.
  PROMPT
  TASKS_PER_BUCKET = 4

  PROMPT_COPY = {
    "en" => {
      title: "Create a short executive report summary based on this data:",
      overall: "Overall:",
      projects: "Projects:",
      kanban_snapshot: "Kanban snapshot (same project scope):",
      highest_risk: "Highest-risk tasks (top 8):",
      bucket_examples: "Bucket examples (same project scope):",
      active_examples: "Active tasks examples",
      overdue_examples: "Overdue tasks examples",
      stale_7d_examples: "Stale 7d tasks examples",
      stale_14d_examples: "Stale 14d tasks examples",
      high_priority_examples: "High-priority open tasks examples",
      ready_to_test_examples: "Ready-to-test tasks examples",
      to_investigate_examples: "To-investigate tasks examples",
      requirements: "Requirements:",
      req_sections: '- 3 short sections: "Key findings", "Risks", "Recommended next actions"',
      req_words: "- Max 220 words",
      req_bullets: "- Use bullets, no markdown tables",
      req_metrics: "- Refer to concrete metrics and at least 2 specific tasks from the provided examples",
      req_grounded: "- Do not invent fields or numbers not present here",
      none: "(none)"
    },
    "de" => {
      title: "Erstelle eine kurze Executive-Zusammenfassung auf Basis dieser Daten:",
      overall: "Gesamtbild:",
      projects: "Projekte:",
      kanban_snapshot: "Kanban-Snapshot (gleicher Projektumfang):",
      highest_risk: "Aufgaben mit hoechstem Risiko (Top 8):",
      bucket_examples: "Beispiele je Gruppe (gleicher Projektumfang):",
      active_examples: "Beispiele aktive Aufgaben",
      overdue_examples: "Beispiele ueberfaellige Aufgaben",
      stale_7d_examples: "Beispiele seit 7 Tagen nicht aktualisiert",
      stale_14d_examples: "Beispiele seit 14 Tagen nicht aktualisiert",
      high_priority_examples: "Beispiele offene Aufgaben mit hoher Prioritaet",
      ready_to_test_examples: "Beispiele Aufgaben in 'Bereit zum Testen'",
      to_investigate_examples: "Beispiele Aufgaben in 'Untersuchen'",
      requirements: "Anforderungen:",
      req_sections: '- 3 kurze Abschnitte: "Key findings", "Risks", "Recommended next actions"',
      req_words: "- Maximal 220 Woerter",
      req_bullets: "- Nutze Aufzaehlungen, keine Markdown-Tabellen",
      req_metrics: "- Nutze konkrete Kennzahlen und mindestens 2 konkrete Aufgaben aus den Beispielen",
      req_grounded: "- Erfinde keine Felder oder Zahlen, die hier nicht vorkommen",
      none: "(keine)"
    },
    "fr" => {
      title: "Cree un court resume executif base sur ces donnees :",
      overall: "Vue d'ensemble :",
      projects: "Projets :",
      kanban_snapshot: "Instantane Kanban (meme perimetre de projets) :",
      highest_risk: "Taches les plus risquees (top 8) :",
      bucket_examples: "Exemples par groupe (meme perimetre de projets) :",
      active_examples: "Exemples de taches actives",
      overdue_examples: "Exemples de taches en retard",
      stale_7d_examples: "Exemples de taches non mises a jour depuis 7 jours",
      stale_14d_examples: "Exemples de taches non mises a jour depuis 14 jours",
      high_priority_examples: "Exemples de taches ouvertes a priorite elevee",
      ready_to_test_examples: "Exemples de taches pretes a tester",
      to_investigate_examples: "Exemples de taches a investiguer",
      requirements: "Exigences :",
      req_sections: '- 3 sections courtes : "Key findings", "Risks", "Recommended next actions"',
      req_words: "- 220 mots maximum",
      req_bullets: "- Utiliser des puces, sans tableaux markdown",
      req_metrics: "- Citer des mesures concretes et au moins 2 taches specifiques issues des exemples",
      req_grounded: "- Ne pas inventer de champs ou de chiffres absents des donnees",
      none: "(aucune)"
    },
    "es" => {
      title: "Crea un resumen ejecutivo corto basado en estos datos:",
      overall: "Vision general:",
      projects: "Proyectos:",
      kanban_snapshot: "Instantanea kanban (mismo alcance de proyectos):",
      highest_risk: "Tareas de mayor riesgo (top 8):",
      bucket_examples: "Ejemplos por grupo (mismo alcance de proyectos):",
      active_examples: "Ejemplos de tareas activas",
      overdue_examples: "Ejemplos de tareas vencidas",
      stale_7d_examples: "Ejemplos de tareas sin actualizar en 7 dias",
      stale_14d_examples: "Ejemplos de tareas sin actualizar en 14 dias",
      high_priority_examples: "Ejemplos de tareas abiertas de alta prioridad",
      ready_to_test_examples: "Ejemplos de tareas listas para probar",
      to_investigate_examples: "Ejemplos de tareas por investigar",
      requirements: "Requisitos:",
      req_sections: '- 3 secciones cortas: "Key findings", "Risks", "Recommended next actions"',
      req_words: "- Maximo 220 palabras",
      req_bullets: "- Usa vietas, sin tablas markdown",
      req_metrics: "- Incluye metricas concretas y al menos 2 tareas especificas de los ejemplos",
      req_grounded: "- No inventes campos ni cifras que no esten en los datos",
      none: "(ninguna)"
    }
  }.freeze

  def self.call(result:, locale:, model_name: nil)
    new(result: result, locale: locale, model_name: model_name).call
  end

  def initialize(result:, locale:, model_name: nil)
    @result = result
    @locale = locale
    @model_name = model_name
  end

  def call
    llm = OllamaLlmService.new(model_name: @model_name || OllamaLlmService::DEFAULT_MODEL, state_key: "reports")
    response = llm.generate_response(prompt, system_prompt: SYSTEM_PROMPT)
    response.response
  end

  private

  def prompt
    copy = prompt_copy
    summary = @result.summary
    projects = @result.projects_breakdown
    kanban_snapshot = build_kanban_snapshot

    project_lines = projects.first(12).map do |pb|
      statuses = ReportStatsService.sorted_status_breakdown(pb.status_breakdown).map { |name, count| "#{name}: #{count}" }.join(", ")
      "- #{pb.project.title}: tasks=#{pb.total_tasks}, completed=#{pb.completed_count}, incomplete=#{pb.incomplete_count}, completion=#{pb.completion_ratio}%, status=[#{statuses}]"
    end.join("\n")

    <<~PROMPT
      #{copy[:title]}

      #{copy[:overall]}
      - total_tasks: #{summary.total_tasks}
      - completed: #{summary.completed_count}
      - incomplete: #{summary.incomplete_count}
      - completion_ratio: #{summary.completion_ratio}%

      #{copy[:projects]}
      #{project_lines}

      #{copy[:kanban_snapshot]}
      - active_tasks: #{kanban_snapshot[:active_tasks]}
      - overdue_tasks: #{kanban_snapshot[:overdue_tasks]}
      - stale_7d_tasks: #{kanban_snapshot[:stale_7d_tasks]}
      - stale_14d_tasks: #{kanban_snapshot[:stale_14d_tasks]}
      - high_priority_open: #{kanban_snapshot[:high_priority_open]}
      - ready_to_test_count: #{kanban_snapshot[:ready_to_test_count]}
      - to_investigate_count: #{kanban_snapshot[:to_investigate_count]}

      #{copy[:highest_risk]}
      #{kanban_snapshot[:risk_lines]}

      #{copy[:bucket_examples]}
      - #{copy[:active_examples]}: #{kanban_snapshot[:active_examples]}
      - #{copy[:overdue_examples]}: #{kanban_snapshot[:overdue_examples]}
      - #{copy[:stale_7d_examples]}: #{kanban_snapshot[:stale_7d_examples]}
      - #{copy[:stale_14d_examples]}: #{kanban_snapshot[:stale_14d_examples]}
      - #{copy[:high_priority_examples]}: #{kanban_snapshot[:high_priority_examples]}
      - #{copy[:ready_to_test_examples]}: #{kanban_snapshot[:ready_to_test_examples]}
      - #{copy[:to_investigate_examples]}: #{kanban_snapshot[:to_investigate_examples]}

      #{copy[:requirements]}
      #{copy[:req_sections]}
      #{copy[:req_words]}
      #{copy[:req_bullets]}
      #{copy[:req_metrics]}
      #{copy[:req_grounded]}
    PROMPT
  end

  def build_kanban_snapshot
    tasks = Task.not_archived
      .includes(:project, :status)
      .where(project_id: @result.project_ids)

    open_tasks = tasks.where(completed: false)
    now = Time.current

    risk_candidates = open_tasks
      .order(priority_rank_sql => :desc, updated_at: :asc)
      .limit(8)
    stale_7d_scope = open_tasks.where("tasks.updated_at < ?", 7.days.ago)
    stale_14d_scope = open_tasks.where("tasks.updated_at < ?", 14.days.ago)
    ready_scope = open_tasks.joins(:status).where(status: { name: Status.default_statuses[:ready_to_test] })
    investigate_scope = open_tasks.joins(:status).where(status: { name: Status.default_statuses[:to_investigate] })

    {
      active_tasks: open_tasks.count,
      overdue_tasks: open_tasks.where("due_date < ?", now).count,
      stale_7d_tasks: stale_7d_scope.count,
      stale_14d_tasks: stale_14d_scope.count,
      high_priority_open: open_tasks.where(priority: "high").count,
      ready_to_test_count: ready_scope.count,
      to_investigate_count: investigate_scope.count,
      risk_lines: risk_candidates.map { |task| format_risk_task(task, now) }.join("\n"),
      active_examples: format_task_examples(open_tasks.order(updated_at: :desc).limit(TASKS_PER_BUCKET)),
      overdue_examples: format_task_examples(open_tasks.where("due_date < ?", now).order(due_date: :asc).limit(TASKS_PER_BUCKET)),
      stale_7d_examples: format_task_examples(stale_7d_scope.order(updated_at: :asc).limit(TASKS_PER_BUCKET)),
      stale_14d_examples: format_task_examples(stale_14d_scope.order(updated_at: :asc).limit(TASKS_PER_BUCKET)),
      high_priority_examples: format_task_examples(open_tasks.where(priority: "high").order(updated_at: :asc).limit(TASKS_PER_BUCKET)),
      ready_to_test_examples: format_task_examples(ready_scope.order(updated_at: :asc).limit(TASKS_PER_BUCKET)),
      to_investigate_examples: format_task_examples(investigate_scope.order(updated_at: :asc).limit(TASKS_PER_BUCKET))
    }
  end

  def priority_rank_sql
    Arel.sql("CASE tasks.priority WHEN 'high' THEN 4 WHEN 'medium' THEN 3 WHEN 'low' THEN 2 ELSE 1 END")
  end

  def format_risk_task(task, now)
    overdue = task.due_date.present? && task.due_date < now
    due_text = task.due_date.present? ? task.due_date.to_date.iso8601 : "none"
    "- [#{task.project.title}] #{task.title} | status=#{task.status&.name} | priority=#{task.priority} | due=#{due_text} | overdue=#{overdue} | updated=#{task.updated_at.to_date.iso8601}"
  end

  def format_task_examples(tasks)
    return prompt_copy[:none] if tasks.blank?

    tasks.map do |task|
      "[#{task.project.title}] #{task.title} (#{task.status&.name}, #{task.priority})"
    end.join(" || ")
  end

  def prompt_copy
    PROMPT_COPY.fetch(@locale.to_s, PROMPT_COPY["en"])
  end
end
