class CreateAiPrompts < ActiveRecord::Migration[7.1]
  # Repare no que esta migration NÃO faz: ela não semeia nada.
  #
  # A do ContentTarget semeava, e estava certa lá — sem linha na tabela, não
  # havia meta nenhuma e a tela apareceria vazia. Aqui é o contrário: quando não
  # existe linha, o `AiPrompt.body_for` devolve a constante do código. Uma tabela
  # vazia já se comporta exatamente como o app se comportava ontem.
  #
  # Isso compra três coisas:
  #   1. o deploy não muda uma vírgula de comportamento, sem precisar copiar
  #      282 linhas de prompt para dentro de um INSERT;
  #   2. prompt que a Daisy nunca editou continua acompanhando o código — se
  #      melhorarmos o texto num commit, ela recebe a melhoria;
  #   3. apagar a linha é o botão de "voltar ao original de fábrica".
  #
  # A linha nasce no primeiro save da tela, e não antes.
  def change
    create_table :ai_prompts do |t|
      t.string :key,  null: false
      t.text   :body, null: false
      t.timestamps
    end
    add_index :ai_prompts, :key, unique: true

    # Histórico. Reescrever um prompt de 282 linhas sem botão de desfazer é
    # construir uma ferramenta que dá medo de usar.
    create_table :ai_prompt_versions do |t|
      t.references :ai_prompt, null: false, foreign_key: true
      t.text       :body,      null: false
      t.datetime   :created_at, null: false
    end
  end
end
