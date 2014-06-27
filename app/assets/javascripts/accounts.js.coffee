$ ->
  subdomain = $("#subdomain")
  $("body.accounts form.new_account #account_domain").on "keyup", ->
    subdomain.html($(this).val())
