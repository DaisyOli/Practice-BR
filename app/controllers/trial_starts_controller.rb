# Entrada do trial vinda da landing. A pessoa acabou de preencher o formulário
# lá e chega aqui com o token na mão: a gente faz o login e ela cai na dashboard
# com as três atividades disponíveis.
#
# O objetivo é um só — que a primeira atividade aconteça sem passar pela caixa
# de entrada. Antes disto o caminho era: "confira seu email" → sair do site →
# achar a mensagem → inventar uma senha → entrar → procurar uma atividade. Três
# desses passos aconteciam fora do nosso alcance.
#
# A senha deixa de ser porta de entrada e vira consequência: quem quiser voltar
# depois usa o link do email, e quem quiser continuar além das três atividades
# cria a senha no fim, já sabendo o que está comprando.
class TrialStartsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :check_trial_restrictions!
  skip_before_action :check_payment_status!

  # Idioma da pessoa: quem chega aqui é sobretudo francófono, e uma boas-vindas
  # que ela não entende é pior que nenhuma. Mesmo padrão do RetentionMailer.
  WELCOME = {
    "fr" => "Bienvenue ! Vous avez 3 activités pour essayer — commençons.",
    "en" => "Welcome! You have 3 activities to try — let's start.",
    "pt" => "Boas-vindas! Você tem 3 atividades para experimentar — vamos lá."
  }.freeze

  EXPIRED = "Este link de acesso já foi usado ou expirou. " \
            "Enviamos um por email quando você se cadastrou — use aquele para entrar.".freeze

  def show
    user = TrialStartToken.redeem(params[:token])

    if user
      sign_in(user)
      redirect_to student_dashboard_path, notice: WELCOME.fetch(user.language, WELCOME["fr"])
    elsif user_signed_in?
      # Link clicado duas vezes, aba recarregada, prefetch do navegador: a pessoa
      # já está dentro, então não tem por que mostrar erro pra ela.
      redirect_to after_sign_in_path_for(current_user)
    else
      redirect_to new_user_session_path, alert: EXPIRED
    end
  end
end
