class AddTrialActivationTracking < ActiveRecord::Migration[7.1]
  # Três perguntas que o banco não sabia responder sobre quem entra no teste:
  #
  #   - entrou na plataforma alguma vez?           → first_access_at
  #   - abriu uma atividade (mesmo sem terminar)?  → first_activity_opened_at
  #   - recebeu o lembrete do mesmo dia?           → first_nudge_sent_at
  #
  # "Terminou uma atividade" não precisa de coluna: é a primeira QuizAttempt.
  #
  # E uma tabela pequena, `trial_events`, para o que precisa de trilha de
  # auditoria e não de um carimbo só: a recuperação manual de trials e a
  # extensão excepcional de prazo. Ela guarda o prazo antigo e o novo, e o
  # índice único (user_id, kind) é o que garante "uma vez só" no próprio banco,
  # mesmo com duas execuções ao mesmo tempo.
  def up
    add_column :users, :first_access_at,          :datetime
    add_column :users, :first_activity_opened_at, :datetime
    add_column :users, :first_nudge_sent_at,      :datetime

    create_table :trial_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.jsonb  :details, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :trial_events, [:user_id, :kind], unique: true

    # Quem entrou pelo link da landing já tem a data de entrada gravada em outro
    # lugar. Só preenche o que está vazio — não sobrescreve nada.
    execute <<~SQL
      UPDATE users SET first_access_at = trial_start_used_at
      WHERE first_access_at IS NULL AND trial_start_used_at IS NOT NULL
    SQL
  end

  def down
    drop_table :trial_events
    remove_column :users, :first_nudge_sent_at
    remove_column :users, :first_activity_opened_at
    remove_column :users, :first_access_at
  end
end
