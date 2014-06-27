# Suppresses deprecation warning by passing :handlers to render options by default
# https://github.com/rspec/rspec-rails/issues/485
module RenderOverrides
  def render(options={}, local_assigns={}, &block)
    options = default_render_options if Hash === options and options.empty?
    super(options, local_assigns, &block)
  end
  
  private
  
  def default_render_options
    view, format, handler = _default_file_to_render.split('.', 3)
    if view and format and handler
      {:template => view, :formats => [format], :handlers => [handler]}
    else
      {:template => _default_file_to_render}
    end
  end
end