FactoryGirl.define do
  factory(:subscription_plan) do
    amount 10
    name "Basic"
    user_limit 3
  end
end
