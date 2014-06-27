require File.dirname(__FILE__) + '/../spec_helper'
include ActiveMerchant::Billing

describe Account do

  fixtures :accounts
  fixtures :subscription_plans
  fixtures :subscription_affiliates

  let(:valid_user) { FactoryGirl.attributes_for(:user) }

  before(:each) do
    @account = accounts(:localhost)
    @plan = subscription_plans(:basic)
    Saas::Config.require_payment_info_for_trials = true
  end

  it 'should be invalid with an missing admin' do
    @account = Account.create(:domain => 'foo')
    @account.errors.full_messages.should include("Admin information is missing")
  end

  it 'should be invalid with an invalid admin' do
    @account = Account.create(:domain => 'foo', :admin_attributes => User.new.attributes.except("account_id"))
    @account.errors.full_messages.should include("Admin password can't be blank")
  end

  it "should set the full domain when created" do
    @account = Account.create(:domain => 'foo', :admin_attributes => valid_user, :plan => subscription_plans(:free))
    @account.full_domain.should == "foo.#{Saas::Config.base_domain}"
  end

  it "should require payment info when being created with a paid plan when the app configuration requires it" do
    @account = Account.new(:domain => 'foo', :admin_attributes => valid_user, :plan => @plan)
    @account.needs_payment_info?.should be_true
  end

  it "should not require payment info when being created with a paid plan when the app configuration does not require it" do
    Saas::Config.require_payment_info_for_trials = false
    @account = Account.new(:domain => 'foo', :admin_attributes => valid_user, :plan => @plan)
    @account.needs_payment_info?.should be_false
  end

  it "should not require payment info when being created with free plan" do
    @account = Account.new(:domain => 'foo', :admin_attributes => valid_user, :plan => subscription_plans(:free))
    @account.needs_payment_info?.should be_false
  end

  it "should create the user when created" do
    lambda do
      @account = Account.create(:domain => 'foo', :admin_attributes => valid_user, :plan => subscription_plans(:free))
    end.should change(User, :count)
  end

  it "should create the subscription when created" do
    lambda do
      @account = Account.create(:domain => 'foo', :admin_attributes => valid_user, :plan => subscription_plans(:free))
    end.should change(Subscription, :count)
    Subscription.last.subscriber.should == @account
  end

  it "should create the subscription with an associated affiliate" do
    @affiliate = subscription_affiliates(:bob)
    lambda do
      @account = Account.new(:domain => 'foo', :admin_attributes => valid_user, :plan => subscription_plans(:free))
      @account.affiliate = @affiliate
      @account.save
    end.should change(Subscription, :count)
    Subscription.last.affiliate.should == @affiliate

  end

  it "should have one admin user when created" do
    @account = Account.create(:domain => 'foo', :admin_attributes => valid_user, :plan => subscription_plans(:free))
    @user = User.last
    @user.account.should == @account
    @user.admin.should be_true
  end

  it "should delegate needs_payment_info? to subscription for existing accounts" do
    @account.subscription.expects(:needs_payment_info?)
    @account.needs_payment_info?
  end

  describe "testing limits" do

    before(:each) do
      @account = Account.create(:domain => 'foo', :plan => subscription_plans(:free))
    end

    it "should indicate the user limit has been reached when the number of active positions equals the user limit" do
      @account.expects(:users).returns([User.new] * @account.subscription.user_limit)
      @account.reached_user_limit?.should be_true
    end

    it "should not indicate the user limit has been reached when the number of active positions is less than the user limit" do
      @account.expects(:users).returns([])
      @account.reached_user_limit?.should_not be_true
    end

    it "should not indicate the user limit has been reached when the account has no user limit" do
      @account.subscription.user_limit = nil
      @account.expects(:users).never
      @account.reached_user_limit?.should_not be_true
    end
  end

  describe "validating domains" do
    before(:each) do
      @account = Account.new
    end

    it "should prevent blank domains" do
      @account.domain = ''
      @account.should_not be_valid
      @account.errors[:domain].should == ['is invalid']
    end

    it "should prevent duplicate domains" do
      FactoryGirl.create(:account, domain: 'foo', admin_attributes: valid_user, plan: subscription_plans(:free))
      @account.domain = 'foo'
      @account.should_not be_valid
      @account.errors[:domain].should == ['is not available']
    end

    it "should prevent bad domain formats" do
      %w(foo.bar foo_bar foo-bar).each do |name|
        @account.domain = name
        @account.should_not be_valid
        @account.errors[:domain].should == ['is invalid']
      end
    end

    it "should not allow the uniqueness check to interfere with updating an account" do
      @account = accounts(:localhost)
      @account.name = 'Blah'
      @account.should be_valid
    end
  end

  describe "when being created with payment info" do
    before(:each) do
      @account = Account.new(:domain => 'foo', :admin_attributes => valid_user, :plan => @plan, :creditcard => @card = CreditCard.new(valid_card), :address => @address = SubscriptionAddress.new(valid_address))
      @account.expects(:build_subscription).with(:plan => @plan, :next_renewal_at => nil, :creditcard => @card, :address => @address, :affiliate => nil).returns(@account.subscription = @subscription = Subscription.new(:plan => @plan, :creditcard => @card, :address => @address))
      @subscription.stubs(:gateway).returns(@gw = BogusGateway.new)

      SubscriptionNotifier.stubs(:welcome).returns(mock('notifier').tap {|m| m.stubs(:deliver) })
    end

    it "should store the CC info with BrainTree and create the account" do
      lambda do
        @account.save.should be_true
      end.should change(Account, :count)
      Account.last.should == @account
    end

    it "should create the subscription" do
      lambda do
        @account.save.should be_true
      end.should change(Subscription, :count)
      Subscription.last.subscriber.should == @account
    end

    it "should report errors when failing to store the CC info with BrainTree" do
      @subscription.stubs(:valid?).returns(false)
      @subscription.errors.expects(:full_messages).returns(["Forced failure"])
      lambda do
         @account.save.should be_false
      end.should_not change(Account, :count)
      @account.errors.full_messages.should == ["Error with payment: Forced failure"]
    end

    it "should log the initial billing, if needed" do
      @gw.stubs(:purchase).returns(Response.new(true, 'Success'))
      @plan.update_attribute(:trial_period, nil)
      lambda do
        @account.save.should be_true
      end.should change(SubscriptionPayment, :count)
      (@sp = SubscriptionPayment.last).subscriber.should == @account
      @sp.subscription.should == @account.subscription
    end
  end

  describe "when checking for a qualifying subscription plan" do
    before(:each) do
      @plan = subscription_plans(:basic)
    end

    describe "against the user limit" do
      before(:each) do
        @plan.user_limit = 3
      end

      it "should qualify if the plan has no user limit" do
        @plan.user_limit = nil
        @account.expects(:users).never
        @account.qualifies_for?(@plan).should be_true
      end

      it "should qualify if the plan has a user limit greater than or equal to the number of users" do
        @account.expects(:users).returns([User.new] * (@plan.user_limit - 1))
        @account.qualifies_for?(@plan).should be_true
        @account.expects(:users).returns([User.new] * @plan.user_limit)
        @account.qualifies_for?(@plan).should be_true
      end

      it "should not qualify if the plan has a user limit less than the number of users" do
        @account.expects(:users).returns([User.new] * (@plan.user_limit + 1))
        @account.qualifies_for?(@plan).should be_false
      end
    end

  end
end
