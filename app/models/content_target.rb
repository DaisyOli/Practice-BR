# Quantas atividades geradas por IA cada nível deve ter.
#
# Isto vivia como constante congelada no Admin::DraftsController:
#
#   TARGET = { "A1" => 30, "A2" => 30, "B1" => 30, "B2" => 20 }.freeze
#
# e fazia dois trabalhos ao mesmo tempo: definir a meta E definir quais níveis
# o agente conhecia. O C1 existe no enum do Activity, na avaliação de
# nivelamento e no formulário da landing, mas estava fora da constante — logo
# era impossível gerar conteúdo C1 por qualquer caminho, e nada avisava.
#
# Agora a meta é dado editável pela tela, e a lista de níveis vem do enum do
# Activity, que é a fonte de verdade.
class ContentTarget < ApplicationRecord
  validates :level,
            presence:   true,
            uniqueness: true,
            inclusion:  { in: ->(_) { Activity.levels.keys } }

  # Meta em branco é intencional e diferente de zero: significa "não sei quanto
  # este nível deveria ter", e o modo automático simplesmente o ignora.
  validates :goal,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil:    true

  # Todos os níveis do enum, na ordem do CEFR, com nil onde não há meta:
  #   { "A1" => 30, "A2" => 30, "B1" => 30, "B2" => 20, "C1" => nil }
  #
  # Sai daqui na ordem do enum e não da tabela, para que um nível novo apareça
  # na tela mesmo antes de alguém definir a meta dele.
  def self.goals
    saved = where(level: Activity.levels.keys).index_by(&:level)
    Activity.levels.keys.index_with { |level| saved[level]&.goal }
  end
end
