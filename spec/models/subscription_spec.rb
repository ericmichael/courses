require File.dirname(__FILE__) + '/../spec_helper'
include ActiveMerchant::Billing

describe Subscription do

  fixtures :subscription_plans
  fixtures :subscription_affiliates
  fixtures :subscription_discounts
  fixtures :subscriptions
  fixtures :accounts

  before(:each) do
    @basic = subscription_plans(:basic)
  end

  it "should be created as a trial by default" do
    s = Subscription.new(:plan => @basic)
    s.state.should == 'trial'
  end

  it "should be created as active with plans that are free" do
    @basic.amount = 0
    s = Subscription.new(:plan => @basic)
    s.state.should == 'active'
  end

  it "should be created with a renewal date a month from now by default" do
    s = Subscription.create(:plan => @basic)
    s.next_renewal_at.localtime.at_midnight.should == Time.now.advance(:months => 1).at_midnight
  end

  it "should be created with a specified renewal date" do
    s = Subscription.create(:plan => @basic, :next_renewal_at => 1.day.from_now)
    s.next_renewal_at.localtime.at_midnight.should == Time.now.advance(:days => 1).at_midnight
  end

  it "should return the amount in pennies" do
    s = Subscription.new(:amount => 10)
    s.amount_in_pennies.should == 1000
  end

  it "should set values from the assigned plan" do
    s = Subscription.new(:plan => @basic)
    s.amount.should == @basic.amount
    s.user_limit.should == @basic.user_limit
  end

  it "should need payment info when no card is saved and the plan is not free" do
    Subscription.new(:plan => @basic).needs_payment_info?.should be_true
  end

  it "should not need payment info when the card is saved and the plan is not free" do
    Subscription.new(:plan => @basic, :card_number => 'foo').needs_payment_info?.should be_false
  end

  it "should not need payment info when no card is saved but the plan is free" do
    @basic.amount = 0
    Subscription.new(:plan => @basic).needs_payment_info?.should be_false
  end

  it "should find expiring trial subscriptions" do
    Subscription.expects(:find).with(:all, :include => :subscriber,
      :conditions => { :state => 'trial', :next_renewal_at => (7.days.from_now.beginning_of_day .. 7.days.from_now.end_of_day) })
    Subscription.find_expiring_trials
  end

  it "should find active subscriptions needing payment" do
    Subscription.expects(:find).with(:all, :include => :subscriber,
      :conditions => { :state => 'active', :next_renewal_at => (Time.now.beginning_of_day .. Time.now.end_of_day) })
    Subscription.find_due
  end

  it "should find active subscriptions needing payment in the past" do
    Subscription.expects(:find).with(:all, :include => :subscriber,
      :conditions => { :state => 'active', :next_renewal_at => (2.days.ago.beginning_of_day .. 2.days.ago.end_of_day) })
    Subscription.find_due(2.days.ago)
  end

  describe "when assigned a discounted plan" do
    before(:each) do
      @basic.discount.should be_nil
      @basic_amount = @basic.amount
      @basic.discount = SubscriptionDiscount.new(:code => 'foo', :amount => 2)
    end

    it "should set the amount based on the discounted plan amount" do
      s = Subscription.new(valid_subscription)
      s.amount.should == @basic_amount - 2
    end

    it "should set the amount based on the account discount, if present" do
      s = Subscription.new(:discount => SubscriptionDiscount.new(:code => 'bar', :amount => 3))
      s.plan = @basic
      s.amount.should == @basic_amount - 3
    end

    it "should set the amount based on the plan discount, if larger than the account discount" do
      s = Subscription.new(:discount => SubscriptionDiscount.new(:code => 'bar', :amount => 1))
      s.plan = @basic
      s.amount.should == @basic_amount - 2
    end

  end

  describe "when being created" do
    before(:each) do
      @sub = Subscription.new(:plan => @basic)
    end

    describe "without a credit card" do
      it "should not include card storage in the validation" do
        @sub.expects(:store_card).never
        @sub.should be_valid
      end
    end

    describe "with a credit card" do
      before(:each) do
        @sub.creditcard = @card = CreditCard.new(valid_card)
        @sub.address = @address = SubscriptionAddress.new(valid_address)
        @sub.stubs(:gateway).returns(@gw = ActiveMerchant::Billing::Base.gateway(:bogus).new)
      end

      it "should include card storage in the validation" do
        @sub.expects(:store_card).with(@card, :billing_address => @address.to_activemerchant).returns(true)
        @sub.should be_valid
      end

      it "should not be valid if the card storage fails" do
        @gw.expects(:store).returns(Response.new(false, 'Forced failure'))
        @sub.should_not be_valid
        @sub.errors.full_messages.should include('Forced failure')
      end

      it "should not be valid if billing fails" do
        @sub.subscription_plan.trial_period = nil
        @gw.expects(:store).returns(Response.new(true, 'Forced success'))
        @gw.expects(:purchase).returns(Response.new(false, 'Purchase failure'))
        @sub.should_not be_valid
        @sub.errors.full_messages.should include('Purchase failure')
      end

      describe "storing the card" do
        before(:each) do
          @time = Time.now.utc
          Time.stubs(:now).returns(@time)
        end

        after(:each) do
          @sub.should be_valid
        end

        it "should keep the subscription in trial state" do
          @sub.expects(:state=).never
        end

        it "should not save the subscription" do
          @sub.expects(:save).never
        end

        it "should set the renewal date if not set" do
          @sub.expects(:next_renewal_at=).with(@time.advance(:months => 1))
        end

        it "should set the renewal date based on the trial period" do
          @sub.subscription_plan.trial_period = 2
          @sub.expects(:next_renewal_at=).with(@time.advance(:months => 2))
        end

        it "should set the renewal date based on the trial interval" do
          @sub.subscription_plan.trial_interval = 'days'
          @sub.subscription_plan.trial_period = 15
          @sub.expects(:next_renewal_at=).with(@time.advance(:days => 15))
        end

        it "should set the renewal date based on the discount" do
          @sub.subscription_plan.discount = SubscriptionDiscount.new(:amount => 0, :code => 'foo', :trial_period_extension => 2)
          @sub.expects(:next_renewal_at=).with(@time.advance(:months => 3))
        end

        it "should keep the renewal date when previously set" do
          @sub.next_renewal_at = 1.day.from_now
          @sub.expects(:next_renewal_at=).never
        end

        it "should not bill now if there is a trial period" do
          @sub.subscription_plan.trial_period = 1
          @gw.expects(:purchase).never
        end

        describe "without a trial period" do
          before(:each) do
            @sub.subscription_plan.trial_period = nil
            @response = Response.new(true, 'Forced Success')
            SubscriptionPayment.any_instance.stubs(:send_receipt).returns(true)
          end

          it "should bill now" do
            @gw.expects(:purchase).returns(@response)
          end

          it "should bill the setup amount, if any" do
            @sub.subscription_plan.setup_amount = 500
            @gw.expects(:purchase).with(@sub.subscription_plan.setup_amount * 100, '1').returns(@response)
          end

          it "should bill the plan amount, if no setup amount" do
            @sub.subscription_plan.setup_amount = nil
            @gw.expects(:purchase).with(@sub.subscription_plan.amount * 100, '1').returns(@response)
          end

          it "should record the charge with the setup amount" do
            @sub.subscription_plan.setup_amount = 500
            @gw.expects(:purchase).returns(@response)
            (ary = []).expects(:build).with(has_entries(:amount => @sub.subscription_plan.setup_amount, :setup => true))
            @sub.expects(:subscription_payments).returns(ary)
          end

          it "should record the charge with the plan amount" do
            @sub.subscription_plan.setup_amount = nil
            @gw.expects(:purchase).returns(@response)
            (ary = []).expects(:build).with(has_entries(:amount => @sub.subscription_plan.amount, :setup => false))
            @sub.expects(:subscription_payments).returns(ary)
          end

          it "should set the renewal date based on the plan's renewal period" do
            @basic.trial_period = nil
            @basic.renewal_period = 3
            @sub = Subscription.new(:plan => @basic)
            @sub.expects(:next_renewal_at=).with(@time.advance(:months => 3))
            @sub.save.should be_true
          end
        end
      end
    end
  end

  describe "" do
    before(:each) do
      @sub = subscriptions(:one)
    end

    it "should apply the discount to the amount when changing the discount" do
      @sub.update_attribute(:discount, @discount = subscription_discounts(:sub))
      @sub.amount.should == @sub.subscription_plan.amount(false) - @discount.calculate(@sub.subscription_plan.amount(false))
    end

    it "should reflect the assigned amount, not the amount from the plan" do
      @sub.update_attribute(:amount, @sub.subscription_plan.amount - 1)
      @sub.reload
      @sub.amount.should == @sub.subscription_plan.amount - 1
    end

    describe "when destroyed" do
      before(:each) do
        @sub.stubs(:gateway).returns(@gw = ActiveMerchant::Billing::Base.gateway(:bogus).new)
      end

      it "should delete the stored card info at the gateway" do
        @gw.expects(:unstore).with(@sub.billing_id).returns(true)
        @sub.destroy
      end

      it "should not attempt to delete the stored card info with no billing id" do
        @sub.billing_id = nil
        @gw.expects(:unstore).never
        @sub.destroy
      end

    end

    describe "when failing to store the card" do
      it "should return false and set the error message to the processor response" do
        @sub.stubs(:gateway).returns(@gw = ActiveMerchant::Billing::Base.gateway(:bogus).new)
        @response = Response.new(false, 'Forced failure')
        @gw.expects(:update).returns(@response)
        @card = stub('CreditCard', :display_number => '1111', :expiry_date => CreditCard::ExpiryDate.new(5, 2012))
        @sub.store_card(@card).should be_false
        @sub.errors.full_messages.should include('Forced failure')
      end
    end

    describe "when storing the credit card" do
      describe "successfully" do
        before(:each) do
          @time = Time.now
          @sub.stubs(:gateway).returns(@gw = ActiveMerchant::Billing::Base.gateway(:bogus).new)
          @response = ActiveMerchant::Billing::Response.new(true, 'Forced success', { 'customer_vault_id' => '123' }, { 'authorization' => 'foo' })
          @card = stub('CreditCard', :display_number => '1111', :expiry_date => CreditCard::ExpiryDate.new(5, 2012))
          Time.stubs(:now).returns(@time)
        end

        after(:each) do
          @sub.expects(:card_number=).with('1111')
          @sub.expects(:card_expiration=).with('05-2012')
          @sub.expects(:state=).with('active')
          @sub.expects(:save)
          @sub.store_card(@card).should be_true
        end

        describe "for the first time" do
          before(:each) do
            @sub.card_number = nil
            @sub.billing_id = nil
          end

          it "should store the card and store the billing id" do
            @gw.expects(:store).with(@card, {}).returns(@response)
            @sub.expects(:billing_id=).with('123')
            @gw.stubs(:purchase).returns(@response)
          end

          it "should bill the amount and set the renewal date a month hence with a renewal date in the past" do
            @sub.next_renewal_at = 2.days.ago
            @gw.stubs(:store).returns(@response)
            @gw.expects(:purchase).with(@sub.amount_in_pennies, @response.token).returns(@response)
            @sub.expects(:next_renewal_at=).with(@time.advance(:months => 1))
          end

          it "should bill the amount and set the renewal date a month hence and with no renewal date" do
            @sub.next_renewal_at = nil
            @gw.stubs(:store).returns(@response)
            @gw.expects(:purchase).with(@sub.amount_in_pennies, @response.token).returns(@response)
            @sub.expects(:next_renewal_at=).with(@time.advance(:months => 1))
          end

          it "should not bill and not change the renewal date with a renewal date in the future" do
            @sub.next_renewal_at = @time.advance(:days => 2)
            @gw.stubs(:store).returns(@response)
            @gw.expects(:purchase).never
            @sub.expects(:next_renewal_at=).never
          end

          it "should record the charge with no renewal date" do
            @sub.next_renewal_at = nil
            @gw.stubs(:store).returns(@response)
            @gw.expects(:purchase).with(@sub.amount_in_pennies, @response.token).returns(@response)
            (ary = []).expects(:build).with(has_entry(:amount => @sub.amount))
            @sub.expects(:subscription_payments).returns(ary)
          end

          it "should not record a charge with a renewal date in the future" do
            @sub.next_renewal_at = @time.advance(:days => 2)
            @gw.stubs(:store).returns(@response)
            @gw.expects(:purchase).never
            @sub.expects(:subscription_payments).never
          end
        end

        describe "subsequent times" do
          before(:each) do
            @gw.stubs(:update).returns(@response)
            @gw.stubs(:purchase).returns(@response)
          end

          it "should not overwrite the billing_id" do
            @gw.expects(:billing_id=).never
          end

          it "should update the vault when updating an existing card" do
            @gw.expects(:update).with(@sub.billing_id, @card, {}).returns(@response)
          end

          it "should make a purchase and set the renewal date a month hence with a renewal date in the past" do
            @sub.next_renewal_at = 2.days.ago
            @gw.expects(:purchase).with(@sub.amount_in_pennies, @sub.billing_id).returns(@response)
            @sub.expects(:next_renewal_at=).with(@time.advance(:months => 1))
          end

          it "should make a purchase and set the renewal date a month hence and with no renewal date" do
            @sub.next_renewal_at = nil
            @gw.expects(:purchase).with(@sub.amount_in_pennies, @sub.billing_id).returns(@response)
            @sub.expects(:next_renewal_at=).with(@time.advance(:months => 1))
          end

          it "should not call the gateway and not change the renewal date with a renewal date in the future" do
            @sub.next_renewal_at = @time.advance(:days => 2)
            @gw.expects(:purchase).never
            @sub.expects(:next_renewal_at=).never
          end

          it "should record the charge with no renewal date" do
            @sub.next_renewal_at = nil
            @gw.expects(:purchase).with(@sub.amount_in_pennies, @sub.billing_id).returns(@response)
            (ary = []).expects(:build).with(has_entry(:amount => @sub.amount))
            @sub.expects(:subscription_payments).returns(ary)
          end

          it "should not record a charge with a renewal date in the future" do
            @sub.next_renewal_at = @time.advance(:days => 2)
            @gw.expects(:purchase).never
            @sub.expects(:subscription_payments).never
          end

        end

        describe "sends receipt" do
          before(:each) do
            @time = Time.now
            @sub.stubs(:gateway).returns(@gw = ActiveMerchant::Billing::Base.gateway(:bogus).new)
            @response = Response.new(true, 'Forced success', { 'customer_vault_id' => '123' }, { 'authorization' => 'foo' })
            @card = stub('CreditCard', :display_number => '1111', :expiry_date => CreditCard::ExpiryDate.new(5, 2012))
            Time.stubs(:now).returns(@time)

            @gw.stubs(:update).returns(@response)
            @gw.stubs(:purchase).returns(@response)

            @emails = ActionMailer::Base.deliveries
            @emails.clear
          end

          it "unless there was no charge" do
            @sub.next_renewal_at = @time.advance(:days => 2)
            lambda { @sub.store_card(@card).should be_true }.should change(SubscriptionPayment, :count).by(0)
            ActionMailer::Base.deliveries.count.should == 0
          end

          it "with an end date in the future if the renewal date was in the past" do
            @sub.next_renewal_at = 2.days.ago
            Account.any_instance.stubs(:email).returns("test@email.com")
            lambda { @sub.store_card(@card).should be_true }.should change(SubscriptionPayment, :count).by(1)
            ActionMailer::Base.deliveries.count.should == 1
            email = ActionMailer::Base.deliveries.last
            email.body.should include("From #{Time.now.to_s(:short_day).strip} to #{Time.now.advance(:months => 1).to_s(:short_day).strip}")
          end
        end
      end

      describe "unsuccessfully" do
        before(:each) do
          @time = Time.now
          @sub.stubs(:gateway).returns(@gw = ActiveMerchant::Billing::Base.gateway(:bogus).new)
          @response = Response.new(true, 'Forced success', { 'customer_vault_id' => '123' }, { 'authorization' => 'foo' })
          @card = stub('CreditCard', :display_number => '1111', :expiry_date => CreditCard::ExpiryDate.new(5, 2012))
          Time.stubs(:now).returns(@time)
        end

        after(:each) do
          @sub.expects(:next_renewal_at=).never
          @sub.expects(:state=).never
          @sub.expects(:save).never
          @sub.store_card(@card).should be_false
          @sub.errors.full_messages.should == ['Forced failure']
        end

        it "should return an error message for a failed capture" do
          @sub.next_renewal_at = nil
          @gw.stubs(:store).returns(@response)
          @gw.expects(:purchase).with(@sub.amount_in_pennies, @sub.billing_id).returns(Response.new(false, 'Forced failure', {}, { :authorization => 'foo' }))
        end

      end
    end

    describe "when switching plans" do
      before(:each) do
        @plan = subscription_plans(:advanced)
      end

      it "should allow switching to a plan with no user limit" do
        @plan.expects(:user_limit).returns(nil).at_least_once
        @sub.plan = @plan
        @sub.valid?.should be_true
      end

      it "should apply the subscription discount to the plan amount" do
        @sub.update_attributes(:plan => @plan, :discount => @discount = subscription_discounts(:sub))
        @sub.amount.should == @plan.amount(false) - @discount.calculate(@plan.amount(false))
      end

      it "should refuse switching to a plan with a user limit less than the current number of users" do
        @plan.expects(:user_limit).returns(2).at_least_once
        @sub.subscriber.stubs(:users).returns(mock('users').tap {|m| m.expects(:count).returns(3).at_least_once })
        @sub.plan = @plan
        @sub.valid?.should be_false
        @sub.errors.full_messages.should include('User limit for new plan would be exceeded.')
      end

      it "should allow switching to a plan with a user limit greater than the current number of users" do
        @plan.expects(:user_limit).returns(2).at_least_once
        @sub.subscriber.stubs(:users).returns(mock('users').tap {|m| m.expects(:count).returns(2).at_least_once })
        @sub.plan = @plan
        @sub.valid?.should be_true
      end
    end

    describe "when charging" do
      before(:each) do
        @sub.stubs(:gateway).returns(@gw = ActiveMerchant::Billing::Base.gateway(:bogus).new)
        @sub.subscriber.class.any_instance.stubs(:email).returns("some@email.com")
        @response = Response.new(true, 'Forced success', {:authorized_amount => (@sub.amount * 100).to_s}, :test => true, :authorization => '411')
      end

      it "should charge nothing for free accounts and update the renewal date and state" do
        @sub.amount = 0
        @gw.expects(:purchase).never
        @sub.expects(:update_attributes).with(:next_renewal_at => @sub.next_renewal_at.advance(:months => 1), :state => 'active')
        @sub.charge.should be_true
      end

      it "should not record a payment when charging nothing" do
        @sub.amount = 0
        @sub.expects(:subscription_payments).never
        @sub.charge.should be_true
      end

      it "should charge for paid accounts and update the renewal date and state" do
        @gw.expects(:purchase).with(@sub.amount * 100, @sub.billing_id).returns(@response)
        @sub.expects(:update_attributes).with(:next_renewal_at => @sub.next_renewal_at.advance(:months => 1), :state => 'active')
        @sub.charge.should be_true
      end

      it "should record the payment when charging paid accounts" do
        @gw.expects(:purchase).with(@sub.amount * 100, @sub.billing_id).returns(@response)
        lambda { @sub.charge.should be_true }.should change(SubscriptionPayment, :count).by(1)
        sp = SubscriptionPayment.last
        { :amount => @sub.amount, :subscriber => @sub.subscriber, :transaction_id => @response.authorization}.each do |meth, val|
          sp.send(meth).should == val
        end
      end

      it "should return an error when the processor fails" do
        @gw.expects(:purchase).with(@sub.amount * 100, @sub.billing_id).returns(Response.new(false, 'Oops'))
        @sub.expects(:update_attribute).never
        @sub.expects(:subscription_payments).never
        @sub.charge.should be_false
        @sub.errors.full_messages.should include('Oops')
      end

      describe "with affiliates" do
        before(:each) do
          @gw.expects(:purchase).with(@sub.amount * 100, @sub.billing_id).returns(@response)
          @sub.affiliate = @affiliate = SubscriptionAffiliate.first
        end

        it "should record the affiliate when charging a subscription linked to an affiliate" do
          @sub.charge.should be_true
          @sub.subscription_payments.last.affiliate.should == @affiliate
        end

        it "should calculate the affiliate fee when charging a subscription linked to an affiliate" do
          @sub.charge.should be_true
          @sub.subscription_payments.last.affiliate_amount.should == @sub.amount * @affiliate.rate
        end

        it "should record no affiliate when charging a subscription not linked to an affiliate" do
          @sub.affiliate = nil
          @sub.charge.should be_true
          @sub.subscription_payments.last.affiliate.should be_nil
        end
      end
    end

  end
end
