class ParagraphOrdering < ApplicationRecord
  include Derangeable

  belongs_to :activity
  has_many :paragraph_sentences, dependent: :destroy

  validates :activity, presence: true

  def shuffled_sentences
    paragraph_sentences.order(:display_position)
  end

  def check_order(sentence_ids_in_order)
    results = sentence_results(sentence_ids_in_order)
    results.present? && results.all? { |r| r["ok"] }
  end

  # Detalhe por posição (dado vs. correto), pra dar crédito parcial em vez
  # de zerar o exercício inteiro por causa de uma frase fora do lugar.
  # Sempre retorna um item por frase do parágrafo, mesmo se a resposta do
  # aluno vier curta ou incompleta.
  def sentence_results(sentence_ids_in_order)
    sentences = paragraph_sentences.to_a
    return [] if sentences.empty?

    correct_order = sentences.sort_by(&:correct_position)

    correct_order.each_with_index.map do |correct_sentence, index|
      given_id       = sentence_ids_in_order[index]
      given_sentence = given_id && sentences.find { |s| s.id == given_id.to_i }
      {
        "given"   => given_sentence&.sentence,
        "correct" => correct_sentence.sentence,
        "ok"      => given_sentence&.id == correct_sentence.id
      }
    end
  end

  def add_sentence(text)
    next_position = paragraph_sentences.maximum(:correct_position).to_i + 1
    paragraph_sentences.create!(
      sentence: text,
      correct_position: next_position,
      display_position: next_position
    )
    shuffle_display_positions!
  end

  private

  # Desarranjo, não `shuffle` puro: nenhuma frase pode cair na sua própria
  # posição, senão o parágrafo aparece já ordenado. Ver `Derangeable`.
  def shuffle_display_positions!
    sentences = paragraph_sentences.to_a
    shuffled = deranged_positions(sentences.length)
    sentences.each_with_index do |s, i|
      s.update_column(:display_position, shuffled[i])
    end
  end
end
