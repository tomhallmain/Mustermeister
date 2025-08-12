require "test_helper"

class TasksViewsTest < ActionView::TestCase
  include ApplicationHelper

  def setup
    @task = tasks(:markdown_test_task)
  end

  test "markdown rendering in task show view" do
    # Simulate the task show view rendering
    rendered_description = markdown_robust(@task.description)
    
    # Test that markdown is properly rendered
    assert_includes rendered_description, "<strong>Bold text</strong>"
    assert_includes rendered_description, "<em>italic text</em>"
    
    # Test list items
    assert_includes rendered_description, "<ul>"
    assert_includes rendered_description, "<li>List item 1</li>"
    assert_includes rendered_description, "<li>List item 2"
    
    # Test nested list
    assert_includes rendered_description, "<ul>"
    assert_includes rendered_description, "<li>Nested item</li>"
    assert_includes rendered_description, "</ul>"
    
    # Test inline code
    assert_includes rendered_description, "<code>inline code</code>"
    
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

  test "markdown rendering in tasks index view" do
    # Simulate the tasks index view rendering
    rendered_description = markdown_robust(@task.description)
    
    # Test that key markdown elements are rendered
    assert_includes rendered_description, "<strong>Bold text</strong>"
    assert_includes rendered_description, "<em>italic text</em>"
    assert_includes rendered_description, "<code>inline code</code>"
    
    # Test that prose class would be applied in the view
    # (This is tested in the system tests for actual HTML rendering)
  end

  test "markdown content is properly escaped and safe" do
    # Test that the output is HTML safe
    rendered_description = markdown_robust(@task.description)
    assert rendered_description.html_safe?
    
    # Test that problematic characters are handled
    # The markdown processor escapes quotes in code blocks
    assert_includes rendered_description, "&quot;"
    
    # Test that the output contains expected HTML structure
    assert_includes rendered_description, "<strong>Bold text</strong>"
    assert_includes rendered_description, "<em>italic text</em>"
  end
end
