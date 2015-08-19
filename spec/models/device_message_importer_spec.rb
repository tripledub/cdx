# encoding UTF8
require 'spec_helper'
require 'fileutils'

describe DeviceMessageImporter, elasticsearch: true do

  let(:user) {User.make}
  let(:institution) {Institution.make user_id: user.id}
  let(:device_model) { DeviceModel.make name: 'test_model', manifests: []}
  let(:device) {Device.make institution_id: institution.id, device_model: device_model}
  let(:sync_dir) { CDXSync::SyncDirectory.new(Dir.mktmpdir('sync')) }

  before do
    sync_dir.ensure_sync_path!
    sync_dir.ensure_client_sync_paths! device.uuid
  end

  def write_file(content, extension, name=nil, encoding='UTF-8')
    File.open(File.join(sync_dir.inbox_path(device.uuid), "#{name || DateTime.now.strftime('%Y%m%d%H%M%S')}.#{extension}"), "w", encoding: encoding) do |io|
      io << content
    end
  end

  let(:manifest) do Manifest.create! definition: %{
    {
      "metadata": {
        "version": "1",
        "api_version": "#{Manifest::CURRENT_VERSION}",
        "device_models": "#{device.device_model.name}",
        "conditions": ["MTB"],
        "source" : { "type" : "#{source}"}
      },
      "field_mapping" : {
        "test.error_code" : {"lookup": "error_code"},
        "test.assays[*].result" : {
          "case": [
          {"lookup": "result"},
          [
            {"when": "positivo", "then" : "positive"},
            {"when": "positive", "then" : "positive"},
            {"when": "negative", "then" : "negative"},
            {"when": "negativo", "then" : "negative"},
            {"when": "inválido", "then" : "n/a"}
          ]
        ]},
        "test.status" : {
          "case": [
          {"lookup": "result"},
          [
            {"when": "inválido", "then" : "invalid"},
            {"when": "invalid", "then" : "invalid"},
            {"when": "*", "then" : "success"}
          ]
        ]}
      }
    }
  }
  end

  context "csv" do
    let(:source) { "csv" }

    it 'parses a csv from sync dir' do
      manifest
      write_file(%{error_code;result\n0;positive\n1;negative}, 'csv')
      DeviceMessageImporter.new.import_from sync_dir

      expect(DeviceMessage.first.index_failure_reason).to be_nil
      tests = all_elasticsearch_tests.sort_by { |test| test["_source"]["test"]["error_code"] }
      test = tests.first["_source"]["test"]
      test["error_code"].should eq(0)
      test["assays"].first["result"].should eq("positive")
      test = tests.last["_source"]["test"]
      test["error_code"].should eq(1)
      test["assays"].first["result"].should eq("negative")
    end

    it 'parses a csv in utf 16' do
      manifest

      write_file(%{error_code;result\r\n0;positivo\r\n1;inválido\r\n}, 'csv', nil, 'UTF-16LE')
      CharDet.stub(:detect).and_return('encoding' => 'UTF-16LE', 'confidence' => 1.0)
      DeviceMessageImporter.new.import_from sync_dir

      expect(DeviceMessage.first.index_failure_reason).to be_nil
      tests = all_elasticsearch_tests.sort_by { |test| test["_source"]["test"]["error_code"] }
      test = tests.first["_source"]["test"]
      test["error_code"].should eq(0)
      test["assays"].first["result"].should eq("positive")
      test = tests.last["_source"]["test"]
      test["error_code"].should eq(1)
      test["assays"].first["result"].should eq("n/a")
    end
  end

  context "json" do

    let(:source) { "json" }

    it 'parses a json from sync dir' do
      manifest
      write_file('[{"error_code": "0", "result": "positive"}, {"error_code": "1", "result": "negative"}]', 'json')
      DeviceMessageImporter.new("*.json").import_from sync_dir

      expect(DeviceMessage.first.index_failure_reason).to be_nil
      tests = all_elasticsearch_tests.sort_by { |test| test["_source"]["test"]["error_code"] }
      test = tests.first["_source"]["test"]
      test["error_code"].should eq(0)
      test["assays"].first["result"].should eq("positive")
      test = tests.last["_source"]["test"]
      test["error_code"].should eq(1)
      test["assays"].first["result"].should eq("negative")
    end

    it 'parses a json from sync dir registering multiple extensions' do
      manifest
      write_file('[{"error_code": "0", "result": "positive"}, {"error_code": "1", "result": "negative"}]', 'json')
      DeviceMessageImporter.new("*.{csv,json}").import_from sync_dir

      expect(DeviceMessage.first.index_failure_reason).to be_nil
      tests = all_elasticsearch_tests.sort_by { |test| test["_source"]["test"]["error_code"] }
      test = tests.first["_source"]["test"]
      test["error_code"].should eq(0)
      test["assays"].first["result"].should eq("positive")
      test = tests.last["_source"]["test"]
      test["error_code"].should eq(1)
      test["assays"].first["result"].should eq("negative")
    end

    it 'parses a json from sync dir registering multiple extensions using import single' do
      manifest
      write_file('[{"error_code": "0", "result": "positive"}, {"error_code": "1", "result": "negative"}]', 'json', 'mytestfile')
      DeviceMessageImporter.new("*.{csv,json}").import_single(sync_dir, File.join(sync_dir.inbox_path(device.uuid), "mytestfile.json"))

      expect(DeviceMessage.first.index_failure_reason).to be_nil
      tests = all_elasticsearch_tests.sort_by { |test| test["_source"]["test"]["error_code"] }
      test = tests.first["_source"]["test"]
      test["error_code"].should eq(0)
      test["assays"].first["result"].should eq("positive")
      test = tests.last["_source"]["test"]
      test["error_code"].should eq(1)
      test["assays"].first["result"].should eq("negative")
    end
  end

  context "real scenarios" do

    def copy_sample_csv(name)
      copy_sample(name, 'csvs')
    end

    def copy_sample_xml(name)
      copy_sample(name, 'xmls')
    end

    def copy_sample(name, format)
      FileUtils.cp File.join(Rails.root, 'spec', 'fixtures', format, name), sync_dir.inbox_path(device.uuid)
    end

    def load_manifest(name)
      Manifest.create! definition: IO.read(File.join(Rails.root, 'db', 'seeds', 'manifests', name))
    end

    context 'epicenter headless_es' do
      let!(:device_model) { DeviceModel.make name: 'epicenter_headless_es', manifests: []}
      let!(:manifest)    { load_manifest 'epicenter_headless_es_manifest.json' }

      it "parses csv in utf-16le" do
        copy_sample_csv 'epicenter_headless_sample_utf16.csv'
        DeviceMessageImporter.new("*.csv").import_from sync_dir

        expect(DeviceMessage.first.index_failure_reason).to be_nil
        tests = all_elasticsearch_tests
        expect(tests.size).to eq(18)
        tests.map{|e| e['_source']['test']['start_time']}.should =~ ['2014-09-09T17:07:32.000Z', '2014-10-28T13:00:58.000Z', '2014-10-28T17:24:34.000Z', '2015-02-10T18:10:28.000Z', '2015-03-03T19:27:36.000Z', '2015-03-31T18:35:19.000Z', '2015-03-31T18:35:19.000Z', '2015-03-31T18:35:19.000Z', '2015-03-31T18:35:19.000Z', '2015-03-31T18:34:08.000Z', '2015-03-31T18:34:08.000Z', '2015-03-31T18:34:08.000Z', '2015-03-31T18:34:08.000Z', '2014-11-05T08:38:30.000Z', '2014-10-29T12:24:59.000Z', '2014-10-29T12:24:59.000Z', '2014-10-29T12:24:59.000Z', '2014-10-29T12:24:59.000Z']
      end
    end

    context 'cepheid' do
      let!(:device_model) { DeviceModel.make name: "GX Model I", manifests: []}
      let!(:manifest)    { load_manifest 'cepheid_demo_manifest.json' }

      it "should parse cepheid's document" do
        copy_sample('cepheid_sample.json', 'jsons')
        DeviceMessageImporter.new("*.json").import_from sync_dir

        expect(DeviceMessage.first.index_failure_reason).to be_nil
        tests = all_elasticsearch_tests
        expect(tests.size).to eq(1)
        tests.first['_source']['test']['start_time'].should eq('2015-04-07T18:31:20-05:00')
      end
    end

    context 'genoscan' do
      let(:device_model) { DeviceModel.make name: 'genoscan', manifests: []}
      let!(:manifest) { load_manifest 'genoscan_manifest.json' }

      it 'parses csv' do
        copy_sample_csv 'genoscan_sample.csv'
        DeviceMessageImporter.new("*.csv").import_from sync_dir

        expect(DeviceMessage.first.index_failure_reason).to be_nil
        tests = all_elasticsearch_tests.sort_by do |test|
          test["_source"]["test"]["assays"][0]['result'] + test["_source"]["test"]["assays"][1]['result'] + test["_source"]["test"]["assays"][2]['result']
        end
        expect(tests.size).to eq(13)

        test = tests[0]["_source"]["test"]
        test["assays"][0]["name"].should eq("mtb")
        test["assays"][0]["result"].should eq("negative")
        test["assays"][1]["name"].should eq("rif")
        test["assays"][1]["result"].should eq("negative")
        test["assays"][2]["name"].should eq("inh")
        test["assays"][2]["result"].should eq("negative")

        test = tests[1]["_source"]["test"]
        test["assays"][0]["name"].should eq("mtb")
        test["assays"][0]["result"].should eq("positive")
        test["assays"][1]["name"].should eq("rif")
        test["assays"][1]["result"].should eq("negative")
        test["assays"][2]["name"].should eq("inh")
        test["assays"][2]["result"].should eq("negative")

        test = tests.last["_source"]["test"]
        test["assays"][0]["name"].should eq("mtb")
        test["assays"][0]["result"].should eq("positive")
        test["assays"][1]["name"].should eq("rif")
        test["assays"][1]["result"].should eq("positive")
        test["assays"][2]["name"].should eq("inh")
        test["assays"][2]["result"].should eq("positive")

        dbtests = TestResult.all
        expect(dbtests.size).to eq(13)
        dbtests.map(&:uuid).should =~ tests.map {|e| e['_source']['test']['uuid']}
      end
    end

    context 'fio' do
      let(:device_model) { DeviceModel.make name: 'FIO', manifests: []}
      let!(:manifest) { load_manifest 'fio_manifest.json' }

      it 'parses xml' do
        copy_sample_xml 'fio_sample.xml'
        DeviceMessageImporter.new("*.xml").import_from sync_dir

        expect(DeviceMessage.first.index_failure_reason).to be_nil
        tests = all_elasticsearch_tests
        expect(tests.size).to eq(1)

        test = tests.first['_source']

        test['test']['id'].should eq('12345678901234567890')
        test['patient']['gender'].should eq('female')
        test['test']['patient_age'].should eq({"years" => 25})
        test['patient']['custom_fields']['pregnancy_status'].should eq('Not Pregnant')
        test['sample']['id'].should eq('0987654321')
        test['test']['start_time'].should  eq('2015-05-18T12:34:56+05:00')
        test['test']['name'].should eq('SD_MALPFPV_02_02')
        test['test']['status'].should eq('success')

        assays = test['test']['assays']
        assays.size.should eq(2)
        assays.first['result'].should eq('positive')
        assays.first['name'].should eq('HRPII')
        assays.second['result'].should eq('negative')
        assays.second['name'].should eq('pLDH')

        TestResult.count.should eq(1)
        db_test = TestResult.first
        db_test.uuid.should eq(test['test']['uuid'])
        db_test.test_id.should eq('12345678901234567890')
      end
    end
  end
end
