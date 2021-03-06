namespace :cdx_elasticsearch do
  desc "Initialize the cdx elasticsearch index template"
  task initialize_template: :environment do
    Cdx::Api.config.log = false
    Cdx::Api::Elasticsearch::MappingTemplate.new.initialize_template "cdx_tests_template_#{Rails.env}"
    begin
      Cdx::Api.client.indices.create index: Cdx::Api.index_name
    rescue Elasticsearch::Transport::Transport::Errors::BadRequest => ex
      raise unless ex.message =~ /IndexAlreadyExistsException/
    end
  end

  desc "Re-Index all the test results into elasticsearch"
  task reindex: :initialize_template do
    total_count = TestResult.count
    index = 0
    TestResult.find_each do |test_result|
      index += 1
      print "\rIndexing #{index} of #{total_count}"
      TestResultIndexer.new(test_result).index
    end
    puts "\rDone#{' ' * 50}"
  end
end
