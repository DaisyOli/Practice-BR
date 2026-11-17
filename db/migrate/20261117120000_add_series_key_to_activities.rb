# Chave da série de pílulas (17/11/2026). A série agrupava pela atividade
# original (source_activity_id), e isso quebrou duas vezes no mesmo dia: apagar
# a original desfazia a série, e o gerador por vídeo também faz séries, sem
# original nenhuma. A chave é só da série.
#
# O `up` religa as séries que já existem, inclusive as do piloto cuja original
# foi apagada: uma série começa na posição 1, e as posições seguintes (2, 3...)
# da mesma professora, criadas até 10 minutos depois, entram nela. A adaptação
# cria tudo de uma vez, então é sempre assim que elas aparecem no banco.
class AddSeriesKeyToActivities < ActiveRecord::Migration[7.1]
  class MigrationActivity < ActiveRecord::Base
    self.table_name = "activities"
  end

  def up
    add_column :activities, :series_key, :string
    add_index  :activities, :series_key

    MigrationActivity.reset_column_information
    chave    = nil
    anterior = nil
    MigrationActivity.where.not(series_position: nil).order(:id).each do |parte|
      continua = anterior &&
                 parte.series_position == anterior.series_position + 1 &&
                 parte.teacher_id == anterior.teacher_id &&
                 parte.created_at - anterior.created_at <= 10.minutes
      chave = "serie-#{parte.id}" unless continua
      parte.update_columns(series_key: chave)
      anterior = parte
    end
  end

  def down
    remove_index  :activities, :series_key
    remove_column :activities, :series_key
  end
end
