# O texto que define como cada IA do app se comporta, editável pela tela.
#
# ---- O chão -------------------------------------------------------------------
#
# Cada prompt tem um padrão que vive no código, como constante. A tabela guarda
# só o que a Daisy REESCREVEU. `body_for` devolve o texto do banco quando existe
# e cai na constante quando não existe.
#
# Isso significa que apagar a linha desfaz qualquer estrago, sempre. Não existe
# estado em que o app fique sem prompt: o pior caso é voltar ao texto de ontem.
#
# ---- Por que {{isto}} e não #{isto} -------------------------------------------
#
# Dois prompts têm buracos a preencher. Em código-fonte isso seria interpolação
# de Ruby (`#{}`), mas um texto que vem do banco é string comum — a interpolação
# já aconteceu (ou não) quando o arquivo .rb foi lido.
#
# A saída de manual seria `format(body, expectations: ...)` com `%{expectations}`.
# E ela QUEBRA neste app, por causa de uma frase que está no prompt de correção:
#
#     "(um 70 vale 70% da questão, não é 'aprovado')"
#
# Aquele `%` solto faz o `format` levantar ArgumentError. Escapar todo `%` do
# texto significaria a Daisy ter que escrever `%%` na tela para dizer "por
# cento" — uma regra de sintaxe imposta a quem só quer escrever português.
#
# Daí o `gsub` com marcador improvável: nada a escapar, nada a explicar.
class AiPrompt < ApplicationRecord
  has_many :versions, -> { order(created_at: :desc) },
           class_name: "AiPromptVersion", dependent: :destroy

  validates :key,  presence: true, uniqueness: true, inclusion: { in: -> (_) { AiPrompt.keys } }
  validates :body, presence: true
  validate  :must_keep_placeholders
  validate  :must_keep_contract_markers

  # Arquiva o texto ANTERIOR antes de sobrescrever. A versão nova não vira
  # histórico — ela é o presente; o histórico é o que ela substituiu.
  before_update :archive_previous_body, if: :body_changed?

  # ---- O registro ---------------------------------------------------------------
  #
  # Um método e não uma constante de propósito: `Activity.levels` só existe
  # depois que o autoload carrega o model, e uma constante avaliada no corpo da
  # classe rodaria cedo demais. Nove entradas são baratas de montar.
  def self.registry
    entries = {
      "activity_generation.system" => {
        group:   "Agente de conteúdo",
        label:   "Instruções principais",
        hint:    "Define tudo que a IA sabe sobre criar uma atividade: o que é uma boa cena, as regras absolutas e o formato do JSON que o app espera receber.",
        default: -> { ActivityGenerationService::SYSTEM_PROMPT },
        # O app lê estas chaves do JSON que a IA devolve. Sem elas na descrição
        # do formato, a geração volta um texto que o parser não sabe montar.
        markers: %w[title description level exercises type]
      },

      "activity_generation.region_addendum" => {
        group:   "Agente de conteúdo",
        label:   "Sorteio de ambientação",
        hint:    "Vai junto do seu pedido, não nas instruções principais. É o que espalha as atividades pelo Brasil em vez de deixar tudo em São Paulo.",
        default: -> { ActivityGenerationService::REGION_ADDENDUM },
        placeholders: %w[pedido regiao ancoras]
      },

      "ai_grading.system" => {
        group:   "Correção de respostas",
        label:   "Moldura da correção",
        hint:    "O texto que envolve a régua do nível. Termina definindo o JSON com a nota e o feedback — se esse formato sumir, o aluno vê erro no lugar da nota.",
        default: -> { AiGradingService::SYSTEM_FRAME },
        placeholders: %w[expectations],
        markers:      %w[score feedback]
      },

      "daily_suggestion.system" => {
        group:   "Sugestão do dia",
        label:   "Instruções do agente",
        hint:    "Como o agente escolhe o tema do dia. Ele precisa terminar chamando a ferramenta propose_suggestion — sem isso, nenhuma sugestão aparece.",
        default: -> { DailySuggestionAgentService::SYSTEM_PROMPT },
        markers: %w[propose_suggestion]
      }
    }

    # A régua de cada nível é um texto separado — é onde se mexe com mais
    # frequência, e misturar os cinco num campo só faria você reler tudo para
    # ajustar o A1. A lista sai do enum do Activity, a fonte de verdade: um
    # nível novo aparece aqui sozinho.
    Activity.levels.keys.each do |level|
      entries["ai_grading.expectations.#{level}"] = {
        group:   "Correção de respostas",
        label:   "Régua do #{level}",
        hint:    "Quanto vale uma resposta boa neste nível. Lembre que a nota vira crédito direto: 85 significa que o aluno perde 15% da questão.",
        default: -> { AiGradingService::LEVEL_EXPECTATIONS[level].to_s }
      }
    end

    entries
  end

  def self.keys = registry.keys

  def self.entry(key) = registry.fetch(key)

  # O texto de fábrica, direto do código.
  def self.default_for(key)
    entry(key)[:default].call.to_s
  end

  # O texto em vigor: o reescrito, se houver; senão o de fábrica.
  def self.body_for(key)
    find_by(key: key)&.body.presence || default_for(key)
  end

  # Preenche os buracos. `vars` são símbolos: render("x", pedido: "...").
  def self.render(key, **vars)
    vars.reduce(body_for(key)) do |text, (name, value)|
      text.gsub("{{#{name}}}", value.to_s)
    end
  end

  def default_body = self.class.default_for(key)

  def customized? = body.present? && body != default_body

  def entry = self.class.entry(key)

  def placeholders = Array(entry[:placeholders])

  def markers = Array(entry[:markers])

  private

  def archive_previous_body
    versions.create!(body: body_was, created_at: Time.current)
  end

  # Um buraco apagado não dá erro nenhum: o prompt simplesmente vai para a IA
  # sem a régua do nível dentro, e as notas mudam sem ninguém entender por quê.
  def must_keep_placeholders
    faltando = placeholders.reject { |name| body.to_s.include?("{{#{name}}}") }
    return if faltando.empty?

    errors.add(:body, "precisa continuar com #{faltando.map { |f| "{{#{f}}}" }.to_sentence} no texto — é onde o app encaixa o conteúdo variável.")
  end

  # O contrato de máquina. Estas palavras não são estilo: são o acordo com o
  # código que lê a resposta da IA.
  def must_keep_contract_markers
    faltando = markers.reject { |m| body.to_s.include?(m) }
    return if faltando.empty?

    errors.add(:body, "precisa continuar mencionando #{faltando.to_sentence} — o app depende dessas palavras para entender a resposta da IA.")
  end
end
