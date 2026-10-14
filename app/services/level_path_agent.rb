require "json"

# O agente do percurso. Lê o catálogo publicado de um nível — texto, tamanho,
# tipos de questão, mídia, e o que os alunos de fato fizeram (nota média,
# estrelas) — e devolve uma proposta. Nunca grava o percurso: quem decide é a
# Daisy, na tela Admin › Percurso (PathSuggestion guarda a proposta).
#
# Dois trabalhos:
#   suggest_path(level)  → os 10 do nível, em ordem, com um motivo cada, e um
#                          tema curto para cada atividade do nível
#   evaluate(activity)   → uma atividade recém-publicada entra no percurso? onde?
#
# Uma chamada só, não um laço de ferramentas: o catálogo inteiro de um nível
# cabe numa mensagem (~40 atividades), e o agente responde por uma ferramenta de
# formato fixo. Mais barato e mais previsível que deixá-lo ir e voltar.
class LevelPathAgent
  MODEL      = "claude-opus-5-5".freeze
  MAX_TOKENS = 32_000
  TEXT_PREVIEW = 400

  SYSTEM_PROMPT = <<~PROMPT
    Você é coordenador pedagógico da Practice-BR, plataforma de português brasileiro para
    adultos estrangeiros (muitos francófonos). Você monta o PERCURSO de um nível do CECRL:
    até 10 atividades, na ordem em que um aluno que acabou de chegar nesse nível deve fazê-las.

    ── O QUE ORDENA O CAMINHO ──
    1. Progressão do CECRL dentro do nível: o que um aluno precisa primeiro (no A1, por
       exemplo, cumprimentar e se apresentar vem antes de narrar a rotina). Use seu
       conhecimento do quadro, mas julgue pelo CONTEÚDO real de cada atividade, não pelo título.
    2. Carga: texto curto antes de texto longo; poucas questões antes de muitas.
    3. Tipo de tarefa: reconhecer (múltipla escolha, associar) antes de produzir (lacuna,
       ordenar, questão aberta).
    4. O que os alunos mostraram, quando houver dados: nota média baixa indica atividade mais
       difícil do que parece; estrelas baixas, atividade que não agradou — evite no começo.
       Poucos dados não são conclusão: diga isso em vez de forçar.
    5. Variedade ao longo do caminho: alterne tema e suporte (texto, áudio, vídeo, imagem).

    ── AS 3 PRIMEIRAS SÃO O TESTE GRATUITO ──
    São a primeira impressão da plataforma: curtas, acolhedoras, as mais caprichadas do nível.
    Se existir no nível uma atividade com questão aberta (corrigida por IA), coloque uma nas 3
    primeiras — é o que mais impressiona.

    ── TEMAS ──
    Dê também um tema curto (1 a 3 palavras, em português, com inicial maiúscula) para CADA
    atividade da lista, não só para as 10. Padronize: atividades parecidas recebem exatamente o
    mesmo nome de tema ("Comida", não "Comida" numa e "Alimentação" na outra). O tema diz do que
    a atividade trata (Cumprimentos, Rotina, Trabalho, Viagem, Comida, Saúde, Cultura...), não o
    ponto gramatical.

    ── REGRAS ──
    - Use SÓ os ids da lista recebida. Nunca invente atividade.
    - Menos de 10 é aceitável se o nível tiver poucas atividades boas.
    - O motivo de cada posição é para a professora: uma frase concreta, citando o que você viu
      ("texto de 80 palavras, só múltipla escolha", "nota média 52 em 6 tentativas").
    - Nos motivos e no resumo, cite outras atividades pelo TÍTULO, nunca pelo id — a professora
      não vê os ids.
    - Se notar um problema numa atividade (texto que não aparece, enunciado que fala de imagem
      e só há áudio, conteúdo que parece teste esquecido), diga no resumo: ela vai querer saber.
    - Responda chamando a ferramenta propose_path, uma vez.
  PROMPT

  NEW_ACTIVITY_PROMPT = <<~PROMPT
    Você é coordenador pedagógico da Practice-BR, plataforma de português brasileiro para
    adultos estrangeiros. O nível já tem um PERCURSO: até 10 atividades em ordem, do mais
    acessível ao mais exigente, montado pela professora. As 3 primeiras são o teste gratuito.

    Uma atividade acabou de ser publicada. Decida se ela melhora o percurso:
    - "none": fica fora — o percurso atual já é melhor naquele ponto, ou ela é avançada demais
      para um começo de nível. Esta é a resposta mais comum, e está tudo bem.
    - "replace": ocupa a posição N no lugar da atividade que está lá (diga qual).
    - "insert": entra na posição N e empurra as seguintes uma casa (a 10ª sai).

    Julgue pelo conteúdo: progressão do CECRL, tamanho do texto, número e tipo de questões,
    o lugar dela em relação às vizinhas. Não mexa nas 3 primeiras (o teste) sem um motivo forte.
    Dê também um tema curto para ela (1 a 3 palavras), reaproveitando EXATAMENTE um dos temas que
    já existem no nível quando servir.

    O motivo é para a professora: uma ou duas frases concretas, citando outras atividades pelo
    TÍTULO, nunca pelo id.
    Responda chamando a ferramenta evaluate_new_activity, uma vez.
  PROMPT

  PATH_TOOL = {
    name: "propose_path",
    description: "Registra o percurso proposto para o nível e o tema de cada atividade.",
    strict: true,
    input_schema: {
      type: "object",
      additionalProperties: false,
      required: %w[path themes summary],
      properties: {
        path: {
          type: "array",
          description: "Até 10 atividades, na ordem do percurso.",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[activity_id reason],
            properties: {
              activity_id: { type: "integer" },
              reason:      { type: "string" }
            }
          }
        },
        themes: {
          type: "array",
          description: "Um tema para cada atividade da lista recebida.",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[activity_id theme],
            properties: {
              activity_id: { type: "integer" },
              theme:       { type: "string" }
            }
          }
        },
        summary: { type: "string", description: "2-3 frases para a professora sobre a lógica do caminho." }
      }
    }
  }.freeze

  NEW_TOOL = {
    name: "evaluate_new_activity",
    description: "Registra se a atividade nova entra no percurso, onde, e o tema dela.",
    strict: true,
    input_schema: {
      type: "object",
      additionalProperties: false,
      required: %w[decision position replaces_activity_id reason theme],
      properties: {
        decision:             { type: "string", enum: %w[none replace insert] },
        position:             { type: ["integer", "null"], description: "1 a 10; null quando decision é none." },
        replaces_activity_id: { type: ["integer", "null"], description: "Só para replace: o id que sai." },
        reason:               { type: "string" },
        theme:                { type: "string" }
      }
    }
  }.freeze

  class Failed < StandardError; end

  def initialize(client: Anthropic::Client.new)
    @client = client
  end

  # → { "path" => [{ "activity_id", "reason", "title" }], "themes" => { id => tema }, "summary" }
  def suggest_path(level)
    activities = catalog(level)
    raise Failed, "Nenhuma atividade publicada no #{level}." if activities.empty?

    input = ask(AiPrompt.body_for("level_path.system"), PATH_TOOL,
                "Nível #{level}. Atividades publicadas:\n\n#{describe(activities)}")

    ids   = activities.map(&:id).to_set
    title = activities.to_h { |a| [a.id, a.title] }
    path  = Array(input[:path]).select { |p| ids.include?(p[:activity_id]) }
                               .uniq { |p| p[:activity_id] }
                               .first(Activity::PATH_SLOTS)
    raise Failed, "O agente não propôs nenhuma atividade válida." if path.empty?

    {
      "path"    => path.map { |p| { "activity_id" => p[:activity_id], "reason" => p[:reason], "title" => title[p[:activity_id]] } },
      "themes"  => Array(input[:themes]).select { |t| ids.include?(t[:activity_id]) }
                                        .to_h { |t| [t[:activity_id].to_s, t[:theme].to_s.strip.first(40)] },
      "summary" => input[:summary].to_s
    }
  end

  # → { "decision", "position", "replaces_activity_id", "reason", "theme" }
  def evaluate(activity)
    level = activity.level
    path  = Activity.published.where(level: level).in_path.to_a
    themes = Activity.published.where(level: level).where.not(theme: [nil, ""]).distinct.pluck(:theme)

    message = <<~MSG
      Nível #{level}.

      PERCURSO ATUAL (em ordem):
      #{path.empty? ? "(ainda não há percurso montado)" : describe(path)}

      TEMAS QUE JÁ EXISTEM NO NÍVEL: #{themes.presence&.join(", ") || "(nenhum ainda)"}

      ATIVIDADE NOVA:
      #{describe([activity])}
    MSG

    input    = ask(AiPrompt.body_for("level_path.new_activity"), NEW_TOOL, message)
    decision = input[:decision].to_s
    position = input[:position].to_i
    path_ids = path.map(&:id)

    # O que não faz sentido vira "fica fora", em vez de uma sugestão quebrada.
    decision = "none" unless decision.in?(%w[replace insert]) && position.between?(1, Activity::PATH_SLOTS)
    decision = "insert" if decision == "replace" && path_ids[position - 1].nil?

    {
      "decision"             => decision,
      "position"             => decision == "none" ? nil : position,
      "replaces_activity_id" => decision == "replace" ? path_ids[position - 1] : nil,
      "reason"               => input[:reason].to_s,
      "theme"                => input[:theme].to_s.strip.first(40)
    }
  end

  private

  def ask(system, tool, text)
    message = @client.messages.stream(
      model:         MODEL,
      max_tokens:    MAX_TOKENS,
      output_config: { effort: "high" },
      system:        system,
      tools:         [tool],
      tool_choice:   { type: "auto" },
      messages:      [{ role: "user", content: text }]
    ).accumulated_message

    raise Failed, "O agente recusou o pedido." if message.stop_reason.to_s == "refusal"

    call = message.content.find { |b| b.type.to_s == "tool_use" && b.name.to_s == tool[:name] }
    raise Failed, "O agente terminou sem responder pela ferramenta." unless call

    # No streaming, o SDK de Ruby entrega o `input` da ferramenta como texto JSON
    # (o acumulado dos pedaços), não como hash — achado na primeira chamada real.
    raw = call.input
    JSON.parse(raw.is_a?(String) ? raw : raw.to_json, symbolize_names: true)
  end

  def catalog(level)
    Activity.published.where(level: level).includes(:questions).order(:created_at).to_a
  end

  # O resumo que o agente lê de cada atividade: o conteúdo para julgar a
  # progressão, e os números para julgar a dificuldade real.
  def describe(activities)
    ids     = activities.map(&:id)
    media   = ActiveStorage::Attachment.where(record_type: "Activity", record_id: ids,
                                              name: %w[video_file audio_file image_file])
                                       .pluck(:record_id, :name).group_by(&:first)
    scores  = QuizAttempt.where(activity_id: ids).where.not(submitted_at: nil).group(:activity_id)
                         .pluck(:activity_id, Arel.sql("AVG(score)"), Arel.sql("COUNT(*)"))
                         .to_h { |id, avg, n| [id, [avg.to_f.round, n]] }
    stars   = ActivityRating.where(activity_id: ids).group(:activity_id)
                            .pluck(:activity_id, Arel.sql("AVG(stars)"), Arel.sql("COUNT(*)"))
                            .to_h { |id, avg, n| [id, [avg.to_f.round(1), n]] }
    orders  = SentenceOrdering.where(activity_id: ids).group(:activity_id).count
    pgraphs = ParagraphOrdering.where(activity_id: ids).group(:activity_id).count
    matches = ColumnMatching.where(activity_id: ids).group(:activity_id).count

    activities.map do |a|
      types  = a.questions.map(&:question_type).tally
      types["sentence_ordering"]  = orders[a.id]  if orders[a.id]
      types["paragraph_ordering"] = pgraphs[a.id] if pgraphs[a.id]
      types["column_matching"]    = matches[a.id] if matches[a.id]
      suportes = (media[a.id] || []).map { |_, n| n.delete_suffix("_file") }
      suportes << "video" if a.video_url.present? && !suportes.include?("video")
      text = ActionController::Base.helpers.strip_tags(a.explanation_text.to_s).squish

      [
        "[id #{a.id}] #{a.title}",
        ("  posição atual no percurso: #{a.path_position}" if a.path_position),
        ("  tema atual: #{a.theme}" if a.theme.present?),
        "  descrição: #{a.description.to_s.squish}",
        ("  enunciado: #{a.statement.to_s.squish.first(200)}" if a.statement.present?),
        "  texto: #{text.split.size} palavras#{text.present? ? " — \"#{text.first(TEXT_PREVIEW)}…\"" : ""}",
        "  questões: #{types.map { |t, n| "#{n} #{t}" }.join(', ').presence || 'nenhuma'}",
        "  suporte: #{suportes.presence&.join(', ') || 'só texto'}",
        "  alunos: #{scores[a.id] ? "nota média #{scores[a.id][0]} em #{scores[a.id][1]} tentativas" : 'sem tentativas'}" \
          "#{stars[a.id] ? ", #{stars[a.id][0]}★ (#{stars[a.id][1]} avaliações)" : ''}"
      ].compact.join("\n")
    end.join("\n\n")
  end
end
