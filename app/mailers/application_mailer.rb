class ApplicationMailer < ActionMailer::Base
  default from: "Practice-BR <no-reply@practicebr.com>",
          reply_to: "contato@practicebr.com"
  layout "mailer"

  def self.configure_headers(headers)
    headers.merge!({
      'X-MC-AutoText' => 'true',
      'X-Priority' => '3',
      'X-Mailer' => 'Exercise App Mailer',
      'Importance' => 'Normal',
      'Message-ID' => "<#{SecureRandom.uuid}@practicebr.com>",
      'Precedence' => 'Bulk'
    })
  end

  # Privado de propósito: no ActionMailer todo método **público** de instância
  # vira uma action do mailer, e um helper de formatação virando action é o tipo
  # de surpresa que só aparece quando alguém tenta entregá-la.
  private

  # Data no formato que a pessoa lê sem hesitar.
  #
  # Não dá pra usar o `l()` do I18n aqui: dentro de um mailer o locale é o padrão
  # da aplicação (português), então um email em francês sairia com data em
  # português. E `%B` sem trocar o locale sai em inglês — por isso fr e pt ficam
  # em número puro, e só o inglês ganha nome de mês.
  #
  # O motivo de não deixar tudo numérico: 07/08/2026 é ambíguo pra quem lê em
  # inglês, que entende 8 de julho.
  def format_date(date, language)
    language == "en" ? date.strftime("%B %-d, %Y") : date.strftime("%d/%m/%Y")
  end
end
