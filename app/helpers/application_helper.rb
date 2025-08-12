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

  def markdown(text)
    return '' if text.blank?
    
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: '_blank', rel: 'noopener' }
    )
    
    markdown = Redcarpet::Markdown.new(renderer, {
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true,
      underline: true,
      highlight: true,
      quote: true,
      footnotes: true,
      # Ensure code blocks are properly parsed
      disable_indented_code_blocks: false,
      # More aggressive code block detection
      space_after_headers: false
    })
    
    # Pre-process the text to handle problematic characters in code blocks
    processed_text = preprocess_markdown(text)
    
    markdown.render(processed_text).html_safe
  end
  
  private
  
  # Note: Markdown requires proper spacing around code blocks.
  # Code blocks must be preceded by a blank line to be properly parsed.
  # Example:
  #   Not working: "text```lang\ncode```"
  #   Working: "text\n\n```lang\ncode```"
  def preprocess_markdown(text)
    # Handle code blocks with special characters
    text.gsub(/```(\w+)?\n(.*?)```/m) do |match|
      lang = $1
      code_content = $2
      
      # Escape problematic characters that might interfere with parsing
      # Replace > with HTML entity to prevent blockquote interpretation
      escaped_code = code_content.gsub('>', '&gt;')
      
      # Ensure proper code block formatting
      "```#{lang}\n#{escaped_code}\n```"
    end
  end
  
  # Alternative method for more robust markdown rendering
  # This method automatically handles common markdown formatting issues:
  # - Adds proper spacing around code blocks
  # - Escapes problematic characters in code content
  # - Handles long content better
  def markdown_robust(text)
    return '' if text.blank?
    
    # Use a different approach for problematic content
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: '_blank', rel: 'noopener' }
    )
    
    markdown = Redcarpet::Markdown.new(renderer, {
      autolink: false, # Disable autolink to prevent interference
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true,
      underline: true,
      highlight: true,
      quote: true,
      footnotes: false, # Disable footnotes to prevent interference
      disable_indented_code_blocks: false,
      space_after_headers: false
    })
    
    # More aggressive preprocessing for problematic content
    processed_text = text.dup
    
    # Ensure proper spacing around code blocks
    # Add newlines before code blocks if they don't have them
    processed_text.gsub!(/([^\n])(```\w*\n)/, "\\1\n\n\\2")
    
    # Handle code blocks more carefully
    processed_text.gsub!(/```(\w+)?\n(.*?)```/m) do |match|
      lang = $1 || ''
      code_content = $2
      
      # Escape all potentially problematic characters
      escaped_code = code_content
        .gsub('>', '&gt;')
        .gsub('<', '&lt;')
        .gsub('&', '&amp;')
      
      # Ensure proper formatting
      "```#{lang}\n#{escaped_code}\n```"
    end
    
    markdown.render(processed_text).html_safe
  end
end
