# Transcreve em background a resposta em áudio de um aluno (pergunta aberta,
# resolve_quiz). Antes disso a chamada ao Whisper acontecia dentro da própria
# requisição HTTP — com vários alunos gravando ao mesmo tempo, cada chamada
# prendia uma thread do Puma até a OpenAI responder.
class AudioTranscriptionJob < ApplicationJob
  queue_as :default

  def perform(transcription_id)
    transcription = AudioTranscription.find_by(id: transcription_id)
    return unless transcription && transcription.status == "queued"
    return unless transcription.audio_file.attached?

    transcription.audio_file.open do |file|
      result = WhisperTranscriptionService.new(file).call
      if result[:success]
        transcription.update!(status: "done", text: result[:text])
      else
        transcription.update!(status: "failed", error_message: result[:error])
      end
    end
  rescue => e
    Rails.logger.error "AudioTranscriptionJob: #{e.class} - #{e.message}"
    transcription&.update!(status: "failed", error_message: "Erro ao transcrever o áudio. Tente digitar sua resposta.")
  ensure
    transcription&.audio_file&.purge_later
  end
end
