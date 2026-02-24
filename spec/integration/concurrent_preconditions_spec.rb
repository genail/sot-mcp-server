require 'spec_helper'

RSpec.describe 'Concurrent preconditions' do
  let!(:schema) { create(:table_schema, :stateful, namespace: 'org', name: 'locks') }
  let(:user1_pair) { SOT::User.create_with_token(name: 'user1') }
  let(:user1) { user1_pair.first }
  let(:user2_pair) { SOT::User.create_with_token(name: 'user2') }
  let(:user2) { user2_pair.first }

  it 'only one of two concurrent updates with same precondition succeeds' do
    record = SOT::MutationService.create(
      schema: schema,
      data: { 'title' => 'Shared Resource' },
      state: 'open',
      user: user1
    )

    results = []
    threads = [user1, user2].map do |user|
      Thread.new do
        begin
          SOT::MutationService.update(
            record: record,
            state: 'closed',
            preconditions: { 'state' => 'open' },
            expected_version: 1,
            user: user
          )
          results << :success
        rescue SOT::MutationService::PreconditionFailed, SOT::MutationService::VersionConflict
          results << :failed
        end
      end
    end

    threads.each(&:join)

    expect(results).to contain_exactly(:success, :failed)
    expect(SOT::Record[record.id].state).to eq('closed')
  end
end
