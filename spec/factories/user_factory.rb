FactoryGirl.define do
  factory(:user) do
    name Faker::Name.name
    email Faker::Internet.email
    account
    password 'foobar'
    password_confirmation 'foobar'
  end
end
