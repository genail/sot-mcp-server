require 'spec_helper'

RSpec.describe SOT::Feedback do
  let(:user) { create(:user) }
  let(:schema) { create(:entity_schema) }

  describe 'validations' do
    it 'requires user_id' do
      fb = SOT::Feedback.new(context: 'ctx', confusion: 'confused')
      expect(fb.valid?).to be false
      expect(fb.errors[:user_id]).not_to be_empty
    end

    it 'requires context' do
      fb = SOT::Feedback.new(user_id: user.id, confusion: 'confused')
      expect(fb.valid?).to be false
      expect(fb.errors[:context]).not_to be_empty
    end

    it 'requires confusion' do
      fb = SOT::Feedback.new(user_id: user.id, context: 'ctx')
      expect(fb.valid?).to be false
      expect(fb.errors[:confusion]).not_to be_empty
    end

    it 'saves a valid feedback' do
      fb = SOT::Feedback.new(
        user_id: user.id,
        context: 'Trying to lock a resource',
        confusion: 'Description is unclear'
      )
      expect(fb.save).to be_a(SOT::Feedback)
    end

    it 'allows optional schema_id' do
      fb = SOT::Feedback.create(
        user_id: user.id,
        schema_id: schema.id,
        context: 'ctx',
        confusion: 'confused'
      )
      expect(fb.schema).to eq(schema)
    end

    it 'allows optional suggestion' do
      fb = SOT::Feedback.create(
        user_id: user.id,
        context: 'ctx',
        confusion: 'confused',
        suggestion: 'Make it clearer'
      )
      expect(fb.suggestion).to eq('Make it clearer')
    end
  end

  describe 'resolved flag' do
    it 'defaults to false' do
      fb = SOT::Feedback.create(
        user_id: user.id,
        context: 'ctx',
        confusion: 'confused'
      )
      expect(fb.resolved).to be false
    end

    it 'can be set to true' do
      fb = SOT::Feedback.create(
        user_id: user.id,
        context: 'ctx',
        confusion: 'confused'
      )
      fb.update(resolved: true)
      expect(fb.reload.resolved).to be true
    end
  end
end
