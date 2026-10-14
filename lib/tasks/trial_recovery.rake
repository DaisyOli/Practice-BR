# Recuperação de trials que se cadastraram e não fizeram nenhuma atividade.
# Ver TrialRecovery para as regras. Datas no fuso da aplicação (Paris).
#
#   1. Prévia — só lê, não muda nada:
#        heroku run -a practicebr rake "trial_recovery:preview[2026-10-12,2026-10-13]"
#
#   2. Envio — só para os ids aprovados, e só com CONFIRM=sim:
#        heroku run -a practicebr rake "trial_recovery:run[2026-10-12,2026-10-13]" IDS=410,411 CONFIRM=sim
#
#   EXTENSION_DAYS=7 (nas duas tarefas) muda quanto ganha quem está vencido ou a
#   menos de 48h do fim. Sem ele, 48h.
#
# Rodar o envio duas vezes não manda nada em dobro: o segundo encontra o
# registro em trial_events e pula.
namespace :trial_recovery do
  # Lambdas e não `def`: método definido num arquivo rake vira método de todo
  # objeto do Ruby. E o email sai mascarado — a saída de `heroku run` é texto
  # de terminal, e dado pessoal não tem por que estar ali inteiro.
  mask = ->(email) { local, domain = email.split("@", 2); "#{local[0]}•••@#{domain}" }
  fmt  = ->(time) { time ? time.in_time_zone.strftime("%d/%m %H:%M") : "—" }
  extension = -> { ENV["EXTENSION_DAYS"].present? ? ENV["EXTENSION_DAYS"].to_i.days : 48.hours }

  desc "Lista os trials da janela de datas e quem está elegível para a recuperação (não muda nada)"
  task :preview, [:from, :to] => :environment do |_t, args|
    abort "Uso: rake \"trial_recovery:preview[AAAA-MM-DD,AAAA-MM-DD]\"" if args[:from].blank?

    recovery = TrialRecovery.new(from: args[:from], to: args[:to] || args[:from], extension: extension.call)
    rows     = recovery.report
    puts "Janela: #{recovery.range.begin} → #{recovery.range.end} (#{Time.zone.name})"
    puts "Agora:  #{Time.current}"
    puts "Quem estiver vencido ou a menos de 48h do fim ganha: #{(recovery.extension / 1.hour).round}h"
    puts "Cadastros na janela: #{rows.size}"
    puts

    rows.each do |row|
      u = row.user
      puts "#{row.eligible ? '✅ ELEGÍVEL' : '⛔ fora'}  id #{u.id}  #{mask.(u.email)}  (#{u.language}, #{u.level})"
      puts "    cadastro:   #{fmt.(u.created_at)}   papel: #{u.role}"
      puts "    expira:     #{fmt.(u.trial_expires_at)}#{'   → seria reaberto' if row.will_extend}"
      puts "    boas-vindas: #{row.welcome}"
      puts "    entrou pela landing: #{fmt.(u.trial_start_used_at)}   1º acesso: #{fmt.(u.first_access_at)}   senha: #{u.password_set_at ? 'sim' : 'não'}"
      puts "    abriu atividade: #{fmt.(u.first_activity_opened_at)}   concluídas: #{u.quiz_attempts.count}   último email automático: #{u.trial_winback_sent_at ? 'winback (\"o último\")' : '—'}"
      puts "    lembretes: mesmo dia #{fmt.(u.first_nudge_sent_at)} · D+1 #{fmt.(u.activation_nudge_sent_at)}"
      puts "    motivo: #{row.reason}" unless row.eligible
      puts
    end

    eligible = rows.select(&:eligible)
    puts "Elegíveis: #{eligible.size}  →  IDS=#{eligible.map { |r| r.user.id }.join(',')}"
    puts "Seriam reabertos: #{eligible.count(&:will_extend)}"
    puts "Nada foi enviado nem alterado."
  end

  desc "Envia a recuperação para os IDS aprovados (exige CONFIRM=sim)"
  task :run, [:from, :to] => :environment do |_t, args|
    abort "Uso: rake \"trial_recovery:run[AAAA-MM-DD,AAAA-MM-DD]\" IDS=1,2 CONFIRM=sim" if args[:from].blank?
    ids = ENV["IDS"].to_s.split(",").map(&:strip).reject(&:blank?)
    abort "Faltou IDS=... — rode a prévia e copie a linha IDS dela." if ids.empty?
    abort "Faltou CONFIRM=sim. Nada foi enviado." unless ENV["CONFIRM"] == "sim"

    result = TrialRecovery.new(from: args[:from], to: args[:to] || args[:from], extension: extension.call).run!(ids)
    puts "Enviados (na fila): #{result[:sent].size}  #{result[:sent].join(', ')}"
    result[:skipped].each { |id, reason| puts "Pulado id #{id}: #{reason}" }
  end
end
