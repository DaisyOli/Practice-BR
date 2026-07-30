module Users
  # Existe por um motivo só: o `destroy` do Devise apagava o usuário sem avisar o
  # Stripe. A assinatura continuava viva e o cartão seguia sendo cobrado — de uma
  # pessoa que não tem mais conta pra entrar e cancelar, e sem nada no app
  # registrando isso. A cobrança acontecia, o webhook não encontrava usuário
  # nenhum (`return unless user`) e desistia em silêncio.
  #
  # Herda de DeviseInvitable::RegistrationsController, não de Devise, porque é
  # esse que está em uso (o devise_invitable substitui o de registrations).
  class RegistrationsController < DeviseInvitable::RegistrationsController
    STRIPE_FAILURE_ALERT = "Não conseguimos cancelar sua assinatura agora, então não apagamos sua conta — " \
                           "apagar sem cancelar deixaria a cobrança correndo. Já fomos avisados e vamos " \
                           "resolver; se preferir, escreva para contato@practicebr.com.".freeze

    TEACHER_REFUSAL_ALERT = "Contas de professora não são apagadas por aqui, porque as atividades que você " \
                            "criou continuam sendo usadas pelos alunos. Escreva para " \
                            "contato@practicebr.com que a gente cuida disso com você.".freeze

    def destroy
      return refuse_teacher_self_deletion if resource.teacher?

      # A ordem importa: cancelar ANTES de apagar. Se apagássemos primeiro e o
      # Stripe falhasse, ficaríamos exatamente com o problema que este controller
      # existe pra resolver — assinatura órfã cobrando um fantasma.
      cancel_subscription!

      AdminMailer.account_deleted_notification(
        user_id:            resource.id,
        role:               resource.role,
        stripe_customer_id: resource.stripe_customer_id
      ).deliver_later

      super
    rescue Stripe::StripeError => e
      # Não apaga. Uma conta apagada com assinatura ativa é pior que uma conta que
      # sobreviveu: a segunda a pessoa pode tentar de novo, a primeira cobra em
      # silêncio. O RGPD dá até um mês pra atender o pedido, então esperar um dia
      # não é descumprimento.
      Rails.logger.error "[Conta] Falha ao cancelar assinatura na exclusão · user ##{resource.id}: #{e.message}"
      AdminMailer.account_deletion_failed_notification(resource.id, e.message).deliver_later
      redirect_to student_dashboard_path, alert: STRIPE_FAILURE_ALERT
    end

    private

    # Cancelamento imediato, não `cancel_at_period_end`. A conta está sendo
    # apagada: deixar a assinatura agendada manteria, num plano anual, uma
    # assinatura "ativa" no Stripe por meses pra alguém que não existe mais.
    def cancel_subscription!
      sub_id = resource.stripe_subscription_id
      return if sub_id.blank?
      return if resource.subscription_status == "canceled"

      Stripe::Subscription.cancel(sub_id)
      Rails.logger.info "[Conta] Assinatura cancelada antes de apagar · user ##{resource.id}"
    end

    def refuse_teacher_self_deletion
      redirect_to teacher_dashboard_path, alert: TEACHER_REFUSAL_ALERT
    end
  end
end
