# O alerta existe porque a Daisy descobriu por acaso, dez dias depois, que a
# primeira aluna orgânica tinha parado de praticar. Estes testes guardam as duas
# coisas que fazem ele servir: avisar quem realmente sumiu, e não virar email
# diário — que é como um alerta deixa de ser lido.
require 'rails_helper'

RSpec.describe StudentWentQuietJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:teacher)  { create(:user, :teacher) }
  let(:activity) { create(:activity, teacher: teacher) }

  def pagante(**attrs)
    create(:user, :student, subscription_status: "active", **attrs)
  end

  def praticou_ha(student, tempo)
    create(:quiz_attempt, user: student, activity: activity, submitted_at: tempo.ago)
  end

  # Tentativa com `submitted_at` nulo não nasce mais assim: `QuizAttempt` tem um
  # `before_create :set_submitted_at` que preenche o campo. Elas existem no
  # banco como herança de antes desse callback — e é só por causa delas que o
  # cálculo da última prática precisa olhar para `created_at`. `update_columns`
  # é o único jeito de reproduzir uma, justamente porque pula os callbacks.
  def praticou_sem_submeter_ha(student, tempo)
    create(:quiz_attempt, user: student, activity: activity)
      .update_columns(submitted_at: nil, created_at: tempo.ago)
  end

  def emails_enviados
    ActionMailer::Base.deliveries
  end

  # Conta idas ao banco, ignorando o ruído de transação e de schema.
  def consultas_durante
    total = 0
    inscricao = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      ruido = payload[:name].to_s.in?(%w[SCHEMA TRANSACTION]) ||
              payload[:sql].to_s.start_with?("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE")
      total += 1 unless ruido
    end
    yield
    total
  ensure
    ActiveSupport::Notifications.unsubscribe(inscricao)
  end

  before { ActionMailer::Base.deliveries.clear }

  it "avisa quando um pagante passa do silêncio" do
    aluno = pagante
    praticou_ha(aluno, 10.days)

    described_class.perform_now

    expect(emails_enviados.size).to eq(1)
    expect(emails_enviados.last.subject).to include("não pratica há 7 dias")
  end

  it "não avisa de quem praticou ontem" do
    praticou_ha(pagante, 1.day)

    described_class.perform_now

    expect(emails_enviados).to be_empty
  end

  # Sem isto o email chegaria todo dia até a pessoa voltar, e um alerta que
  # chega todo dia é um alerta que ninguém abre.
  it "avisa uma vez só por ausência" do
    aluno = pagante
    praticou_ha(aluno, 10.days)

    described_class.perform_now
    described_class.perform_now

    expect(emails_enviados.size).to eq(1)
    expect(aluno.reload.quiet_alert_sent_at).to be_present
  end

  # Precisa de viagem no tempo: "voltou a praticar" só conta se a prática for
  # posterior ao aviso, e depois é preciso silenciar outros sete dias.
  it "avisa de novo se a pessoa voltar e sumir outra vez" do
    aluno = pagante

    travel_to(20.days.ago) { praticou_ha(aluno, 0.days) }
    travel_to(12.days.ago) { described_class.perform_now } # 8 dias parada → 1º aviso

    travel_to(10.days.ago) { praticou_ha(aluno, 0.days) }  # reapareceu
    travel_to(1.day.ago)   { described_class.perform_now }  # 9 dias parada → 2º aviso

    expect(emails_enviados.size).to eq(2)
  end

  it "ignora quem nunca praticou (isso é ativação, não sumiço)" do
    pagante

    described_class.perform_now

    expect(emails_enviados).to be_empty
  end

  it "ignora quem não é pagante" do
    trial = create(:user, :trial)
    create(:quiz_attempt, user: trial, activity: activity, submitted_at: 10.days.ago)

    described_class.perform_now

    expect(emails_enviados).to be_empty
  end

  it "junta todo mundo num email só" do
    2.times { praticou_ha(pagante, 9.days) }

    described_class.perform_now

    expect(emails_enviados.size).to eq(1)
    expect(emails_enviados.last.subject).to include("2 alunos pagantes sumiram")
  end

  it "não manda nada quando está todo mundo em dia" do
    praticou_ha(pagante, 2.days)

    described_class.perform_now

    expect(emails_enviados).to be_empty
  end

  # Esta era a metade não testada: os testes acima olhavam só para quem ENTRA
  # na lista, nenhum olhava para COMO a última prática é calculada.
  describe "como decide qual foi a última prática" do
    # A versão antiga fazia `maximum(:submitted_at) || maximum(:created_at)`, e
    # só caía no `created_at` quando a pessoa nunca tinha submetido nada na
    # vida. Uma tentativa recente que ficou sem `submitted_at` — queda de banco,
    # aba fechada no meio — não contava, e a aluna era dada como sumida mesmo
    # tendo aparecido anteontem.
    it "conta a tentativa recente que ficou sem submitted_at" do
      aluno = pagante
      praticou_ha(aluno, 30.days)
      praticou_sem_submeter_ha(aluno, 2.days)

      described_class.perform_now

      expect(emails_enviados).to be_empty
    end

    it "continua avisando quando a tentativa sem submitted_at também é antiga" do
      aluno = pagante
      praticou_sem_submeter_ha(aluno, 30.days)

      described_class.perform_now

      expect(emails_enviados.size).to eq(1)
    end

    it "escreve no email a data da última atividade" do
      praticou_ha(pagante, 9.days)

      described_class.perform_now

      expect(emails_enviados.last.body.to_s)
        .to include(I18n.l(9.days.ago.to_date, format: :long))
    end
  end

  # O job carregava todos os pagantes e ia ao banco duas vezes por aluno para
  # descobrir a última prática — e a view do email repetia a conta na hora de
  # renderizar. Hoje é uma consulta agrupada só, e o número não pode voltar a
  # crescer com o tamanho da turma.
  it "não faz mais consultas ao banco por causa de mais alunos" do
    3.times { praticou_ha(pagante, 9.days) }
    com_3_alunos = consultas_durante { described_class.perform_now }

    ActionMailer::Base.deliveries.clear
    User.update_all(quiet_alert_sent_at: nil)
    3.times { praticou_ha(pagante, 9.days) }
    com_6_alunos = consultas_durante { described_class.perform_now }

    expect(emails_enviados.last.subject).to include("6 alunos")
    expect(com_6_alunos).to eq(com_3_alunos)
  end
end
