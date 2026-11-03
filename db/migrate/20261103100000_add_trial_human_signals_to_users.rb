class AddTrialHumanSignalsToUsers < ActiveRecord::Migration[7.1]
  # O funil não sabia separar gente de robô. `first_access_at` e
  # `first_activity_opened_at` são gravados quando a página é pedida ao servidor,
  # e o antivírus de email que segue o link do botão também pede a página.
  #
  #   first_human_at          → primeira interação real (toque, tecla, rolagem)
  #   first_activity_human_at → a mesma coisa, dentro de uma atividade
  #   first_answer_at         → começou a responder, antes de enviar
  #   first_entry_source      → por onde entrou pela primeira vez: landing ou email
  #
  # Sem preenchimento retroativo de propósito: em contas antigas o dado não
  # existe, e copiar de outra coluna foi o erro de `first_access_at` em outubro.
  def change
    add_column :users, :first_human_at,          :datetime
    add_column :users, :first_activity_human_at, :datetime
    add_column :users, :first_answer_at,         :datetime
    add_column :users, :first_entry_source,      :string
  end
end
