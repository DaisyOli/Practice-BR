# O funil do teste numa janela de datas. Ver TrialFunnel.
#
#   heroku run -a practicebr rake "trial_funnel:report[2026-10-01]"
#   heroku run -a practicebr rake "trial_funnel:report[2026-09-01,2026-09-30]" EXCLUDE=331,364
#
# EXCLUDE serve para tirar contas de teste da conta — com amostras pequenas,
# uma conta de teste muda a taxa inteira.
namespace :trial_funnel do
  desc "Funil do teste: pediu → usou o link → interagiu → respondeu → concluiu (só lê)"
  task :report, [:from, :to] => :environment do |_t, args|
    abort "Uso: rake \"trial_funnel:report[AAAA-MM-DD(,AAAA-MM-DD)]\"" if args[:from].blank?

    from = Time.zone.parse(args[:from]).beginning_of_day
    to   = args[:to].present? ? Time.zone.parse(args[:to]).end_of_day : Time.current
    s    = TrialFunnel.new(from: from, to: to, exclude_ids: ENV["EXCLUDE"].to_s.split(",")).stats

    puts "Funil do teste · #{from.to_date} → #{to.to_date}"
    puts "  pediram o teste ........ #{s[:requested]}"
    puts "  usaram o link .......... #{s[:link_used]}"
    puts "  concluíram a primeira .. #{s[:completed_first]}"
    puts "  venceram sem nada ...... #{s[:expired_untouched]}"
    puts "  assinaram .............. #{s[:converted]}"
    puts "  taxa de ativação ....... #{s[:activation_rate]}%  (concluíram ≥1 ÷ pediram)"
    puts "  medido de verdade, só contas desde #{TrialFunnel.measured_since.to_date}: #{s[:measured]}"
    puts "    interagiram no app ... #{s[:entered]}"
    puts "    interagiram com atividade #{s[:opened_activity]}"
    puts "    começaram a responder  #{s[:answered]}"
    puts "    por onde entraram .... #{s[:by_source].map { |fonte, n| "#{fonte}: #{n}" }.join(', ').presence || '-'}"
    puts "  primeira atividade veio depois de:"
    s[:activated_after].each { |label, n| puts "    #{label}: #{n}" }
    puts "  (\"depois de\" é ordem no tempo, não prova que o email causou a volta)"
  end
end
