require 'rails_helper'

# Ponto 1.3: na geração por vídeo, a IA devolve onde o trecho começa e termina,
# tirado das marcações de tempo da transcrição. Trecho sem sentido é ignorado:
# o vídeo toca inteiro e a geração segue.
RSpec.describe "Trecho de vídeo na geração" do
  before { allow(Anthropic::Client).to receive(:new).and_return(instance_double(Anthropic::Client)) }

  let(:teacher) { create(:user, :teacher) }

  def gerar(extra = {})
    dados = {
      "title" => "Pílula de vídeo", "description" => "Descrição", "level" => "B1",
      "exercises" => [{ "type" => "multiple_choice", "content" => "Qual?", "options" => %w[a b c d], "correct_answer" => "a" }]
    }.merge(extra)
    ActivityGenerationService.new(prompt: "x", teacher: teacher).send(:build_activity, dados)[:activity]
  end

  it "guarda o trecho que a IA marcou" do
    atividade = gerar("video_start" => "1:20", "video_end" => "3:45")
    expect([atividade.video_start_seconds, atividade.video_end_seconds]).to eq([80, 225])
  end

  it "ignora trecho sem sentido, e a atividade sai mesmo assim" do
    expect(gerar("video_start" => "3:45", "video_end" => "1:20")).not_to be_video_excerpt  # fim antes do início
    expect(gerar("video_start" => "0:00", "video_end" => "15:00")).not_to be_video_excerpt # longo demais
    expect(gerar("video_start" => "um", "video_end" => "dois")).not_to be_video_excerpt    # não é tempo
    expect(gerar).not_to be_video_excerpt                                                  # sem tempos
  end

  describe "o pedido de vídeo" do
    let(:servico) { ActivityFromVideoService.new(youtube_url: "https://youtu.be/abcdefghijk", transcript: transcricao, teacher: nil) }
    let(:transcricao) { "0:00\nOlá!\n0:05\nHoje vamos cozinhar." }

    it "nas pílulas, pede os tempos de cada trecho" do
      pedido = servico.build_prompt
      expect(pedido).to include("TRECHO NO PLAYER", '"video_start"', '"video_end"')
    end

    it "lê até 20 mil caracteres da transcrição" do
      longa = ActivityFromVideoService.new(youtube_url: "https://youtu.be/abcdefghijk", transcript: "a" * 25_000, teacher: nil)
      expect(longa.instance_variable_get(:@transcript).size).to eq(20_000)
    end
  end
end
