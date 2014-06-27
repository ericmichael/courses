class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :recoverable, :rememberable, :trackable, authentication_keys: [ :email, :account_id ]

  belongs_to :account, :inverse_of => :users

  validates_presence_of   :email
  validates_uniqueness_of :email, :scope => :account_id
  validates_format_of     :email, :with  => /\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/

  validates_presence_of     :password, :if => :password_required?
  validates_confirmation_of :password, :if => :password_required?
  validates_length_of       :password, :within => 6..20, :allow_blank => true

  protected

      # Checks whether a password is needed or not. For validations only.
      # Passwords are always required if it's a new record, or if the password
      # or confirmation are being set somewhere.
      def password_required?
        !persisted? || !password.blank? || !password_confirmation.blank?
      end

  rails_admin do
    object_label_method :email
  end
end
