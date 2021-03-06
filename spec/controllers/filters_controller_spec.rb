require 'spec_helper'

describe FiltersController do
  let(:user) { User.make }
  let!(:institution) { user.create Institution.make_unsaved }
  let!(:filter) { user.filters.make query: { laboratory: 1 } }
  before(:each) { sign_in user }

  it "list filters" do
    get :index, format: :json
    expect(response.body).to eq([filter].to_json)
  end
end
