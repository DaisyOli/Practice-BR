# O link dos emails do teste que leva a pessoa para dentro, já logada, e direto
# para onde o email prometeu (a atividade, a dashboard ou a assinatura).
#
# **O problema que ele resolve.** Quem entra pela landing nunca escolhe senha. A
# sessão dela vive num cookie do navegador onde ela se cadastrou. Os emails
# antigos mandavam para `solve_activity_url` ou `billing_new_url`, que exigem
# login: quem abria o email no celular depois de se cadastrar no computador (ou
# com a sessão vencida) caía na tela de login, sem senha para digitar. O único
# caminho era o link do email de boas-vindas — que levava a "Criar nova senha",
# em português, para quem talvez só lesse francês. Era a mesma barreira de
# senha que zerou a ativação em julho, só que mudada de lugar.
#
# **Por que não reusar o TrialStartToken.** Aquele vale 30 minutos e queima no
# primeiro uso, porque viaja pela URL da landing. Um link de email precisa
# sobreviver a cliques repetidos e aos robôs de antivírus (Outlook, Gmail) que
# abrem os links antes da pessoa — um token de uso único seria gasto pelo robô.
#
# **O risco, e por que é o mesmo que já existia.** O link do email de
# boas-vindas já era, na prática, um login de 8 dias (redefinir a senha loga a
# pessoa). Este tem o mesmo prazo (User::PASSWORDLESS_LINK_VALIDITY) e regras
# mais estreitas:
#
#   - só serve para conta de teste que nunca escolheu senha. Quem escolheu
#     senha tem como entrar sozinha, e o link deixa de funcionar na hora;
#   - nunca serve para professora ou admin;
#   - o destino vem assinado dentro do token, não de um parâmetro da URL — não
#     dá para transformar o link num redirecionamento para fora do site.
class TrialEmailLink
  PURPOSE      = "trial_email".freeze
  VALIDITY     = User::PASSWORDLESS_LINK_VALIDITY
  DESTINATIONS = %w[activity dashboard billing].freeze

  Result = Struct.new(:user, :destination, :activity_id, keyword_init: true)

  class << self
    def generate(user, to: "dashboard", activity: nil)
      raise ArgumentError, "destino desconhecido: #{to}" unless DESTINATIONS.include?(to)

      payload = { "u" => user.id, "to" => to, "a" => activity&.id }
      verifier.generate(payload, purpose: PURPOSE, expires_in: VALIDITY)
    end

    # Devolve um Result, ou nil se o token for inválido, vencido, ou se a conta
    # não puder mais entrar por link.
    def redeem(raw_token)
      return nil if raw_token.blank?

      payload = verifier.verified(raw_token, purpose: PURPOSE)
      return nil unless payload.is_a?(Hash)

      user = User.find_by(id: payload["u"])
      return nil unless usable_by?(user)

      Result.new(user: user, destination: payload["to"], activity_id: payload["a"])
    end

    def usable_by?(user)
      user.present? && user.trial? && user.passwordless? && !user.admin?
    end

    private

    def verifier
      Rails.application.message_verifier(:trial_email)
    end
  end
end
