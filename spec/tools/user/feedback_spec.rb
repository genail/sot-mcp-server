require 'spec_helper'

RSpec.describe SOT::Tools::User::FeedbackTool, type: :tool do
  let(:user) { create(:user) }

  describe '.call' do
    it 'creates feedback' do
      response = call_tool(described_class, user: user,
                           context: 'Trying to lock a resource',
                           confusion: 'Description says only locker can unlock but no locked_by field')
      expect(response_error?(response)).to be_falsey
      expect(response_text(response)).to include('Feedback recorded')
      expect(SOT::Feedback.count).to eq(1)
    end

    it 'links feedback to a schema when table is provided' do
      schema = create(:table_schema, namespace: 'org', name: 'locks')
      call_tool(described_class, user: user,
                table: 'org.locks',
                context: 'ctx',
                confusion: 'confused')
      expect(SOT::Feedback.first.schema_id).to eq(schema.id)
    end

    it 'saves suggestion when provided' do
      call_tool(described_class, user: user,
                context: 'ctx',
                confusion: 'confused',
                suggestion: 'Add a locked_by field')
      expect(SOT::Feedback.first.suggestion).to eq('Add a locked_by field')
    end

    it 'attributes feedback to the current user' do
      call_tool(described_class, user: user,
                context: 'ctx',
                confusion: 'confused')
      expect(SOT::Feedback.first.user_id).to eq(user.id)
    end
  end
end
