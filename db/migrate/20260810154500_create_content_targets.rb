class CreateContentTargets < ActiveRecord::Migration[7.1]
  def up
    create_table :content_targets do |t|
      t.string  :level, null: false
      t.integer :goal
      t.timestamps
    end
    add_index :content_targets, :level, unique: true

    # Preserva as metas que viviam congeladas na constante TARGET do
    # Admin::DraftsController, para que o deploy não mude comportamento nenhum.
    #
    # O C1 entra sem meta: continua fora do modo automático (que não sabe
    # quanto conteúdo ele deveria ter), mas passa a ser escolhível na mão.
    # Antes ele não existia para o agente por caminho nenhum.
    execute(<<~SQL)
      INSERT INTO content_targets (level, goal, created_at, updated_at) VALUES
        ('A1', 30,   NOW(), NOW()),
        ('A2', 30,   NOW(), NOW()),
        ('B1', 30,   NOW(), NOW()),
        ('B2', 20,   NOW(), NOW()),
        ('C1', NULL, NOW(), NOW())
    SQL
  end

  def down
    drop_table :content_targets
  end
end
