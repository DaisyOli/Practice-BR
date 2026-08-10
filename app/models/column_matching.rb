class ColumnMatching < ApplicationRecord
  include Derangeable

  belongs_to :activity
  has_many :matching_pairs, dependent: :destroy

  validates :activity, presence: true

  # A coluna da esquerda sai por `.order(:position)` e esta aqui alimenta a da
  # direita. Se o sorteio devolvesse a ordem original, as duas colunas saíam
  # alinhadas linha a linha e o exercício se respondia sozinho — com 3 pares
  # isso acontecia em 1 de cada 6 aberturas. Ver `Derangeable`.
  def shuffled_pairs
    deranged_list(matching_pairs.order(:position).to_a)
  end

  def pair_results(answer_string)
    pairs = matching_pairs.order(:position).to_a
    return [] if pairs.empty?

    given = answer_string.to_s.split(',').each_with_object({}) do |entry, hash|
      left_id, right_id = entry.split(':')
      hash[left_id] = right_id
    end

    pairs.map do |pair|
      {
        "left"    => pair.left_item,
        "right"   => pair.right_item,
        "correct" => given[pair.id.to_s] == pair.id.to_s
      }
    end
  end

  def add_pair(left_item, right_item)
    next_position = matching_pairs.maximum(:position).to_i + 1
    matching_pairs.create!(left_item: left_item, right_item: right_item, position: next_position)
  end
end
