require 'spec_helper'

RSpec.describe SOT::User do
  describe 'validations' do
    it 'requires name' do
      user = SOT::User.new(token_hash: BCrypt::Password.create('x'))
      expect(user.valid?).to be false
      expect(user.errors[:name]).not_to be_empty
    end

    it 'requires token_hash' do
      user = SOT::User.new(name: 'test')
      expect(user.valid?).to be false
      expect(user.errors[:token_hash]).not_to be_empty
    end

    it 'requires unique name' do
      create(:user, name: 'alice')
      user = SOT::User.new(name: 'alice', token_hash: BCrypt::Password.create('x'))
      expect(user.valid?).to be false
    end

    it 'saves a valid user' do
      user = create(:user)
      expect(user.id).not_to be_nil
    end
  end

  describe '.authenticate' do
    it 'returns the user for a valid token' do
      token = 'my_secret_token'
      user = create(:user, raw_token: token)
      expect(SOT::User.authenticate(token)).to eq(user)
    end

    it 'returns nil for an invalid token' do
      create(:user, raw_token: 'correct_token')
      expect(SOT::User.authenticate('wrong_token')).to be_nil
    end

    it 'returns nil for nil token' do
      expect(SOT::User.authenticate(nil)).to be_nil
    end

    it 'returns nil for empty token' do
      expect(SOT::User.authenticate('')).to be_nil
    end

    it 'returns nil for inactive user with valid token' do
      token = 'valid_token'
      create(:user, :inactive, raw_token: token)
      expect(SOT::User.authenticate(token)).to be_nil
    end
  end

  describe '.create_with_token' do
    it 'returns user and token pair' do
      user, token = SOT::User.create_with_token(name: 'bob')
      expect(user).to be_a(SOT::User)
      expect(user.name).to eq('bob')
      expect(token).to be_a(String)
      expect(token.length).to eq(64)
    end

    it 'creates a non-admin user by default' do
      user, _token = SOT::User.create_with_token(name: 'bob')
      expect(user.is_admin).to be false
    end

    it 'can create an admin user' do
      user, _token = SOT::User.create_with_token(name: 'admin', is_admin: true)
      expect(user.is_admin).to be true
    end

    it 'generates a token that can be authenticated' do
      user, token = SOT::User.create_with_token(name: 'carol')
      expect(SOT::User.authenticate(token)).to eq(user)
    end
  end

  describe 'timestamps' do
    it 'sets created_at and updated_at on create' do
      user = create(:user)
      expect(user.created_at).not_to be_nil
      expect(user.updated_at).not_to be_nil
    end
  end
end
