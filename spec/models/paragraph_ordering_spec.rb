require 'rails_helper'

RSpec.describe ParagraphOrdering, type: :model do
  let(:activity) { create(:activity) }
  let(:ordering) { activity.paragraph_orderings.create! }

  before do
    ordering.add_sentence("Primeiro parágrafo.")
    ordering.add_sentence("Segundo parágrafo.")
    ordering.add_sentence("Terceiro parágrafo.")
  end

  let(:sentences) { ordering.paragraph_sentences.order(:correct_position).to_a }

  # Mesmo bug de SentenceOrdering: `shuffle` puro sorteia a permutação
  # identidade em 1/n! das vezes e o parágrafo abre já ordenado.
  describe 'embaralhamento das posições' do
    it 'nunca deixa uma frase na sua posição correta' do
      30.times do
        subject = activity.paragraph_orderings.create!
        subject.add_sentence("Primeiro.")
        subject.add_sentence("Segundo.")
        subject.add_sentence("Terceiro.")

        pares = subject.paragraph_sentences.map { |s| [s.correct_position, s.display_position] }
        expect(pares.none? { |correta, exibida| correta == exibida }).to be(true),
               "frase exibida na posição correta: #{pares.inspect}"
      end
    end

    it 'não trava com uma frase só, onde desarranjo não existe' do
      subject = activity.paragraph_orderings.create!

      expect { Timeout.timeout(5) { subject.add_sentence("Sozinha.") } }.not_to raise_error
      expect(subject.paragraph_sentences.first.display_position).to eq(1)
    end
  end

  describe '#sentence_results' do
    it 'marca todas as posições como corretas quando o aluno acerta tudo' do
      answer = sentences.map(&:id)

      results = ordering.sentence_results(answer)

      expect(results.size).to eq(3)
      expect(results).to all(include("ok" => true))
    end

    it 'marca só as posições erradas quando o aluno acerta parte' do
      answer = [sentences[1].id, sentences[0].id, sentences[2].id] # trocou as 2 primeiras

      results = ordering.sentence_results(answer)

      expect(results.count { |r| r["ok"] }).to eq(1)
      expect(results[0]["ok"]).to be false
      expect(results[0]["correct"]).to eq(sentences[0].sentence)
    end

    it 'retorna um item por frase mesmo quando a resposta vem incompleta' do
      results = ordering.sentence_results([sentences[0].id])

      expect(results.size).to eq(3)
      expect(results.first["ok"]).to be true
      expect(results[1]["given"]).to be_nil
    end
  end

  describe '#check_order' do
    it 'retorna true quando toda a ordem está correta' do
      expect(ordering.check_order(sentences.map(&:id))).to be true
    end

    it 'retorna false quando há pelo menos uma posição errada' do
      answer = [sentences[1].id, sentences[0].id, sentences[2].id]
      expect(ordering.check_order(answer)).to be false
    end
  end
end
