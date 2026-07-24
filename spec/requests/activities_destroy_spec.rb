require 'rails_helper'

RSpec.describe "DELETE /activities/:slug", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:owner) { create(:user, :teacher) }
  let!(:activity) { create(:activity, teacher: owner) }

  context "quando quem pede é a professora dona da atividade, mas não é admin" do
    before { sign_in owner }

    it "bloqueia e não apaga a atividade" do
      expect {
        delete activity_path(activity)
      }.not_to change(Activity, :count)

      expect(response).to redirect_to(activities_path)
      expect(activity.reload).to be_present
    end
  end

  context "quando quem pede é outra professora (não dona, não admin)" do
    before { sign_in create(:user, :teacher) }

    it "bloqueia e não apaga a atividade" do
      expect {
        delete activity_path(activity)
      }.not_to change(Activity, :count)

      expect(response).to redirect_to(activities_path)
    end
  end

  context "quando quem pede é admin" do
    before { sign_in create(:user, :admin) }

    it "apaga a atividade mesmo não sendo a dona" do
      expect {
        delete activity_path(activity)
      }.to change(Activity, :count).by(-1)

      expect(response).to redirect_to(activities_url)
    end
  end
end
