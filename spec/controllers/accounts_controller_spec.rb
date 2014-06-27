require File.dirname(__FILE__) + '/../spec_helper'
include ActiveMerchant::Billing

describe AccountsController do

  fixtures :accounts, :users, :subscriptions, :subscription_plans, :subscription_discounts

  before(:each) do
    controller.stubs(:current_account).returns(@account = accounts(:localhost))
    @plan = subscription_plans(:basic).name
    @admin = @account.users.where(:admin => true).first
  end

  describe "creating a new account" do
    before(:each) do
      @user = User.new(@user_params = { 'email' => 'foo@foo.com', 'password' => 'password', 'password_confirmation' => 'password' })
      @account = Account.new(@acct_params = { 'name' => 'Bob', 'domain' => 'Bob', 'admin_attributes' => @user_params })
      @account.expects(:admin).returns(@user)
      @account.expects(:save).returns(true)
      Account.expects(:new).with(@acct_params).returns(@account)
    end

    it "should create one" do
      post :create, :account => @acct_params, :plan => @plan
      response.should redirect_to(thanks_url)
      flash[:domain].should == @account.domain
    end

    it "should save the affiliate specified by the cookie with the subscription" do
      SubscriptionAffiliate.expects(:find_by_token).returns(@aff = SubscriptionAffiliate.new)
      @account.expects(:affiliate=).with(@aff)
      request.cookies['affiliate'] = CGI::Cookie.new('name' => 'affiliate', 'value' => 'foo')
      post :create, :account => @acct_params, :plan => @plan
    end

    it "should not attempt to load an affiliate if the affiliate cookie is empty" do
      SubscriptionAffiliate.expects(:find_with_token).never
      post :create, :account => @acct_params, :plan => @plan
    end
  end

  describe "plan list" do
    it "should list plans with the most expensive first" do
      get :plans
      assigns(:plans).should == SubscriptionPlan.order('amount desc')
    end

    it "should apply a discount to plans, if supplied" do
      @discount = subscription_discounts(:sub)
      get :plans, :discount => @discount.code
      assigns(:plans).first.discount.should == @discount
    end
  end

  describe "loading the account creation page" do
    before(:each) do
      @plan = subscription_plans(:basic)
      get :new, :plan => @plan.name
    end

    it "should load the plan by name" do
      assigns(:plan).should == @plan
    end

    it "should apply a discount to the plan, if supplied" do
      @discount = subscription_discounts(:sub)
      get :new, :plan => @plan.name, :discount => @discount.code
      assigns(:plan).discount.should == @discount
    end
  end

  describe "starting account creation with affiliates" do
    before(:each) do
      @plan = SubscriptionPlan.first.name
    end

    it "should set an affiliate cookie when loaded with an affiliate url" do
      SubscriptionAffiliate.expects(:find_by_token).with('foo').returns(SubscriptionAffiliate.new(:name => 'Foo', :token => 'foo', :rate => 0.10))
      get :new, :plan => @plan, :ref => 'foo'
      response.cookies['affiliate'].should == 'foo'
    end

    it "should not set an affiliate cookie when loaded with an affiliate url with an invalid token" do
      SubscriptionAffiliate.expects(:find_by_token).with('foo').returns(nil)
      get :new, :plan => @plan, :ref => 'foo'
      response.cookies['affiliate'].should be_nil
    end

    it "should not set an affiliate cookie when no affiliate info is specified in the url" do
      get :new, :plan => @plan
      response.cookies['affiliate'].should be_nil
    end
  end

  describe 'updating an existing account' do
    it 'should prevent a non-admin from updating' do
      sign_in @account.users.where(:admin => false).first
      @account.expects(:update_attributes).never
      put :update, :account => { :name => 'Foo' }
      response.should redirect_to(new_user_session_url)
    end

    it 'should allow an admin to update' do
      sign_in @admin
      @account.expects(:update_attributes).with('name' => 'Foo').returns(true)
      put :update, :account => { :name => 'Foo' }
      response.should redirect_to(account_url)
    end
  end

  describe "changing a plan" do
    before(:each) do
      sign_in @admin
      @subscription = @account.subscription
    end

    it "should apply the existing discount to the plans in the plan list" do
      @subscription.stubs(:discount).returns(@discount = subscription_discounts(:sub))
      get :plan
      assigns(:plans).first.discount.should == @discount
    end

    it "should change the plan when submitted" do
      SubscriptionPlan.expects(:find).with('24').returns(@plan = SubscriptionPlan.new)
      @subscription.expects(:plan=).with(@plan)
      @subscription.expects(:save).returns(true)
      SubscriptionNotifier.expects(:plan_changed).returns(mock('notifier').tap {|m| m.expects(:deliver) })
      post :plan, :plan_id => '24'
    end

  end

  describe "updating billing info" do
    before(:each) do
      sign_in @admin
    end

    it "should store the card when it and the address are valid" do
      CreditCard.stubs(:new).returns(@card = mock('CreditCard', :valid? => true, :first_name => 'Bo', :last_name => 'Peep'))
      SubscriptionAddress.stubs(:new).returns(@address = mock('SubscriptionAddress', :valid? => true, :to_activemerchant => 'foo'))
      @address.expects(:first_name=).with('Bo')
      @address.expects(:last_name=).with('Peep')
      @account.subscription.expects(:store_card).with(@card, :billing_address => 'foo', :ip => '0.0.0.0').returns(true)
      post :billing, :creditcard => {}, :address => {}
    end

    describe "with stripe" do
      it "should store the token" do
        token = 'asdf'
        @account.subscription.expects(:store_card).with(token).returns(true)
        post :billing, :stripeToken => token
      end
    end

  end

  describe "when canceling" do
    before(:each) do
      sign_in @admin
    end

    it "should not destroy the account without confirmation" do
      @account.expects(:destroy).never
      post :cancel
      response.should render_template('cancel')
    end

    it "should destroy the account" do
      @account.expects(:destroy).returns(true)
      post :cancel, :confirm => 1
      response.should redirect_to('/account/canceled')
    end

    it "should log out the user" do
      @account.stubs(:destroy).returns(true)
      controller.expects(:sign_out).with(:user)
      post :cancel, :confirm => 1
    end
  end
end
