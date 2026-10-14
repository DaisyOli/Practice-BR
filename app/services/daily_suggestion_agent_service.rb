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
  MAX_ITERATIONS = 8
  # Erros só dos últimos meses: o que os alunos erravam há um ano pode já ter
  # virado atividade.
  ERRORS_WINDOW  = 180.days
  ERRORS_SHOWN   = 12
  LEVELS = %w[A1 A2 B1 B2 C1].freeze

  # Feature em fase de teste (Daisy não precisa de sugestão nova todo dia
  # ainda) — o Scheduler do Heroku roda este job diariamente, mas o serviço
  # se recusa a gerar mais de uma por semana, e nunca gera uma segunda
  # enquanto houver uma pendente sem revisão.
  MIN_INTERVAL = 7.days

  TOOLS = [
    {
      name: "level_syllabus",
      description: "Retorna o programa do nível escrito pela professora: os temas comunicativos e os pontos gramaticais que um aluno daquele nível do CECRL precisa encontrar na plataforma. É a régua para achar lacunas.",
      input_schema: {
        type: "object",
        properties: { level: { type: "string", enum: LEVELS } },
        required: ["level"]
      }
    },
    {
      name: "level_catalog",
      description: "Lista TODAS as atividades publicadas de um nível (de todas as professoras), com tema e descrição curta. Compare com o programa do nível para ver o que já está coberto e o que falta.",
      input_schema: {
        type: "object",
        properties: { level: { type: "string", enum: LEVELS } },
        required: ["level"]
      }
    },
    {
      name: "frequent_errors",
      description: "Retorna as questões de um nível que os alunos mais erraram nos últimos meses, com a resposta certa e as respostas erradas que deram. Serve para identificar o ponto de dificuldade real (ex.: confundem ser e estar). Pode dizer que os dados são insuficientes.",
      input_schema: {
        type: "object",
        properties: { level: { type: "string", enum: LEVELS } },
        required: ["level"]
      }
    },
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
    Sua tarefa: escolher UM tema de atividade para a professora revisar e, se aprovar, gerar com IA.

    Use as ferramentas antes de decidir — não invente dados. Se uma ferramenta disser que os dados são
    insuficientes, tudo bem: baseie-se no que houver e não force conclusão onde não há dado.

    COMO DECIDIR, nesta ordem:
    1. LACUNAS DO PROGRAMA. Para o nível que você avaliar, compare o programa (level_syllabus) com o que já
       existe (level_catalog). Um tema ou ponto gramatical do programa sem nenhuma atividade é a melhor
       sugestão possível. Prefira o nível com a lacuna mais básica — no A1, faltar "apresentar-se" pesa mais
       que faltar "clima".
    2. DIFICULDADES REAIS. Se não houver lacuna clara, ou se o tema for repetir algo que já existe, use
       frequent_errors para mirar no que os alunos de fato erram: identifique o ponto gramatical por trás das
       respostas erradas (ex.: escreveram "sou" onde era "estou" → ser × estar) e proponha uma atividade que
       trabalhe exatamente isso, num tema novo.
    3. GOSTO DOS ALUNOS. Quando houver dados, favoreça o estilo das atividades bem avaliadas e evite o das mal
       avaliadas (rating_insights).
    4. Não repita tema/estilo recente (recent_themes).

    Ao final, chame propose_suggestion com theme, level e rationale. A justificativa deve dizer QUAL dos
    critérios acima decidiu e citar o que as ferramentas retornaram — "o programa do A1 pede X e o catálogo
    não tem nenhuma atividade sobre isso", "4 de 6 alunos escreveram 'sou' em 'Eu ___ cansado'" —, nunca
    platitudes genéricas.
  PROMPT

  # O programa de cada nível: a régua contra a qual o agente mede as lacunas do
  # catálogo. É ponto de partida, escrito a partir do CECRL para o português
  # brasileiro; a Daisy ajusta em "A voz das IAs" (AiPrompt
  # "daily_suggestion.syllabus.<NÍVEL>") — é a visão DELA do nível que vale.
  SYLLABUS = {
    "A1" => <<~TXT,
      Comunicação: cumprimentar e se despedir; apresentar-se e apresentar alguém; nacionalidade, origem e
      profissão; números, idade, telefone e preços; família; dias da semana, horas e rotina simples; comida e
      pedidos em restaurante/padaria; compras básicas; a casa; localização simples (onde fica, perto, longe);
      gostos (gosto de / não gosto de); clima básico.
      Gramática: ser × estar (usos básicos); presente dos verbos regulares (-ar, -er, -ir) e de ter, ir, fazer,
      querer, poder; artigos e gênero/número; possessivos; preposições de, em, para e contrações (no, na, do,
      da); pronomes interrogativos (o que, qual, onde, de onde, quando, quanto); estar + gerúndio; ir + infinitivo
      (futuro próximo).
    TXT
    "A2" => <<~TXT,
      Comunicação: contar o que fez (fim de semana, viagem); falar da infância e de hábitos antigos; descrever
      pessoas e lugares; saúde e corpo (ir ao médico, farmácia); compras e roupas; transporte e direções; casa e
      tarefas domésticas; trabalho e estudos; convites, aceitar e recusar; mensagens curtas e emails informais.
      Gramática: pretérito perfeito (regulares e irregulares frequentes); pretérito imperfeito e contraste com o
      perfeito; comparativos e superlativos; pronomes oblíquos (me, te, o, a, lhe) na fala brasileira;
      advérbios de frequência e de tempo; imperativo em instruções e conselhos; preposições de lugar e
      movimento; futuro com ir + infinitivo.
    TXT
    "B1" => <<~TXT,
      Comunicação: dar opinião e justificar; concordar e discordar; contar histórias e experiências com detalhe;
      planos e projetos; trabalho (entrevista, reunião, email profissional simples); cultura brasileira
      (festas, música, regiões); meio ambiente e cidade; notícias simples; reclamar e resolver problemas;
      conselhos e sugestões.
      Gramática: presente do subjuntivo (desejo, dúvida, conselho: espero que, talvez, é importante que);
      futuro do pretérito (condicional) para polidez e hipóteses; pretérito mais-que-perfeito composto (tinha
      feito); conectores (porque, embora, então, por isso, apesar de); pronomes relativos (que, onde, quem);
      voz passiva simples; discurso indireto básico.
    TXT
    "B2" => <<~TXT,
      Comunicação: argumentar em debate; textos de opinião; temas sociais (desigualdade, educação, saúde
      pública, tecnologia); mundo do trabalho e empreendedorismo; mídia e notícias; humor, ironia e registro
      informal brasileiro (gírias comuns, expressões idiomáticas); literatura e crônica brasileira.
      Gramática: imperfeito e futuro do subjuntivo (se eu tivesse, quando você puder); orações condicionais
      reais e hipotéticas; infinitivo pessoal; concordância verbal e nominal em casos difíceis; regência verbal
      frequente; colocação pronominal no registro formal × informal; marcadores do discurso.
    TXT
    "C1" => <<~TXT
      Comunicação: debate e argumentação sofisticados; textos acadêmicos e profissionais; nuances de registro
      (formal, informal, regional) e intenção (ironia, eufemismo); literatura, música e cinema brasileiros;
      política, economia e sociedade; variação linguística no Brasil como objeto de observação.
      Gramática: tempos compostos do subjuntivo; mesóclise e ênclise (reconhecer o registro formal escrito);
      estruturas de ênfase e topicalização; nominalização; coesão e coerência em textos longos; expressões
      idiomáticas e provérbios; falsos cognatos com o francês e o espanhol.
    TXT
  }.freeze

  def initialize(teacher:)
    @teacher = teacher
    @client = Anthropic::Client.new
  end

  def call
    return { skipped: true, reason: "already_has_suggestion" } if ActivitySuggestion.for_teacher(@teacher).pending.any?

    last = ActivitySuggestion.for_teacher(@teacher).order(created_at: :desc).first
    return { skipped: true, reason: "too_recent" } if last && last.created_at > MIN_INTERVAL.ago

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
        system: AiPrompt.body_for("daily_suggestion.system"),
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
             when "level_syllabus"       then level_syllabus(level)
             when "level_catalog"        then level_catalog(level)
             when "frequent_errors"      then frequent_errors(level)
             when "recent_themes"        then recent_themes(level)
             when "rating_insights"       then rating_insights(level)
             when "low_performing_topics" then low_performing_topics(level)
             else "Ferramenta desconhecida"
             end
    { type: "tool_result", tool_use_id: tool_use.id, content: result }
  end

  def level_syllabus(level)
    AiPrompt.body_for("daily_suggestion.syllabus.#{level}")
  end

  def level_catalog(level)
    acts = Activity.published.where(level: level).order(:theme, :title).pluck(:title, :theme, :description)
    return "Nenhuma atividade publicada no #{level} ainda." if acts.empty?

    lines = acts.map do |title, theme, desc|
      "- #{title}#{" [#{theme}]" if theme.present?} — #{desc.to_s.squish.truncate(90)}"
    end
    "#{acts.size} atividades publicadas no #{level}:\n#{lines.join("\n")}"
  end

  # As questões que mais erram, com o que escreveram no lugar. Só múltipla
  # escolha e lacuna: ali "errado" é inequívoco. A questão aberta tem nota de
  # IA, e ordenação/associação não dizem qual ponto gramatical falhou.
  #
  # Ficam de fora professoras e as contas em STATS_EXCLUDE_USER_IDS (a conta de
  # aluna da Daisy, contas de teste) — senão o "erro mais comum" pode ser dela.
  def frequent_errors(level)
    excluded = ENV["STATS_EXCLUDE_USER_IDS"].to_s.split(",").map(&:to_i)
    attempts = QuizAttempt.joins(:activity, :user)
                          .where(activities: { level: level, draft: false })
                          .where.not(users: { role: "teacher" })
                          .where.not(user_id: excluded)
                          .where("quiz_attempts.submitted_at >= ?", ERRORS_WINDOW.ago)
                          .includes(:activity)

    stats = Hash.new { |h, k| h[k] = { total: 0, wrong: 0, given: Hash.new(0) } }
    attempts.find_each do |attempt|
      Hash(attempt.results&.dig("results")).each do |qid, r|
        next unless r.is_a?(Hash) && r["question_type"].in?(%w[multiple_choice fill_in_blank])

        key = [attempt.activity.title, qid]
        stat = stats[key]
        stat[:question] ||= r["question_text"].to_s.squish.truncate(140)
        stat[:correct]  ||= r["correct_answer"].to_s
        stat[:total]    += 1
        next if r["is_correct"]

        stat[:wrong] += 1
        wrongs = r["blank_results"].is_a?(Array) ? r["blank_results"].reject { |b| b["ok"] }.map { |b| b["given"] } : [r["given_answer"]]
        wrongs.each { |w| stat[:given][w.to_s.strip] += 1 }
      end
    end

    top = stats.select { |_, st| st[:wrong].positive? }.sort_by { |_, st| [-st[:wrong], -st[:total]] }.first(ERRORS_SHOWN)
    return "Dados insuficientes: nenhum erro registrado no #{level} nos últimos #{ERRORS_WINDOW.in_days.to_i} dias." if top.empty?

    lines = top.map do |(title, _), st|
      erradas = st[:given].sort_by { |_, n| -n }.first(3).map { |g, n| "\"#{g}\" (#{n})" }.join(", ")
      "- [#{title}] \"#{st[:question]}\" · certa: \"#{st[:correct]}\" · erraram #{st[:wrong]} de #{st[:total]} · escreveram: #{erradas}"
    end
    "Questões mais erradas no #{level} (últimos #{ERRORS_WINDOW.in_days.to_i} dias, #{attempts.size} tentativas):\n#{lines.join("\n")}"
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
