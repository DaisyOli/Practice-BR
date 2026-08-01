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

  describe "fim do teste" do
    it "avisa quem esgotou as 3 atividades" do
      pessoa = teste(trial_activities_used: 3)

      expect { described_class.perform_now }
        .to have_enqueued_mail(TrialMailer, :ended_email)

      expect(pessoa.reload.trial_ended_email_sent_at).to be_present
    end

    it "avisa quem deixou o prazo vencer" do
      teste(trial_expires_at: 1.day.ago, created_at: 8.days.ago)

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
      pessoa = teste(trial_expires_at: 1.day.ago, created_at: 8.days.ago,
                     trial_activities_used: 0, language: "fr")

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
