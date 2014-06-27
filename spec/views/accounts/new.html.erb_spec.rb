require File.dirname(__FILE__) + '/../../spec_helper'

describe "/accounts/new.html.erb" do

  fixtures :users, :accounts, :subscription_plans

  it "should omit the credit card form when creating a free account" do
    assign(:plan, @plan = subscription_plans(:free))
    assign(:account, Account.new(:plan => @plan))
    render
    rendered.should_not have_selector('input', :name => 'creditcard[first_name]')
  end

  it "should include the credit card form when creating a paid account (payment is collected post-signup)" do
    assign(:plan, @plan = subscription_plans(:basic))
    assign(:creditcard, @card = ActiveMerchant::Billing::CreditCard.new)
    assign(:address, @address = SubscriptionAddress.new)
    assign(:account, @account = Account.new(:plan => @plan))
    @account.stubs(:needs_payment_info?).returns(true)
    render
    rendered.should_not have_selector('input', :name => 'creditcard[first_name]')
  end

  it "should omit the credit card form when creating a paid account without payment info required up-front" do
    Saas::Config.require_payment_info_for_trials = false
    assign(:plan, @plan = subscription_plans(:basic))
    assign(:creditcard, @card = ActiveMerchant::Billing::CreditCard.new)
    assign(:address, @address = SubscriptionAddress.new)
    assign(:account, @account = Account.new(:plan => @plan))
    @account.stubs(:needs_payment_info?).returns(false)
    render
    rendered.should_not have_selector('input', :name => 'creditcard[first_name]')
  end
end
