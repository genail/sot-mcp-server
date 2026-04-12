FactoryBot.define do
  factory :user, class: 'SOT::User' do
    sequence(:name) { |n| "user_#{n}" }
    token_hash { BCrypt::Password.create('default_test_token') }
    is_admin { false }
    is_active { true }
    role_id { SOT::Role.find_or_create(name: 'member') { |r| r.description = 'Default role' }.id }

    trait :admin do
      is_admin { true }
      role_id { SOT::Role.find_or_create(name: 'admin') { |r| r.description = 'Admin role' }.id }
    end

    trait :inactive do
      is_active { false }
    end

    transient do
      raw_token { nil }
    end

    after(:build) do |user, evaluator|
      if evaluator.raw_token
        user.token_hash = BCrypt::Password.create(evaluator.raw_token)
      end
    end
  end
end
