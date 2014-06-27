(function($){
  function stripeResponseHandler(status, response) {
      if (response.error) {
          // insert payment-errors div if necessary
          if ($('.payment-errors')[0] == undefined)
          $("#new_creditcard").prepend($('<div class="errorExplanation payment-errors"></div>'));
          // re-enable the submit button
          $('input[name=commit]').removeAttr("disabled");
          //show the errors on the form
          $(".payment-errors").html('<h2>Errors encountered with your payment:</h2><ul><li>'+response.error.message+'</li></ul>');
      } else {
          var form$ = $("#new_creditcard");
          // token contains id, last4, and card type
          var token = response['id'];
          var cc_digits = response['card']['last4'];
          var cc_exp = response['card']['exp_month']+'-'+response['card']['exp_year'];
          // reset form to prevent billing info from being sent in cleartext
          form$.get(0).reset();
          // insert the token into the form so it gets submitted to the server
          form$.append("<input type='hidden' name='stripeToken' value='" + token + "'/>");
          // and submit
          form$.get(0).submit();
      }
  }
  
  $(document).ready(function() {
    $("#new_creditcard").submit(function(event) {
      // disable the submit button to prevent repeated clicks
      $('input[name=commit]').attr("disabled", "disabled");

      var amount = null; //amount you want to charge in cents
      Stripe.createToken({
        number: $('#creditcard_number').val(),
        cvc: $('#creditcard_verification_value').val(),
        exp_month: $('#creditcard_month').val(),
        exp_year: $('#creditcard_year').val(),
        name: $('#creditcard_first_name').val()+' '+$('#creditcard_last_name').val(),
        address_line1: $('#address_address1').val(),
        address_line2: $('#address_address2').val(),
        address_state: $('#address_state').val(),
        address_zip: $('#address_zip').val(),
        address_country: $('#address_country').val()
      }, amount, stripeResponseHandler);

      // prevent the form from submitting with the default action
      return false;
    });
    
    // Form submit is disabled by default to prevent form submission without javascript
    $("#new_creditcard input[name=commit]").removeAttr('disabled');
  });
})(jQuery);
