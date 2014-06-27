require File.dirname(__FILE__) + '/../../spec_helper'

describe "/accounts/billing.html.erb" do

  fixtures :users, :accounts

  before(:each) do
    assign(:account, @account = accounts(:localhost))
    assign(:subscription, @account.subscription)
    assign(:creditcard, ActiveMerchant::Billing::CreditCard.new)
    assign(:address, SubscriptionAddress.new)
  end
  
  it 'should have a form for billing information' do
    render
    rendered.should have_selector("form", :action => billing_account_path)
  end
  
  it "should initially disable input when gateway is stripe and stripe_publishable_key is set" do
    Saas::Config.gateway = 'stripe'
    Saas::Config.credentials['stripe_publishable_key'] = 'bar'
    render
    rendered.should have_selector('input[name="commit"]') do |submit|
      submit.first.attributes.keys.should include('disabled')
    end
  end
end
