class SaasAdmin < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable, :lockable and :timeoutable
  devise :database_authenticatable, :rememberable, :trackable

  rails_admin do
    object_label_method :email
  end
end
