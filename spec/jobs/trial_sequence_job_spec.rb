require 'rails_helper'

# Medido em produção em 2026-08-01: de 5 pessoas reais que entraram no teste, 4
# nunca responderam uma questão. E quem chegava ao fim sem assinar nunca mais era
# procurado — o próximo email possível era o aviso de exclusão, 11 meses depois.
#
# Esta sequência é o que existe entre "entrou" e "sumiu para sempre".
RSpec.describe TrialSequenceJob, type: :job do
  include ActiveJob::TestHelper

  let!(:disponivel) { create(:activity, :B1, draft: false) }

  def teste(**attrs)
    create(:user, :trial, level: "B1", **attrs)
  end

  describe "ativação (D+1 sem ter começado)" do
    it "fala com quem entrou e não fez nada" do
      pessoa = teste(created_at: 2.days.ago)

      expect { described_class.perform_now }
        .to have_enqueued_mail(TrialMailer, :activation_email).with(pessoa, disponivel)

      expect(pessoa.reload.activation_nudge_sent_at).to be_present
    end

    it "espera o primeiro dia passar — ninguém desistiu em duas horas" do
      teste(created_at: 2.hours.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :activation_email)
    end

    it "não fala com quem já começou" do
      teste(created_at: 2.days.ago, trial_activities_used: 1)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :activation_email)
    end

    it "manda uma vez só" do
      teste(created_at: 2.days.ago, activation_nudge_sent_at: 1.day.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :activation_email)
    end

    it "não manda sem ter atividade do nível pra oferecer" do
      disponivel.destroy
      teste(created_at: 2.days.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :activation_email)
    end
  end

  describe "reabertura (nunca chegou a usar)" do
    it "devolve o teste em vez de pedir dinheiro por algo que a pessoa não viu" do
      pessoa = teste(trial_expires_at: 1.day.ago, created_at: 8.days.ago, trial_activities_used: 0)

      expect { described_class.perform_now }
        .to have_enqueued_mail(TrialMailer, :reopen_email)

      pessoa.reload
      expect(pessoa.trial_reopened_at).to be_present
      expect(pessoa.trial_access_active?).to be true
      expect(pessoa.trial_expires_at).to be > 6.days.from_now
    end

    it "manda um link que entra sem senha — a pessoa está trancada pra fora" do
      # Quem entrou pela landing nunca criou senha, e o link do email original
      # vale 8 dias. Até 2026-10-14 o link novo era o de criar senha; agora entra
      # direto.
      pessoa = teste(trial_expires_at: 1.day.ago, created_at: 12.days.ago, trial_activities_used: 0)

      perform_enqueued_jobs { described_class.perform_now }

      corpo = ActionMailer::Base.deliveries.last.body.encoded
      token = CGI.unescape(corpo[%r{/entrar\?token=([^"&]+)}, 1])
      expect(TrialEmailLink.redeem(token).user).to eq(pessoa)
      expect(corpo).not_to include("reset_password_token")
    end

    it "não reabre pra quem já praticou — essa pessoa viu o produto" do
      teste(trial_activities_used: 3)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :reopen_email)
    end

    it "reabre uma vez só" do
      teste(trial_expires_at: 1.day.ago, created_at: 20.days.ago,
            trial_activities_used: 0, trial_reopened_at: 10.days.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :reopen_email)
    end

    it "quem ignorou a reabertura recebe o fim, e aí sim a assinatura" do
      teste(trial_expires_at: 1.day.ago, created_at: 20.days.ago,
            trial_activities_used: 0, trial_reopened_at: 10.days.ago)

      expect { described_class.perform_now }
        .to have_enqueued_mail(TrialMailer, :ended_email)
    end

    it "não manda ativação no dia seguinte à reabertura" do
      teste(created_at: 20.days.ago, trial_activities_used: 0,
            trial_reopened_at: 1.day.ago, trial_expires_at: 6.days.from_now)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :activation_email)
    end
  end

  describe "fim do teste" do
    it "avisa quem esgotou as 3 atividades" do
      pessoa = teste(trial_activities_used: 3)

      expect { described_class.perform_now }
        .to have_enqueued_mail(TrialMailer, :ended_email)

      expect(pessoa.reload.trial_ended_email_sent_at).to be_present
    end

    it "avisa quem praticou e deixou o prazo vencer" do
      teste(trial_expires_at: 1.day.ago, created_at: 8.days.ago, trial_activities_used: 2)

      expect { described_class.perform_now }
        .to have_enqueued_mail(TrialMailer, :ended_email)
    end

    it "não avisa quem ainda está testando" do
      teste(trial_activities_used: 1)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :ended_email)
    end

    it "manda uma vez só" do
      teste(trial_activities_used: 3, trial_ended_email_sent_at: 2.days.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :ended_email)
    end

    it "não diz 'você viu o que o teste tinha' pra quem não viu nada" do
      # O caso de 4 das 5 pessoas reais. Um balanço de algo que não aconteceu é
      # a pior coisa pra mandar justamente pra elas.
      # Chega aqui só depois de ignorar a reabertura — por isso o trial_reopened_at.
      pessoa = teste(trial_expires_at: 1.day.ago, created_at: 20.days.ago,
                     trial_activities_used: 0, trial_reopened_at: 10.days.ago,
                     language: "fr")

      corpo = CGI.unescapeHTML(TrialMailer.ended_email(pessoa, 145).body.encoded)
      expect(corpo).to include("sans qu'on se croise")
      expect(corpo).not_to include("Vous avez fait le tour")

      described_class.perform_now
      expect(pessoa.reload.trial_ended_email_sent_at).to be_present
    end

    it "faz o balanço com quem praticou de verdade" do
      pessoa = teste(trial_activities_used: 3, language: "fr")

      corpo = CGI.unescapeHTML(TrialMailer.ended_email(pessoa, 145).body.encoded)
      expect(corpo).to include("Vous avez fait le tour")
      expect(corpo).to include("145")
    end
  end

  describe "volta (dias depois do fim)" do
    it "faz o último chamado" do
      pessoa = teste(trial_activities_used: 3, trial_ended_email_sent_at: 6.days.ago)

      expect { described_class.perform_now }
        .to have_enqueued_mail(TrialMailer, :winback_email).with(pessoa, disponivel)

      expect(pessoa.reload.trial_winback_sent_at).to be_present
    end

    it "não atropela o email do fim — espera os dias combinados" do
      teste(trial_activities_used: 3, trial_ended_email_sent_at: 1.day.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :winback_email)
    end

    it "é o último: não se repete" do
      teste(trial_activities_used: 3,
            trial_ended_email_sent_at: 10.days.ago,
            trial_winback_sent_at: 3.days.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :winback_email)
    end
  end

  describe "quem não deve receber nada" do
    it "não fala com ex-aluno pagante que cancelou" do
      # Cancelar a assinatura devolve o papel `trial`, com o trial_expires_at do
      # teste original de meses atrás. Sem o filtro de stripe_customer_id, essa
      # pessoa receberia a sequência de boas-vindas no dia seguinte ao
      # cancelamento — depois de ter pago meses.
      teste(stripe_customer_id: "cus_123", trial_expires_at: 6.months.ago,
            created_at: 7.months.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :ended_email)
    end

    it "não fala com aluno pagante" do
      create(:user, :student, level: "B1")

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :activation_email)
    end
  end

  describe "um email por rodada" do
    it "não manda ativação e fim na mesma manhã" do
      # Quem esgotou as 3 atividades no primeiro dia cai nas duas regras.
      pessoa = teste(created_at: 2.days.ago, trial_activities_used: 3)

      described_class.perform_now

      pessoa.reload
      expect([pessoa.activation_nudge_sent_at, pessoa.trial_ended_email_sent_at].compact.size).to eq(1)
    end
  end

  describe "lembrete do mesmo dia (4h sem ter começado)" do
    it "fala com quem entrou há 4 horas e não fez nada" do
      pessoa = teste(created_at: 5.hours.ago)

      expect { described_class.perform_now }
        .to have_enqueued_mail(TrialMailer, :first_nudge_email).with(pessoa, disponivel)

      expect(pessoa.reload.first_nudge_sent_at).to be_present
    end

    it "não fala com quem acabou de chegar" do
      teste(created_at: 2.hours.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :first_nudge_email)
    end

    it "não fala com quem já concluiu uma atividade" do
      pessoa = teste(created_at: 5.hours.ago)
      create(:quiz_attempt, user: pessoa, activity: disponivel)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :first_nudge_email)
    end

    it "é pulado se passou da janela — chegaria colado no D+1" do
      teste(created_at: 22.hours.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :first_nudge_email)
    end

    it "não manda link para teste vencido" do
      teste(created_at: 5.hours.ago, trial_expires_at: 1.minute.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :first_nudge_email)
    end

    it "segura o D+1 até 12h depois do lembrete do mesmo dia" do
      teste(created_at: 25.hours.ago, first_nudge_sent_at: 3.hours.ago)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :activation_email)
    end

    it "manda o D+1 quando o espaço já passou" do
      teste(created_at: 26.hours.ago, first_nudge_sent_at: 21.hours.ago)

      expect { described_class.perform_now }
        .to have_enqueued_mail(TrialMailer, :activation_email)
    end
  end

  describe "rodar de novo não repete nada" do
    # O job roda de hora em hora. Cada email tem uma coluna que só uma execução
    # consegue marcar.
    it "duas rodadas seguidas mandam um email só" do
      teste(created_at: 5.hours.ago)

      expect {
        described_class.perform_now
        described_class.perform_now
      }.to have_enqueued_mail(TrialMailer, :first_nudge_email).once
    end

    it "não manda se outra execução já marcou a pessoa entre a leitura e o envio" do
      pessoa = teste(created_at: 5.hours.ago)
      # Simula a corrida: a outra execução marca a coluna no banco depois que
      # esta já conferiu a pessoa na memória e logo antes de ela reservar.
      allow(User).to receive(:transaction).and_wrap_original do |original, *args, &bloco|
        User.where(id: pessoa.id).update_all(first_nudge_sent_at: Time.current)
        original.call(*args, &bloco)
      end

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(TrialMailer, :first_nudge_email)
    end
  end

  describe "os links dos emails" do
    it "entram sem senha e levam à atividade" do
      pessoa = teste(created_at: 5.hours.ago)

      perform_enqueued_jobs { described_class.perform_now }

      corpo = ActionMailer::Base.deliveries.last.body.encoded
      token = CGI.unescape(corpo[%r{/entrar\?token=([^"&]+)}, 1])
      resultado = TrialEmailLink.redeem(token)
      expect(resultado.user).to eq(pessoa)
      expect(resultado.activity_id).to eq(disponivel.id)
    end
  end
end
