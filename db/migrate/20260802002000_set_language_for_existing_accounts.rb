class SetLanguageForExistingAccounts < ActiveRecord::Migration[7.1]
  # Continuação de FixDefaultLanguageToFrench: as contas que não são de teste.
  #
  # Nenhuma dessas pessoas escolheu inglês — elas nasceram assim por causa do
  # `default: "en"` da coluna. A Daisy, que conhece cada uma pelo nome, disse
  # quem é o quê em 2026-08-01. Identificação por id, nunca por email (regra 2
  # de docs/PROTECAO_DE_DADOS.md).
  #
  # O `language = 'en'` no WHERE é proposital: se alguém tiver escolhido um
  # idioma de verdade nesse meio-tempo, esta migração não passa por cima.
  FRANCOFONAS = [133, 134, 201, 232].freeze  # duas professoras e dois alunos
  BRASILEIRA  = [100].freeze                 # conta de aluna da própria Daisy

  def up
    execute "UPDATE users SET language = 'fr' WHERE id IN (#{FRANCOFONAS.join(',')}) AND language = 'en'"
    execute "UPDATE users SET language = 'pt' WHERE id IN (#{BRASILEIRA.join(',')}) AND language = 'en'"
  end

  # Sem `down`: reverter seria devolver essas pessoas a um inglês que elas nunca
  # pediram. A migração anterior já cuida do default da coluna.
  def down
  end
end
