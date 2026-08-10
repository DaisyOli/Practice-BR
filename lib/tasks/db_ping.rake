# O ping que mantém o banco acordado.
#
# Ele funciona desde 10/07/2026, mas até agora existia só como um texto colado no
# painel do Heroku Scheduler: invisível para quem lê o repositório, impossível de
# testar, e sem como mudar junto com o resto do código. Este arquivo traz o ping
# para dentro do projeto.
#
# ---- Por que ele precisa dizer o próprio nome ---------------------------------
#
# Quando o essential-0 recusa conexão, o ping falha — e isso é SINAL, não ruído. É
# ele que prova que o problema é do banco e não do app: processo separado, sem
# controller, sem IA. Foi assim que se descartou a IA como culpada em 04/08/2026.
# Silenciar seria jogar fora a única testemunha isenta.
#
# O problema é outro. No relatório de 08/08/2026, 51 dos 53 eventos eram esta
# falha, e ela chegava ao Sentry sem nada que a identificasse — com a mesma cara
# de um erro de banco na tela de um aluno. O risco de uma parede de eventos iguais
# não é a cota de 5 mil por mês: é a pessoa se acostumar a não abrir o relatório.
#
# ---- Quem coloca a etiqueta ---------------------------------------------------
#
# Ninguém, aqui. A tarefa não captura nada e não trata exceção: ela deixa o erro
# subir.
#
# Quem marca é a integração de Rake do próprio SDK (`sentry-ruby/lib/sentry/rake.rb`),
# que já põe `rake_task: db:ping` e usa o nome da tarefa como transação — o mesmo
# campo que mostrou `WebhooksController#stripe` no erro do dia 03/08. Ela cobre até
# a falha que acontece ANTES desta linha, no carregamento do `:environment`, onde um
# `rescue` daqui não alcançaria.
#
# Escrever aqui um `capture_exception` com etiqueta própria não mudaria uma linha
# do comportamento; só pareceria estar fazendo alguma coisa. O que o `db_ping_spec.rb`
# trava é justamente a suposição em que isso se apoia: que a integração está ligada.
#
# ---- Como ligar ---------------------------------------------------------------
#
#   heroku addons:open scheduler -a practicebr
#
# e trocar o comando do job de 10 em 10 minutos por `rake db:ping`. Enquanto o
# comando antigo estiver lá, nada disto vale: é ele que continua rodando.

namespace :db do
  desc "Ping do banco (Heroku Scheduler, a cada 10 min). Mantém o essential-0 acordado."
  task ping: :environment do
    ActiveRecord::Base.connection.select_value("SELECT 1")
    puts "[db:ping] ok"
  end
end
