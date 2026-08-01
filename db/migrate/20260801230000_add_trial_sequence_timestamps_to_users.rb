class AddTrialSequenceTimestampsToUsers < ActiveRecord::Migration[7.1]
  # A sequência de emails do teste. Cada coluna é a prova de que aquele email já
  # saiu — mesmo padrão de trial_reminder_sent_at e inactivity_nudge_sent_at.
  #
  # Um carimbo por etapa, e não um contador, porque cada email da sequência sai
  # UMA vez na vida da pessoa. Contador convidaria a reenviar.
  def change
    # D+1 sem ter feito a primeira atividade. É onde estavam 4 das 5 pessoas.
    add_column :users, :activation_nudge_sent_at, :datetime

    # No dia em que o teste morre (esgotou as 3 ou venceu o prazo).
    add_column :users, :trial_ended_email_sent_at, :datetime

    # Alguns dias depois do fim. O último email antes do silêncio de 11 meses.
    add_column :users, :trial_winback_sent_at, :datetime
  end
end
