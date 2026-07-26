# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.

# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers: a minimum and maximum.
# Any libraries that use thread pools should be configured to match
# the maximum value specified for Puma. Default is set to 5 threads for minimum
# and maximum; this matches the default thread size of Active Record.
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 8 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

rails_env = ENV.fetch("RAILS_ENV") { "development" }

if rails_env == "production"
  # Melhoria na configuração de workers para produção
  # Na maioria dos dyno do Heroku, 2-3 workers é uma boa configuração
  worker_count = Integer(ENV.fetch("WEB_CONCURRENCY") { 2 })
  
  workers worker_count
  
  # Preload app para melhor desempenho com múltiplos workers
  preload_app!
  
  # Aumentar o timeout do worker para evitar problemas com requisições longas
  worker_timeout 120
  
  # Configuração para requisições maiores
  persistent_timeout 60
  
  # Configurações de baixa latência
  # fast_exit!  # Removendo esta linha que está causando o erro
  
  # Adiciona recomendação para variável de ambiente
  unless ENV["RAILS_MAX_THREADS"]
    puts "AVISO: A variável RAILS_MAX_THREADS não está definida. Usando valor padrão de #{max_threads_count}."
    puts "Recomendamos configurar RAILS_MAX_THREADS=8 e WEB_CONCURRENCY=2 em seu Heroku."
  end
  
  # Adiciona configuração para manter o aplicativo aquecido
  # GoodJob roda em modo :async dentro dos workers do Puma; os hooks abaixo
  # param/reiniciam os threadpools ao redor do fork (recomendação do README do GoodJob)
  #
  # GoodJob.shutdown sem argumento espera INDEFINIDAMENTE o job em andamento
  # terminar (timeout: -1 é o default). Como o Heroku só dá 30s entre SIGTERM
  # e o SIGKILL forçado (erro R12), um job de IA que demore mais que isso
  # (é comum) travava o processo até ser morto à força no meio do deploy.
  # Com um timeout de 20s aqui, é o próprio GoodJob que desiste a tempo e
  # deixa o Puma encerrar limpo, em vez do Heroku matar o processo na marra.
  GOOD_JOB_SHUTDOWN_TIMEOUT = 20

  before_fork do
    puts "Puma inicializando com #{worker_count} workers e #{max_threads_count} threads por worker"
    GoodJob.shutdown(timeout: GOOD_JOB_SHUTDOWN_TIMEOUT) if defined?(GoodJob)
  end

  on_worker_boot do
    GoodJob.restart if defined?(GoodJob)
  end

  on_worker_shutdown do
    GoodJob.shutdown(timeout: GOOD_JOB_SHUTDOWN_TIMEOUT) if defined?(GoodJob)
  end

  MAIN_PID = Process.pid
  at_exit do
    GoodJob.shutdown(timeout: GOOD_JOB_SHUTDOWN_TIMEOUT) if defined?(GoodJob) && Process.pid == MAIN_PID
  end
end

# Specifies the `worker_timeout` threshold that Puma will use to wait before
# terminating a worker in development environments.
worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT") { 3000 }

# Specifies the `environment` that Puma will run in.
environment rails_env

# Specifies the `pidfile` that Puma will use.
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart
