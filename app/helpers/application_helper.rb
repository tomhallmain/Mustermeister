module ApplicationHelper
  def toast_notice(message, auto_dismiss: true, dismiss_delay: 15000)
    content_tag :div, class: "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mt-4",
                      data: { 
                        controller: "toast",
                        toast_auto_dismiss_value: auto_dismiss,
                        toast_dismiss_delay_value: dismiss_delay
                      } do
      content_tag :div, class: "bg-green-50 border-l-4 border-green-400 p-3 rounded-md transition-all duration-150 ease-in-out" do
        content_tag :div, class: "flex items-center justify-between" do
          content_tag(:div, class: "flex items-center") do
            concat(
              content_tag(:div, class: "flex-shrink-0") do
                content_tag(:svg, class: "h-4 w-4 text-green-400", viewBox: "0 0 20 20", fill: "currentColor") do
                  content_tag(:path, "", fill_rule: "evenodd", d: "M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z", clip_rule: "evenodd")
                end
              end
            )
            concat(
              content_tag(:div, class: "ml-2") do
                content_tag(:p, message, class: "text-xs text-green-700")
              end
            )
          end +
          content_tag(:button, class: "text-green-400 hover:text-green-600 ml-2", data: { action: "click->toast#dismiss" }) do
            content_tag(:svg, class: "h-4 w-4", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
              content_tag(:path, "", stroke_linecap: "round", stroke_linejoin: "round", stroke_width: "2", d: "M6 18L18 6M6 6l12 12")
            end
          end
        end
      end
    end
  end

  def toast_alert(message, auto_dismiss: true, dismiss_delay: 15000)
    content_tag :div, class: "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mt-4",
                      data: { 
                        controller: "toast",
                        toast_auto_dismiss_value: auto_dismiss,
                        toast_dismiss_delay_value: dismiss_delay
                      } do
      content_tag :div, class: "bg-red-50 border-l-4 border-red-400 p-3 rounded-md transition-all duration-150 ease-in-out" do
        content_tag :div, class: "flex items-center justify-between" do
          content_tag(:div, class: "flex items-center") do
            concat(
              content_tag(:div, class: "flex-shrink-0") do
                content_tag(:svg, class: "h-4 w-4 text-red-400", viewBox: "0 0 20 20", fill: "currentColor") do
                  content_tag(:path, "", fill_rule: "evenodd", d: "M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z", clip_rule: "evenodd")
                end
              end
            )
            concat(
              content_tag(:div, class: "ml-2") do
                content_tag(:p, message, class: "text-xs text-red-700")
              end
            )
          end +
          content_tag(:button, class: "text-red-400 hover:text-red-600 ml-2", data: { action: "click->toast#dismiss" }) do
            content_tag(:svg, class: "h-4 w-4", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
              content_tag(:path, "", stroke_linecap: "round", stroke_linejoin: "round", stroke_width: "2", d: "M6 18L18 6M6 6l12 12")
            end
          end
        end
      end
    end
  end

  # Opening fence with an optional info string (e.g. "ruby", "c++"), up to the
  # next ``` that closes it.
  FENCED_CODE_BLOCK = /```([^`\n]*)\n(.*?)```/m

  def markdown(text)
    render_markdown(text, autolink: true, footnotes: true)
  end

  # Used for user- and LLM-written content (task descriptions, comments, task
  # insights answers). Bare URLs are not turned into links and footnote syntax
  # is not processed.
  def markdown_robust(text)
    render_markdown(text, autolink: false, footnotes: false)
  end

  private

  def render_markdown(text, autolink:, footnotes:)
    return '' if text.blank?

    # escape_html: the result is marked html_safe, so raw HTML in the source is
    # shown as text. safe_links_only: drops links with schemes such as
    # "javascript:".
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      escape_html: true,
      safe_links_only: true,
      link_attributes: { target: '_blank', rel: 'noopener' }
    )

    markdown = Redcarpet::Markdown.new(renderer, {
      autolink: autolink,
      footnotes: footnotes,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true,
      underline: true,
      # "file_name_v2" must not open an underline. Otherwise Redcarpet can close
      # it on an underscore inside a later `code span`, which breaks the
      # pairing of every backtick after it.
      no_intra_emphasis: true,
      highlight: true,
      quote: true,
      disable_indented_code_blocks: false,
      space_after_headers: false
    })

    markdown.render(normalize_code_fences(text)).html_safe
  end

  # Redcarpet only recognizes an opening fence at the start of a line and a
  # closing fence alone on its line, but content can contain "text```ruby" and
  # "end```". This moves such fences onto their own lines, keeping the opening
  # fence's indentation (e.g. inside a list) for the closing fence. Code content
  # is left unescaped; Redcarpet escapes it when rendering.
  def normalize_code_fences(text)
    text.gsub(FENCED_CODE_BLOCK) do
      match = Regexp.last_match
      text_before_on_line = match.pre_match[/[^\n]*\z/]
      if text_before_on_line.strip.empty?
        separator = ""
        indent = text_before_on_line
      else
        separator = "\n\n"
        indent = ""
      end
      code = match[2].sub(/\n?[ \t]*\z/, "")

      "#{separator}```#{match[1].strip}\n#{code}\n#{indent}```\n"
    end
  end
end
