# Tela de confirmação da exclusão de conta. Só mostra o que vai acontecer — o
# DELETE em si é o do Devise, em Users::RegistrationsController#destroy.
#
# É uma tela e não um `confirm()` do navegador porque o RGPD e a LGPD pedem que a
# pessoa saiba o que está apagando, e porque aqui tem uma consequência de
# dinheiro: a assinatura é cancelada na hora, sem devolução do período pago.
class AccountDeletionsController < ApplicationController
  before_action :redirect_teachers

  def new
    @has_subscription = current_user.stripe_subscription_id.present? &&
                        current_user.subscription_status != "canceled"
    @attempts_count = current_user.quiz_attempts.count
  end

  private

  # Professora não se auto-exclui: as atividades dela continuam sendo usadas
  # pelos alunos. Pedido vai por email, pra Daisy decidir o destino do conteúdo.
  def redirect_teachers
    return unless current_user&.teacher?

    redirect_to teacher_dashboard_path,
                alert: Users::RegistrationsController::TEACHER_REFUSAL_ALERT
  end
end
