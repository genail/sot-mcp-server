require 'spec_helper'

RSpec.describe SOT::Role do
  describe 'validations' do
    it 'requires name' do
      role = SOT::Role.new
      expect(role.valid?).to be false
      expect(role.errors[:name]).not_to be_empty
    end

    it 'requires unique name' do
      SOT::Role.find_or_create(name: 'test_role')
      role = SOT::Role.new(name: 'test_role')
      expect(role.valid?).to be false
    end

    it 'requires lowercase alphanumeric name' do
      role = SOT::Role.new(name: 'Invalid-Name')
      expect(role.valid?).to be false
    end

    it 'accepts valid lowercase name with underscores' do
      role = SOT::Role.create(name: 'custom_role')
      expect(role.id).not_to be_nil
    end
  end

  describe '#system_role?' do
    it 'returns true for admin' do
      role = SOT::Role.first(name: 'admin')
      expect(role.system_role?).to be true
    end

    it 'returns true for member' do
      role = SOT::Role.first(name: 'member')
      expect(role.system_role?).to be true
    end

    it 'returns false for custom roles' do
      role = SOT::Role.create(name: 'support')
      expect(role.system_role?).to be false
    end
  end
end
