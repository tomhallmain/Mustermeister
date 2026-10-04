# The "show completed tasks" toggle is remembered in the session, once for
# the task index and once per project page. The pages themselves write it
# (tasks#index, projects#show, tasks#new); everything here only reads it.
module ShowCompletedPreferences
  extend ActiveSupport::Concern

  included do
    before_action :initialize_show_completed_prefs
  end

  private

  def initialize_show_completed_prefs
    session[:projects_show_completed] ||= {}
    session[:tasks_show_completed] = false if session[:tasks_show_completed].nil?
  end

  # An explicit show_completed param wins over the remembered value.
  def tasks_show_completed_preference
    return params[:show_completed] == 'true' if params[:show_completed].present?

    session[:tasks_show_completed]
  end

  def project_show_completed_preference(project)
    session[:projects_show_completed][project.id.to_s] || false
  end

  # Where to send the user after changing a task: its project's page,
  # or the task index for a task without one, each with its remembered toggle.
  def task_list_path_for(project)
    if project
      project_path(project, show_completed: project_show_completed_preference(project))
    else
      tasks_path(show_completed: session[:tasks_show_completed])
    end
  end
end
