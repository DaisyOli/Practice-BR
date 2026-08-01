require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from `public/`, relying on NGINX/Apache to do so instead.
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{1.year.to_i}, s-maxage=#{30.days.to_i}"
  }

  # Tailwind gera CSS moderno — SassC não suporta; deixar sem compressor
  config.assets.css_compressor = nil
  config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  config.active_storage.service = :cloudinary

  # Mount Action Cable outside main process or domain.
  # config.action_cable.mount_path = nil
  # config.action_cable.url = "wss://example.com/cable"
  # config.action_cable.allowed_request_origins = [ "http://example.com", /http:\/\/example.*/ ]

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # "info" includes generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). If you
  # want to log everything, set the level to "debug".
  # Em "debug" o Rails loga cada query com os valores dentro — ou seja, email de
  # aluno e o texto das respostas abertas iriam parar nos logs do Heroku. Isso é
  # dado pessoal em lugar que não precisa dele. Para depurar um problema pontual,
  # suba temporariamente com `heroku config:set RAILS_LOG_LEVEL=debug` e volte
  # pra "info" logo depois.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Configuração de cache otimizada para Heroku com fallback para memory_store
  if ENV["MEMCACHIER_SERVERS"]
    config.cache_store = :mem_cache_store,
                        ENV["MEMCACHIER_SERVERS"].split(","),
                        {
                          username: ENV["MEMCACHIER_USERNAME"],
                          password: ENV["MEMCACHIER_PASSWORD"],
                          failover: true,
                          socket_timeout: 1.5,
                          socket_failure_delay: 0.2,
                          down_retry_delay: 60,
                          pool_size: ENV.fetch("RAILS_MAX_THREADS") { 5 }
                        }
    config.action_controller.perform_caching = true
    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.to_i}"
    }
  else
    config.cache_store = :memory_store, { size: 64.megabytes }
    config.action_controller.perform_caching = true
  end

  # Use a real queuing backend for Active Job (and separate queues per environment).
  # GoodJob guarda a fila no próprio Postgres e roda em modo :async — threads
  # dentro do processo web, sem dyno extra. max_threads baixo para respeitar
  # o limite de 20 conexões do plano essential-0.
  config.active_job.queue_adapter = :good_job
  config.good_job = {
    execution_mode: :async,
    max_threads: 2,
    poll_interval: 10,
    shutdown_timeout: 25,
    # LISTEN/NOTIFY desligado: no essential-0 a conexão dedicada do Notifier
    # cai e ele entra em loop de reconexão (visto em 2026-07-09). O poller
    # de 10s acima é quem pega os jobs — comprovado nos logs de produção.
    enable_listen_notify: false,
    # Cron nativo do GoodJob: roda dentro do próprio dyno, sem Heroku Scheduler
    # (que exigiria um dyno one-off extra). 07:00 horário da França (a maioria
    # dos alunos e a Daisy estão lá) — fugit resolve o fuso e o horário de
    # verão automaticamente a partir do sufixo "Europe/Paris".
    enable_cron: true,
    cron: {
      trial_reminder: {
        cron: "0 7 * * * Europe/Paris",
        class: "TrialReminderJob"
      },
      weekly_reminder: {
        cron: "0 7 * * 1 Europe/Paris",
        class: "WeeklyReminderJob"
      },
      # Meia hora depois do lembrete do 3º dia, de propósito: os dois nunca
      # falam com a mesma pessoa (um é de quem começou, outro de quem não),
      # mas se um dia se cruzarem, chegam em horas diferentes.
      trial_sequence: {
        cron: "30 7 * * * Europe/Paris",
        class: "TrialSequenceJob"
      },
      # A cada 6h (não 1x/dia): o gatilho é "48h desde a última atividade",
      # então precisa rodar várias vezes ao dia pra não deixar passar de
      # 48h + quase 1 dia inteiro por causa do agendamento.
      inactivity_nudge: {
        cron: "0 */6 * * *",
        class: "InactivityNudgeJob"
      },
      # 1x/dia e de madrugada: é o único job que apaga dado de gente, então roda
      # longe do horário de uso. Um dia de atraso num prazo de 3 anos não é
      # descumprimento de nada.
      account_retention: {
        cron: "30 3 * * * Europe/Paris",
        class: "AccountRetentionJob"
      }
    }
  }
  config.active_job.queue_name_prefix = "practicebr_production"

  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  config.action_mailer.raise_delivery_errors = true

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Resend para envio de emails em produção (resend.com)
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.smtp_settings = {
    address: 'smtp.resend.com',
    port: 587,
    user_name: 'resend',
    password: ENV['RESEND_API_KEY'],
    authentication: :plain,
    enable_starttls_auto: true
  }

  config.action_mailer.default_options = {
    from: 'Practice-BR <contato@practicebr.com>',
    reply_to: 'contato@practicebr.com'
  }

  # Host para os links nos emails
  config.action_mailer.default_url_options = { host: 'app.practicebr.com', protocol: 'https' }
end
