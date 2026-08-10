# Embaralhamento que garante que nada fique no lugar de origem.
#
# `Array#shuffle` sorteia uniformemente entre TODAS as permutações possíveis —
# inclusive a que não mexe em nada. Nos exercícios de ordenar, essa permutação
# entrega a resposta pronta: numa lista de 3 itens ela saía em 1 de cada 6
# aberturas (16,6% medido), com 4 itens em 4,2%.
#
# O que se quer aqui é um "desarranjo" (derangement): permutação sem nenhum
# ponto fixo. A estratégia é sortear e rejeitar enquanto sobrar item parado,
# que custa em média e ≈ 2,7 tentativas seja qual for o tamanho da lista.
#
# Usado por SentenceOrdering, ParagraphOrdering e ColumnMatching.
module Derangeable
  extend ActiveSupport::Concern

  private

  # Devolve [1..count] embaralhado, sem nenhum número na sua própria casa.
  #
  # Listas de 0 ou 1 item voltam intactas: desarranjo de 1 elemento não existe,
  # e sem essa guarda a rejeição rodaria para sempre. Não é caso hipotético —
  # `SentenceOrdering` valida 3 CARACTERES, não 3 palavras, então "Bonjour" é
  # uma frase válida de uma palavra só.
  def deranged_positions(count)
    return (1..count).to_a if count < 2

    base = (1..count).to_a
    loop do
      candidate = base.shuffle
      return candidate if candidate.each_with_index.none? { |position, i| position == i + 1 }
    end
  end

  # Mesma ideia, para quando o que se embaralha é a própria lista de objetos em
  # vez de números de posição. Compara por `id` porque os itens vêm do banco.
  def deranged_list(items)
    return items if items.size < 2

    loop do
      candidate = items.shuffle
      return candidate if candidate.each_with_index.none? { |item, i| item.id == items[i].id }
    end
  end
end
