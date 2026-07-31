# A conta não é apagada de surpresa: o AccountRetentionJob avisa por email antes
# e só apaga depois da carência. Esta coluna guarda a data do aviso — sem ela não
# há como saber se a pessoa já foi avisada, e o job ou avisaria todo dia ou
# apagaria sem ter avisado nunca.
#
# Volta a nil quando a pessoa pratica de novo: o relógio da inatividade reinicia.
class AddRetentionWarningSentAtToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :retention_warning_sent_at, :datetime
  end
end
