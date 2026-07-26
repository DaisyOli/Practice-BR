class CreateAudioTranscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :audio_transcriptions do |t|
      t.bigint :user_id, null: false
      t.string :status, default: "queued", null: false
      t.text :text
      t.text :error_message

      t.timestamps
    end

    add_index :audio_transcriptions, :user_id
    add_foreign_key :audio_transcriptions, :users
  end
end
