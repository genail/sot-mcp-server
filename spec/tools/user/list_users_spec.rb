require 'spec_helper'

RSpec.describe SOT::Tools::User::ListUsers, type: :tool do
  describe '.call' do
    it 'returns all user names' do
      create(:user, name: 'alice')
      create(:user, name: 'bob')
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).to include('- alice')
      expect(text).to include('- bob')
    end

    it 'does not expose admin status' do
      create(:user, name: 'alice', is_admin: true)
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).not_to include('admin')
    end

    it 'lists the calling user when they are the only one' do
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).to start_with('Users:')
    end
  end
end
