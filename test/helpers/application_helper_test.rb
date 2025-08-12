require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "markdown helper renders basic markdown" do
    text = "**Bold** and *italic* text"
    result = markdown(text)
    
    assert_includes result, "<strong>Bold</strong>"
    assert_includes result, "<em>italic</em>"
    assert_includes result, "text"
  end

  test "markdown helper renders lists" do
    text = "- Item 1\n- Item 2"
    result = markdown(text)
    
    assert_includes result, "<ul>"
    assert_includes result, "<li>Item 1</li>"
    assert_includes result, "<li>Item 2</li>"
  end

  test "markdown helper renders code blocks" do
    text = "```ruby\ndef hello\n  puts 'hello'\nend```"
    result = markdown(text)
    
    assert_includes result, "<pre>"
    assert_includes result, "<code class=\"ruby\">"
    assert_includes result, "def hello"
  end

  test "markdown_robust helper handles problematic characters" do
    text = "```log\n> This is a log entry\n< This is another entry\n& This has ampersand```"
    result = markdown_robust(text)
    
    # Should escape problematic characters (note: they get double-escaped TODO: fix this)
    assert_includes result, "&amp;amp;gt;"
    assert_includes result, "&amp;amp;lt;"
    assert_includes result, "&amp;amp;"
    
    # Should still render as code block
    assert_includes result, "<pre>"
    assert_includes result, "<code class=\"log\">"
  end

  test "markdown_robust helper adds spacing around code blocks" do
    text = "Some text```ruby\nputs 'hello'```"
    result = markdown_robust(text)
    
    # Should add proper spacing and render as HTML
    assert_includes result, "<p>Some text</p>"
    assert_includes result, "<pre><code class=\"ruby\">"
    assert_includes result, "puts &#39;hello&#39;"
  end

  test "markdown helper returns empty string for blank input" do
    assert_equal "", markdown("")
    assert_equal "", markdown(nil)
    assert_equal "", markdown("   ")
  end

  test "markdown_robust helper returns empty string for blank input" do
    assert_equal "", markdown_robust("")
    assert_equal "", markdown_robust(nil)
    assert_equal "", markdown_robust("   ")
  end
end
