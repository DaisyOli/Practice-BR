# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn,

  # Webhook do Resend: traz destinatário e assunto, e o assunto interno de "Novo
  # trial" contém o email da pessoa. Regex exata porque, como símbolo, `to` também
  # esconderia `total`, `token` e tudo o mais que contenha essas letras.
  # `headers` leva o link de descadastro, com o token da pessoa, e
  # `diagnosticCode` é a resposta do servidor dela, que às vezes repete o
  # endereço. O aviso inteiro continua no painel do Resend.
  /\A(to|from|subject|headers|diagnosticCode)\z/,

  # Dado pessoal de aluno. Mesmo com log_level "info" o Rails escreve a linha
  # "Parameters: {...}" de todo POST — sem isto, o texto das respostas abertas e
  # os emails ficariam guardados nos logs, que não são lugar pra esse dado.
  # O casamento é parcial: :answers pega sentence_ordering_answers,
  # column_matching_answers e os demais.
  :answers, :email, :audio
]
