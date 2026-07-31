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

    ACCOUNT_DELETED_NOTICE = "Sua conta foi apagada. Foi bom ter você por aqui — a porta fica aberta. 💚".freeze

    def destroy
      return refuse_teacher_self_deletion if resource.teacher?

      user_id = resource.id

      # O como está em AccountDeletionService — o mesmo caminho que o
      # AccountRetentionJob usa pra apagar conta abandonada. Aqui fica só o que é
      # HTTP: recusa da professora, sessão e mensagem.
      AccountDeletionService.new(resource).call

      sign_out(resource_name)
      redirect_to root_path, notice: ACCOUNT_DELETED_NOTICE
    rescue Stripe::StripeError, ActiveRecord::ActiveRecordError => e
      # Não apaga. Uma conta apagada com assinatura ativa é pior que uma conta que
      # sobreviveu: a segunda a pessoa pode tentar de novo, a primeira cobra em
      # silêncio. O RGPD dá até um mês pra atender o pedido, então esperar um dia
      # não é descumprimento.
      Rails.logger.error "[Conta] Exclusão abortada · user ##{user_id}: #{e.class} — #{e.message}"
      AdminMailer.account_deletion_failed_notification(user_id, "#{e.class}: #{e.message}").deliver_later
      redirect_to student_dashboard_path, alert: STRIPE_FAILURE_ALERT
    end

    private

    def refuse_teacher_self_deletion
      redirect_to teacher_dashboard_path, alert: TEACHER_REFUSAL_ALERT
    end
  end
end
