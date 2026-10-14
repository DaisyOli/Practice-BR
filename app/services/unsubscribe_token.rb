# O link de "não quero mais receber" que vai no rodapé e no cabeçalho
# List-Unsubscribe dos emails não transacionais.
#
# **Não vence.** Um email de três meses atrás precisa continuar sabendo
# descadastrar — é a exigência da CNIL e dos provedores (Gmail, Yahoo). E o
# estrago possível com ele é mínimo: o pior que alguém faz com um link vazado é
# parar os lembretes de outra pessoa, que pode religar na mesma página.
class UnsubscribeToken
  PURPOSE = "unsubscribe".freeze

  class << self
    def generate(user)
      verifier.generate(user.id, purpose: PURPOSE)
    end

    def user_for(raw_token)
      return nil if raw_token.blank?

      id = verifier.verified(raw_token, purpose: PURPOSE)
      id && User.find_by(id: id)
    end

    private

    def verifier
      Rails.application.message_verifier(:unsubscribe)
    end
  end
end
