require 'spec_helper'

RSpec.describe SOT::Tools::Admin::ViewFeedback, type: :tool do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  before do
    SOT::Feedback.create(
      user_id: user.id,
      context: 'Trying to lock',
      confusion: 'Description unclear',
      suggestion: 'Add locked_by'
    )
  end

  describe 'list action' do
    it 'lists feedback entries' do
      response = call_tool(described_class, user: admin)
      text = response_text(response)
      expect(text).to include('Trying to lock')
      expect(text).to include('Description unclear')
      expect(text).to include('[OPEN]')
    end

    it 'filters by resolved status' do
      SOT::Feedback.first.update(resolved: true)
      response = call_tool(described_class, user: admin, resolved: false)
      expect(response_text(response)).to include('No feedback entries found')
    end

    it 'handles no feedback' do
      SOT::Feedback.dataset.delete
      response = call_tool(described_class, user: admin)
      expect(response_text(response)).to include('No feedback entries found')
    end
  end

  describe 'resolve action' do
    it 'marks feedback as resolved' do
      fb = SOT::Feedback.first
      response = call_tool(described_class, user: admin,
                           action: 'resolve', feedback_id: fb.id)
      expect(response_error?(response)).to be_falsey
      expect(fb.reload.resolved).to be true
    end

    it 'returns error for missing feedback_id' do
      response = call_tool(described_class, user: admin, action: 'resolve')
      expect(response_error?(response)).to be true
    end

    it 'returns error for unknown feedback_id' do
      response = call_tool(described_class, user: admin,
                           action: 'resolve', feedback_id: 99999)
      expect(response_error?(response)).to be true
    end
  end
end
