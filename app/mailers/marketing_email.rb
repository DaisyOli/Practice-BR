# Emails que a pessoa não pediu — lembretes, a sequência do teste, campanhas —
# em oposição aos transacionais (boas-vindas, pagamento, aviso de exclusão de
# conta), que saem sempre.
#
# Duas regras, aplicadas aqui e não em cada job, para nenhum caminho escapar
# (cron, botão do admin, rake de campanha):
#
#   1. Quem pediu para não receber não recebe: a mensagem é montada e não sai.
#   2. Quem recebe ganha o cabeçalho List-Unsubscribe com clique único
#      (RFC 8058) — o "Cancelar inscrição" que o Gmail mostra no topo.
#
# O link do rodapé fica no partial `trial_mailer/_message`.
module MarketingEmail
  extend ActiveSupport::Concern

  included do
    class_attribute :marketing_actions, default: [].freeze
    after_action :apply_marketing_rules
  end

  class_methods do
    def marketing(*names)
      self.marketing_actions = (marketing_actions + names.map(&:to_s)).freeze
    end
  end

  private

  def apply_marketing_rules
    return unless marketing_actions.include?(action_name)

    recipient = @user || @student
    return if recipient.nil?

    if recipient.marketing_emails_opted_out?
      message.perform_deliveries = false
      return
    end

    url = unsubscribe_url(token: UnsubscribeToken.generate(recipient))
    message.header["List-Unsubscribe"]      = "<#{url}>"
    message.header["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
  end
end
