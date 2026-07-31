# Roda uma vez por dia (cron do GoodJob, ver config/environments/production.rb).
# Cumpre o art. 5.1.e do RGPD — não guardar dado por mais tempo que o necessário
# — apagando conta abandonada nos prazos declarados no registre des traitements.
#
# É o único job que apaga dado de gente, então ele é deliberadamente lento e
# conservador:
#
#   1. avisa por email quando falta a carência (30 dias) pro prazo vencer;
#   2. só apaga quem foi avisado e deixou a carência inteira passar;
#   3. se a pessoa voltou a praticar no meio, o aviso é limpo e tudo recomeça.
#
# Quem nunca entra na conta: professora, admin e quem tem assinatura em curso —
# `User#retention_deadline` devolve nil pra esses e o job pula. A regra de quem
# é candidato mora no model, não aqui, porque a spec do model é mais fácil de
# ler que a do job.
class AccountRetentionJob < ApplicationJob
  queue_as :default

  def perform
    warned  = []
    deleted = []
    failed  = []

    candidates.find_each do |user|
      next if user.retention_deadline.nil?

      unless user.retention_warning_due?
        # Voltou a praticar depois de avisada: o relógio reinicia e o aviso
        # anterior não vale mais. Sem isto, um retorno breve não impediria a
        # exclusão — o aviso velho seguiria "maduro".
        user.update_column(:retention_warning_sent_at, nil) if user.retention_warning_sent_at.present?
        next
      end

      if user.retention_warning_sent_at.blank?
        RetentionMailer.deletion_warning(user).deliver_now
        user.update_column(:retention_warning_sent_at, Time.current)
        warned << user.id
        next
      end

      next unless user.retention_expired? && user.retention_warning_matured?

      begin
        deleted << AccountDeletionService.new(user, notify_admin: false).call
      rescue StandardError => e
        # Uma conta que falha não pode derrubar a varredura das outras. E não
        # apagar é sempre o lado seguro do erro: amanhã tenta de novo.
        Rails.logger.error "[Retenção] Exclusão falhou · user ##{user.id}: #{e.class} — #{e.message}"
        failed << user.id
      end
    end

    report(warned: warned, deleted: deleted, failed: failed)
  end

  private

  # Professora e admin ficam fora já na consulta, além do guarda do model: são
  # dois filtros pra mesma coisa de propósito. `admin` é booleano que aceita nil,
  # daí o `[nil, false]` — `where.not(admin: true)` não pega os nil no SQL, e
  # esse é o valor da maioria das contas.
  def candidates
    User.where(role: %w[student trial]).where(admin: [nil, false])
  end

  # Só escreve quando aconteceu alguma coisa: um relatório diário dizendo "nada"
  # vira ruído e ninguém lê o dia em que ele deixa de dizer nada.
  #
  # Identifica por id, nunca por email — regra 2 do PROTECAO_DE_DADOS.md.
  def report(warned:, deleted:, failed:)
    return if warned.empty? && deleted.empty? && failed.empty?

    Rails.logger.info(
      "[Retenção] avisados: #{warned.size} · apagados: #{deleted.size} · falhas: #{failed.size} " \
      "· ids apagados: #{deleted.inspect}"
    )
    AdminMailer.retention_report(warned: warned, deleted: deleted, failed: failed).deliver_later
  end
end
