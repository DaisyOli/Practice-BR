class AddPastDueSinceToUsers < ActiveRecord::Migration[7.1]
  # Quando o cartão de um aluno é recusado, o acesso não cai na hora: ele tem
  # alguns dias de tolerância pra atualizar o pagamento (User::PAYMENT_GRACE_DAYS).
  # Para contar esses dias precisamos saber QUANDO a primeira cobrança falhou —
  # o updated_at não serve, porque qualquer outra alteração no usuário o mexeria.
  def change
    add_column :users, :past_due_since, :datetime
  end
end
