class AddTrialReopenedAtToUsers < ActiveRecord::Migration[7.1]
  # Reabrir o teste de quem nunca chegou a usá-lo.
  #
  # Pedir assinatura a quem não abriu uma única atividade é pedir dinheiro por
  # algo que a pessoa nunca viu. Antes de falar em pagar, a plataforma devolve o
  # que ela não usou — uma vez só, e esta coluna é o "uma vez só".
  def change
    add_column :users, :trial_reopened_at, :datetime
  end
end
