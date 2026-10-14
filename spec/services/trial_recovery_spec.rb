require 'rails_helper'

# A recuperação manual de trials (lib/tasks/trial_recovery.rake). Ela muda prazo
# e manda email para gente real, então os testes cobrem sobretudo o que ela NÃO
# pode fazer: mandar para quem não foi aprovado, mandar duas vezes, estender
# duas vezes, ou mandar um link que não abre.
RSpec.describe TrialRecovery do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let!(:atividade) { create(:activity, :B1, draft: false) }

  # Hoje é 14/10/2026, 10h em Paris. A janela é 12 e 13/10.
  around { |ex| travel_to(Time.zone.parse("2026-10-14 10:00")) { ex.run } }

  let(:recovery) { described_class.new(from: "2026-10-12", to: "2026-10-13") }

  def trial_em(hora_paris, **attrs)
    create(:user, :trial, level: "B1",
           created_at: Time.zone.parse(hora_paris),
           trial_expires_at: Time.zone.parse(hora_paris) + 7.days, **attrs)
  end

  describe "#report (prévia)" do
    it "usa o fuso de Paris para os limites da janela" do
      # 11/10 23h30 em Paris é 21h30 UTC — fora. 12/10 00h30 em Paris é 11/10
      # 22h30 UTC — dentro. Com UTC a lista sairia errada nas duas pontas.
      fora   = trial_em("2026-10-11 23:30")
      dentro = trial_em("2026-10-12 00:30")
      ultimo = trial_em("2026-10-13 23:50")
      depois = trial_em("2026-10-14 00:10")

      ids = recovery.report.map { |r| r.user.id }
      expect(ids).to include(dentro.id, ultimo.id)
      expect(ids).not_to include(fora.id, depois.id)
    end

    it "explica por que cada pessoa está fora" do
      fez    = trial_em("2026-10-12 10:00")
      create(:quiz_attempt, user: fez, activity: atividade)
      pagou  = trial_em("2026-10-12 11:00", stripe_customer_id: "cus_1")
      aluno  = create(:user, :student, created_at: Time.zone.parse("2026-10-12 12:00"))
      ok     = trial_em("2026-10-13 09:00")

      linhas = recovery.report.index_by { |r| r.user.id }
      expect(linhas[fez.id].reason).to eq("já fez atividade")
      expect(linhas[pagou.id].reason).to include("Stripe")
      expect(linhas[aluno.id].reason).to include("não é trial")
      expect(linhas[ok.id].eligible).to be true
    end

    it "não muda nada nem enfileira email" do
      pessoa = trial_em("2026-10-12 10:00")

      expect { recovery.report }.not_to have_enqueued_mail
      expect(pessoa.reload.trial_events).to be_empty
    end

    it "mostra se o email de boas-vindas saiu, pela fila" do
      pessoa = trial_em("2026-10-12 10:00")
      linha  = recovery.report.find { |r| r.user == pessoa }

      expect(linha.welcome).to eq("sem registro na fila")
    end
  end

  describe "#run! (envio)" do
    it "manda só para os ids aprovados" do
      aprovada = trial_em("2026-10-12 10:00")
      nao      = trial_em("2026-10-12 11:00")

      expect { recovery.run!([aprovada.id]) }
        .to have_enqueued_mail(TrialMailer, :recovery_email).once

      expect(nao.reload.trial_events).to be_empty
    end

    it "pula aprovado que ficou inelegível entre a prévia e o envio" do
      pessoa = trial_em("2026-10-12 10:00")
      create(:quiz_attempt, user: pessoa, activity: atividade)

      resultado = nil
      expect { resultado = recovery.run!([pessoa.id]) }.not_to have_enqueued_mail
      expect(resultado[:skipped][pessoa.id]).to eq("já fez atividade")
    end

    it "pula id que não é da janela" do
      outra = trial_em("2026-10-01 10:00")

      resultado = recovery.run!([outra.id])
      expect(resultado[:skipped][outra.id]).to eq("fora da janela de datas")
    end

    it "não estende quem ainda tem dias de teste" do
      pessoa = trial_em("2026-10-12 10:00")
      prazo  = pessoa.trial_expires_at

      recovery.run!([pessoa.id])

      expect(pessoa.reload.trial_expires_at).to be_within(1.second).of(prazo)
      expect(pessoa.trial_events.pluck(:kind)).to eq(["recovery_email"])
    end

    it "estende 48h quem está a menos de 48h do fim, e registra o prazo antigo" do
      pessoa = trial_em("2026-10-12 10:00", trial_expires_at: Time.zone.parse("2026-10-14 20:00"))

      recovery.run!([pessoa.id])

      pessoa.reload
      expect(pessoa.trial_expires_at).to be_within(1.second).of(Time.zone.parse("2026-10-16 10:00"))
      evento = pessoa.trial_events.find_by(kind: "extension_48h")
      expect(Time.zone.parse(evento.details["from"])).to eq(Time.zone.parse("2026-10-14 20:00"))
    end

    it "teste vencido: estende antes de mandar, e o email diz isso — nada de link morto" do
      pessoa = trial_em("2026-10-12 10:00", trial_expires_at: 2.hours.ago, language: "pt")

      perform_enqueued_jobs { recovery.run!([pessoa.id]) }

      expect(pessoa.reload.trial_access_active?).to be true
      corpo = CGI.unescapeHTML(ActionMailer::Base.deliveries.last.body.encoded)
      expect(corpo).to include("Acrescentamos 48 horas")
      expect(corpo).to include("16/10/2026")
    end

    it "não deixa a sequência automática mandar outro lembrete logo em seguida" do
      pessoa = trial_em("2026-10-13 09:00")

      recovery.run!([pessoa.id])

      expect { TrialSequenceJob.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :activation_email)
      expect(pessoa.reload.first_nudge_sent_at).to be_present
    end

    describe "rodar de novo" do
      it "não duplica email nem extensão" do
        pessoa = trial_em("2026-10-12 10:00", trial_expires_at: 1.hour.ago)
        recovery.run!([pessoa.id])
        prazo = pessoa.reload.trial_expires_at

        expect { recovery.run!([pessoa.id]) }.not_to have_enqueued_mail

        expect(pessoa.reload.trial_expires_at).to eq(prazo)
        expect(pessoa.trial_events.count).to eq(2)
      end

      it "o banco recusa o segundo registro mesmo se duas execuções passarem pela checagem" do
        pessoa = trial_em("2026-10-12 10:00")
        # A outra execução gravou o evento depois desta ter checado a elegibilidade.
        allow(recovery).to receive(:ineligibility_reason).and_return(nil)
        TrialEvent.create!(user: pessoa, kind: "recovery_email")

        resultado = nil
        expect { resultado = recovery.run!([pessoa.id]) }.not_to have_enqueued_mail
        expect(resultado[:skipped][pessoa.id]).to eq("já recuperado")
      end
    end
  end

  describe "quem foi recuperado consegue praticar", type: :request do
    include Devise::Test::IntegrationHelpers

    it "o link do email entra, abre a atividade e a conclusão conta" do
      pessoa = trial_em("2026-10-12 10:00", trial_expires_at: 1.hour.ago)
      create(:question, :multiple_choice, activity: atividade)

      perform_enqueued_jobs { recovery.run!([pessoa.id]) }
      corpo = ActionMailer::Base.deliveries.last.body.encoded
      link  = CGI.unescapeHTML(corpo[%r{https?://[^"]+/entrar\?token=[^"]+}])

      get URI(link).request_uri
      expect(response).to redirect_to(solve_activity_path(atividade))

      get solve_activity_path(atividade)
      expect(response).to have_http_status(:ok)
      expect(pessoa.reload.first_activity_opened_at).to be_present

      questao = atividade.questions.first
      post submit_activity_path(atividade), params: { answers: { questao.id.to_s => "Brasília" } }

      expect(pessoa.reload.quiz_attempts.count).to eq(1)
      expect(pessoa.trial_activities_used).to eq(1)
    end
  end
end
