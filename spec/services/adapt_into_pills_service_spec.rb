require 'rails_helper'

# "✂️ Adaptar em pílulas" (ponto 1.4, 17/11/2026).
RSpec.describe AdaptIntoPillsService do
  let(:teacher)  { create(:user, :teacher) }
  let(:original) do
    create(:activity, :B2, teacher: teacher, draft: false, title: "Uma viagem longa",
                            explanation_text: "Texto longo da original sobre uma viagem.")
  end
  let(:client)   { instance_double(Anthropic::Client) }
  let(:messages) { double("messages") }

  before do
    create(:question, :multiple_choice, activity: original, content: "Para onde ela foi?",
                                         options: %w[Recife Natal Belém Manaus], correct_answer: "Recife")
    create(:question, :open_ended, activity: original, content: "Conte uma viagem sua.")
    allow(Anthropic::Client).to receive(:new).and_return(client)
    allow(client).to receive(:messages).and_return(messages)
  end

  def pilula(titulo, extra = {})
    { "title" => titulo, "description" => "Descrição", "level" => "A1", "explanation_text" => "Parte do texto.",
      "exercises" => [
        { "type" => "multiple_choice", "content" => "Para onde ela foi?",
          "options" => %w[Recife Natal Belém Manaus], "correct_answer" => "Recife" },
        { "type" => "open_ended", "content" => "Conte uma viagem sua." }
      ] }.merge(extra)
  end

  def responde(json, stop: :end_turn)
    allow(messages).to receive(:create)
      .and_return(double(stop_reason: stop, content: [double(type: :text, text: json)]))
  end

  def adaptar(transcript: nil)
    described_class.new(source: original, teacher: teacher, transcript: transcript).call
  end

  it "cria a série de rascunhos, no nível da original e ligada a ela" do
    responde({ pills: [pilula("A chegada"), pilula("O passeio")] }.to_json)
    resultado = adaptar

    expect(resultado[:success]).to be true
    partes = resultado[:activities]
    expect(partes.map(&:title)).to eq(["A chegada", "O passeio"])
    expect(partes.map(&:series_position)).to eq([1, 2])
    expect(partes).to all(have_attributes(source_activity_id: original.id, level: "B2",
                                          pill: true, draft: true, ai_generated: true))
    expect(resultado[:activity]).to eq(partes.first)
    expect(partes.first.writing_challenge.content).to eq("Conte uma viagem sua.")
    expect(original.reload.adapted_pills.count).to eq(2)
  end

  it "a IA recebe a original inteira, com os exercícios, para reaproveitar" do
    pedido = described_class.new(source: original, teacher: teacher).user_prompt

    expect(pedido).to include("Uma viagem longa", "Texto longo da original", "nível B2", "REAPROVEITE",
                              "[multiple_choice] Para onde ela foi?", "certa: Recife",
                              "[open_ended] Conte uma viagem sua.", '{"pills"')
    expect(pedido).not_to include("TRANSCRIÇÃO COM TEMPOS", "{{")
  end

  it "no máximo 3 pílulas" do
    responde({ pills: (1..4).map { |i| pilula("Pílula #{i}") } }.to_json)
    expect(adaptar[:activities].size).to eq(3)
  end

  it "tudo ou nada: se uma pílula não monta, nenhuma fica nos rascunhos" do
    responde({ pills: [pilula("Boa"), pilula("")] }.to_json) # sem título não salva
    resultado = nil

    expect { resultado = adaptar }.not_to change(Activity, :count)
    expect(resultado[:success]).to be false
    expect(resultado[:error]).to include("pílula 2")
  end

  it "resposta cortada vira um erro claro, sem rascunho" do
    responde({ pills: [pilula("X")] }.to_json, stop: :max_tokens)
    resultado = nil

    expect { resultado = adaptar }.not_to change(Activity, :count)
    expect(resultado[:error]).to include("cortada")
  end

  it "uma pílula não é adaptada de novo" do
    original.update!(pill: true)
    expect(messages).not_to receive(:create)

    expect(adaptar[:error]).to include("já é uma pílula")
  end

  describe "atividade com vídeo" do
    before { original.update!(video_url: "https://www.youtube.com/watch?v=abcdefghijk") }

    it "sem a transcrição com tempos, nem chama a IA" do
      expect(messages).not_to receive(:create)
      expect(adaptar[:error]).to include("transcrição")
    end

    it "cada pílula ganha o vídeo e o seu trecho" do
      responde({ pills: [pilula("Começo", "video_start" => "0:00", "video_end" => "1:30"),
                         pilula("Fim",    "video_start" => "1:30", "video_end" => "3:10")] }.to_json)
      servico = described_class.new(source: original, teacher: teacher, transcript: "0:00\nOlá\n1:30\nDepois")

      expect(servico.user_prompt).to include("TRANSCRIÇÃO COM TEMPOS", "0:00\nOlá", '"video_start"')
      partes = servico.call[:activities]
      expect(partes.map(&:video_url).uniq).to eq([original.video_url])
      expect(partes.map { |p| [p.video_start_seconds, p.video_end_seconds] }).to eq([[0, 90], [90, 190]])
      expect(partes).to all(be_explanation_is_transcript)
    end
  end
end
