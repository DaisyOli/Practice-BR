# A sequência inteira do teste, nos três idiomas. Serve pra Daisy ler os textos
# antes de eles saírem — os emails do teste são os únicos que falam com gente que
# ainda não decidiu nada sobre a plataforma.
class TrialMailerPreview < ActionMailer::Preview
  def welcome_fr
    TrialMailer.welcome_email(pessoa("fr"))
  end

  def welcome_pt
    TrialMailer.welcome_email(pessoa("pt", nome: "Marina"))
  end

  def welcome_en
    TrialMailer.welcome_email(pessoa("en"))
  end

  # Lembrete do mesmo dia (~4h depois do cadastro, sem ter começado).
  def first_nudge_fr
    TrialMailer.first_nudge_email(pessoa("fr"), atividade)
  end

  def first_nudge_pt
    TrialMailer.first_nudge_email(pessoa("pt", nome: "Marina"), atividade)
  end

  def first_nudge_en
    TrialMailer.first_nudge_email(pessoa("en"), atividade)
  end

  # Recuperação manual (rake trial_recovery:run). Duas versões: com e sem a
  # extensão de 48h — a frase do prazo muda.
  def recovery_fr
    TrialMailer.recovery_email(pessoa("fr"), atividade)
  end

  def recovery_fr_com_extensao
    TrialMailer.recovery_email(pessoa("fr"), atividade, extended: true)
  end

  # Campanha da base antiga: cadastro de julho que já recebeu o "último email".
  def recovery_fr_antigo_com_promessa
    pessoa = pessoa("fr")
    pessoa.created_at = 3.months.ago
    pessoa.trial_winback_sent_at = 2.months.ago
    TrialMailer.recovery_email(pessoa, atividade, extended: true)
  end

  def recovery_pt
    TrialMailer.recovery_email(pessoa("pt", nome: "Marina"), atividade)
  end

  def recovery_en
    TrialMailer.recovery_email(pessoa("en"), atividade)
  end

  def activation_fr
    TrialMailer.activation_email(pessoa("fr"), atividade)
  end

  def activation_pt
    TrialMailer.activation_email(pessoa("pt", nome: "Marina"), atividade)
  end

  def activation_en
    TrialMailer.activation_email(pessoa("en"), atividade)
  end

  def reminder_fr
    TrialMailer.reminder_email(pessoa("fr", feitas: 1))
  end

  def reminder_pt
    TrialMailer.reminder_email(pessoa("pt", nome: "Marina", feitas: 2))
  end

  # Reabertura: o email de quem nunca chegou a usar o teste. É o que as 4
  # pessoas reais receberiam na primeira rodada.
  def reopen_fr
    TrialMailer.reopen_email(pessoa("fr"), atividade)
  end

  def reopen_pt
    TrialMailer.reopen_email(pessoa("pt", nome: "Marina"), atividade)
  end

  # Quem nunca abriu uma atividade: é o caso de 4 das 5 pessoas reais.
  def ended_fr_sem_ter_comecado
    TrialMailer.ended_email(pessoa("fr"), 145)
  end

  def ended_fr_tendo_praticado
    TrialMailer.ended_email(pessoa("fr", feitas: 3), 145)
  end

  def ended_pt_sem_ter_comecado
    TrialMailer.ended_email(pessoa("pt", nome: "Marina"), 145)
  end

  def ended_pt_tendo_praticado
    TrialMailer.ended_email(pessoa("pt", nome: "Marina", feitas: 3), 145)
  end

  # Fase B, o do meio: a próxima atividade do percurso.
  def next_step_fr
    TrialMailer.next_step_email(pessoa("fr", feitas: 3), atividade)
  end

  def next_step_pt
    TrialMailer.next_step_email(pessoa("pt", nome: "Marina", feitas: 3), atividade)
  end

  def winback_fr
    TrialMailer.winback_email(pessoa("fr"), atividade)
  end

  def winback_pt
    TrialMailer.winback_email(pessoa("pt", nome: "Marina"), atividade)
  end

  private

  def pessoa(lang, nome: nil, feitas: 0)
    User.new(
      name: nome,
      email: "teste@exemplo.com",
      language: lang,
      level: "B1",
      trial_expires_at: 4.days.from_now,
      trial_activities_used: feitas
    )
  end

  def atividade
    Activity.published.where(level: "B1").first ||
      Activity.new(title: "Exemplo de Atividade", level: "B1", slug: "exemplo",
                   description: "Uma atividade de exemplo para a preview.")
  end
end
