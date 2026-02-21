FactoryBot.define do
  factory :user, class: 'SOT::User' do
    sequence(:name) { |n| "user_#{n}" }
    token_hash { BCrypt::Password.create('default_test_token') }
    is_admin { false }

    trait :admin do
      is_admin { true }
    end

    # Use initialize_with to support raw_token transient
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
