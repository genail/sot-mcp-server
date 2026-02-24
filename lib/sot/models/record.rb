require 'json'

module SOT
  class Record < Sequel::Model(:_records)
    plugin :timestamps, update_on_create: true
    plugin :validation_helpers

    many_to_one :schema, class: 'SOT::Schema'
    many_to_one :creator, class: 'SOT::User', key: :created_by
    many_to_one :updater, class: 'SOT::User', key: :updated_by

    def validate
      super
      validates_presence [:schema_id, :data, :created_by, :updated_by]
    end

    def parsed_data
      JSON.parse(data)
    end

    def parsed_data=(hash)
      self.data = JSON.generate(hash)
    end

    def current_version
      version || 1
    end
  end
end
