# Arquivar (ponto 1.5, 17/11/2026): tirar uma atividade de circulação sem
# apagar o histórico. Excluir destrói tentativas, notas, textos e horas de
# formação dos alunos; arquivar só esconde. Vazio = em circulação.
class AddArchivedAtToActivities < ActiveRecord::Migration[7.1]
  def change
    add_column :activities, :archived_at, :datetime
  end
end
