require 'rails_helper'

# Ponto 1.2 da reformulação "Practice em pílulas" (16/11/2026): na pílula, a
# pergunta aberta sai do quiz e vira um desafio de escrita opcional, oferecido
# depois do resultado. A nota conta só os exercícios fechados; o desafio tem a
# própria correção da IA e fica em "Minhas expressões escritas".
RSpec.describe "Desafio de escrita da pílula", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:teacher) { create(:user, :teacher) }
  let(:student) { create(:user, :student) }

  let(:pilula)   { create(:activity, :B1, teacher: teacher, draft: false, pill: true) }
  let!(:mc1)     { create(:question, :multiple_choice, activity: pilula) }
  let!(:mc2)     { create(:question, :multiple_choice, activity: pilula, content: "Qual é a capital da França?",
                          options: %w[Paris Lyon Nice Lille], correct_answer: "Paris") }
  let!(:desafio) { create(:question, :open_ended, activity: pilula, content: "Escreva 3 frases sobre o seu fim de semana.") }

  let(:nota_provisoria) { I18n.t('quiz.ai_grading_note') }

  before { sign_in student }

  def enviar_quiz(respostas = { mc1.id.to_s => "Brasília", mc2.id.to_s => "Paris" })
    post submit_activity_path(pilula), params: { answers: respostas }
  end

  def enviar_desafio(texto)
    post challenge_activity_path(pilula), params: { challenge_answer: texto }
  end

  def tentativa
    student.quiz_attempts.find_by(activity: pilula)
  end

  describe "no quiz" do
    it "a pergunta aberta não aparece, e o contador conta só os fechados" do
      get solve_activity_path(pilula)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(mc1.content)
      expect(response.body).not_to include(desafio.content)
      expect(response.body).to include("1 de 2")
    end

    it "a nota conta só os fechados, e nada vai para a IA" do
      expect { enviar_quiz }.not_to have_enqueued_job(AiGradingJob)

      expect(tentativa.score).to eq(100.0)
      expect(tentativa.results["total_questions"]).to eq(2)
      expect(tentativa.results["results"]).not_to have_key(desafio.id.to_s)
    end
  end

  describe "na tela de resultado" do
    before { enviar_quiz }

    it "convida para o desafio, sem o aviso de nota provisória" do
      get results_activity_path(pilula)

      expect(response.body).to include("Desafio de escrita")
      expect(response.body).to include(desafio.content)
      expect(response.body).to include('name="challenge_answer"')
      expect(response.body).to include("Agora não")
      expect(response.body).not_to include(nota_provisoria)
    end

    it "o cartão de nota avisa que o desafio existe" do
      get solve_activity_path(pilula, show_score: true)
      expect(response.body).to include("No resultado tem um desafio de escrita")
    end
  end

  describe "ao enviar o desafio" do
    before { enviar_quiz }

    it "guarda o texto como desafio, fora da nota, e chama a IA" do
      expect { enviar_desafio("Eu fui à praia com a minha irmã.") }
        .to have_enqueued_job(AiGradingJob).with(tentativa.id)

      expect(response).to redirect_to(results_activity_path(pilula, anchor: "desafio"))
      entrada = tentativa.challenge_entry
      expect(entrada).to include("challenge" => true, "ai_pending" => true,
                                 "given_answer" => "Eu fui à praia com a minha irmã.",
                                 "question_type" => "open_ended")
      expect(tentativa.score).to eq(100.0)

      get results_activity_path(pilula)
      expect(response.body).to include("A IA está lendo o seu texto")
      expect(response.body).to include('data-controller="grading-status"')
      expect(response.body).not_to include(nota_provisoria)
    end

    it "texto em branco não grava nada" do
      expect { enviar_desafio("   ") }.not_to have_enqueued_job(AiGradingJob)
      expect(tentativa.challenge_entry).to be_nil
      expect(flash[:alert]).to be_present
    end

    it "o segundo envio (duplo clique, aba antiga) é ignorado" do
      enviar_desafio("Primeiro texto.")
      expect { enviar_desafio("Segundo texto.") }.not_to have_enqueued_job(AiGradingJob)
      expect(tentativa.challenge_entry["given_answer"]).to eq("Primeiro texto.")
    end

    it "texto gigante é cortado no teto" do
      enviar_desafio("a" * (ActivitiesController::CHALLENGE_MAX_CHARS + 500))
      expect(tentativa.challenge_entry["given_answer"].size).to eq(ActivitiesController::CHALLENGE_MAX_CHARS)
    end
  end

  describe "a correção da IA" do
    let(:client) { instance_double(Anthropic::Client) }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("chave-de-teste")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY").and_return("chave-de-teste")
      allow(Anthropic::Client).to receive(:new).and_return(client)
      allow(client).to receive_message_chain(:messages, :create)
        .and_return(double(content: [double(type: :text, text: '{"score": 90, "feedback": "Muito bem!"}')]))
    end

    it "corrige o desafio sem mexer na nota da pílula" do
      enviar_quiz(mc1.id.to_s => "Brasília", mc2.id.to_s => "Lyon") # metade certa
      expect(tentativa.score).to eq(50.0)

      enviar_desafio("Eu descansei e li um livro.")
      AiGradingService.new(tentativa).call

      tentativa.reload
      expect(tentativa.score).to eq(50.0)
      expect(tentativa.results["total_questions"]).to eq(2)
      expect(tentativa.challenge_entry).to include("ai_score" => 90, "ai_feedback" => "Muito bem!")
      expect(tentativa.challenge_entry).not_to have_key("ai_pending")

      get results_activity_path(pilula)
      expect(response.body).to include("Muito bem!")
      expect(response.body).to include("90/100")
      expect(response.body).to include("Minhas expressões escritas")
    end
  end

  it "refazer a pílula mantém o desafio e o comentário da professora sobre ele" do
    enviar_quiz
    enviar_desafio("Meu texto do desafio.")
    tentativa.update!(teacher_comments: { "question_#{desafio.id}" => "Ótimo texto!",
                                          "question_#{mc1.id}" => "Reveja esta." })

    enviar_quiz(mc1.id.to_s => "Salvador", mc2.id.to_s => "Paris")

    tentativa.reload
    expect(tentativa.score).to eq(50.0)
    expect(tentativa.challenge_entry["given_answer"]).to eq("Meu texto do desafio.")
    expect(tentativa.teacher_comments).to eq("question_#{desafio.id}" => "Ótimo texto!")
  end

  it "o desafio aparece em Minhas expressões escritas só depois de enviado" do
    enviar_quiz
    get student_dashboard_path
    expect(response.body).to include('data-has-written="false"')

    enviar_desafio("Agora tenho uma expressão escrita.")
    get student_dashboard_path
    expect(response.body).to include('data-has-written="true"')
  end

  describe "atividade que não é pílula" do
    let(:comum)   { create(:activity, :B1, teacher: teacher, draft: false) }
    let!(:fechada) { create(:question, :multiple_choice, activity: comum, content: "Pergunta da atividade comum?",
                            options: %w[Sim Não Talvez Nunca], correct_answer: "Sim") }
    let!(:aberta)  { create(:question, :open_ended, activity: comum, content: "Pergunta aberta da atividade comum.") }

    it "continua como sempre: a aberta fica no quiz e conta na nota" do
      get solve_activity_path(comum)
      expect(response.body).to include(aberta.content)

      post submit_activity_path(comum), params: { answers: { fechada.id.to_s => "Sim" } } # aberta em branco
      attempt = student.quiz_attempts.find_by(activity: comum)
      expect(attempt.score).to eq(50.0)

      get results_activity_path(comum)
      expect(response.body).not_to include("Desafio de escrita")
    end

    it "o resultado de uma atividade não mostra a tentativa de outra" do
      enviar_quiz # pílula
      post submit_activity_path(comum), params: { answers: { fechada.id.to_s => "Sim" } }

      # A sessão agora guarda a tentativa da atividade comum.
      get results_activity_path(pilula)
      expect(response.body).to include(mc1.content)
      expect(response.body).not_to include(fechada.content)
    end
  end

  it "a revisão de rascunho mostra a aberta da pílula como desafio" do
    rascunho = create(:activity, :A1, teacher: teacher, draft: true, pill: true)
    create(:question, :open_ended, activity: rascunho, content: "Apresente-se em 2 frases.")

    sign_in teacher
    get review_draft_activity_path(rascunho)

    expect(response.body).to include("Desafio de escrita")
    expect(response.body).not_to include("Preencher lacuna")
  end
end
