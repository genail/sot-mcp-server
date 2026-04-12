FactoryBot.define do
  factory :table_schema, class: 'SOT::Schema' do
    sequence(:name) { |n| "table_#{n}" }
    namespace { 'test' }
    description { 'A test table' }
    fields do
      JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'description' => 'The title', 'required' => true },
        { 'name' => 'count', 'type' => 'integer', 'description' => 'A count', 'required' => false }
      ])
    end
    states { nil }
    read_roles { JSON.generate(%w[admin member]) }
    create_roles { JSON.generate(%w[admin member]) }
    update_roles { JSON.generate(%w[admin member]) }
    delete_roles { JSON.generate(%w[admin member]) }

    trait :stateful do
      states do
        JSON.generate([
          { 'name' => 'open', 'description' => 'Open for modification' },
          { 'name' => 'closed', 'description' => 'Closed and finalized' },
          { 'name' => 'archived', 'description' => 'Archived and read-only' }
        ])
      end
    end

    trait :admin_only do
      read_roles { '[]' }
      create_roles { '[]' }
      update_roles { '[]' }
      delete_roles { '[]' }
    end

    trait :read_only_member do
      read_roles { JSON.generate(%w[admin member]) }
      create_roles { '[]' }
      update_roles { '[]' }
      delete_roles { '[]' }
    end
  end
end
