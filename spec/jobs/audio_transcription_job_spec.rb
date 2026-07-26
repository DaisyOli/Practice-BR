require 'rails_helper'

RSpec.describe AudioTranscriptionJob, type: :job do
  let(:student) { create(:user, :student) }

  let(:transcription) do
    t = AudioTranscription.create!(user: student, status: "queued")
    t.audio_file.attach(io: StringIO.new("fake audio"), filename: "recording.webm", content_type: "audio/webm")
    t
  end

  it "marca done e salva o texto quando o Whisper funciona" do
    allow(WhisperTranscriptionService).to receive(:new)
      .and_return(double(call: { success: true, text: "Eu moro em Paris." }))

    described_class.perform_now(transcription.id)

    transcription.reload
    expect(transcription.status).to eq("done")
    expect(transcription.text).to eq("Eu moro em Paris.")
  end

  it "marca failed quando o Whisper retorna erro" do
    allow(WhisperTranscriptionService).to receive(:new)
      .and_return(double(call: { success: false, error: "Não entendi." }))

    described_class.perform_now(transcription.id)

    transcription.reload
    expect(transcription.status).to eq("failed")
    expect(transcription.error_message).to eq("Não entendi.")
  end

  it "descarta o áudio depois de transcrever" do
    allow(WhisperTranscriptionService).to receive(:new)
      .and_return(double(call: { success: true, text: "ok" }))

    expect { described_class.perform_now(transcription.id) }
      .to have_enqueued_job(ActiveStorage::PurgeJob)
  end

  it "não quebra se a transcrição já não existir mais" do
    id = transcription.id
    transcription.destroy
    expect { described_class.perform_now(id) }.not_to raise_error
  end
end
