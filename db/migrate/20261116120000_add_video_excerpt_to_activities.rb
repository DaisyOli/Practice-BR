# Trecho de vídeo da pílula (ponto 1.3, 16/11/2026): o player do YouTube toca
# só do início ao fim marcados, em segundos. Vazio = o vídeo inteiro, como
# sempre foi.
class AddVideoExcerptToActivities < ActiveRecord::Migration[7.1]
  def change
    add_column :activities, :video_start_seconds, :integer
    add_column :activities, :video_end_seconds, :integer
  end
end
