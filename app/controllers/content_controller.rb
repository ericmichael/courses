# This controller is used to serve (mostly) static pages that are
# the front-end of your site.  For example, the index action is your landing
# page.
class ContentController < ApplicationController
  skip_before_filter :authenticate_user!
  skip_before_filter :collect_billing_info
end
