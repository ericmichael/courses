class AccountsController < ApplicationController
  inherit_resources

  before_filter :authenticate_user!, :except => [ :new, :create, :plans, :canceled, :thanks]
  before_filter :authorized?, :except => [ :new, :create, :plans, :canceled, :thanks]
  before_filter :build_user, :only => [:new, :create]
  before_filter :load_billing, :only => [ :billing ]
  before_filter :load_subscription, :only => [ :billing, :plan ]
  before_filter :load_discount, :only => [ :plans, :plan, :new, :create ]
  before_filter :build_plan, :only => [:new, :create]
  skip_before_filter :collect_billing_info

  def new
    # render :layout => 'public' # Uncomment if your "public" site has a different layout than the one used for logged-in users
  end

  def create
    @account.affiliate = SubscriptionAffiliate.find_by_token(cookies[:affiliate]) unless cookies[:affiliate].blank?

    if @account.save
      flash[:domain] = @account.domain
      redirect_to thanks_url
    else
      render :action => 'new'#, :layout => 'public' # Uncomment if your "public" site has a different layout than the one used for logged-in users
    end
  end

  def update
    if resource.update_attributes(params[:account].permit(:name))
      flash[:notice] = "Your account has been updated."
      redirect_to redirect_url
    else
      render :action => 'edit'
    end
  end

  def plans
    @plans = SubscriptionPlan.order('amount desc').collect {|p| p.discount = @discount; p }
    # render :layout => 'public' # Uncomment if your "public" site has a different layout than the one used for logged-in users
  end

  def billing
    if request.post?
      result = if params[:stripeToken].present?
        @subscription.store_card(params[:stripeToken])
      else
        @address.first_name = @creditcard.first_name
        @address.last_name = @creditcard.last_name

        (@creditcard.valid? & @address.valid?) && @subscription.store_card(@creditcard, :billing_address => @address.to_activemerchant, :ip => request.remote_ip)
      end

      if result
        flash[:notice] = "Your billing information has been updated."
        redirect_to :action => "billing"
      end
    end
  end

  def plan
    if request.post?
      @subscription.plan = SubscriptionPlan.find(params[:plan_id])

      if @subscription.save
        flash[:notice] = "Your subscription has been changed."
        SubscriptionNotifier.plan_changed(@subscription).deliver
      else
        flash[:error] = "Error updating your plan: #{@subscription.errors.full_messages.to_sentence}"
      end
      redirect_to :action => "plan"
    else
      @plans = SubscriptionPlan.where(['id <> ?', @subscription.subscription_plan_id]).order('amount desc').collect {|p| p.discount = @subscription.discount; p }
    end
  end

  def cancel
    if request.post? and !params[:confirm].blank?
      current_account.destroy
      sign_out(:user)
      redirect_to :action => "canceled"
    end
  end

  def thanks
    redirect_to :action => "plans" and return unless flash[:domain]
    # render :layout => 'public' # Uncomment if your "public" site has a different layout than the one used for logged-in users
  end

  def dashboard
  end

  protected

    def resource
      @account ||= current_account
    end

    def build_user
      build_resource.admin = User.new unless build_resource.admin
    end

    def build_plan
      redirect_to :action => "plans" unless @plan = SubscriptionPlan.find_by_name(params[:plan])
      @plan.discount = @discount
      @account.plan = @plan
    end

    def redirect_url
      { :action => 'show' }
    end

    def load_billing
      @creditcard = ActiveMerchant::Billing::CreditCard.new(params[:creditcard])
      @address = SubscriptionAddress.new(params[:address])
    end

    def load_subscription
      @subscription = current_account.subscription
    end

    # Load the discount by code, but not if it's not available
    def load_discount
      if params[:discount].blank? || !(@discount = SubscriptionDiscount.find_by_code(params[:discount])) || !@discount.available?
        @discount = nil
      end
    end

    def authorized?
      redirect_to new_user_session_url unless self.action_name == 'dashboard' || admin?
    end

    def permitted_params
      params.permit(:plan, :account => [ :name, :domain, :admin_attributes => [ :email, :password, :password_confirmation ] ])
    end

end
