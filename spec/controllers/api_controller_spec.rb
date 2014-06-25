require 'spec_helper'

describe ApiController do
  let(:institution) {Institution.create name: "baz"}
  let!(:device) {Device.make name: "foo", institution: institution}
  let(:data) {Oj.dump result: "positive"}

  def get_all_elasticsearch_events
    client = Elasticsearch::Client.new log: true
    client.indices.refresh index: institution.elasticsearch_index_name
    client.search(index: institution.elasticsearch_index_name)["hits"]["hits"].first["_source"]
  end

  it "should create event in the database" do
    conn = post :create, data, device_uuid: device.secret_key
    conn.status.should eq(200)

    event = Event.first
    event.device_id.should eq(device.id)
    event.raw_data.should_not eq(data)
    event.decrypt.raw_data.should eq(data)
  end

  it "should create event in elasticsearch" do
    conn = post :create, data, device_uuid: device.secret_key

    event = get_all_elasticsearch_events
    event["result"].should eq("positive")
    event["created_at"].should_not eq(nil)
    event["device_uuid"].should eq(device.secret_key)
  end

  it "applies an existing manifest" do
    manifest = Manifest.create definition: %{{
      "metadata" : {
        "device_models" : ["#{device.device_model.name}"],
        "version" : 1
      },
      "field_mapping" : [{
          "target_field" : "assay_name",
          "selector" : "assay/name",
          "type" : "core"
        }]
    }}
    post :create, Oj.dump(assay: {name: "GX4002"}, patient_id: 1234), device_uuid: device.secret_key

    event = get_all_elasticsearch_events
    event["assay_name"].should eq("GX4002")
    event["created_at"].should_not eq(nil)
    event["patient_id"].should be(nil)
  end
end