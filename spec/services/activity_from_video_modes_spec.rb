require 'rails_helper'

# Gerador por vídeo com escolha de formato (17/11/2026): "em pílulas" (uma
# série, cada pílula com o seu trecho) ou "vídeo inteiro" (uma pílula só, sem
# cortar).
RSpec.describe ActivityFromVideoService, "formatos" do
  let(:teacher)    { create(:user, :teacher) }
  let(:client)     { instance_double(Anthropic::Client) }
  let(:url)        { "https://www.youtube.com/watch?v=abcdefghijk" }
  let(:transcricao) { "0:00\nOlá, gente!\n1:30\nAgora a receita.\n3:10\nE o final." }

  before { allow(Anthropic::Client).to receive(:new).and_return(client) }

  def pilula(titulo, inicio, fim)
    { "title" => titulo, "description" => "Descrição", "level" => "B1", "explanation_text" => "Transcrição.",
      "video_start" => inicio, "video_end" => fim,
      "exercises" => [
        { "type" => "multiple_choice", "content" => "Qual?", "options" => %w[a b c d], "correct_answer" => "a" },
        { "type" => "open_ended", "content" => "Escreva 3 frases." }
      ] }
  end

  def responde_em_streaming(json, stop: "end_turn")
    mensagem = double(stop_reason: stop, content: [double(type: :text, text: json)])
    allow(client).to receive_message_chain(:messages, :stream).and_return(double(accumulated_message: mensagem))
  end

  def servico(**opcoes)
    described_class.new(youtube_url: url, transcript: transcricao, teacher: teacher, level_hint: "B1", **opcoes)
  end

  describe "em pílulas" do
    it "cria a série, cada pílula com o vídeo e o seu trecho" do
      responde_em_streaming({ pills: [pilula("A chegada", "0:00", "1:30"), pilula("A receita", "1:30", "3:10")] }.to_json)
      resultado = servico(mode: "pills").call

      partes = resultado[:activities]
      expect(partes.map(&:series_position)).to eq([1, 2])
      expect(partes.map(&:series_key).uniq.size).to eq(1)
      expect(partes.first.series_key).to start_with("video-")
      expect(partes.map(&:video_url).uniq).to eq([url])
      expect(partes.map { |p| [p.video_start_seconds, p.video_end_seconds] }).to eq([[0, 90], [90, 190]])
      expect(partes).to all(have_attributes(pill: true, draft: true, explanation_is_transcript: true, source_activity_id: nil))
      expect(partes.first.series_label(published_only: false)).to eq("Parte 1 de 2")
      expect(resultado[:activity]).to eq(partes.first)
    end

    it "a quantidade escolhida vai no pedido; sem escolha, a IA decide de 1 a 3" do
      expect(servico(mode: "pills", pill_count: "4").build_prompt).to include("Escolha exatamente 4 trechos")
      expect(servico(mode: "pills").build_prompt).to include("Escolha de 1 a 3")
      expect(servico(mode: "pills", pill_count: "9").build_prompt).to include("Escolha de 1 a 3") # fora de 2 a 5
    end

    it "no máximo 5 pílulas, mesmo que a IA mande mais" do
      responde_em_streaming({ pills: (1..7).map { |i| pilula("Parte #{i}", "0:00", "1:00") } }.to_json)
      expect(servico(mode: "pills", pill_count: "5").call[:activities].size).to eq(5)
    end

    it "sem os tempos na transcrição, nem chama a IA" do
      expect(client).not_to receive(:messages)
      resultado = described_class.new(youtube_url: url, transcript: "Olá, gente! Agora a receita.",
                                      teacher: teacher, mode: "pills").call
      expect(resultado[:error]).to include("com os tempos")
    end

    it "resposta cortada vira um erro claro, sem rascunho" do
      responde_em_streaming({ pills: [pilula("A", "0:00", "1:30")] }.to_json, stop: "max_tokens")
      resultado = nil

      expect { resultado = servico(mode: "pills").call }.not_to change(Activity, :count)
      expect(resultado[:error]).to include("cortada")
    end
  end

  describe "vídeo inteiro" do
    it "faz uma pílula só, e o vídeo toca sem corte mesmo que a IA mande tempos" do
      allow(client).to receive_message_chain(:messages, :create)
        .and_return(double(stop_reason: :end_turn, content: [double(type: :text, text: pilula("Tudo", "1:00", "2:00").to_json)]))
      resultado = servico(mode: "whole").call

      atividade = resultado[:activity]
      expect(atividade).to have_attributes(pill: true, video_url: url, explanation_is_transcript: true, series_key: nil)
      expect(atividade).not_to be_video_excerpt
    end

    it "o pedido é sobre o vídeo todo, e não precisa de tempos" do
      inteiro = described_class.new(youtube_url: url, transcript: "Olá, gente!", teacher: teacher, mode: "whole")
      expect(inteiro.build_prompt).to include("VÍDEO INTEIRO")
      expect(inteiro.build_prompt).not_to include("TRECHO NO PLAYER")
    end
  end
end
