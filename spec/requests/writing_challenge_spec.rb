require 'rails_helper'

# Desafio de escrita da pílula (pontos 1.2 e 1.2b da reformulação "Practice em
# pílulas", 16/11/2026): a pergunta aberta vira o último passo do quiz,
# opcional, com "Pular". A nota conta só os exercícios fechados; o texto, se
# houver, é corrigido pela IA à parte e vai para "Minhas expressões escritas".
#
# Na primeira versão o desafio ficava na tela de resultado, mas a nota já soa
# como "acabou" e o convite ficava esquecido.
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

  let(:certas)          { { mc1.id.to_s => "Brasília", mc2.id.to_s => "Paris" } }
  let(:nota_provisoria) { I18n.t('quiz.ai_grading_note') }

  before { sign_in student }

  def enviar(respostas: certas, texto: nil, pular: false)
    params = { answers: respostas }
    params[:challenge_answer] = texto if texto
    params[:skip_challenge]   = "1" if pular
    post submit_activity_path(pilula), params: params
  end

  def tentativa
    student.quiz_attempts.find_by(activity: pilula)
  end

  describe "no quiz" do
    it "o desafio é o último passo, opcional, com o botão de pular" do
      get solve_activity_path(pilula)

      expect(response).to have_http_status(:ok)
      corpo = response.body
      expect(corpo).to include(mc1.content, desafio.content, "opcional · não muda a sua nota")
      expect(corpo.index(mc2.content)).to be < corpo.index(desafio.content)
      expect(corpo).to include('name="challenge_answer"', 'name="skip_challenge"', "Pular e ver minha nota")
      expect(corpo).not_to include(%(name="answers[#{desafio.id}]"))
      expect(corpo).to include("1 de 3") # 2 fechados + o desafio
    end
  end

  describe "ao enviar" do
    it "sem texto: a nota conta só os fechados, nada vai para a IA, e fica registrado que pulou" do
      expect { enviar }.not_to have_enqueued_job(AiGradingJob)

      expect(tentativa.score).to eq(100.0)
      expect(tentativa.results["total_questions"]).to eq(2)
      expect(tentativa.challenge_entry).to be_nil
      expect(tentativa.results["challenge"]).to eq("skipped")
    end

    it "com texto: guarda como desafio, fora da nota, e chama a IA" do
      expect { enviar(texto: "Eu fui à praia com a minha irmã.") }.to have_enqueued_job(AiGradingJob)

      expect(tentativa.score).to eq(100.0)
      expect(tentativa.results["total_questions"]).to eq(2)
      expect(tentativa.results["challenge"]).to eq("written")
      expect(tentativa.challenge_entry).to include("challenge" => true, "ai_pending" => true,
                                                   "given_answer" => "Eu fui à praia com a minha irmã.",
                                                   "question_type" => "open_ended")
    end

    it "o botão Pular ignora o que estiver escrito" do
      expect { enviar(texto: "Texto pela metade", pular: true) }.not_to have_enqueued_job(AiGradingJob)

      expect(tentativa.challenge_entry).to be_nil
      expect(tentativa.results["challenge"]).to eq("skipped")
    end

    it "texto gigante é cortado no teto" do
      enviar(texto: "a" * (QuizAttempt::CHALLENGE_MAX_CHARS + 500))
      expect(tentativa.challenge_entry["given_answer"].size).to eq(QuizAttempt::CHALLENGE_MAX_CHARS)
    end
  end

  describe "na tela de resultado" do
    it "quem pulou não vê convite nem cartão do desafio" do
      enviar
      get results_activity_path(pilula)

      expect(response.body).not_to include("Desafio de escrita")
      expect(response.body).not_to include('name="challenge_answer"')
      expect(response.body).not_to include(nota_provisoria)
    end

    it "quem escreveu vê a IA lendo, sem o aviso de nota provisória" do
      enviar(texto: "Eu descansei e li um livro.")
      get results_activity_path(pilula)

      expect(response.body).to include("Desafio de escrita", "A IA está lendo o seu texto")
      expect(response.body).to include('data-controller="grading-status"')
      expect(response.body).not_to include(nota_provisoria)
    end

    it "o cartão de nota não anuncia mais o desafio" do
      enviar
      get solve_activity_path(pilula, show_score: true)
      expect(response.body).not_to include("No resultado tem um desafio")
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
      enviar(respostas: { mc1.id.to_s => "Brasília", mc2.id.to_s => "Lyon" }, texto: "Eu descansei e li um livro.")
      expect(tentativa.score).to eq(50.0)

      AiGradingService.new(tentativa).call

      tentativa.reload
      expect(tentativa.score).to eq(50.0)
      expect(tentativa.results["total_questions"]).to eq(2)
      expect(tentativa.challenge_entry).to include("ai_score" => 90, "ai_feedback" => "Muito bem!")
      expect(tentativa.challenge_entry).not_to have_key("ai_pending")

      get results_activity_path(pilula)
      expect(response.body).to include("Muito bem!", "90/100", "Minhas expressões escritas")
    end
  end

  describe "refazer a pílula" do
    before do
      enviar(texto: "Meu primeiro texto.")
      tentativa.update!(teacher_comments: { "question_#{desafio.id}" => "Ótimo texto!",
                                            "question_#{mc1.id}" => "Reveja esta." })
    end

    it "o quiz avisa que já existe um texto" do
      get solve_activity_path(pilula)
      expect(response.body).to include("Você já enviou um texto neste desafio")
    end

    it "pular mantém o texto antigo e o comentário da professora sobre ele" do
      enviar(respostas: { mc1.id.to_s => "Salvador", mc2.id.to_s => "Paris" }, pular: true)

      tentativa.reload
      expect(tentativa.score).to eq(50.0)
      expect(tentativa.challenge_entry["given_answer"]).to eq("Meu primeiro texto.")
      expect(tentativa.teacher_comments).to eq("question_#{desafio.id}" => "Ótimo texto!")
    end

    it "um texto novo substitui o antigo, e o comentário sobre o antigo sai" do
      expect { enviar(texto: "Meu segundo texto.") }.to have_enqueued_job(AiGradingJob)

      tentativa.reload
      expect(tentativa.challenge_entry["given_answer"]).to eq("Meu segundo texto.")
      expect(tentativa.teacher_comments).to eq({})
    end
  end

  it "o tour de Minhas expressões escritas só liga depois de um texto enviado" do
    enviar
    get student_dashboard_path
    expect(response.body).to include('data-has-written="false"')

    enviar(texto: "Agora tenho uma expressão escrita.")
    get student_dashboard_path
    expect(response.body).to include('data-has-written="true"')
  end

  describe "atividade que não é pílula" do
    let(:comum)    { create(:activity, :B1, teacher: teacher, draft: false) }
    let!(:fechada) { create(:question, :multiple_choice, activity: comum, content: "Pergunta da atividade comum?",
                            options: %w[Sim Não Talvez Nunca], correct_answer: "Sim") }
    let!(:aberta)  { create(:question, :open_ended, activity: comum, content: "Pergunta aberta da atividade comum.") }

    it "continua como sempre: a aberta fica no quiz e conta na nota" do
      get solve_activity_path(comum)
      expect(response.body).to include(%(name="answers[#{aberta.id}]"))
      expect(response.body).not_to include("Pular e ver minha nota")

      post submit_activity_path(comum), params: { answers: { fechada.id.to_s => "Sim" } } # aberta em branco
      attempt = student.quiz_attempts.find_by(activity: comum)
      expect(attempt.score).to eq(50.0)
      expect(attempt.results).not_to have_key("challenge")

      get results_activity_path(comum)
      expect(response.body).not_to include("Desafio de escrita")
    end

    it "o resultado de uma atividade não mostra a tentativa de outra" do
      enviar # pílula
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

    expect(response.body).to include("Desafio de escrita · último passo, opcional")
    expect(response.body).not_to include("Preencher lacuna")
  end
end
