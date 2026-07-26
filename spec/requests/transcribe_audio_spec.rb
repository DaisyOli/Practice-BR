require 'rails_helper'

RSpec.describe "Transcrição de áudio em background", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:teacher)  { create(:user, :teacher) }
  let(:student)  { create(:user, :student) }
  let(:activity) { create(:activity, teacher: teacher) }
  let(:audio_file) do
    Rack::Test::UploadedFile.new(
      StringIO.new("fake audio data"),
      "audio/webm",
      original_filename: "recording.webm"
    )
  end

  describe "autenticação" do
    it "redireciona usuário não autenticado" do
      post transcribe_activity_path(activity)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "POST /activities/:slug/transcribe — como aluno autenticado" do
    before { sign_in student }

    context "sem áudio no request" do
      it "retorna 422 com mensagem de erro, sem criar transcrição" do
        expect {
          post transcribe_activity_path(activity), as: :json
        }.not_to change(AudioTranscription, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to be_present
      end
    end

    context "com áudio" do
      it "cria a transcrição, enfileira o job e devolve o id (sem chamar o Whisper na requisição)" do
        expect(WhisperTranscriptionService).not_to receive(:new)

        expect {
          post transcribe_activity_path(activity), params: { audio: audio_file }
        }.to change(AudioTranscription, :count).by(1).and have_enqueued_job(AudioTranscriptionJob)

        expect(response).to have_http_status(:ok)
        transcription = AudioTranscription.last
        expect(transcription.user).to eq(student)
        expect(transcription.audio_file).to be_attached
        expect(JSON.parse(response.body)["transcription_id"]).to eq(transcription.id)
      end
    end
  end

  describe "GET /activities/:slug/transcribe_status" do
    before { sign_in student }

    it "devolve queued enquanto o job não rodou" do
      transcription = AudioTranscription.create!(user: student, status: "queued")

      get transcribe_status_activity_path(activity), params: { id: transcription.id }
      expect(response.parsed_body["status"]).to eq("queued")
    end

    # Regressão do bug de produção: o JS montava a URL como
    # "...transcribe_status?locale=pt?id=1" (duas "?"), então o Rails lia
    # locale="pt?id=1" e params[:id] ficava nil -> "Transcrição não encontrada".
    # Aqui garantimos que a URL bem-formada (locale E id na MESMA query string,
    # separados por &) é lida corretamente.
    it "lê params[:id] quando a URL já tem locale na query string" do
      transcription = AudioTranscription.create!(user: student, status: "queued")

      get "/activities/#{activity.slug}/transcribe_status?locale=pt&id=#{transcription.id}"
      expect(response.parsed_body["status"]).to eq("queued")
    end

    it "devolve o texto quando o job termina com sucesso" do
      allow(WhisperTranscriptionService).to receive(:new)
        .and_return(double(call: { success: true, text: "Eu moro em Paris." }))

      post transcribe_activity_path(activity), params: { audio: audio_file }
      transcription_id = response.parsed_body["transcription_id"]

      perform_enqueued_jobs

      get transcribe_status_activity_path(activity), params: { id: transcription_id }
      expect(response.parsed_body["status"]).to eq("done")
      expect(response.parsed_body["text"]).to eq("Eu moro em Paris.")
    end

    it "devolve o erro quando o serviço falha" do
      allow(WhisperTranscriptionService).to receive(:new)
        .and_return(double(call: { success: false, error: "Não entendi o áudio." }))

      post transcribe_activity_path(activity), params: { audio: audio_file }
      transcription_id = response.parsed_body["transcription_id"]

      perform_enqueued_jobs

      get transcribe_status_activity_path(activity), params: { id: transcription_id }
      expect(response.parsed_body["status"]).to eq("failed")
      expect(response.parsed_body["error"]).to eq("Não entendi o áudio.")
    end

    it "não deixa um aluno consultar a transcrição de outro" do
      other_student = create(:user, :student)
      foreign = AudioTranscription.create!(user: other_student, status: "done", text: "segredo")

      get transcribe_status_activity_path(activity), params: { id: foreign.id }
      expect(response.parsed_body["status"]).to eq("failed")
      expect(response.parsed_body["text"]).to be_nil
    end
  end

  describe "como professora autenticada" do
    before do
      sign_in teacher
      allow(WhisperTranscriptionService).to receive(:new)
        .and_return(double(call: { success: true, text: "Texto transcrito." }))
    end

    it "também pode transcrever (para testar as próprias atividades)" do
      post transcribe_activity_path(activity), params: { audio: audio_file }
      expect(response).to have_http_status(:ok)

      perform_enqueued_jobs
      transcription_id = response.parsed_body["transcription_id"]

      get transcribe_status_activity_path(activity), params: { id: transcription_id }
      expect(response.parsed_body["status"]).to eq("done")
    end
  end
end
