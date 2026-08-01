class AddPasswordSetAtToUsers < ActiveRecord::Migration[7.1]
  # Quem entra pela landing nunca escolhe uma senha: a conta nasce com uma
  # aleatória (Api::V1::TrialsController) que ninguém nunca vê. Até aqui não
  # havia como distinguir essa pessoa de quem digitou a própria senha — e é
  # justamente essa distinção que decide se a gente pede a senha depois do
  # pagamento e por quanto tempo o link do email continua valendo.
  def up
    add_column :users, :password_set_at, :datetime

    # Backfill conservador: só marca quem com certeza escolheu a própria senha,
    # que é quem aceitou um convite (a tela de aceite exige senha). Na dúvida,
    # deixa nulo: o erro para esse lado custa no máximo um formulário de senha
    # oferecido a quem já tem uma. O erro para o outro lado deixa alguém sem
    # caminho de volta, que é o problema que esta coluna existe pra resolver.
    execute <<~SQL
      UPDATE users
      SET password_set_at = invitation_accepted_at
      WHERE invitation_accepted_at IS NOT NULL
    SQL
  end

  def down
    remove_column :users, :password_set_at
  end
end
