require "anthropic"
require "json"

# Agente que decide o TEMA da sugestão do dia consultando o catálogo de
# atividades, as avaliações dos alunos e o desempenho em quizzes antes de
# propor algo — em vez de inventar um tema no vácuo (como o antigo serviço de
# sugestões de vídeo fazia). A geração da atividade em si continua sendo
# trabalho do ActivityGenerationService, via AiActivityGenerationJob
# (kind: "prompt") — este serviço só produz {theme, level, rationale}.
class DailySuggestionAgentService
  MIN_RATINGS    = 3 # mesmo limiar de Admin::ActivitiesController
  MIN_ATTEMPTS   = 3
  MAX_ITERATIONS = 6
  LEVELS = %w[A1 A2 B1 B2 C1].freeze

  TOOLS = [
    {
      name: "recent_themes",
      description: "Lista os títulos das atividades mais recentes de um nível CEFR para este professor, para evitar repetir tema/estilo já coberto. Chame isso primeiro.",
      input_schema: {
        type: "object",
        properties: { level: { type: "string", enum: LEVELS } },
        required: ["level"]
      }
    },
    {
      name: "rating_insights",
      description: "Retorna quais atividades de um nível os alunos avaliaram melhor e pior (estrelas). Pode dizer que os dados são insuficientes.",
      input_schema: {
        type: "object",
        properties: { level: { type: "string", enum: LEVELS } },
        required: ["level"]
      }
    },
    {
      name: "low_performing_topics",
      description: "Retorna atividades de um nível onde os alunos tiveram desempenho mais baixo nos quizzes (nota média), indicando possíveis pontos de dificuldade. Pode dizer que os dados são insuficientes.",
      input_schema: {
        type: "object",
        properties: { level: { type: "string", enum: LEVELS } },
        required: ["level"]
      }
    },
    {
      name: "propose_suggestion",
      description: "Registra sua sugestão final de tema de atividade. Chame isso UMA VEZ, ao final, depois de consultar as ferramentas de pesquisa relevantes.",
      input_schema: {
        type: "object",
        properties: {
          theme:     { type: "string", description: "Tema/tópico proposto, em português, curto (ex: 'Pedir comida por app de delivery')" },
          level:     { type: "string", enum: LEVELS },
          rationale: { type: "string", description: "1-3 frases explicando POR QUE este tema, citando o que as ferramentas retornaram (catálogo, avaliações, desempenho)." }
        },
        required: %w[theme level rationale]
      }
    }
  ].freeze

  SYSTEM_PROMPT = <<~PROMPT
    Você é um agente de curadoria pedagógica da Practice-BR, plataforma de português brasileiro para adultos.
    Sua tarefa diária: escolher UM tema de atividade para a professora revisar e, se aprovar, gerar com IA.

    Você tem ferramentas que consultam o catálogo existente, avaliações de alunos e desempenho em quizzes.
    Use as ferramentas relevantes antes de decidir — não invente dados. Se uma ferramenta disser que os dados são
    insuficientes, tudo bem: baseie-se no que houver (o catálogo está sempre disponível) e não force uma conclusão
    sobre avaliações/desempenho quando não houver dados.

    Escolha um nível CEFR (A1/A2/B1/B2/C1) e um tema que:
    - não repita tema/estilo já coberto recentemente naquele nível (recent_themes)
    - favoreça padrões que os alunos avaliaram bem, evite os que avaliaram mal (rating_insights), quando houver dados
    - considere onde os alunos têm errado mais, quando houver dados (low_performing_topics)

    Ao final, chame propose_suggestion com theme, level e rationale. A justificativa deve citar o que as
    ferramentas retornaram, não platitudes genéricas.
  PROMPT

  def initialize(teacher:)
    @teacher = teacher
    @client = Anthropic::Client.new
  end

  def call
    return { skipped: true, reason: "already_has_suggestion" } if ActivitySuggestion.for_teacher(@teacher).today.pending.any?

    proposal = run_agent_loop
    return { success: false, error: "Agente não retornou uma sugestão" } unless proposal

    suggestion = ActivitySuggestion.create!(
      teacher:    @teacher,
      theme:      proposal[:theme],
      level_hint: proposal[:level],
      rationale:  proposal[:rationale],
      status:     "pending"
    )
    { success: true, suggestion: suggestion }
  rescue => e
    Rails.logger.error "[DailySuggestionAgent] #{e.class}: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def run_agent_loop
    messages = [{ role: "user", content: "Escolha o tema de atividade de hoje. Consulte as ferramentas de pesquisa antes de propor." }]

    MAX_ITERATIONS.times do
      response = @client.messages.create(
        model: "claude-opus-4-8",
        max_tokens: 1500,
        system: SYSTEM_PROMPT,
        tools: TOOLS,
        messages: messages
      )

      return nil if response.stop_reason == :refusal

      tool_uses = response.content.select { |b| b.type == :tool_use }

      final = tool_uses.find { |t| t.name == "propose_suggestion" }
      return final.input if final

      return nil if tool_uses.empty? # terminou sem propor — não arriscar um palpite

      messages << { role: "assistant", content: response.content.map { |b| serialize_block(b) } }
      messages << { role: "user", content: tool_uses.map { |t| execute_tool(t) } }
    end

    nil
  end

  def serialize_block(block)
    case block.type
    when :text     then { type: "text", text: block.text }
    when :tool_use then { type: "tool_use", id: block.id, name: block.name, input: block.input }
    end
  end

  def execute_tool(tool_use)
    level = tool_use.input[:level]
    result = case tool_use.name
             when "recent_themes"        then recent_themes(level)
             when "rating_insights"       then rating_insights(level)
             when "low_performing_topics" then low_performing_topics(level)
             else "Ferramenta desconhecida"
             end
    { type: "tool_result", tool_use_id: tool_use.id, content: result }
  end

  def recent_themes(level)
    titles = Activity.where(teacher: @teacher, ai_generated: true, level: level)
                      .order(created_at: :desc).limit(20).pluck(:title)
    return "Nenhuma atividade recente neste nível ainda." if titles.empty?

    titles.join("; ")
  end

  def rating_insights(level)
    scope = Activity.where(level: level)
                     .joins(:activity_ratings)
                     .group("activities.id")
                     .having("COUNT(activity_ratings.id) >= ?", MIN_RATINGS)
                     .select("activities.*, AVG(activity_ratings.stars) AS stars_avg, COUNT(activity_ratings.id) AS stars_count")
    return "Dados insuficientes de avaliação para o nível #{level} ainda." if scope.none?

    best  = scope.order("stars_avg DESC").limit(3).map { |a| "#{a.title} (#{a.stars_avg.round(1)}★)" }
    worst = scope.order("stars_avg ASC").limit(3).map  { |a| "#{a.title} (#{a.stars_avg.round(1)}★)" }
    "Melhor avaliadas: #{best.join(', ')}. Pior avaliadas: #{worst.join(', ')}."
  end

  def low_performing_topics(level)
    scope = Activity.where(level: level, draft: false)
                     .joins(:quiz_attempts)
                     .where.not(quiz_attempts: { submitted_at: nil })
                     .group("activities.id")
                     .having("COUNT(quiz_attempts.id) >= ?", MIN_ATTEMPTS)
                     .select("activities.*, AVG(quiz_attempts.score) AS avg_score, COUNT(quiz_attempts.id) AS attempts_count")
    return "Dados insuficientes de desempenho em quizzes para o nível #{level} ainda." if scope.none?

    scope.order("avg_score ASC").limit(3)
         .map { |a| "#{a.title} (nota média #{a.avg_score.round(1)}, #{a.attempts_count} tentativas)" }
         .join("; ")
  end
end
