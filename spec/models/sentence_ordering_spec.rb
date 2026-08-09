require 'rails_helper'

RSpec.describe SentenceOrdering, type: :model do
  let(:activity) { create(:activity) }
  let(:ordering) { activity.sentence_orderings.create!(sentence: "Eu gosto de café") }
  let(:words) { ordering.sentence_words.order(:correct_position).to_a }

  describe '#word_results' do
    it 'marca todas as posições como corretas quando o aluno acerta tudo' do
      answer = words.map(&:id)

      results = ordering.word_results(answer)

      expect(results.size).to eq(4)
      expect(results).to all(include("ok" => true))
    end

    it 'marca só as posições erradas quando o aluno acerta parte' do
      answer = [words[0].id, words[1].id, words[3].id, words[2].id] # trocou as 2 últimas

      results = ordering.word_results(answer)

      expect(results.count { |r| r["ok"] }).to eq(2)
      expect(results[2]["ok"]).to be false
      expect(results[2]["correct"]).to eq(words[2].word)
    end

    it 'retorna um item por palavra mesmo quando a resposta vem incompleta' do
      results = ordering.word_results([words[0].id])

      expect(results.size).to eq(4)
      expect(results.first["ok"]).to be true
      expect(results[1]["ok"]).to be false
      expect(results[1]["given"]).to be_nil
    end
  end

  # O embaralhamento não pode devolver a frase já montada: `shuffle` sozinho
  # sorteia a permutação identidade em 1/n! das vezes (16,6% numa frase de 3
  # palavras), e o aluno abria o exercício com a resposta à vista.
  describe 'embaralhamento das posições' do
    it 'nunca deixa uma palavra na sua posição correta' do
      50.times do
        subject = activity.sentence_orderings.create!(sentence: "Eu gosto de café")
        pares = subject.sentence_words.map { |w| [w.correct_position, w.display_position] }

        expect(pares.none? { |correta, exibida| correta == exibida }).to be(true),
               "palavra exibida na posição correta: #{pares.inspect}"
      end
    end

    it 'nunca devolve a frase já ordenada nem na frase mais curta possível' do
      50.times do
        subject = activity.sentence_orderings.create!(sentence: "Eu gosto muito")
        exibida = subject.shuffled_words.map(&:word)

        expect(exibida).not_to eq(%w[Eu gosto muito])
      end
    end

    it 'não trava numa frase de uma palavra só, onde desarranjo não existe' do
      # `sentence` valida 3 CARACTERES, não 3 palavras: "Bonjour" é válida.
      # Sem a guarda, a amostragem por rejeição roda para sempre.
      subject = nil
      expect {
        Timeout.timeout(5) { subject = activity.sentence_orderings.create!(sentence: "Bonjour") }
      }.not_to raise_error

      expect(subject.sentence_words.count).to eq(1)
      expect(subject.sentence_words.first.display_position).to eq(1)
    end

    it 'refaz o desarranjo quando a frase é editada' do
      subject = activity.sentence_orderings.create!(sentence: "Eu gosto de café")
      subject.update!(sentence: "Ela bebe água gelada")

      pares = subject.reload.sentence_words.map { |w| [w.correct_position, w.display_position] }
      expect(subject.sentence_words.count).to eq(4)
      expect(pares.none? { |correta, exibida| correta == exibida }).to be true
    end
  end

  describe '#check_order' do
    it 'retorna true quando toda a ordem está correta' do
      expect(ordering.check_order(words.map(&:id))).to be true
    end

    it 'retorna false quando há pelo menos uma posição errada' do
      answer = [words[0].id, words[1].id, words[3].id, words[2].id]
      expect(ordering.check_order(answer)).to be false
    end
  end
end
