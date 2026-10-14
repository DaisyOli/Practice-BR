class AddTrialShowcasePositionToActivities < ActiveRecord::Migration[7.1]
  # A "Vitrine do teste": até 3 atividades por nível, escolhidas pela Daisy no
  # painel admin, na ordem em que quem está começando deve encontrá-las. Nulo =
  # fora da vitrine. O índice único impede duas atividades na mesma posição do
  # mesmo nível.
  def change
    add_column :activities, :trial_showcase_position, :integer
    add_index :activities, [:level, :trial_showcase_position], unique: true,
              where: "trial_showcase_position IS NOT NULL"
  end
end
