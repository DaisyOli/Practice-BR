require 'rails_helper'

# A escolha de formato no formulário do gerador por vídeo (17/11/2026).
RSpec.describe "Gerador por vídeo: formato", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:teacher) { create(:user, :teacher) }
  let(:url)     { "https://www.youtube.com/watch?v=abcdefghijk" }
  let(:com_tempos) { "0:00\nOlá!\n1:30\nAgora a receita." }

  before { sign_in teacher }

  it "o formulário oferece as duas opções, com pílulas marcado e a quantidade" do
    get generate_from_video_activities_path

    expect(response.body).to include("Em pílulas", "Vídeo inteiro", "A IA decide (1 a 3)")
    expect(response.body).to match(/value="pills"[^>]*checked/)
    expect(response.body).to include('<option value="5">5</option>')
  end

  it "em pílulas, guarda o formato e a quantidade para o job" do
    expect {
      post generate_from_video_activities_path, params: { youtube_url: url, transcript: com_tempos, mode: "pills", pill_count: "4" }
    }.to have_enqueued_job(AiActivityGenerationJob)

    expect(AiGeneration.last.request_params).to include("mode" => "pills", "pill_count" => "4")
  end

  it "em pílulas sem os tempos, volta pedindo a transcrição certa" do
    expect {
      post generate_from_video_activities_path, params: { youtube_url: url, transcript: "Olá! Agora a receita.", mode: "pills" }
    }.not_to have_enqueued_job(AiActivityGenerationJob)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("com os tempos")
  end

  # Relato da Daisy (18/11/2026): a cópia do YouTube gruda cada tempo na fala,
  # e o formulário recusava a transcrição por "não ter tempos".
  it "aceita a transcrição copiada do YouTube e guarda a versão limpa" do
    copia = "0:000 segundosOlá, pessoal!\n1:301 minuto e 30 segundosAgora a receita."

    expect {
      post generate_from_video_activities_path, params: { youtube_url: url, transcript: copia, mode: "pills" }
    }.to have_enqueued_job(AiActivityGenerationJob)

    expect(AiGeneration.last.request_params["transcript"]).to eq("0:00 Olá, pessoal!\n1:30 Agora a receita.")
  end

  it "vídeo inteiro não precisa dos tempos" do
    expect {
      post generate_from_video_activities_path, params: { youtube_url: url, transcript: "Olá! Agora a receita.", mode: "whole" }
    }.to have_enqueued_job(AiActivityGenerationJob)

    expect(AiGeneration.last.request_params).to include("mode" => "whole")
  end
end
