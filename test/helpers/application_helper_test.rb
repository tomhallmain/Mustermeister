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
    
    # Escaped exactly once, so the browser shows the original characters
    assert_includes result, "&gt; This is a log entry"
    assert_includes result, "&lt; This is another entry"
    assert_includes result, "&amp; This has ampersand"
    refute_includes result, "&amp;gt;"
    refute_includes result, "&amp;lt;"
    refute_includes result, "&amp;amp;"

    # Should still render as code block
    assert_includes result, "<pre>"
    assert_includes result, "<code class=\"log\">"
  end

  test "markdown_robust keeps underscores inside words and code spans literal" do
    text = "See: `List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words_V2` under sd-runner_sus\n" \
           "See: `Sperrliste_mehrsprachige_Musterkennung_hinzufügen.md`\n" \
           "See: `multilingual_content_moderation_spec.md`"
    result = markdown_robust(text)

    assert_includes result, "<code>List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words_V2</code> under sd-runner_sus"
    assert_includes result, "<code>Sperrliste_mehrsprachige_Musterkennung_hinzufügen.md</code>"
    assert_includes result, "<code>multilingual_content_moderation_spec.md</code>"
    refute_includes result, "<u>"
  end

  test "markdown_robust still underlines standalone underscore emphasis" do
    assert_includes markdown_robust("some _underlined_ text"), "<u>underlined</u>"
  end

  test "markdown_robust escapes raw HTML" do
    result = markdown_robust("Hello <script>alert(1)</script> <img src=x onerror=alert(1)>")

    refute_includes result, "<script>"
    refute_includes result, "<img"
    assert_includes result, "&lt;script&gt;"
  end

  test "markdown_robust does not render javascript links" do
    result = markdown_robust("[click](javascript:alert(1))")

    refute_includes result, "href=\"javascript:"
  end

  test "markdown_robust does not add a blank line at the end of code blocks" do
    result = markdown_robust("```ruby\nputs 1\n```")

    assert_includes result, "puts 1\n</code>"
    refute_includes result, "puts 1\n\n</code>"
  end

  test "markdown_robust pairs code fences whose info string is not a plain word" do
    text = "```c++\nint x;\n```\n\nBetween blocks\n\n```ruby\nputs 1\n```"
    result = markdown_robust(text)

    assert_includes result, "int x;"
    assert_includes result, "<p>Between blocks</p>"
    assert_includes result, "<code class=\"ruby\">puts 1"
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
