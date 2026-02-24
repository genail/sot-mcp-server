FactoryBot.define do
  factory :record, class: 'SOT::Record' do
    transient do
      with_schema { create(:table_schema) }
      with_user { create(:user) }
    end

    schema_id { with_schema.id }
    data { JSON.generate({ 'title' => 'Test Record', 'count' => '1' }) }
    state { nil }
    created_by { with_user.id }
    updated_by { with_user.id }
  end
end
