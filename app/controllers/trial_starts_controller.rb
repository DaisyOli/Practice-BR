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
      # "Lembrar de mim" sem a pessoa pedir, e de propósito: ela não tem senha
      # pra digitar se a sessão morrer. Sem isto, fechar o navegador significava
      # depender do link do email — que é o caminho mais frágil dos dois.
      #
      # Marcar no objeto **antes** do sign_in é o que dispara o hook do Devise
      # que grava o cookie. Não existe um `remember_me` de controller aqui.
      user.remember_me = true
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

  # Entrada pelos emails do teste (ver TrialEmailLink). Diferente do `show`, o
  # link não queima: email é aberto duas vezes, no celular e no computador, e
  # antivírus de email clica antes da pessoa.
  LINK_EXPIRED = "Este link de acesso expirou. Para entrar, use \"Esqueci minha senha\" " \
                 "com o seu email — enviamos um link novo na hora.".freeze

  def link
    result = TrialEmailLink.redeem(params[:token])

    if result.nil?
      return redirect_to(after_sign_in_path_for(current_user)) if user_signed_in?
      return redirect_to(new_user_session_path, alert: LINK_EXPIRED)
    end

    user = result.user
    unless current_user == user
      user.remember_me = true
      sign_in(user)
    end

    redirect_to destination_for(result)
  end

  private

  # O destino vem assinado no token; aqui só se confere se ele ainda faz
  # sentido. Uma atividade que saiu do ar, de outro nível, ou já feita leva à
  # dashboard — onde o bloco "Comece por aqui" oferece a próxima. Teste vencido
  # não precisa de caso especial: o check_trial_restrictions! manda para a tela
  # de fim de teste em qualquer destino.
  def destination_for(result)
    case result.destination
    when "billing"
      billing_new_path
    when "activity"
      activity = Activity.published.find_by(id: result.activity_id)
      if activity && !result.user.locked_activity?(activity)
        solve_activity_path(activity)
      else
        student_dashboard_path
      end
    else
      student_dashboard_path
    end
  end
end
