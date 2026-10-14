class AddTrialNextStepSentAtToUsers < ActiveRecord::Migration[7.1]
  # O email do meio da Fase B (3 dias depois do fim do teste): a próxima
  # atividade do percurso, concreta. Mesma trava de "uma vez só" dos outros
  # emails da sequência (TrialSequenceJob#send_once).
  def change
    add_column :users, :trial_next_step_sent_at, :datetime
  end
end
