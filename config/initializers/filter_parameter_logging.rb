# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn,

  # Dado pessoal de aluno. Mesmo com log_level "info" o Rails escreve a linha
  # "Parameters: {...}" de todo POST — sem isto, o texto das respostas abertas e
  # os emails ficariam guardados nos logs, que não são lugar pra esse dado.
  # O casamento é parcial: :answers pega sentence_ordering_answers,
  # column_matching_answers e os demais.
  :answers, :email, :audio
]
