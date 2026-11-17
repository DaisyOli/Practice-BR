# Uma geração de atividade por IA rodando em background (AiActivityGenerationJob).
# A página de espera consulta o status até virar done (-> revisar rascunho)
# ou failed (-> mostrar o erro e oferecer tentar de novo).
class AiGeneration < ApplicationRecord
  STATUSES = %w[queued running done failed].freeze
  # agent = gerado pelo agente de conteúdo do admin
  # adapt = "Adaptar em pílulas": uma atividade longa vira uma série (ponto 1.4)
  KINDS    = %w[prompt video agent adapt].freeze

  belongs_to :teacher, class_name: "User"
  belongs_to :activity, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :kind,   inclusion: { in: KINDS }

  def done?   = status == "done"
  def failed? = status == "failed"
end
