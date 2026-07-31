# O aviso que antecede a exclusão automática por inatividade.
#
# É o único email da plataforma que anuncia perda de dado, então ele diz três
# coisas e não só uma: o que vai acontecer, como impedir (praticar de novo) e
# como levar os dados embora antes (`/meus-dados`). Avisar sem oferecer a
# exportação seria cumprir o art. 5.1.e atrapalhando o art. 20.
#
# Vai no idioma da pessoa: quem recebe é sobretudo aluno francófono, e um aviso
# de exclusão que a pessoa não entende é o mesmo que não ter avisado.
class RetentionMailer < ApplicationMailer
  COPY = {
    "fr" => {
      subject:  "Votre compte Practice-BR sera supprimé le %{date}",
      heading:  "Ça fait un moment qu'on ne s'est pas vus",
      lead:     "Nous ne conservons pas de données plus longtemps que nécessaire. Votre compte est inactif depuis un certain temps, alors il sera supprimé — avec votre historique d'activités — le %{date}.",
      keep:     "Pour le garder, il suffit de revenir faire une activité. Le compte est conservé et ce message ne reviendra pas.",
      cta:      "Reprendre le portugais →",
      export:   "Vous préférez partir ? Vous pouvez télécharger toutes vos données avant cette date :",
      exportcta: "Télécharger mes données",
      footer:   "© Practice-BR · Ceci est un message automatique."
    },
    "en" => {
      subject:  "Your Practice-BR account will be deleted on %{date}",
      heading:  "It's been a while",
      lead:     "We don't keep data for longer than we need it. Your account has been inactive for some time, so it will be deleted — along with your activity history — on %{date}.",
      keep:     "To keep it, just come back and do one activity. The account stays, and this message won't come back.",
      cta:      "Pick Portuguese back up →",
      export:   "Rather move on? You can download all of your data before that date:",
      exportcta: "Download my data",
      footer:   "© Practice-BR · This is an automated message."
    },
    "pt" => {
      subject:  "Sua conta na Practice-BR será apagada em %{date}",
      heading:  "Faz um tempo que a gente não se vê",
      lead:     "A gente não guarda dado por mais tempo do que precisa. Sua conta está parada há um bom tempo, então ela será apagada — junto com seu histórico de atividades — em %{date}.",
      keep:     "Para mantê-la, basta voltar e fazer uma atividade. A conta fica, e esta mensagem não volta.",
      cta:      "Voltar a praticar →",
      export:   "Prefere seguir seu caminho? Você pode baixar todos os seus dados antes dessa data:",
      exportcta: "Baixar meus dados",
      footer:   "© Practice-BR · Esta é uma mensagem automática."
    }
  }.freeze

  def deletion_warning(user)
    @user       = user
    @copy       = COPY.fetch(user.language, COPY["fr"])
    @deadline   = format_date(user.retention_deadline, user.language)
    @login_url  = new_user_session_url(host: default_url_options[:host], protocol: default_url_options[:protocol] || "https")
    @export_url = data_export_url(host: default_url_options[:host], protocol: default_url_options[:protocol] || "https")

    mail(to: user.email, subject: format(@copy[:subject], date: @deadline))
  end

  private

  # Sem nome de mês de propósito nas versões fr e pt: `%B` sai em inglês a menos
  # que se troque o locale, e "15 August" num email em francês fica pior que
  # 15/08.
  def format_date(date, language)
    language == "en" ? date.strftime("%B %-d, %Y") : date.strftime("%d/%m/%Y")
  end
end
