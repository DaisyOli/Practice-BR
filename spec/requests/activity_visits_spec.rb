require 'rails_helper'

# Até onde o aluno chega numa atividade (ponto 2.1 da reformulação "Practice em
# pílulas", 17/11/2026). Quem abandona no meio não gera tentativa; é esta linha
# que mostra onde a pessoa parou.
RSpec.describe "Medição de até onde o aluno chega", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:aluno)     { create(:user, :student, level: "A1") }
  let(:atividade) { create(:activity, :A1, draft: false) }
  let!(:q1)       { create(:question, :multiple_choice, activity: atividade) }
  let!(:q2)       { create(:question, :multiple_choice, activity: atividade) }
  let!(:q3)       { create(:question, :fill_in_blank, activity: atividade) }
  let(:token)     { SecureRandom.uuid }

  def avisar(step: 1, answered: false, slug: atividade.slug, token: self.token)
    post visit_activity_path(slug), params: { token: token, step: step, answered: answered }, as: :json
  end

  def abertura
    ActivityVisit.find_by(token: token)
  end

  before { sign_in aluno }

  describe "POST /activities/:slug/visit" do
    it "o primeiro aviso cria a linha, com o total contado no servidor" do
      expect { avisar }.to change(ActivityVisit, :count).by(1)

      expect(response).to have_http_status(:no_content)
      expect(abertura).to have_attributes(user_id: aluno.id, activity_id: atividade.id,
                                          furthest_step: 1, total_steps: 3, answered_at: nil, submitted_at: nil)
    end

    it "avisos seguintes da mesma abertura atualizam a mesma linha" do
      avisar(step: 1)
      expect { avisar(step: 2) }.not_to change(ActivityVisit, :count)

      expect(abertura.furthest_step).to eq(2)
    end

    it "o passo nunca volta: um aviso atrasado não apaga o avanço" do
      avisar(step: 3)
      avisar(step: 2)

      expect(abertura.furthest_step).to eq(3)
    end

    it "o passo não passa do total nem fica abaixo de 1" do
      avisar(step: 99)
      expect(abertura.furthest_step).to eq(3)

      outra = SecureRandom.uuid
      avisar(step: -4, token: outra)
      expect(ActivityVisit.find_by(token: outra).furthest_step).to eq(1)
    end

    it "guarda a hora da primeira resposta, e só a primeira" do
      avisar(answered: true)
      primeira = abertura.answered_at
      expect(primeira).to be_present

      travel 1.minute do
        avisar(step: 2, answered: true)
      end
      expect(abertura.answered_at).to eq(primeira)
    end

    it "avançar sem responder não marca resposta" do
      avisar(step: 3, answered: false)

      expect(abertura.answered_at).to be_nil
    end

    it "recarregar a página é outra abertura" do
      avisar
      avisar(token: SecureRandom.uuid)

      expect(aluno.activity_visits.count).to eq(2)
    end

    it "ignora token fora do formato" do
      expect { avisar(token: "abc") }.not_to change(ActivityVisit, :count)
      expect(response).to have_http_status(:no_content)
    end

    it "não mexe na abertura de outra pessoa, mesmo com o token dela" do
      outro = create(:user, :student, level: "A1")
      ActivityVisit.record!(user: outro, activity: atividade, token: token, step: 1)

      avisar(step: 3, answered: true)

      expect(abertura).to have_attributes(user_id: outro.id, furthest_step: 1, answered_at: nil)
    end

    it "não grava atividade em rascunho nem slug que não existe" do
      rascunho = create(:activity, :A1, draft: true)

      expect {
        avisar(slug: rascunho.slug)
        avisar(slug: "nao-existe", token: SecureRandom.uuid)
      }.not_to change(ActivityVisit, :count)
    end

    it "não mede a professora testando a atividade" do
      sign_in create(:user, :teacher)

      expect { avisar }.not_to change(ActivityVisit, :count)
      expect(response).to have_http_status(:no_content)
    end

    it "mede quem está no teste, inclusive com o teste já encerrado" do
      pessoa = create(:user, :trial, level: "A1")
      pessoa.update_columns(trial_activities_used: 3)
      sign_in pessoa

      expect { avisar }.to change(ActivityVisit, :count).by(1)
      expect(response).to have_http_status(:no_content)
    end

    it "exige login" do
      sign_out aluno
      expect { avisar }.not_to change(ActivityVisit, :count)
    end
  end

  describe "na página do quiz" do
    it "o aluno recebe o medidor e o token no formulário" do
      get solve_activity_path(atividade)

      expect(response.body).to include('data-controller="quiz-progress quiz-visit"')
      expect(response.body).to include("quiz-progress:step->quiz-visit#advance")
      token_da_pagina = response.body[/name="visit_token"[^>]*value="([^"]+)"/, 1] ||
                        response.body[/value="([^"]+)"[^>]*name="visit_token"/, 1]
      expect(token_da_pagina).to match(ActivityVisit::TOKEN)
      expect(response.body).to include(%(data-quiz-visit-token-value="#{token_da_pagina}"))
    end

    it "a professora não recebe o medidor" do
      sign_in create(:user, :teacher)
      get solve_activity_path(atividade)

      expect(response.body).not_to include("quiz-visit")
      expect(response.body).not_to include('name="visit_token"')
    end

    it "abrir a página sozinho não cria linha: quem cria é o primeiro toque" do
      expect { get solve_activity_path(atividade) }.not_to change(ActivityVisit, :count)
    end
  end

  describe "no envio" do
    let(:respostas) { { answers: { q1.id.to_s => "Brasília" } } }

    it "marca a abertura como enviada, sem mexer no passo" do
      avisar(step: 2, answered: true)

      post submit_activity_path(atividade), params: respostas.merge(visit_token: token)

      expect(abertura.submitted_at).to be_present
      expect(abertura.furthest_step).to eq(2)
    end

    it "se o aviso do navegador não chegou antes, a linha nasce no envio" do
      expect {
        post submit_activity_path(atividade), params: respostas.merge(visit_token: token)
      }.to change(ActivityVisit, :count).by(1)

      expect(abertura.submitted_at).to be_present
    end

    it "envio sem token continua funcionando, só não mede" do
      expect {
        post submit_activity_path(atividade), params: respostas
      }.to change(QuizAttempt, :count).by(1).and change(ActivityVisit, :count).by(0)
    end
  end

  describe "Activity#quiz_step_count" do
    it "conta questões, ordenações e ligações de colunas, como o \"1 de N\" da tela" do
      SentenceOrdering.create!(activity: atividade, sentence: "Eu gosto de café")
      expect(atividade.reload.quiz_step_count).to eq(4)
    end
  end

  describe "ao apagar" do
    it "some junto com a conta" do
      avisar
      expect { aluno.destroy }.to change(ActivityVisit, :count).by(-1)
    end

    it "some junto com a atividade" do
      avisar
      expect { atividade.destroy }.to change(ActivityVisit, :count).by(-1)
    end
  end
end
