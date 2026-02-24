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

    trait :stateful do
      states do
        JSON.generate([
          { 'name' => 'open', 'description' => 'Open for modification' },
          { 'name' => 'closed', 'description' => 'Closed and finalized' },
          { 'name' => 'archived', 'description' => 'Archived and read-only' }
        ])
      end
    end
  end
end
