require "test_helper"

class ProjectsViewsTest < ActionView::TestCase
  include ApplicationHelper

  def setup
    @project = projects(:markdown_test_project)
    @task = tasks(:markdown_test_task)
  end

  test "markdown rendering in project show view task descriptions" do
    # Simulate the project show view rendering of task descriptions
    rendered_description = markdown_robust(@task.description)
    
    # Test that markdown is properly rendered
    assert_includes rendered_description, "<strong>Bold text</strong>"
    assert_includes rendered_description, "<em>italic text</em>"
    assert_includes rendered_description, "<code>inline code</code>"
    
    # Test list items
    assert_includes rendered_description, "<ul>"
    assert_includes rendered_description, "<li>List item 1</li>"
    assert_includes rendered_description, "<li>List item 2"
    
    # Test nested list structure
    assert_includes rendered_description, "<ul>"
    assert_includes rendered_description, "<li>Nested item</li>"
    
    # Test code block
    assert_includes rendered_description, "<pre>"
    assert_includes rendered_description, "<code class=\"ruby\">"
    assert_includes rendered_description, "def hello_world"
    assert_includes rendered_description, "puts &quot;Hello, World!&quot;"
    
    # Test blockquote
    assert_includes rendered_description, "<blockquote>"
    assert_includes rendered_description, "<p>This is a blockquote with some important information</p>"
    
    # Test link
    assert_includes rendered_description, "<a href=\"https://example.com\" target=\"_blank\" rel=\"noopener\">Link to example</a>"
  end

  test "project show view renders markdown content correctly" do
    # Test that the markdown content is properly processed
    rendered_description = markdown_robust(@task.description)
    
    # Verify the raw markdown syntax is not present
    assert_not_includes rendered_description, "**Bold text**"
    assert_not_includes rendered_description, "*italic text*"
    assert_not_includes rendered_description, "`inline code`"
    
    # Verify the rendered HTML is present
    assert_includes rendered_description, "<strong>Bold text</strong>"
    assert_includes rendered_description, "<em>italic text</em>"
    assert_includes rendered_description, "<code>inline code</code>"
  end

  test "markdown rendering maintains proper structure" do
    rendered_description = markdown_robust(@task.description)
    
    # Test that the overall structure is maintained
    assert_includes rendered_description, "This task tests various markdown features:"
    
    # Test that lists maintain their structure
    assert_includes rendered_description, "<ul>"
    assert_includes rendered_description, "<li>List item 1</li>"
    assert_includes rendered_description, "<li>List item 2"
    
    # Test that code blocks maintain their structure
    assert_includes rendered_description, "<pre>"
    assert_includes rendered_description, "<code class=\"ruby\">"
    
    # Test that blockquotes maintain their structure
    assert_includes rendered_description, "<blockquote>"
    assert_includes rendered_description, "<p>This is a blockquote with some important information</p>"
  end
end
