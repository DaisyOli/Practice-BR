# Trilha de auditoria do que a plataforma fez, por decisão humana, com o teste
# de alguém: o email de recuperação e a extensão excepcional de prazo.
#
# Não é log de tudo — os emails automáticos continuam marcados nas colunas
# `*_sent_at` do User. Isto aqui existe para o que precisa responder "quem
# decidiu, quando, e qual era o prazo antes".
#
# O índice único (user_id, kind) é a trava de "uma vez só": duas execuções
# simultâneas da recuperação não conseguem gravar o mesmo evento duas vezes.
class TrialEvent < ApplicationRecord
  # `extension_48h` é o nome antigo (recuperação de 12–13/10); `extension`
  # guarda a duração nos detalhes.
  KINDS = %w[recovery_email extension extension_48h].freeze

  belongs_to :user

  validates :kind, inclusion: { in: KINDS }
end
