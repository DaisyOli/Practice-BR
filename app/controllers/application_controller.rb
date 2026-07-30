class ApplicationController < ActionController::Base
  # Token CSRF desatualizado (aba aberta há muito tempo, botão "voltar", etc.)
  # manda pro login de novo em vez de mostrar a página de erro padrão do Rails.
  rescue_from ActionController::InvalidAuthenticityToken do
    reset_session
    redirect_to new_user_session_path, alert: t("devise.failure.timeout")
  end

  # Autenticação padrão
  before_action :authenticate_user!
  before_action :suppress_redundant_flash
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :check_trial_restrictions!
  before_action :check_payment_status!
  around_action :switch_locale

  def after_sign_in_path_for(resource)
    if resource.teacher?
      teacher_dashboard_path
    elsif resource.trial? && resource.invitation_accepted_at.present?
      billing_new_path
    elsif resource.student_like?
      student_dashboard_path
    else
      root_path
    end
  end
  
  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name, :language])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name, :language])
    devise_parameter_sanitizer.permit(:accept_invitation, keys: [:name, :language])
    devise_parameter_sanitizer.permit(:invite, keys: [:name, :role, :language, :email])
  end

  private

  def suppress_redundant_flash
    redundant = [
      I18n.t('devise.failure.unauthenticated'),
      I18n.t('devise.failure.already_authenticated'),
      I18n.t('devise.sessions.signed_in'),
      I18n.t('devise.sessions.signed_out'),
      I18n.t('devise.sessions.already_signed_out')
    ]
    [:notice, :alert].each { |k| flash.delete(k) if redundant.include?(flash[k]) }
  end

  def check_trial_restrictions!
    return unless current_user&.trial?
    return if devise_controller?
    return if controller_name == "billing"
    return if controller_name == "webhooks"

    if current_user.invitation_accepted_at.present?
      # Aluno convidado pelo professor: redireciona para assinatura
      redirect_to billing_new_path
    else
      # Aluno da landing page: trial de 3 atividades ou 7 dias
      return if controller_name == "home" && action_name == "trial_expired"
      redirect_to trial_expired_path if current_user.trial_expired? || current_user.trial_exhausted?
    end
  end

  # Cartão recusado não corta o acesso na hora: o aluno tem
  # User::PAYMENT_GRACE_DAYS pra atualizar o pagamento, avisado por email
  # (StudentMailer#payment_failed) e pelo banner na dashboard. Vencida a
  # tolerância, aí sim o acesso de pagante para.
  #
  # Antes disto o `subscription_status` era gravado mas nunca lido: um aluno com
  # cartão recusado seguia com acesso completo até o Stripe desistir das
  # tentativas, o que pode levar semanas.
  def check_payment_status!
    return unless current_user&.payment_grace_expired?
    return if devise_controller?
    # A própria tela do problema, a rota que leva pra fatura e o webhook precisam
    # continuar acessíveis — senão o aluno fica sem caminho pra resolver.
    return if controller_name.in?(%w[billing webhooks])

    redirect_to billing_payment_problem_path
  end

  def switch_locale(&action)
    I18n.with_locale(I18n.default_locale, &action)
  end
end

