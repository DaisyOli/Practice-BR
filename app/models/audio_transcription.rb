# Transcrição de resposta em áudio (aluno respondendo pergunta aberta por voz)
# rodando em background (AudioTranscriptionJob). O áudio em si é descartado
# assim que a transcrição termina — só o texto fica guardado.
class AudioTranscription < ApplicationRecord
  STATUSES = %w[queued done failed].freeze

  belongs_to :user
  has_one_attached :audio_file

  validates :status, inclusion: { in: STATUSES }

  def done?   = status == "done"
  def failed? = status == "failed"
end
