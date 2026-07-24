require 'rails_helper'

RSpec.describe "Admin::ActivitySuggestions", type: :request do
  include Devise::Test::IntegrationHelpers

  # A professora do app é fixa (Admin::ActivitySuggestionsController::TEACHER_EMAIL),
  # como já é o padrão em Admin::DraftsController — precisa bater com esse email.
  let(:admin) { create(:user, :admin, email: Admin::ActivitySuggestionsController::TEACHER_EMAIL) }

  describe "acesso" do
    it "bloqueia quem não é admin" do
      sign_in create(:user, :teacher)
      get admin_activity_suggestions_path
      expect(response).to redirect_to(root_path)
    end
  end

  context "autenticado como admin" do
    before { sign_in admin }

    describe "GET /admin/activity_suggestions" do
      it "lista as sugestões pendentes" do
        create(:activity_suggestion, status: "pending", theme: "Tema X")
        create(:activity_suggestion, status: "rejected", theme: "Tema Rejeitado")

        get admin_activity_suggestions_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Tema X")
        expect(response.body).not_to include("Tema Rejeitado")
      end
    end

    describe "POST /admin/activity_suggestions/:id/approve" do
      let(:suggestion) { create(:activity_suggestion, theme: "Pedir comida por app de delivery", level_hint: "A1", rationale: "Justificativa X") }

      it "cria a AiGeneration reaproveitando o pipeline existente e enfileira o job" do
        expect {
          post approve_admin_activity_suggestion_path(suggestion)
        }.to change(AiGeneration, :count).by(1).and have_enqueued_job(AiActivityGenerationJob)

        generation = AiGeneration.last
        expect(generation.kind).to eq("prompt")
        expect(generation.request_params["prompt"]).to include("Pedir comida por app de delivery")
        expect(generation.request_params["prompt"]).to include("Justificativa X")
        expect(response).to redirect_to(generation_wait_activities_path(id: generation.id))
        expect(suggestion.reload.status).to eq("approved")
      end
    end

    describe "POST /admin/activity_suggestions/:id/reject" do
      let(:suggestion) { create(:activity_suggestion) }

      it "marca como rejeitada" do
        post reject_admin_activity_suggestion_path(suggestion)
        expect(suggestion.reload.status).to eq("rejected")
        expect(response).to redirect_to(admin_activity_suggestions_path)
      end
    end

    describe "POST /admin/activity_suggestions/generate_now" do
      it "dispara o agente e mostra sucesso" do
        allow_any_instance_of(DailySuggestionAgentService).to receive(:call)
          .and_return(success: true, suggestion: create(:activity_suggestion))

        post generate_now_admin_activity_suggestions_path

        expect(response).to redirect_to(admin_activity_suggestions_path)
        follow_redirect!
        expect(response.body).to include("Nova sugestão gerada!")
      end

      it "avisa quando já existe sugestão hoje" do
        allow_any_instance_of(DailySuggestionAgentService).to receive(:call)
          .and_return(skipped: true, reason: "already_has_suggestion")

        post generate_now_admin_activity_suggestions_path

        follow_redirect!
        expect(response.body).to include("já tem uma sugestão para hoje")
      end
    end
  end
end
