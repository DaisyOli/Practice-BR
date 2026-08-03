# Relatório de erros.
#
# O problema que resolve: até 02/08/2026 um erro 500 na cara de um aluno só era
# descoberto se ele escrevesse contando. E quem toma erro numa plataforma que
# ainda não conhece não escreve — desiste. Das 5 primeiras pessoas reais do
# trial, 4 nunca fizeram uma atividade, e não havia como saber se alguma tinha
# esbarrado num erro ou simplesmente perdido o interesse.
#
# ---- Desligado por padrão -----------------------------------------------------
#
# Sem `SENTRY_DSN` no ambiente, este arquivo não faz nada: nenhuma conexão, zero
# custo, nenhum dado saindo. É o que mantém desenvolvimento e teste intocados, e
# o que deixa a decisão de ligar num `heroku config:set`.
return if ENV["SENTRY_DSN"].blank?

# ---- Dado pessoal não sai daqui -----------------------------------------------
#
# A plataforma passou 30 e 31/07 tirando dado pessoal dos logs. Mandar o mesmo
# dado pra um serviço externo desfaria aquilo em silêncio, então a limpeza é
# explícita e em três camadas: `send_default_pii` desligado, os filtros do Rails
# reaproveitados, e um pente final no texto de qualquer evento.

# Local, não constante: um initializer não precisa deixar nome solto em Object.
#
# Existe porque email aparece no TEXTO da exceção mesmo com os parâmetros
# filtrados: "falha ao corrigir a resposta de x@y.com", um erro da Resend citando o
# destinatário, uma validação que ecoa o email. O dado não está nos params, está na
# frase — e nenhum filtro de parâmetro alcança uma frase.
email_in_text = /[\w.+-]+@[\w-]+\.[\w.-]+/

# Os mesmos filtros dos logs (:email, :answers, :audio, :passw, :token...),
# reaproveitados de propósito. Uma lista só, num lugar só: se alguém adicionar um
# campo sensível em filter_parameter_logging.rb, ele passa a valer aqui sem
# ninguém precisar lembrar.
#
# O `require` é obrigatório e não é decorativo: `ActiveSupport::ParameterFilter`
# NÃO está na lista de autoload do ActiveSupport. Quem o carrega é o ActionDispatch,
# mais tarde no boot — depois dos initializers. Sem esta linha o app subia normal em
# desenvolvimento (onde o arquivo sai na linha 14, sem DSN) e morria no boot em
# produção no instante em que SENTRY_DSN fosse definido.
require "active_support/parameter_filter"

param_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]

  # Só produção. Erro em desenvolvimento já aparece na tela, e mandar pra fora
  # gastaria a cota de 5 mil eventos/mês com coisa que a Daisy está vendo ao vivo.
  config.enabled_environments = %w[production]
  config.environment          = Rails.env

  # Não manda IP, cookies nem corpo de requisição. O que sobra é o que interessa:
  # a exceção, o arquivo, a linha e a rota.
  config.send_default_pii = false

  config.before_send = lambda do |event, _hint|
    event.request.data = param_filter.filter(event.request.data) if event.request&.data.is_a?(Hash)

    # Pente final: o que escapou dos params porque estava escrito na mensagem.
    event.exception&.values&.each do |exception|
      exception.value = exception.value.to_s.gsub(email_in_text, "[email removido]")
    end

    event
  end

  # ---- Peso ---------------------------------------------------------------------
  #
  # Nada de performance tracing: o dyno tem 512MB compartilhados com o GoodJob
  # rodando dentro do Puma, e tracing é a parte mais pesada da biblioteca. O que
  # se quer aqui é saber que quebrou, não medir quanto demorou.
  #
  # Tem que ser `nil`, e não `0.0`. Parece a mesma coisa e não é: `0.0` é uma taxa
  # VÁLIDA, então `tracing_enabled?` responde true, o railtie do sentry-rails
  # registra os subscribers de ActiveRecord/ActionView/ActiveJob e faz patch em
  # ActiveSupport::Notifications — todo o peso — pra descartar 100% das amostras
  # no fim. Só `nil` não passa por `valid_sample_rate?` e desliga de verdade.
  config.traces_sample_rate = nil

  # Erro repetido não perde valor por ser repetido — é justamente o que mostra
  # que muita gente está batendo nele. Manda todos.
  config.sample_rate = 1.0

  # ---- Ruído --------------------------------------------------------------------
  #
  # Aqui não tem nada de propósito. O robô procurando /wp-admin
  # (ActionController::RoutingError), o token de CSRF vencido
  # (InvalidAuthenticityToken), a requisição malformada (BadRequest,
  # Rack::QueryParser::InvalidParameterError) — o sentry-rails já ignora tudo isso
  # sozinho, via Sentry::Rails::IGNORE_DEFAULT somado ao IGNORE_DEFAULT do
  # sentry-ruby. Uma lista repetindo esses nomes não mudaria uma linha do
  # comportamento; só pareceria estar protegendo alguma coisa.
  #
  # A exceção: `SystemExit` não está em nenhuma das duas listas padrão, e aparece.
  #
  # É o sinal de saída do Ruby, nunca defeito de aplicação. Todo `heroku run rails
  # runner` que termina mal levanta um — foi o que aconteceu em 03/08/2026, quando
  # uma consulta de diagnóstico usou um campo inexistente e virou alerta por email.
  # Dyno de one-off reporta igual ao resto, e um comando manual com erro de digitação
  # não é notícia.
  #
  # O que NÃO dá pra fazer: excluir tudo que vem de `runner`. O primeiro erro que
  # este arquivo capturou em produção foi uma falha de conexão do ping do Scheduler,
  # que roda por `runner` — e aquilo era sinal de verdade.
  config.excluded_exceptions += ["SystemExit"]

  # Qual deploy quebrou. O Heroku expõe o commit quando o lab
  # `runtime-dyno-metadata` está ligado; sem ele fica nulo e o Sentry apenas não
  # mostra a versão.
  config.release = ENV["HEROKU_SLUG_COMMIT"].presence
end
