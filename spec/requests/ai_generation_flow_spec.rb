require 'rails_helper'

RSpec.describe "Geração de atividade por IA em background", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:teacher) { create(:user, :teacher) }

  before { sign_in teacher }

  describe "POST /activities/generate_with_ai" do
    it "cria a AiGeneration, enfileira o job e manda para a página de espera" do
      expect {
        post generate_with_ai_activities_path, params: { ai_prompt: "Atividade sobre pretérito perfeito" }
      }.to change(AiGeneration, :count).by(1).and have_enqueued_job(AiActivityGenerationJob)

      generation = AiGeneration.last
      expect(generation.kind).to eq("prompt")
      expect(generation.request_params["prompt"]).to include("pretérito")
      expect(response).to redirect_to(generation_wait_activities_path(id: generation.id))
    end
  end

  describe "POST /activities/generate_from_video" do
    it "valida transcrição vazia sem enfileirar" do
      expect {
        post generate_from_video_activities_path, params: { youtube_url: "https://youtu.be/abc", transcript: "" }
      }.not_to change(AiGeneration, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Desde 17/11, o padrão é "em pílulas", que pede a transcrição com tempos.
    it "enfileira com transcrição presente" do
      post generate_from_video_activities_path,
           params: { youtube_url: "https://youtu.be/abc", transcript: "0:00\nOlá, hoje vamos falar de..." }

      generation = AiGeneration.last
      expect(generation.kind).to eq("video")
      expect(response).to redirect_to(generation_wait_activities_path(id: generation.id))
    end
  end

  describe "página de espera e status" do
    let(:generation) { AiGeneration.create!(teacher: teacher, kind: "prompt", request_params: { prompt: "x" }) }

    it "renderiza a espera enquanto roda" do
      get generation_wait_activities_path(id: generation.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('ai_generation.wait_title'))
    end

    it "status devolve redirect_url quando pronta" do
      activity = create(:activity, teacher: teacher)
      generation.update!(status: "done", activity: activity)

      get generation_status_activities_path(id: generation.id)
      expect(response.parsed_body["status"]).to eq("done")
      expect(response.parsed_body["redirect_url"]).to eq(review_draft_activity_path(activity))
    end

    it "renderiza o erro e o tentar de novo quando falha" do
      generation.update!(status: "failed", error_message: "Deu ruim na IA")

      get generation_wait_activities_path(id: generation.id)
      expect(response.body).to include("Deu ruim na IA")
      expect(response.body).to include(I18n.t('ai_generation.try_again'))
    end

    it "não mostra geração de outra professora" do
      other = create(:user, :teacher)
      foreign = AiGeneration.create!(teacher: other, kind: "prompt", request_params: { prompt: "y" })

      get generation_wait_activities_path(id: foreign.id)
      expect(response).to redirect_to(activities_path)
    end
  end
end
