module ApplicationHelper
  # Render a submit button and cancel link
  def submit_or_cancel(cancel_url = session[:return_to] ? session[:return_to] : url_for(:action => 'index'), label = 'Save Changes', submit_html_options = {})
    submit_html_options.merge!({ :class => "btn btn-primary" })
    raw(content_tag(:div, submit_tag(label, submit_html_options) + ' or ' +
      link_to('Cancel', cancel_url), :id => 'submit_or_cancel', :class => 'submit'))
  end
end
