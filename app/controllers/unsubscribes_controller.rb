# "Não quero mais receber estes emails." Funciona sem login — quem está no teste
# nunca escolheu senha, e o link precisa servir de qualquer caixa de entrada.
# Quem prova a identidade é o UnsubscribeToken.
#
# O GET só pergunta; o POST descadastra. Os antivírus de email abrem todo link
# que veem, e um descadastro por GET tiraria pessoas da lista sem elas saberem.
# O POST sem formulário vem do botão "Cancelar inscrição" do Gmail (RFC 8058),
# por isso não exige o token CSRF — o token do link já autentica.
class UnsubscribesController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :check_trial_restrictions!
  skip_before_action :check_payment_status!
  skip_forgery_protection only: [:create, :destroy]

  before_action :load_user

  def show
    @state = @user.marketing_emails_opted_out? ? :done : :ask
  end

  def create
    @user.update_column(:marketing_emails_opted_out_at, Time.current) unless @user.marketing_emails_opted_out?
    @state = :done
    render :show
  end

  def destroy
    @user.update_column(:marketing_emails_opted_out_at, nil)
    @state = :back
    render :show
  end

  private

  def load_user
    @user  = UnsubscribeToken.user_for(params[:token])
    @token = params[:token]
    @lang  = @user&.language.presence_in(User::LANGUAGES) || "fr"
    @state = :invalid if @user.nil?
    render :show, status: :not_found if @user.nil?
  end
end
