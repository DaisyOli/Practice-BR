require 'rails_helper'

# Trecho de vídeo da pílula (ponto 1.3, 16/11/2026).
RSpec.describe Activity, "trecho do vídeo" do
  let(:video) { "https://www.youtube.com/watch?v=abcdefghijk" }
  let(:activity) { create(:activity, :B1, video_url: video) }

  it "recebe 1:20 no formulário e guarda segundos" do
    activity.update!(video_start: "1:20", video_end: "3:45")

    expect(activity.video_start_seconds).to eq(80)
    expect(activity.video_end_seconds).to eq(225)
    expect(activity.video_start).to eq("1:20")
    expect(activity).to be_video_excerpt
  end

  it "campos em branco voltam ao vídeo inteiro" do
    activity.update!(video_start: "1:20", video_end: "3:45")
    activity.update!(video_start: "", video_end: "")

    expect(activity).not_to be_video_excerpt
  end

  it "tempo escrito errado não salva e diz o formato certo" do
    expect(activity.update(video_start: "um minuto")).to be false
    expect(activity.errors.full_messages.to_sentence).to include("O início do trecho precisa estar no formato 1:20")
  end

  it "o fim precisa vir depois do início" do
    expect(activity.update(video_start: "3:00", video_end: "1:00")).to be false
    expect(activity.errors.full_messages.to_sentence).to include("O fim do trecho precisa vir depois do início")
  end

  describe "quando o vídeo muda" do
    before { activity.update!(video_start: "1:20", video_end: "3:45") }

    it "trocar por outro vídeo apaga o trecho, que era do antigo" do
      activity.update!(video_url: "https://www.youtube.com/watch?v=zzzzzzzzzzz")
      expect(activity.reload).not_to be_video_excerpt
    end

    it "trocar o vídeo já com o trecho novo guarda o trecho novo" do
      activity.update!(video_url: "https://www.youtube.com/watch?v=zzzzzzzzzzz", video_start: "0:10", video_end: "2:00")
      expect([activity.reload.video_start_seconds, activity.video_end_seconds]).to eq([10, 120])
    end

    it "remover o vídeo apaga o trecho" do
      activity.update!(video_url: nil)
      expect(activity.reload).not_to be_video_excerpt
    end
  end

  # A geração por vídeo grava o trecho antes do link (ActivityFromVideoService).
  it "ganhar o primeiro vídeo não apaga um trecho já marcado" do
    sem_video = create(:activity, :B1, video_start_seconds: 80, video_end_seconds: 225)
    sem_video.update!(video_url: video)

    expect([sem_video.reload.video_start_seconds, sem_video.video_end_seconds]).to eq([80, 225])
  end
end
