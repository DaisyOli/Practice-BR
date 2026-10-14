class RenameTrialShowcasePositionToPathPosition < ActiveRecord::Migration[7.1]
  # A vitrine do teste (3 por nível) virou o começo do percurso do nível (10).
  # Renomear em vez de criar coluna nova preserva o que a Daisy já escolheu: as
  # posições 1–3 continuam sendo a vitrine, agora como início do caminho.
  def change
    rename_column :activities, :trial_showcase_position, :path_position
  end
end
