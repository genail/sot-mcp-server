require 'spec_helper'

RSpec.describe SOT::TypeCoercion do
  describe '.coerce' do
    context 'string type' do
      it 'passes through strings' do
        expect(described_class.coerce('hello', 'string', field_name: 'f')).to eq('hello')
      end

      it 'coerces integers to string' do
        expect(described_class.coerce(42, 'string', field_name: 'f')).to eq('42')
      end

      it 'coerces nil to nil' do
        expect(described_class.coerce(nil, 'string', field_name: 'f')).to be_nil
      end
    end

    context 'text type' do
      it 'passes through strings' do
        expect(described_class.coerce('long text', 'text', field_name: 'f')).to eq('long text')
      end

      it 'coerces integers to string' do
        expect(described_class.coerce(42, 'text', field_name: 'f')).to eq('42')
      end
    end

    context 'integer type' do
      it 'coerces integer to string representation' do
        expect(described_class.coerce(42, 'integer', field_name: 'f')).to eq('42')
      end

      it 'coerces string integer to string representation' do
        expect(described_class.coerce('42', 'integer', field_name: 'f')).to eq('42')
      end

      it 'coerces negative integers' do
        expect(described_class.coerce('-5', 'integer', field_name: 'f')).to eq('-5')
      end

      it 'coerces zero' do
        expect(described_class.coerce('0', 'integer', field_name: 'f')).to eq('0')
      end

      it 'coerces float with no fractional part' do
        expect(described_class.coerce(42.0, 'integer', field_name: 'f')).to eq('42')
      end

      it 'rejects float with fractional part' do
        expect {
          described_class.coerce(42.5, 'integer', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /cannot.*integer.*lose precision/i)
      end

      it 'rejects non-numeric string' do
        expect {
          described_class.coerce('hello', 'integer', field_name: 'count')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /count.*cannot coerce.*integer/)
      end

      it 'rejects float string' do
        expect {
          described_class.coerce('42.5', 'integer', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError)
      end

      it 'handles string with whitespace' do
        expect(described_class.coerce('  42  ', 'integer', field_name: 'f')).to eq('42')
      end
    end

    context 'float type' do
      it 'coerces float to string representation' do
        expect(described_class.coerce(3.14, 'float', field_name: 'f')).to eq('3.14')
      end

      it 'coerces integer to float string representation' do
        expect(described_class.coerce(42, 'float', field_name: 'f')).to eq('42.0')
      end

      it 'coerces string float' do
        expect(described_class.coerce('3.14', 'float', field_name: 'f')).to eq('3.14')
      end

      it 'coerces string integer to float string' do
        expect(described_class.coerce('42', 'float', field_name: 'f')).to eq('42.0')
      end

      it 'rejects non-numeric string' do
        expect {
          described_class.coerce('hello', 'float', field_name: 'price')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /price.*cannot coerce.*float/)
      end
    end

    context 'boolean type' do
      it 'coerces true' do
        expect(described_class.coerce(true, 'boolean', field_name: 'f')).to eq('true')
      end

      it 'coerces false' do
        expect(described_class.coerce(false, 'boolean', field_name: 'f')).to eq('false')
      end

      it 'coerces "true" string' do
        expect(described_class.coerce('true', 'boolean', field_name: 'f')).to eq('true')
      end

      it 'coerces "false" string' do
        expect(described_class.coerce('false', 'boolean', field_name: 'f')).to eq('false')
      end

      it 'coerces "yes"' do
        expect(described_class.coerce('yes', 'boolean', field_name: 'f')).to eq('true')
      end

      it 'coerces "no"' do
        expect(described_class.coerce('no', 'boolean', field_name: 'f')).to eq('false')
      end

      it 'coerces "1"' do
        expect(described_class.coerce('1', 'boolean', field_name: 'f')).to eq('true')
      end

      it 'coerces "0"' do
        expect(described_class.coerce('0', 'boolean', field_name: 'f')).to eq('false')
      end

      it 'is case-insensitive' do
        expect(described_class.coerce('TRUE', 'boolean', field_name: 'f')).to eq('true')
        expect(described_class.coerce('False', 'boolean', field_name: 'f')).to eq('false')
        expect(described_class.coerce('YES', 'boolean', field_name: 'f')).to eq('true')
      end

      it 'rejects invalid boolean' do
        expect {
          described_class.coerce('maybe', 'boolean', field_name: 'active')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /active.*cannot coerce.*boolean/)
      end
    end

    context 'date type' do
      it 'accepts valid YYYY-MM-DD' do
        expect(described_class.coerce('2026-02-25', 'date', field_name: 'f')).to eq('2026-02-25')
      end

      it 'accepts leap year Feb 29' do
        expect(described_class.coerce('2024-02-29', 'date', field_name: 'f')).to eq('2024-02-29')
      end

      it 'coerces nil to nil' do
        expect(described_class.coerce(nil, 'date', field_name: 'f')).to be_nil
      end

      it 'rejects non-leap year Feb 29' do
        expect {
          described_class.coerce('2026-02-29', 'date', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /invalid date/)
      end

      it 'rejects Feb 30' do
        expect {
          described_class.coerce('2026-02-30', 'date', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /invalid date/)
      end

      it 'rejects blank string' do
        expect {
          described_class.coerce('', 'date', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /blank/)
      end

      it 'rejects date with time component' do
        expect {
          described_class.coerce('2026-02-25T15:00:00', 'date', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /YYYY-MM-DD/)
      end

      it 'rejects ambiguous formats like MM/DD/YYYY' do
        expect {
          described_class.coerce('02/25/2026', 'date', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /YYYY-MM-DD/)
      end

      it 'rejects text' do
        expect {
          described_class.coerce('tomorrow', 'date', field_name: 'due')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /YYYY-MM-DD/)
      end

      it 'strips whitespace' do
        expect(described_class.coerce('  2026-02-25  ', 'date', field_name: 'f')).to eq('2026-02-25')
      end
    end

    context 'datetime type' do
      it 'parses ISO 8601 with Z' do
        expect(described_class.coerce('2026-02-25T15:00:00Z', 'datetime', field_name: 'f')).to eq('2026-02-25T15:00:00Z')
      end

      it 'parses ISO 8601 with offset and normalizes to UTC' do
        result = described_class.coerce('2026-02-25T17:00:00+02:00', 'datetime', field_name: 'f')
        expect(result).to eq('2026-02-25T15:00:00Z')
      end

      it 'parses human-readable format with UTC' do
        result = described_class.coerce('25 Feb 2026 15:00:00 UTC', 'datetime', field_name: 'f')
        expect(result).to eq('2026-02-25T15:00:00Z')
      end

      it 'parses format with GMT' do
        result = described_class.coerce('25 Feb 2026 15:00:00 GMT', 'datetime', field_name: 'f')
        expect(result).to eq('2026-02-25T15:00:00Z')
      end

      it 'parses ISO 8601 with negative offset' do
        result = described_class.coerce('2026-02-25T10:00:00-05:00', 'datetime', field_name: 'f')
        expect(result).to eq('2026-02-25T15:00:00Z')
      end

      it 'rejects datetime without timezone' do
        expect {
          described_class.coerce('2026-02-25T15:00:00', 'datetime', field_name: 'due_at')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /due_at.*timezone/)
      end

      it 'rejects date-only string' do
        expect {
          described_class.coerce('2026-02-25Z', 'datetime', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /time component/)
      end

      it 'rejects date-only string with timezone offset (offset should not be mistaken for time)' do
        expect {
          described_class.coerce('2026-02-25+02:00', 'datetime', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /time component/)
      end

      it 'rejects invalid date (Feb 30)' do
        expect {
          described_class.coerce('2026-02-30T15:00:00Z', 'datetime', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /invalid datetime/)
      end

      it 'rejects non-leap year Feb 29' do
        expect {
          described_class.coerce('2026-02-29T00:00:00Z', 'datetime', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /invalid datetime/)
      end

      it 'accepts leap year Feb 29' do
        result = described_class.coerce('2024-02-29T00:00:00Z', 'datetime', field_name: 'f')
        expect(result).to eq('2024-02-29T00:00:00Z')
      end

      it 'rejects blank string' do
        expect {
          described_class.coerce('', 'datetime', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /blank/)
      end

      it 'rejects ambiguous timezone abbreviations' do
        expect {
          described_class.coerce('2026-02-25 15:00:00 EST', 'datetime', field_name: 'f')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /timezone/)
      end
    end

    context 'user type' do
      let!(:user) { create(:user, name: 'Alice') }

      it 'accepts an existing user name' do
        expect(described_class.coerce('Alice', 'user', field_name: 'assignee')).to eq('Alice')
      end

      it 'accepts a deactivated user name' do
        user.update(is_active: false)
        expect(described_class.coerce('Alice', 'user', field_name: 'assignee')).to eq('Alice')
      end

      it 'rejects a non-existent user name' do
        expect {
          described_class.coerce('NonExistent', 'user', field_name: 'assignee')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /assignee.*not found/)
      end

      it 'rejects blank string' do
        expect {
          described_class.coerce('', 'user', field_name: 'assignee')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /blank/)
      end

      it 'lists available users in error message' do
        create(:user, name: 'Bob')
        expect {
          described_class.coerce('Charlie', 'user', field_name: 'assignee')
        }.to raise_error(SOT::TypeCoercion::CoercionError, /Alice.*Bob/)
      end
    end
  end

  describe '.coerce_data' do
    let(:schema) do
      create(:table_schema, fields: JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'required' => true },
        { 'name' => 'count', 'type' => 'integer', 'required' => false }
      ]))
    end

    it 'coerces values according to schema field types' do
      result = described_class.coerce_data({ 'title' => 'Test', 'count' => 42 }, schema)
      expect(result['title']).to eq('Test')
      expect(result['count']).to eq('42')
    end

    it 'leaves nil values unchanged' do
      result = described_class.coerce_data({ 'title' => 'Test', 'count' => nil }, schema)
      expect(result['count']).to be_nil
    end

    it 'only coerces fields present in data' do
      result = described_class.coerce_data({ 'title' => 'Test' }, schema)
      expect(result).to eq({ 'title' => 'Test' })
    end
  end
end
