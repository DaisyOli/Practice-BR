require 'rails_helper'

# Trecho de vídeo da pílula (ponto 1.3, 16/11/2026): o player do YouTube toca só
# do início ao fim marcados, e a professora marca o trecho no bloco do vídeo.
RSpec.describe "Trecho do vídeo", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:teacher)  { create(:user, :teacher) }
  let(:student)  { create(:user, :student) }
  let(:video)    { "https://www.youtube.com/watch?v=abcdefghijk" }
  let(:activity) { create(:activity, :B1, teacher: teacher, draft: false, video_url: video) }

  before { create(:question, :multiple_choice, activity: activity) }

  describe "no quiz do aluno" do
    before { sign_in student }

    it "com trecho: o player começa e para nos tempos marcados, e a legenda avisa" do
      activity.update!(video_start: "1:20", video_end: "3:45")
      get solve_activity_path(activity)

      expect(response.body).to include("youtube.com/embed/abcdefghijk?end=225&amp;start=80")
      expect(response.body).to include("Só um pedaço do vídeo", "1:20", "3:45")
    end

    it "sem trecho: o vídeo inteiro, como sempre" do
      get solve_activity_path(activity)

      expect(response.body).to include(%(youtube.com/embed/abcdefghijk"))
      expect(response.body).not_to include("Só um pedaço do vídeo")
    end
  end

  describe "a professora marca o trecho" do
    before { sign_in teacher }

    it "salva e o link do YouTube abre no começo do trecho" do
      patch activity_path(activity), params: { activity: { video_url: video, video_start: "1:20", video_end: "3:45" } }

      expect(response).to redirect_to(activity_path(activity, ultimo_conteudo: "video"))
      expect([activity.reload.video_start_seconds, activity.video_end_seconds]).to eq([80, 225])

      get activity_path(activity)
      expect(response.body).to include("watch?v=abcdefghijk&amp;t=80s")
      expect(response.body).to include('name="activity[video_start]"', 'value="1:20"')
    end

    it "tempo errado volta para o bloco do vídeo com o motivo, sem salvar" do
      patch activity_path(activity), params: { activity: { video_url: video, video_start: "3:00", video_end: "1:00" } }

      expect(response).to redirect_to(activity_path(activity, anchor: "video"))
      expect(flash[:alert]).to include("O fim do trecho precisa vir depois do início")
      expect(activity.reload).not_to be_video_excerpt
    end
  end

  it "a revisão de rascunho mostra o trecho" do
    rascunho = create(:activity, :A1, teacher: teacher, draft: true, video_url: video,
                      video_start_seconds: 80, video_end_seconds: 225)
    sign_in teacher
    get review_draft_activity_path(rascunho)

    expect(response.body).to include("youtube.com/embed/abcdefghijk?end=225&amp;start=80")
  end
end
