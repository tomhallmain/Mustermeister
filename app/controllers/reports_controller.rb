# frozen_string_literal: true

class ReportsController < ApplicationController
  REPORT_CONFIG_SESSION_KEY = "report_config"

  AVAILABLE_STATS = %w[
    total_tasks
    complete_incomplete
    status_breakdown
  ].freeze

  SORT_BY_OPTIONS = %w[total_tasks completion_ratio name].freeze
  SORT_DIRECTIONS = %w[asc desc].freeze

  def index
    @projects = current_user.projects.order(:title)
    @available_stats = AVAILABLE_STATS
    # Pre-fill from session when returning from analysis (or from params for backwards compatibility)
    @selected_project_ids = report_config_project_ids
    @selected_stats = report_config_stats
  end

  def set_config
    project_ids = (params[:project_ids] || []).reject(&:blank?).map(&:to_i)
    stats = (params[:stats] || []) & AVAILABLE_STATS
    stats = AVAILABLE_STATS.dup if stats.empty?
    session[REPORT_CONFIG_SESSION_KEY] = {
      "project_ids" => project_ids,
      "stats" => stats
    }
    redirect_format = params[:redirect_format].to_s == "pdf" ? :pdf : nil
    redirect_to reports_analysis_path(format: redirect_format)
  end

  def analysis
    # Use session when URL has no report params (short URL); params still supported for backwards compatibility
    project_ids = params[:project_ids].present? ? params[:project_ids].reject(&:blank?).map(&:to_i) : report_config_project_ids
    stats_to_show = params[:stats].present? ? (params[:stats] & AVAILABLE_STATS) : report_config_stats
    stats_to_show = AVAILABLE_STATS.dup if stats_to_show.empty?
    sort_by = SORT_BY_OPTIONS.include?(params[:sort_by]) ? params[:sort_by] : "total_tasks"
    sort_direction = SORT_DIRECTIONS.include?(params[:sort_direction]) ? params[:sort_direction] : "desc"

    @projects_scope = current_user.projects
    @result = ReportStatsService.call(@projects_scope, project_ids: project_ids.presence)
    @result.projects_breakdown.sort! do |a, b|
      ka = sort_key_for(a, sort_by)
      kb = sort_key_for(b, sort_by)
      cmp = ka <=> kb
      sort_direction == "desc" ? -cmp : cmp
    end

    @stats_to_show = stats_to_show
    @selected_project_ids = project_ids || []
    @selected_stats = stats_to_show
    @sort_by = sort_by
    @sort_direction = sort_direction

    respond_to do |format|
      format.html
      format.pdf do
        send_data render_pdf,
                  filename: pdf_filename,
                  type: "application/pdf",
                  disposition: "attachment"
      end
    end
  end

  private

  def render_pdf
    Prawn::Document.new do |pdf|
      pdf.text I18n.t("views.reports.analysis.title"), size: 18, style: :bold
      pdf.move_down 12

      ps = @result.projects_summary
      pdf.text I18n.t("views.reports.analysis.projects_summary"), size: 14, style: :bold
      pdf.move_down 6
      pdf.text I18n.t("views.reports.analysis.total_projects") + ": #{ps.total_projects}"
      pdf.text I18n.t("views.reports.analysis.complete_projects") + ": #{ps.complete_projects_count}"
      pdf.text I18n.t("views.reports.analysis.incomplete_projects") + ": #{ps.incomplete_projects_count}"
      pdf.text I18n.t("views.reports.analysis.project_completion_ratio") + ": #{ps.project_completion_ratio}%"
      pdf.move_down 12

      summary = @result.summary
      pdf.text I18n.t("views.reports.analysis.summary"), size: 14, style: :bold
      pdf.move_down 6
      pdf.text I18n.t("views.reports.analysis.total_tasks") + ": #{summary.total_tasks}"
      pdf.text I18n.t("views.reports.analysis.completed") + ": #{summary.completed_count}"
      pdf.text I18n.t("views.reports.analysis.incomplete") + ": #{summary.incomplete_count}"
      pdf.text I18n.t("views.reports.analysis.completion_ratio") + ": #{summary.completion_ratio}%"
      if @stats_to_show.include?("status_breakdown") && summary.status_breakdown.any?
        pdf.move_down 6
        pdf.text I18n.t("views.reports.analysis.by_status"), size: 12, style: :bold
        ReportStatsService.sorted_status_breakdown(summary.status_breakdown).each do |name, count|
          pdf.text "  #{name}: #{count}"
        end
      end
      pdf.move_down 16

      pdf.text I18n.t("views.reports.analysis.by_project"), size: 14, style: :bold
      pdf.move_down 6
      @result.projects_breakdown.each do |pb|
        pdf.text pb.project.title, style: :bold
        pdf.text "  #{I18n.t('views.reports.analysis.total_tasks')}: #{pb.total_tasks}, " \
                 "#{I18n.t('views.reports.analysis.completed')}: #{pb.completed_count}, " \
                 "#{I18n.t('views.reports.analysis.completion_ratio')}: #{pb.completion_ratio}%"
        if @stats_to_show.include?("status_breakdown") && pb.status_breakdown.any?
          ReportStatsService.sorted_status_breakdown(pb.status_breakdown).each { |name, count| pdf.text "    #{name}: #{count}" }
        end
        pdf.move_down 8
      end
    end.render
  end

  def pdf_filename
    "mustermeister-report-#{Time.current.strftime('%Y%m%d-%H%M')}.pdf"
  end

  def sort_key_for(pb, sort_by)
    case sort_by
    when "total_tasks" then pb.total_tasks
    when "completion_ratio" then pb.completion_ratio
    when "name" then pb.project.title.to_s.downcase
    else pb.total_tasks
    end
  end

  def report_config_project_ids
    ids = session.dig(REPORT_CONFIG_SESSION_KEY, "project_ids")
    ids.present? ? ids.map(&:to_i) : []
  end

  def report_config_stats
    stats = session.dig(REPORT_CONFIG_SESSION_KEY, "stats")
    stats.present? ? (stats & AVAILABLE_STATS) : AVAILABLE_STATS.dup
  end
end
