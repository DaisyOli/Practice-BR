class ActivateWeeklyReminderByDefault < ActiveRecord::Migration[7.1]
  # O lembrete semanal nasceu desligado (`default: false` na migração que criou
  # a coluna) e só ligava se a pessoa marcasse a caixa no aceite de convite —
  # caixa que quem vem da landing nunca vê, porque lá o cadastro é só email e
  # nível. Resultado em produção: os dois alunos pagantes de verdade não
  # recebiam nada durante a semana. O lembrete é o único contato regular que a
  # plataforma tem com quem estuda; desligado por padrão, ele não existe.
  #
  # O UPDATE em massa é seguro HOJE porque nenhum `false` no banco é escolha de
  # ninguém: todos vêm do default antigo, e os dois `true` que existem foram
  # ligados à mão. Se um dia houver desligamento deliberado, este backfill não
  # pode ser repetido — quem desligou tem que continuar desligado.
  #
  # A saída continua a um clique: o toggle na dashboard (students#toggle_weekly).
  def up
    change_column_default :users, :weekly_reminder_email, from: false, to: true
    execute "UPDATE users SET weekly_reminder_email = TRUE"
  end

  def down
    change_column_default :users, :weekly_reminder_email, from: true, to: false
  end
end
