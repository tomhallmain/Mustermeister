require 'test_helper'

class I18nTest < ActiveSupport::TestCase
  test "priority translations are available" do
    assert_equal 'Leisure', I18n.t('priorities.leisure')
    assert_equal 'Low', I18n.t('priorities.low')
    assert_equal 'Medium', I18n.t('priorities.medium')
    assert_equal 'High', I18n.t('priorities.high')
  end

  test "status translations are available" do
    assert_equal 'Not Started', I18n.t('statuses.not_started')
    assert_equal 'To Investigate', I18n.t('statuses.to_investigate')
    assert_equal 'Investigated', I18n.t('statuses.investigated')
    assert_equal 'In Progress', I18n.t('statuses.in_progress')
    assert_equal 'Ready to Test', I18n.t('statuses.ready_to_test')
    assert_equal 'Complete', I18n.t('statuses.complete')
    assert_equal 'Closed', I18n.t('statuses.closed')
  end

  test "non-english priority and status translations are loaded" do
    I18n.with_locale(:de) do
      assert_equal 'Mittel', I18n.t('priorities.medium')
      assert_equal 'In Bearbeitung', I18n.t('statuses.in_progress')
    end

    I18n.with_locale(:fr) do
      assert_equal 'Moyen', I18n.t('priorities.medium')
      assert_equal 'En cours', I18n.t('statuses.in_progress')
    end

    I18n.with_locale(:es) do
      assert_equal 'Medio', I18n.t('priorities.medium')
      assert_equal 'En curso', I18n.t('statuses.in_progress')
    end
  end

  test "task result translations are available" do
    assert_equal 'Complete', I18n.t('task_results.values.complete')
    assert_equal 'Incomplete', I18n.t('task_results.values.incomplete')
  end

  test "task model translations are available" do
    assert_equal 'Task', I18n.t('activerecord.models.task.one')
    assert_equal 'Tasks', I18n.t('activerecord.models.task.other')
    assert_equal 'Title', I18n.t('activerecord.attributes.task.title')
    assert_equal 'Description', I18n.t('activerecord.attributes.task.description')
    assert_equal 'Priority', I18n.t('activerecord.attributes.task.priority')
    assert_equal 'Status', I18n.t('activerecord.attributes.task.status')
    assert_equal 'Due Date', I18n.t('activerecord.attributes.task.due_date')
  end

  test "project model translations are available" do
    assert_equal 'Project', I18n.t('activerecord.models.project.one')
    assert_equal 'Projects', I18n.t('activerecord.models.project.other')
    assert_equal 'Title', I18n.t('activerecord.attributes.project.title')
    assert_equal 'Description', I18n.t('activerecord.attributes.project.description')
    assert_equal 'Default Priority', I18n.t('activerecord.attributes.project.default_priority')
    assert_equal 'Due Date', I18n.t('activerecord.attributes.project.due_date')
  end

  test "task priority display method works" do
    task = Task.new(priority: 'high')
    assert_equal 'High', task.priority_display
  end

  test "task status display method works" do
    task = tasks(:one)
    task.status = statuses(:project_one_not_started)
    assert_equal 'Not Started', task.status_display
  end

  test "project default priority display method works" do
    project = Project.new(default_priority: 'medium')
    assert_equal 'Medium', project.default_priority_display
  end

  test "application translations are available" do
    assert_equal 'Mustermeister', I18n.t('application.title')
    assert_equal 'Task and Project Management', I18n.t('application.tagline')
    assert_equal 'Tasks', I18n.t('application.navigation.tasks')
    assert_equal 'Projects', I18n.t('application.navigation.projects')
  end
end
