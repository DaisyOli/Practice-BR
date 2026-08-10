class SentenceOrdering < ApplicationRecord
  include Derangeable

  belongs_to :activity
  has_many :sentence_words, dependent: :destroy

  validates :sentence, presence: true, length: { minimum: 3 }

  after_create :process_words!
  before_update :reprocess_words!, if: :sentence_changed?

  def shuffled_words
    sentence_words.order(:display_position)
  end

  def check_order(word_ids_in_order)
    results = word_results(word_ids_in_order)
    results.present? && results.all? { |r| r["ok"] }
  end

  # Detalhe por posição (dado vs. correto), pra dar crédito parcial em vez
  # de zerar o exercício inteiro por causa de uma palavra fora do lugar.
  # Sempre retorna um item por palavra da frase, mesmo se a resposta do
  # aluno vier curta ou incompleta.
  def word_results(word_ids_in_order)
    words = sentence_words.to_a
    return [] if words.empty?

    correct_order = words.sort_by(&:correct_position)

    correct_order.each_with_index.map do |correct_word, index|
      given_id   = word_ids_in_order[index]
      given_word = given_id && words.find { |w| w.id == given_id.to_i }
      {
        "given"   => given_word&.word,
        "correct" => correct_word.word,
        "ok"      => given_word&.id == correct_word.id
      }
    end
  end

  private

  def process_words!
    words = sentence.split(/\s+/)
    positions = deranged_positions(words.length)

    words.each_with_index do |word_text, i|
      sentence_words.create!(
        word: word_text,
        correct_position: i + 1,
        display_position: positions[i]
      )
    end
  end

  def reprocess_words!
    sentence_words.destroy_all
    process_words!
  end
end
