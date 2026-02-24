require 'spec_helper'

RSpec.describe SOT::ActivityLog do
  let(:user) { create(:user) }
  let(:schema) { create(:table_schema) }

  describe 'validations' do
    it 'requires user_id' do
      log = SOT::ActivityLog.new(schema_id: schema.id, action: 'create', changes: '{}')
      expect(log.valid?).to be false
      expect(log.errors[:user_id]).not_to be_empty
    end

    it 'requires schema_id' do
      log = SOT::ActivityLog.new(user_id: user.id, action: 'create', changes: '{}')
      expect(log.valid?).to be false
      expect(log.errors[:schema_id]).not_to be_empty
    end

    it 'requires action' do
      log = SOT::ActivityLog.new(user_id: user.id, schema_id: schema.id, changes: '{}')
      expect(log.valid?).to be false
      expect(log.errors[:action]).not_to be_empty
    end

    it 'requires changes' do
      log = SOT::ActivityLog.new(user_id: user.id, schema_id: schema.id, action: 'create')
      expect(log.valid?).to be false
      expect(log.errors[:changes]).not_to be_empty
    end

    it 'validates action is one of create, update, delete' do
      log = SOT::ActivityLog.new(user_id: user.id, schema_id: schema.id, action: 'invalid', changes: '{}')
      expect(log.valid?).to be false
    end

    %w[create update delete].each do |action|
      it "accepts '#{action}' as a valid action" do
        log = SOT::ActivityLog.new(user_id: user.id, schema_id: schema.id, action: action, changes: '{}')
        expect(log.valid?).to be true
      end
    end
  end

  describe '#parsed_changes' do
    it 'parses the changes JSON' do
      log = SOT::ActivityLog.create(
        user_id: user.id,
        schema_id: schema.id,
        action: 'create',
        changes: JSON.generate({ before: nil, after: { title: 'test' } })
      )
      expect(log.parsed_changes['after']['title']).to eq('test')
    end
  end

  describe 'associations' do
    it 'belongs to a user' do
      log = SOT::ActivityLog.create(
        user_id: user.id,
        schema_id: schema.id,
        action: 'create',
        changes: '{}'
      )
      expect(log.user).to eq(user)
    end
  end
end
