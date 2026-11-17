# Pílulas em série (ponto 1.4, 17/11/2026): uma atividade longa adaptada vira
# 1 a 3 pílulas. Cada pílula guarda de qual atividade veio e a sua posição,
# para a parte seguinte passar na frente na "Próxima atividade". Se a original
# for apagada, as pílulas ficam, só perdem o vínculo.
class AddSeriesToActivities < ActiveRecord::Migration[7.1]
  def change
    add_reference :activities, :source_activity, foreign_key: { to_table: :activities, on_delete: :nullify }
    add_column :activities, :series_position, :integer
  end
end
