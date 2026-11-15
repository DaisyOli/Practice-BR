class AddEmailBouncedAtToUsers < ActiveRecord::Migration[7.1]
  # O servidor da pessoa recusou o email de forma definitiva (webhook do Resend).
  # A conta 497 recebeu seis envios seguidos sem nenhum chegar: insistir não
  # alcança ninguém e prejudica a reputação de envio do domínio.
  def change
    add_column :users, :email_bounced_at, :datetime
  end
end
