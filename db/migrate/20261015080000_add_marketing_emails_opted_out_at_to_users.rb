class AddMarketingEmailsOptedOutAtToUsers < ActiveRecord::Migration[7.1]
  # "Não quero mais receber" dos emails que a pessoa não pediu: lembretes,
  # sequência do teste, campanhas. Data e não booleano: guarda quando ela pediu,
  # que é o que importa se um dia alguém perguntar.
  def change
    add_column :users, :marketing_emails_opted_out_at, :datetime
  end
end
