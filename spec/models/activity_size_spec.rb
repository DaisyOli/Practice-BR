require 'rails_helper'

# Tempo e tamanho da atividade, para os cartões (ponto 2.2 da reformulação
# "Practice em pílulas", 18/11/2026). A conta foi calibrada com 89 tentativas
# reais, mirando a pessoa típica: o que pesa é escrever (~4 min), ler (~2 min
# por 100 palavras) e o vídeo, e não o exercício fechado (~¾ de minuto).
RSpec.describe "Activity: tempo e tamanho", type: :model do
  let(:atividade) { create(:activity, :A2, draft: false, statement: nil, explanation_text: nil) }

  def palavras(n)
    (["palavra"] * n).join(" ")
  end

  def fresca
    Activity.find(atividade.id)
  end

  describe "#exercise_count" do
    it "conta todos os tipos: escolha, lacuna, ordenar frase, ordenar parágrafo e ligar colunas" do
      create(:question, :multiple_choice, activity: atividade)
      create(:question, :fill_in_blank, activity: atividade)
      SentenceOrdering.create!(activity: atividade, sentence: "Eu gosto de café")
      ParagraphOrdering.create!(activity: atividade)
      ColumnMatching.create!(activity: atividade)

      expect(fresca.exercise_count).to eq(5)
    end

    it "na pílula, o desafio de escrita fica de fora: ele é opcional" do
      atividade.update!(pill: true)
      create(:question, :multiple_choice, activity: atividade)
      create(:question, :open_ended, activity: atividade)

      expect(fresca.exercise_count).to eq(1)
      expect(fresca.writing_challenge?).to be(true)
    end

    it "fora da pílula, a questão aberta é exercício como os outros" do
      create(:question, :multiple_choice, activity: atividade)
      create(:question, :open_ended, activity: atividade)

      expect(fresca.exercise_count).to eq(2)
      expect(fresca.writing_challenge?).to be(false)
    end
  end

  describe "#estimated_minutes" do
    it "¾ de minuto por exercício fechado, arredondando para cima" do
      4.times { create(:question, :multiple_choice, activity: atividade) }

      expect(fresca.estimated_minutes).to eq(3)
    end

    it "4 minutos por questão aberta dentro do quiz" do
      create(:question, :multiple_choice, activity: atividade)
      create(:question, :open_ended, activity: atividade)

      # 0,75 + 4 = 4,75 → 5
      expect(fresca.estimated_minutes).to eq(5)
    end

    it "o desafio opcional da pílula não entra no tempo" do
      atividade.update!(pill: true)
      3.times { create(:question, :multiple_choice, activity: atividade) }
      create(:question, :open_ended, activity: atividade)

      # só os 3 fechados: 2,25 → 3
      expect(fresca.estimated_minutes).to eq(3)
    end

    it "2 minutos por 100 palavras de texto, arredondando para cima" do
      atividade.update!(statement: palavras(100), explanation_text: "<p>#{palavras(30)}</p>")
      2.times { create(:question, :multiple_choice, activity: atividade) }

      # 2 exercícios (1,5) + 130 palavras (2,6) = 4,1 → 5
      expect(fresca.estimated_minutes).to eq(5)
    end

    it "a transcrição do vídeo não conta como leitura: o tempo dela está no vídeo" do
      atividade.update!(explanation_text: palavras(900), explanation_is_transcript: true,
                        video_url: "https://youtu.be/abcdefghijk")
      3.times { create(:question, :multiple_choice, activity: atividade) }

      # 3 exercícios (2,25) + vídeo inteiro (5) = 7,25 → 8
      expect(fresca.estimated_minutes).to eq(8)
    end

    it "o trecho de vídeo conta a própria duração" do
      atividade.update!(video_url: "https://youtu.be/abcdefghijk", video_start: "1:00", video_end: "2:30")
      3.times { create(:question, :multiple_choice, activity: atividade) }

      # 3 exercícios (2,25) + 90 s (1,5) = 3,75 → 4
      expect(fresca.estimated_minutes).to eq(4)
    end

    it "um trecho longo nunca pesa mais que um vídeo inteiro" do
      atividade.update!(video_url: "https://youtu.be/abcdefghijk", video_start: "0:00", video_end: "6:00")
      3.times { create(:question, :multiple_choice, activity: atividade) }

      # 3 exercícios (2,25) + teto do vídeo (5) = 7,25 → 8
      expect(fresca.estimated_minutes).to eq(8)
    end

    it "nunca promete menos de 2 minutos" do
      create(:question, :multiple_choice, activity: atividade)

      expect(fresca.estimated_minutes).to eq(Activity::MIN_MINUTES)
    end
  end

  describe ".with_size" do
    it "traz os mesmos números que a contagem uma a uma, para a lista inteira" do
      atividade.update!(pill: true, statement: palavras(60))
      create(:question, :multiple_choice, activity: atividade)
      create(:question, :open_ended, activity: atividade)
      SentenceOrdering.create!(activity: atividade, sentence: "Eu gosto de café")
      ColumnMatching.create!(activity: atividade)
      outra = create(:activity, :A2, draft: false, statement: nil)
      create(:question, :open_ended, activity: outra)

      lista = Activity.where(id: [atividade.id, outra.id]).with_size.index_by(&:id)

      [atividade, outra].each do |a|
        sozinha = Activity.find(a.id)
        expect(lista[a.id].exercise_count).to eq(sozinha.exercise_count)
        expect(lista[a.id].estimated_minutes).to eq(sozinha.estimated_minutes)
        expect(lista[a.id].writing_challenge?).to eq(sozinha.writing_challenge?)
      end
      expect(lista[atividade.id].exercise_count).to eq(3)
    end

    it "não faz consulta por cartão (com os anexos que o painel já carrega)" do
      3.times do
        a = create(:activity, :A2, draft: false)
        create(:question, :multiple_choice, activity: a)
      end
      lista = Activity.where(level: "A2").with_size
                      .with_attached_video_file.with_attached_audio_file.to_a

      consultas = 0
      contador = ->(*, payload) { consultas += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(contador, "sql.active_record") do
        lista.each { |a| [a.exercise_count, a.estimated_minutes, a.writing_challenge?] }
      end

      expect(consultas).to eq(0)
    end
  end

  describe "#pill_excess" do
    it "lista o que passa do tamanho de pílula, com os limites do prompt" do
      atividade.update!(level: "A1", statement: palavras(80), video_url: "https://youtu.be/abcdefghijk")
      6.times { create(:question, :multiple_choice, activity: atividade) }
      2.times { create(:question, :open_ended, activity: atividade) }

      expect(fresca.pill_excess).to eq([
        "6 exercícios fechados (pílula: até 5)", "2 questões abertas (pílula: 1, opcional)",
        "80 palavras de texto (A1: até 60)", "vídeo inteiro (pílula: um trecho)"
      ])
    end

    it "vazio quando a atividade já cabe numa pílula" do
      atividade.update!(statement: palavras(90), video_url: "https://youtu.be/abcdefghijk", video_start: "0:10", video_end: "1:00")
      5.times { create(:question, :multiple_choice, activity: atividade) }
      create(:question, :open_ended, activity: atividade)

      expect(fresca.pill_excess).to eq([])
    end
  end

  it "#writing_challenge? concorda com #writing_challenge" do
    atividade.update!(pill: true)
    create(:question, :open_ended, activity: atividade)

    expect(fresca.writing_challenge?).to eq(fresca.writing_challenge.present?)
  end
end
