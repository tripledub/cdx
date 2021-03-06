class Subscriber < ActiveRecord::Base
  VALID_VERBS = %w(GET POST)

  belongs_to :user
  belongs_to :filter

  serialize :fields, JSON

  validates_presence_of :user
  validates_presence_of :filter
  validates_presence_of :name
  validates_presence_of :url
  validates_presence_of :verb
  validates_inclusion_of :verb, in: VALID_VERBS

  def self.notify_all
    PoirotRails::Activity.start("Subscriber.notify_all") do
      Subscriber.find_each do |subscriber|
        begin
          subscriber.notify
        rescue => ex
          Rails.logger.error "#{ex.message} : #{ex.backtrace}"
        end
      end
    end
  end

  def self.available_field_names
    available_fields.map(&:scoped_name)
  end

  def self.available_fields
    # We only keep fields at level 2 (1 is scope, 2 is field).
    # Sub fields, like in the case of `test.assays.result`, are
    # not returned: only the field of `test.assays` is.
    fields = []
    Cdx.core_fields.each do |field|
      if field.scope.is_a?(Cdx::Field::NestedField)
        fields << field.scope
      else
        fields << field unless field.pii?
      end
    end
    fields.uniq
  end

  def self.default_schema
    TestsSchema.new("en-US").build
  end

  def notify
    fields = self.fields
    query = self.filter.query.merge "page_size" => 10000, "test.updated_time_since" => last_run_at.iso8601
    Rails.logger.info "Filter : #{query}"
    tests = TestResult.query(query, filter.user).execute["tests"]

    now = Time.now
    tests.each do |test|
      PoirotRails::Activity.start("Publish test to subscriber #{self.name}") do

        filtered_test = filter_test(test, fields)

        callback_url = self.url

        if self.verb == 'GET'
          callback_url = URI.parse self.url
          callback_query = Rack::Utils.parse_nested_query(callback_url.query || "")
          merged_query = filtered_test.merge(callback_query)
          callback_url = "#{callback_url.scheme}://#{callback_url.host}:#{callback_url.port}#{callback_url.path}?#{merged_query.to_query}"
        end

        options = {}
        if self.url_user && self.url_password
          options[:user] = self.url_user
          options[:password] = self.url_password
        end

        request = RestClient::Resource.new(callback_url, options)
        begin
          if self.verb == 'GET'
            request.get
          else
            request.post filtered_test.to_json
          end
        rescue Exception => ex
          Rails.logger.warn "Could not #{verb} to subscriber #{id} at #{callback_url}: #{ex.message}\n#{ex.backtrace}"
        end

      end
    end
    self.last_run_at = now
    self.save!
  end

  def filter_test(indexed_test, fields)
    test = TestResult.includes(:sample, :device, :institution).find_by_uuid(indexed_test["test"]["uuid"])
    merged_test = indexed_test.deep_merge(test.entity_scope => test.plain_sensitive_data)
    merged_test = merged_test.deep_merge(test.sample.entity_scope => test.sample.plain_sensitive_data) if test.sample
    fields = Subscriber.available_field_names if fields.nil? || fields.empty? # use all fields if none is specified

    filtered_test = {}

    fields.each do |field_name|
      field = Subscriber.available_fields.find { |field| field_name == field.scoped_name }
      if field
        filtered_test[field.root_scope.name] ||= {}
        if (data = merged_test[field.root_scope.name])
          filtered_test[field.root_scope.name][field.name] = data[field.name]
        end
      end
    end
    filtered_test
  end
end
