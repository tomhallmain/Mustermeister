module ProjectsHelper
  # Renders one project's current value for a MergeProjectsService::MERGEABLE_FIELDS
  # field, for the merge picker's side-by-side radio comparison.
  def merge_field_display_value(project, field)
    case field
    when 'default_priority'
      project.default_priority.present? ? project.default_priority_display : t('views.projects.merge.blank_value')
    when 'default_category_id'
      project.default_category&.display_name || t('views.projects.merge.blank_value')
    when 'due_date'
      project.due_date&.strftime('%b %d, %Y') || t('views.projects.merge.blank_value')
    when 'color'
      project.color.present? ? project.color_display : t('views.projects.merge.blank_value')
    else
      project.public_send(field).presence || t('views.projects.merge.blank_value')
    end
  end
end
