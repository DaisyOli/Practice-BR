require 'rails_helper'

RSpec.describe ColumnMatching, type: :model do
  let(:activity) { create(:activity) }
  let(:matching) { activity.column_matchings.create!(title: "Capitais") }

  let!(:pair1) { matching.add_pair("Brasil", "Brasília") }
  let!(:pair2) { matching.add_pair("França", "Paris") }
  let!(:pair3) { matching.add_pair("Japão", "Tóquio") }
  let!(:pair4) { matching.add_pair("Egito", "Cairo") }

  # A coluna da direita não pode sair alinhada com a da esquerda: seria a
  # resposta de graça. Com 4 pares, `shuffle` sozinho fazia isso em 1/24 das
  # aberturas; com 3, em 1/6.
  describe '#shuffled_pairs' do
    let(:ordem_da_esquerda) { matching.matching_pairs.order(:position).map(&:id) }

    it 'nunca alinha um par com a linha que ele ocupa na esquerda' do
      50.times do
        embaralhada = matching.shuffled_pairs.map(&:id)

        expect(embaralhada.each_with_index.none? { |id, i| id == ordem_da_esquerda[i] }).to be(true),
               "par alinhado: #{embaralhada.inspect} vs #{ordem_da_esquerda.inspect}"
      end
    end

    it 'devolve todos os pares, sem perder nem duplicar nenhum' do
      expect(matching.shuffled_pairs.map(&:id).sort).to eq(ordem_da_esquerda.sort)
    end

    it 'não trava com um par só, onde desarranjo não existe' do
      solo = activity.column_matchings.create!(title: "Um par")
      par  = solo.add_pair("Brasil", "Brasília")

      expect {
        Timeout.timeout(5) { expect(solo.shuffled_pairs.map(&:id)).to eq([par.id]) }
      }.not_to raise_error
    end

    it 'devolve lista vazia quando não há pares' do
      vazio = activity.column_matchings.create!(title: "Vazio")
      expect(vazio.shuffled_pairs).to eq([])
    end
  end

  describe '#pair_results' do
    it 'marca todos os pares como corretos quando o aluno acerta tudo' do
      answer = [pair1, pair2, pair3, pair4].map { |p| "#{p.id}:#{p.id}" }.join(',')

      results = matching.pair_results(answer)

      expect(results.size).to eq(4)
      expect(results).to all(include("correct" => true))
    end

    it 'marca só os pares errados como incorretos quando o aluno acerta parte' do
      answer = [
        "#{pair1.id}:#{pair1.id}",
        "#{pair2.id}:#{pair2.id}",
        "#{pair3.id}:#{pair3.id}",
        "#{pair4.id}:#{pair1.id}" # trocou o par 4
      ].join(',')

      results = matching.pair_results(answer)

      expect(results.count { |r| r["correct"] }).to eq(3)
      wrong = results.find { |r| r["left"] == "Egito" }
      expect(wrong["correct"]).to be false
    end

    it 'marca todos os pares como incorretos quando a resposta está em branco' do
      results = matching.pair_results("")

      expect(results.size).to eq(4)
      expect(results).to all(include("correct" => false))
    end

    it 'retorna lista vazia quando não há pares cadastrados' do
      empty_matching = activity.column_matchings.create!(title: "Vazio")

      expect(empty_matching.pair_results("1:1")).to eq([])
    end
  end
end
