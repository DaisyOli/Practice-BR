require 'rails_helper'

# "✂️ Adaptar em pílulas" e a série no caminho do aluno (ponto 1.4, 17/11/2026).
RSpec.describe "Adaptar em pílulas", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:teacher)  { create(:user, :teacher) }
  let(:original) { create(:activity, :B1, teacher: teacher, draft: false, title: "Atividade longa") }

  def parte(posicao, **attrs)
    create(:activity, :B1, teacher: teacher, pill: true, ai_generated: true, source_activity: original,
                           series_key: "adaptacao-teste", series_position: posicao, **attrs)
  end

  describe "a professora" do
    before { sign_in teacher }

    it "vê o botão na atividade, e a tela explica o que vai acontecer" do
      get activity_path(original)
      expect(response.body).to include("Adaptar em pílulas", adapt_activity_path(original))

      get adapt_activity_path(original)
      expect(response.body).to include("1 a 3 pílulas", "continua como está")
      expect(response.body).not_to include('name="transcript"')
    end

    it "manda adaptar: a IA trabalha em segundo plano e a tela de espera abre" do
      expect { post adapt_activity_path(original) }.to have_enqueued_job(AiActivityGenerationJob)

      geracao = AiGeneration.last
      expect(geracao).to have_attributes(kind: "adapt", teacher_id: teacher.id)
      expect(geracao.request_params["source_activity_id"]).to eq(original.id)
      expect(response).to redirect_to(generation_wait_activities_path(id: geracao.id))

      get generation_wait_activities_path(id: geracao.id)
      expect(response.body).to include("revisão da primeira pílula")
    end

    it "atividade com vídeo pede a transcrição com tempos" do
      original.update!(video_url: "https://www.youtube.com/watch?v=abcdefghijk")

      get adapt_activity_path(original)
      expect(response.body).to include('name="transcript"', "deixando os tempos")

      expect { post adapt_activity_path(original), params: { transcript: "  " } }
        .not_to have_enqueued_job(AiActivityGenerationJob)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "pílula não tem o botão" do
      pilula = create(:activity, :B1, teacher: teacher, draft: false, pill: true)

      get activity_path(pilula)
      expect(response.body).not_to include(adapt_activity_path(pilula))
      get adapt_activity_path(pilula)
      expect(response).to redirect_to(activity_path(pilula))
    end

    it "a revisão mostra a parte, a original e as outras partes" do
      p1 = parte(1, draft: true)
      parte(2, draft: true)

      get review_draft_activity_path(p1)
      expect(response.body).to include("Parte 1 de 2", "adaptada de", "«Atividade longa»", "Parte 2 · rascunho")
    end

    describe "ao publicar" do
      before { create(:user, :student, level: "B1") }

      it "a parte 1 avisa os alunos" do
        expect(PushNotificationService).to receive(:send_to_user).at_least(:once)
        post publish_draft_activity_path(parte(1, draft: true))
      end

      it "a parte 2 não avisa de novo" do
        expect(PushNotificationService).not_to receive(:send_to_user)
        post publish_draft_activity_path(parte(2, draft: true))
      end
    end
  end

  it "outra professora não adapta atividade alheia" do
    sign_in create(:user, :teacher)
    get adapt_activity_path(original)
    expect(response).to redirect_to(activities_path)
  end

  describe "o aluno" do
    let(:student) { create(:user, :student, level: "B1") }
    let!(:p1)     { parte(1, draft: false) }
    let!(:p2)     { parte(2, draft: false, title: "A segunda parte") }
    let!(:q1)     { create(:question, :multiple_choice, activity: p1) }

    before { sign_in student }

    it "no fim da parte 1 recebe a parte 2 como continuação, antes do percurso" do
      no_percurso = create(:activity, :B1, teacher: teacher, draft: false)
      Activity.set_path!("B1", [no_percurso.id])

      post submit_activity_path(p1), params: { answers: { q1.id.to_s => "Brasília" } }
      get results_activity_path(p1)

      expect(response.body).to include("Continuar · Parte 2 de 2", "A segunda parte")
    end

    it "o quiz mostra em que parte o aluno está" do
      get solve_activity_path(p1)
      expect(response.body).to include("Parte 1 de 2")
    end
  end
end
