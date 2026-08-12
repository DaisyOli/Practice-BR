# Uma versão anterior de um prompt, guardada no momento em que foi substituída.
#
# Sem `updated_at` de propósito: uma versão arquivada é imutável por definição.
# Se ela pudesse mudar, não seria histórico.
class AiPromptVersion < ApplicationRecord
  belongs_to :ai_prompt

  validates :body, presence: true
end
