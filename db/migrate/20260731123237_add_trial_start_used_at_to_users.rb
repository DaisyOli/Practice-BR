# Marca que o link de entrada do trial já foi usado. É o que torna o token de
# uso único — e ele faz login, então uso único importa. Ver TrialStartToken.
class AddTrialStartUsedAtToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :trial_start_used_at, :datetime
  end
end
