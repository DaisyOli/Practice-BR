class DatabaseConnectionRetry
  MAX_RETRIES = 2

  # O router do Heroku desliga o pedido aos 30s e devolve a página de timeout
  # dele, que não é nossa. Parar antes disso garante que o erro suba a tempo de
  # renderizarmos public/500.html — onde o aluno lê que as respostas dele estão
  # guardadas. Com connect_timeout de 3s as três tentativas somam ~10s, então
  # este teto só entra em ação se algum timeout for afrouxado no futuro.
  TIME_BUDGET = 20

  RETRYABLE = [
    ActiveRecord::DatabaseConnectionError,
    ActiveRecord::ConnectionTimeoutError,
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    started_at = monotonic_now
    retries = 0

    begin
      @app.call(env)
    rescue *RETRYABLE => e
      elapsed = monotonic_now - started_at
      delay = (retries + 1) * 0.5

      if retries < MAX_RETRIES && (elapsed + delay) < TIME_BUDGET
        retries += 1
        Rails.logger.warn "[DB Retry] #{e.class} — tentativa #{retries}/#{MAX_RETRIES} após #{elapsed.round(1)}s, aguardando #{delay}s"
        sleep delay
        # Não usar connection_pool.disconnect! aqui: derrubaria conexões
        # em uso por outras requisições. O Rails descarta sozinho a conexão
        # quebrada e abre uma nova no próximo checkout.
        env['rack.input'].rewind if env['rack.input'].respond_to?(:rewind)
        retry
      else
        Rails.logger.error "[DB Retry] Banco inacessível após #{retries + 1} tentativa(s) em #{elapsed.round(1)}s: #{e.message}"
        raise
      end
    end
  end

  private

  # CLOCK_MONOTONIC não anda pra trás se o relógio do sistema for ajustado.
  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
