# A sequência inteira do teste, nos três idiomas. Serve pra Daisy ler os textos
# antes de eles saírem — os emails do teste são os únicos que falam com gente que
# ainda não decidiu nada sobre a plataforma.
class TrialMailerPreview < ActionMailer::Preview
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
