# O link que leva a pessoa da landing direto pra dentro do app, já logada.
#
# Existe porque o primeiro contato com o produto não podia depender de uma ida à
# caixa de entrada: quem preenche o formulário quer praticar agora, e cada passo
# entre a vontade e a primeira atividade é gente que some. O email continua
# saindo — ele deixa de ser portão e vira o caminho de volta.
#
# **Por que não reusar o `reset_password_token`.** Ele tem um trabalho só, que é
# definir a senha pelo email, e é justamente o caminho de volta quando a pessoa
# fecha o navegador. Um token que faz login e um token que troca senha viverem no
# mesmo campo é o tipo de economia que se paga caro depois.
#
# O token entra pela query string, então precisa continuar sendo filtrado dos
# logs — `:token` já está em `filter_parameter_logging.rb`. Sem isso, um token de
# login ficaria escrito no log do Heroku, que é exatamente o que a regra 2 do
# PROTECAO_DE_DADOS.md existe pra impedir.
class TrialStartToken
  PURPOSE  = "trial_start".freeze
  VALIDITY = 30.minutes

  class << self
    def generate(user)
      verifier.generate(user.id, purpose: PURPOSE, expires_in: VALIDITY)
    end

    # Devolve o usuário e **queima** o token, ou nil se ele for inválido,
    # expirado ou já usado.
    #
    # Uso único porque este token faz login: se vazar pelo histórico do
    # navegador ou por um header de referer, ele vale uma vez e só nos primeiros
    # 30 minutos. Quem clicar depois cai no fluxo normal de login.
    def redeem(raw_token)
      return nil if raw_token.blank?

      user_id = verifier.verified(raw_token, purpose: PURPOSE)
      return nil if user_id.blank?

      user = User.find_by(id: user_id)
      return nil if user.nil?
      # Só serve pra estrear um trial. Um token velho não pode virar atalho de
      # login pra uma conta que já virou aluna pagante.
      return nil unless user.trial?
      return nil if user.trial_start_used_at.present?

      user.update_column(:trial_start_used_at, Time.current)
      user
    end

    private

    def verifier
      Rails.application.message_verifier(:trial_start)
    end
  end
end
