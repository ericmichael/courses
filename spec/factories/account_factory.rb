FactoryGirl.define do
  factory(:account) do
    name Faker::Company.name
    full_domain 'foo'
  end
end
