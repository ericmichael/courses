class Account < ActiveRecord::Base

  has_many :users, :dependent => :destroy, :inverse_of => :account
  has_one :admin, -> { where(admin: true) }, :class_name => "User"
  accepts_nested_attributes_for :admin

  #
  # Set up the account to own subscriptions. An alternative would be to
  # call 'has_subscription' on the user model, if you only want one user per
  # subscription.
  #
  # The limits hash is used to add some methods to the class that you can
  # use to check whether the subscriber has the rights to do something.
  # The hash keys match the *_limit fields in the subscriptions and
  # subscription_plan tables, and the values are the methods that will be
  # called to see if that limit has been reached.  For example,
  #
  # { 'user_limit' => Proc.new {|a| a.users.count } }
  #
  # defines a single limit based on the user_limit attribute that would
  # call users.account on the instance of the model that is invoking this
  # method.  In other words, if you have this:
  #
  # class Account < ActiveRecord::Base
  #   has_subscription({ 'user_limit' => Proc.new {|a| a.users.count } })
  # end
  #
  # then you could call @account.reached_user_limit? to know whether to allow
  # the account to create another user (a.users.count < subscription.user_limit).
  #
  # To add additional limits, add a field named *_limit (like project_limit)
  # to the subscriptions and subscription_plans table in a migration, and
  # add it to the hash here.  The value of the field in the subscription_plans table
  # will be the default for the account's subscription when the subscription
  # is created, so you define your tiers by the different values
  # of the *_limit plans in the subscription_plans table.
  has_subscription :user_limit => Proc.new {|a| a.users.count }

  #
  # The model with "has_subscription" needs to provide an email attribute.
  # But ours is stored in the user model, so we delegate
  #
  def email
    admin.try(:email)
  end

  validates_presence_of :admin, :message => "information is missing"
  validates_associated :admin
  validates_format_of :domain, :with => /\A[a-zA-Z][a-zA-Z0-9]*\Z/
  validates_exclusion_of :domain, :in => %W( support blog www billing help api ), :message => "The domain <strong>{{value}}</strong> is not available."
  validate :valid_domain?

  def domain
    @domain ||= self.full_domain.blank? ? '' : self.full_domain.split('.').first
  end

  def domain=(domain)
    @domain = domain
    self.full_domain = "#{domain}.#{Saas::Config.base_domain}"
  end

  def to_s
    name.blank? ? full_domain : "#{name} (#{full_domain})"
  end

  protected

    def valid_domain?
      conditions = new_record? ? ['full_domain = ?', self.full_domain] : ['full_domain = ? and id <> ?', self.full_domain, self.id]
      self.errors.add(:domain, 'is not available') if self.full_domain.blank? || self.class.where(conditions).count > 0
    end

  rails_admin do
    object_label_method :full_domain
  end
end
