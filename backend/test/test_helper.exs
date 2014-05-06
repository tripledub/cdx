Dynamo.under_test(Cdp.Dynamo)
Dynamo.Loader.enable
ExUnit.start

defmodule TestHelpers do
  use ExUnit.CaseTemplate
  use Dynamo.HTTP.Case
  use Timex
  require Tirexs.Search

  def get_updates(query_string, post_data \\ "") do
    conn = get("/api/results?#{query_string}", post_data)
    assert conn.status == 200
    JSON.decode!(conn.sent_body)
  end

  def get_pii(result_uuid) do
    conn = get("api/results/#{result_uuid}/pii")
    assert conn.status == 200
    JSON.decode!(conn.sent_body)
  end

  def get_one_update(query_string, post_data \\ "") do
    [result] = get_updates(query_string, post_data)
    result
  end

  def assert_no_updates(query_string, post_data \\ "") do
    assert get_updates(query_string, post_data) == []
  end

  def post_result(result, device \\ "foo") do
    post("/api/devices/#{device}/results", JSON.encode!(result))
  end

  def create_result(result, date \\ :calendar.universal_time(), device \\ "foo") do
    TestResult.create(device, JSON.encode!(result), date)
  end

  def format_date(date) do
    DateFormat.format!(Date.from(date), "{ISO}")
  end

  def escape(string) do
    Cgi.escape(string)
  end

  def escape_and_format(date) do
    escape(format_date(date))
  end


  def fetch_many(_, []) do
    []
  end

  def fetch_many(dict, [key|other_keys]) do
    [HashDict.get(dict, key) | fetch_many(dict, other_keys)]
  end

  def assert_values(dict, keys, values) do
    assert fetch_many(dict, keys) == values
  end

  def assert_all_values([], _keys, []) do
    # Ok
  end

  def assert_all_values([dict|other_dicts], keys, [values|other_values]) do
    assert_values dict, keys, values
    assert_all_values other_dicts, keys, other_values
  end

  def create_device_and_laboratory(institution_id, secret_key) do
    laboratory = Repo.create Laboratory.new(institution_id: institution_id, name: "baz")
    device = Repo.create Device.new(institution_id: institution_id, secret_key: secret_key)
    Repo.create DevicesLaboratories.new(laboratory_id: laboratory.id, device_id: device.id)
  end

  def load_fixtures do
    institution = Repo.create Institution.new(name: "baz")
    institution2 = Repo.create Institution.new(name: "baz2")
    root_location = Repo.create Location.new(name: "locr")
    parent_location = Repo.create Location.new(name: "locp", parent_id: root_location.id)
    location1 = Repo.create Location.new(name: "loc1", parent_id: parent_location.id)
    location2 = Repo.create Location.new(name: "loc2", parent_id: parent_location.id)
    location3 = Repo.create Location.new(name: "loc3", parent_id: root_location.id)
    laboratory1 = Repo.create Laboratory.new(institution_id: institution.id, name: "bar", location_id: location1.id)
    laboratory2 = Repo.create Laboratory.new(institution_id: institution.id, name: "bar2", location_id: location2.id)
    laboratory3 = Repo.create Laboratory.new(institution_id: institution.id, name: "bar3", location_id: location3.id)
    device = Repo.create Device.new(institution_id: institution.id, secret_key: "foo")
    Repo.create DevicesLaboratories.new(laboratory_id: laboratory1.id, device_id: device.id)
    data = JSON.encode! [result: "positive"]
    {:ok, institution: institution, institution2: institution2, device: device, data: data, root_location: root_location, parent_location: parent_location, location1: location1, location2: location2, laboratory1: laboratory1, laboratory2: laboratory2, laboratory3: laboratory3}
  end

  def clear_database do
    Enum.each [Institution, Laboratory, Device, TestResult], &Repo.delete_all/1
    Tirexs.ElasticSearch.delete "#{Elasticsearch.index_prefix}*", Tirexs.ElasticSearch.Config.new()
  end
end

defmodule Cdp.TestCase do
  use ExUnit.CaseTemplate
  import TestHelpers

  setup do
    # Enable code reloading on test cases
    Dynamo.Loader.enable

    load_fixtures
  end

  teardown do
    clear_database
  end
end
