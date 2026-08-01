require 'rails_helper'

# Medido em produção em 2026-08-01: de 5 pessoas reais que entraram no teste, 4
# nunca responderam uma questão. E quem chegava ao fim sem assinar nunca mais era
# procurado — o próximo email possível era o aviso de exclusão, 11 meses depois.
#
# Esta sequência é o que existe entre "entrou" e "sumiu para sempre".
RSpec.describe TrialSequenceJob, type: :job do
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

    it "manda um link de acesso novo — a pessoa está trancada pra fora" do
      # Quem entrou pela landing nunca criou senha, e o link do email original
      # vale 8 dias. Um convite sem token novo levaria a uma porta fechada.
      pessoa = teste(trial_expires_at: 1.day.ago, created_at: 12.days.ago,
                     trial_activities_used: 0, reset_password_sent_at: 12.days.ago)

      described_class.perform_now

      pessoa.reload
      expect(pessoa.reset_password_token).to be_present
      expect(pessoa.reset_password_sent_at).to be_within(1.minute).of(Time.current)
      expect(pessoa.reset_password_period_valid?).to be true
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
end
