require 'spec_helper'
require 'policy_spec_helper'

describe TestResultQuery, elasticsearch: true do
  let(:user)            {User.make}
  let(:user_2)          {User.make}

  let(:institution)     {Institution.make user_id: user.id}
  let(:institution_2)   {Institution.make user_id: user.id}
  let(:institution_3)   {Institution.make user_id: user.id}

  let(:laboratory)      {Laboratory.make institution: institution}
  let(:laboratory_2)    {Laboratory.make institution: institution_2}
  let(:laboratory_3)    {Laboratory.make institution: institution_3}

  let(:user_device)     {Device.make institution_id: institution.id, laboratory: laboratory}
  let(:user_device_2)   {Device.make institution_id: institution.id, laboratory: laboratory}
  let(:user_device_3)   {Device.make institution_id: institution_2.id, laboratory: laboratory_2}
  let(:user_device_4)   {Device.make institution_id: institution_3.id, laboratory: laboratory_3}
  let(:non_user_device) {Device.make}

  context "policies" do
    it "applies institution policy" do
      TestResult.create_and_index(
        core_fields: {"results" =>["condition" => "mtb", "result" => :positive]},
        device_messages:[DeviceMessage.make(device: user_device)]
      )
      TestResult.create_and_index(
        core_fields: {"results" =>["condition" => "mtb", "result" => :negative]},
        device_messages:[DeviceMessage.make(device: non_user_device)]
      )

      refresh_index

      result = TestResultQuery.for({"condition" => 'mtb'}, user).execute

      expect(result['total_count']).to eq(1)
      expect(result['tests'].first['test']['results'].first['result']).to eq('positive')
    end

    it "delegates institution policy" do
      TestResult.create_and_index(
        core_fields: {"results" =>["condition" => "mtb", "result" => :positive]},
        device_messages:[DeviceMessage.make(device: user_device)]
      )
      TestResult.create_and_index(
        core_fields: {"results" =>["condition" => "mtb", "result" => :negative]},
        device_messages:[DeviceMessage.make(device: user_device_3)]
      )

      refresh_index

      grant(user, user_2, institution, QUERY_TEST)
      grant(user, user_2, laboratory, QUERY_TEST)
      grant(user, user_2, user_device, QUERY_TEST)

      result = TestResultQuery.for({"condition" => 'mtb'}, user_2).execute

      expect(result['total_count']).to eq(1)
      expect(result['tests'].first['test']['results'].first['result']).to eq('positive')
    end

    it "doesn't fails if no device is indexed for the institution yet" do
      institution

      refresh_index

      result = TestResultQuery.for({"condition" => 'mtb'}, user).execute

      expect(result['total_count']).to eq(0)
      expect(result['tests']).to eq([])
    end

    it "should not access any test if has no policy" do
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device)]
      )

      refresh_index

      result = TestResultQuery.for({"condition" => 'mtb'}, User.new).execute

      expect(result['total_count']).to eq(0)
      expect(result['tests']).to eq([])
    end

    it "applies institution.id filter" do
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device_2)]
      )
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device_3)]
      )
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device_4)]
      )

      refresh_index

      result = TestResultQuery.for({"institution.uuid" => institution_3.uuid}, user).execute
      expect(result['total_count']).to eq(1)
    end

    it "disallows viewing another institution's tests" do
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device)]
      )
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: non_user_device)]
      )

      refresh_index

      result = TestResultQuery.for({"institution.id" => [non_user_device.institution.id.to_s, institution.id]}, user).execute
      expect(result['total_count']).to eq(1)
    end

    it "have access with policy by institution" do
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device)]
      )

      refresh_index

      grant(user, user_2, institution, QUERY_TEST)

      result = TestResultQuery.for({"condition" => 'mtb'}, user_2).execute
      expect(result['total_count']).to eq(1)
    end

    it "have access with policy by laboratory" do
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device)]
      )

      refresh_index

      grant(user, user_2, laboratory, QUERY_TEST)

      result = TestResultQuery.for({"condition" => 'mtb'}, user_2).execute
      expect(result['total_count']).to eq(1)
    end

    it "have access with policy by device" do
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device)]
      )

      refresh_index

      grant(user, user_2, user_device, QUERY_TEST)

      result = TestResultQuery.for({"condition" => 'mtb'}, user_2).execute
      expect(result['total_count']).to eq(1)
    end

    it "has access to all institutions if superadmin" do
      super_user = User.make
      super_institution = user.create Institution.make_unsaved
      super_device = Device.make institution_id: super_institution.id

      policy = Policy.superadmin
      policy.granter_id = nil
      policy.user_id = super_user.id
      policy.save(validate: false)

      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device)]
      )
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: super_device)]
      )

      refresh_index

      result = TestResultQuery.for({"condition" => 'mtb'}, super_user).execute
      expect(result['total_count']).to eq(2)
    end
  end

  context "query adapting" do
    it "should include institution name, device name, and laboratory name in the tests" do
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device)]
      )
      refresh_index

      result = TestResultQuery.for({"condition" => 'mtb'}, user).execute


      expect(result['tests'].first['institution']['name']).to eq(institution.name)
      expect(result['tests'].first['device']['name']).to eq(user_device.name)
      expect(result['tests'].first['laboratory']['name']).to eq(laboratory.name)
    end

    it "should include names if there is no lab" do
      laboratory
      device = Device.make institution_id: institution.id, laboratory: nil
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: device)]
      )
      refresh_index

      result = TestResultQuery.for({"condition" => 'mtb'}, user).execute

      expect(result['tests'].first['institution']['name']).to eq(institution.name)
      expect(result['tests'].first['device']['name']).to eq(device.name)
      expect(result['tests'].first['laboratory']['name']).to eq(nil)
    end

    it "should include the updated institution name, device name, and laboratory name in the tests" do
      TestResult.create_and_index(
        core_fields: {"test" => {"results" =>["condition" => "mtb", "result" => :positive]}},
        device_messages:[DeviceMessage.make(device: user_device)]
      )
      refresh_index

      institution.name = 'abc'
      institution.save!
      result = TestResultQuery.for({"condition" => 'mtb'}, user).execute


      expect(result['tests'].first['institution']['name']).to eq(institution.name)
      expect(result['tests'].first['device']['name']).to eq(user_device.name)
      expect(result['tests'].first['laboratory']['name']).to eq(laboratory.name)
    end

  end
end
