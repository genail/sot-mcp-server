require 'spec_helper'

RSpec.describe SOT::Tools::User::Whoami, type: :tool do
  describe '.call' do
    it 'returns the current user name' do
      user = create(:user, name: 'alice')
      response = call_tool(described_class, user: user)
      expect(response_text(response)).to eq('You are: alice (role: member)')
    end
  end
end
