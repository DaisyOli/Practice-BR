# Pílula (ponto 1 da reformulação, 15/11/2026): atividade curta em que a
# pergunta aberta sai do quiz e vira um desafio de escrita opcional, oferecido
# depois do resultado. A IA marca as que gera; as antigas continuam como eram.
class AddPillToActivities < ActiveRecord::Migration[7.1]
  def change
    add_column :activities, :pill, :boolean, default: false, null: false
  end
end
