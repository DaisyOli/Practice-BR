# Até onde a pessoa chega numa atividade (ponto 2.1, 17/11/2026). Uma linha por
# abertura da página do quiz, criada no primeiro sinal de gente do outro lado
# (toque, tecla, rolagem): o robô do antivírus de email pede a página, mas não
# vira linha.
#
# Sem isso, quem abandona no meio não deixa rastro: a QuizAttempt só nasce no
# envio. Com isso, dá para ver em que questão as pessoas param, e se a tela nova
# do ponto 2 muda alguma coisa.
class CreateActivityVisits < ActiveRecord::Migration[7.1]
  def change
    create_table :activity_visits do |t|
      t.references :user,     null: false, foreign_key: { on_delete: :cascade }
      t.references :activity, null: false, foreign_key: { on_delete: :cascade }
      # Gerado pelo servidor ao montar a página: recarregar = abertura nova.
      t.string   :token,         null: false
      t.integer  :furthest_step, null: false, default: 1
      t.integer  :total_steps,   null: false
      t.datetime :answered_at   # primeira resposta nesta abertura
      t.datetime :submitted_at
      t.timestamps
    end

    add_index :activity_visits, :token, unique: true
  end
end
