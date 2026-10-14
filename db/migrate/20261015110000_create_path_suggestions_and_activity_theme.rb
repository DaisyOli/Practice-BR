class CreatePathSuggestionsAndActivityTheme < ActiveRecord::Migration[7.1]
  # O agente do percurso (LevelPathAgent) trabalha em segundo plano e deixa uma
  # proposta para a Daisy revisar — nunca muda o percurso sozinho. Dois tipos:
  #
  #   full          → o percurso inteiro de um nível, pedido pelo botão
  #   new_activity  → uma atividade recém-publicada: entra no percurso, e onde?
  #
  # `payload` guarda o que o agente devolveu (ordem, motivos, temas); `resolution`
  # guarda o que a Daisy fez com ela.
  #
  # E `activities.theme`: o tema curto de cada atividade ("Cumprimentos",
  # "Comida"), proposto pelo agente e corrigível. É o que vai agrupar a lista de
  # atividades que as professoras mandam aos alunos.
  def change
    add_column :activities, :theme, :string

    create_table :path_suggestions do |t|
      t.string     :level,  null: false
      t.string     :kind,   null: false
      t.string     :status, null: false, default: "queued"
      t.references :activity, foreign_key: true
      t.jsonb      :payload, null: false, default: {}
      t.text       :error_message
      t.string     :resolution
      t.datetime   :resolved_at
      t.timestamps
    end
    add_index :path_suggestions, [:level, :kind, :status]
  end
end
