# Corrige com IA as respostas abertas pendentes de uma QuizAttempt.
# Roda dentro do AiGradingJob, fora do ciclo da requisição — o aluno vê o
# resultado das outras questões na hora e o feedback da IA chega em seguida.
require "anthropic"

class AiGradingService
  # A exigência acompanha o nível QECR da atividade: no A1 celebra-se a
  # comunicação; a régua sobe progressivamente até o C1.
  #
  # IMPORTANTE: desde o crédito parcial (2026-07-21), este score vira
  # DIRETAMENTE a fração de crédito da questão (credit_fraction = score/100)
  # — não é mais só aprovado/reprovado (>=70 valendo 100%). Por isso as
  # faixas abaixo foram recalibradas pra cima: uma resposta boa precisa
  # valer perto de 100% de crédito, não 70-90%.
  LEVEL_EXPECTATIONS = {
    "A1" => <<~TXT,
      Nível do aluno: A1 (iniciante). SEJA MUITO GENEROSO.
      - Se a resposta comunica a ideia e responde à pergunta, o score fica entre 90 e 100 — MESMO com erros de conjugação, concordância, acento ou ortografia ("eu gosta de café" responde perfeitamente "do que você gosta?").
      - Resposta que responde só em parte à pergunta: 60-89, nunca menos só por isso.
      - Só desça abaixo de 60 se a resposta não responder à pergunta ou for incompreensível.
      - Feedback: comece celebrando o acerto; depois, no máximo UMA correção gentil, a mais importante. Use português muito simples, frases curtas, que um A1 entenda.
    TXT
    "A2" => <<~TXT,
      Nível do aluno: A2 (básico). Seja muito generoso, com um degrau a mais de atenção.
      - Comunicação clara e vocabulário adequado valem mais que perfeição: resposta compreensível que responde à pergunta fica entre 85 e 100.
      - Erros básicos recorrentes (ser/estar, concordância simples, presente dos verbos comuns) descontam pouco (uns 10-15 pontos no máximo), nunca derrubam abaixo de 70 uma resposta que comunica.
      - Só desça abaixo de 60 se a resposta não responder à pergunta ou for incompreensível.
      - Feedback: elogie o que funcionou e aponte no máximo DUAS correções, em português simples.
    TXT
    "B1" => <<~TXT,
      Nível do aluno: B1 (intermediário). Exigência moderada, sem ser avara.
      - Resposta que comunica bem, mesmo com alguns erros básicos (presente, ser/estar, concordância simples), fica entre 80 e 95 — esses erros descontam pouco, não cortam a nota pela metade.
      - Erros em estruturas novas do nível (subjuntivo, tempos do passado em contraste) quase não descontam — estão em aquisição.
      - Reserve 96-100 para respostas praticamente sem erros. Só desça abaixo de 70 se a resposta não responder bem à pergunta ou tiver erros que atrapalham a compreensão.
      - Feedback: reconheça o mérito e corrija até TRÊS pontos, explicando brevemente o porquê.
    TXT
    "B2" => <<~TXT,
      Nível do aluno: B2 (avançado). Exigência real, mas nunca aviltante.
      - Resposta que comunica bem, com vocabulário e estrutura adequados mas alguma imprecisão de nuance, fica entre 75 e 90.
      - Reserve 90+ para respostas precisas E naturais. Erros básicos (que não deveriam mais ocorrer neste nível) descontam mais, mas imprecisões pequenas isoladas não devem derrubar abaixo de 70.
      - Feedback: rigoroso e específico, ainda construtivo — aponte os erros, sugira a forma natural que um falante usaria.
    TXT
    "C1" => <<~TXT
      Nível do aluno: C1 (proficiente). Exigência de quase-nativo, mas o score ainda é crédito direto.
      - Resposta idiomática e precisa: 95-100. Pequenas imprecisões de registro ou naturalidade: 80-94.
      - Erros estruturais reais descontam de verdade, mas um erro isolado não deve derrubar abaixo de 65.
      - Feedback: trate como um par avançado — refinamentos de estilo e expressões mais idiomáticas.
    TXT
  }.freeze

  PASSING_SCORE = 70

  def initialize(quiz_attempt)
    @attempt = quiz_attempt
  end

  # Corrige cada questão pendente salvando o progresso uma a uma: se o job
  # sofrer retry no meio, só as questões ainda pendentes são reenviadas à IA.
  def call
    return if pending_ids.empty?

    questions = @attempt.activity.questions.index_by(&:id)

    pending_ids.each do |key|
      entry    = @attempt.results["results"][key]
      question = questions[key.to_i]

      graded = if question.nil? || ENV["ANTHROPIC_API_KEY"].blank?
        { score: nil, feedback: I18n.t('ai.errors.generic') }
      else
        grade_question(question, entry["given_answer"])
      end

      apply_result!(key, graded)
    end

    recompute_totals!
  end

  # Usado quando os retries do job se esgotam: destrava a tela do aluno
  # com a mensagem de indisponibilidade em vez de "corrigindo..." eterno.
  def mark_pending_as_unavailable!(message)
    return if pending_ids.empty?

    pending_ids.each { |key| apply_result!(key, { score: nil, feedback: message }) }
    recompute_totals!
  end

  private

  def correction_system_prompt
    level = @attempt.activity.level.to_s
    expectations = LEVEL_EXPECTATIONS[level] || LEVEL_EXPECTATIONS["B1"]

    <<~PROMPT
      Você é um avaliador de respostas de estudantes de português como segunda língua, alinhado ao QECR: a exigência acompanha o nível do aluno.

      #{expectations}
      Regras gerais:
      - O score vira DIRETAMENTE a fração de crédito da questão (um 70 vale 70% da questão, não é "aprovado"). Por isso notas baixas são reservadas para respostas que realmente não respondem ou são incompreensíveis — não para pequenos deslizes numa resposta que comunica bem.
      - Nunca desconte por resposta curta se a pergunta permite resposta curta.
      - Avalie o conteúdo da resposta, não a opinião do aluno.
      - O feedback fala COM o aluno (use "você"), em tom caloroso.

      Responda SOMENTE com JSON neste formato exato (sem markdown, sem texto extra):
      {"score": <inteiro de 0 a 100>, "feedback": "<feedback curto em português>"}
    PROMPT
  end

  def pending_ids
    results_hash.select { |_k, r| r.is_a?(Hash) && r["ai_pending"] }.keys
  end

  def results_hash
    data = @attempt.results
    data.is_a?(Hash) && data["results"].is_a?(Hash) ? data["results"] : {}
  end

  def grade_question(question, given_answer)
    client = Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))

    rubric_line = question.evaluation_prompt.present? \
      ? "Critérios de avaliação: #{question.evaluation_prompt}\n" \
      : ""

    message = client.messages.create(
      model: :"claude-haiku-4-5",
      max_tokens: 1024, # folga p/ feedback longo: 256 cortava o JSON no meio (só pagamos o que for gerado)
      system: correction_system_prompt,
      messages: [{
        role: "user",
        content: "Questão: #{ActionView::Base.full_sanitizer.sanitize(question.content.to_s)}\n#{rubric_line}Resposta do aluno: #{given_answer.to_s.strip}"
      }]
    )

    text_block = message.content.find { |b| b.type == :text }
    raw = text_block ? text_block.text : ""
    # A IA às vezes envolve o JSON em prosa ou cercas ```json; extrai do primeiro { ao último }
    parsed = JSON.parse(raw[/\{.*\}/m] || raw)
    { score: parsed["score"].to_i.clamp(0, 100), feedback: parsed["feedback"].to_s }

  rescue Anthropic::Errors::RateLimitError, Anthropic::Errors::APITimeoutError, Anthropic::Errors::APIConnectionError
    raise # temporários: deixa o AiGradingJob fazer retry com backoff
  rescue Anthropic::Errors::APIStatusError => e
    Rails.logger.error "AI grading API error: #{e.message}"
    { score: nil, feedback: I18n.t('ai.errors.api', message: e.message) }
  rescue JSON::ParserError => e
    Rails.logger.error "AI grading JSON parse error: #{e.message}; stop_reason=#{message&.stop_reason}; raw=#{raw.inspect}"
    { score: nil, feedback: I18n.t('ai.errors.invalid_format') }
  end

  def apply_result!(key, graded)
    @attempt.results_will_change!
    entry = @attempt.results["results"][key]
    entry.delete("ai_pending")

    if graded[:score].nil?
      entry["is_correct"]     = nil
      entry["ai_score"]       = nil
      entry["ai_feedback"]    = graded[:feedback]
      entry["ai_unavailable"] = true
    else
      entry["is_correct"]     = graded[:score] >= PASSING_SCORE
      entry["ai_score"]       = graded[:score]
      entry["ai_feedback"]    = graded[:feedback]
      entry["credit_fraction"] = graded[:score] / 100.0
    end

    @attempt.save!
  end

  # Reaplica a mesma regra de pontuação do QuizSubmissionService: média
  # ponderada dos exercícios avaliados; pendentes e indisponíveis ficam fora.
  #
  # Usa o "credit_fraction" já calculado por cada exercício (lacunas,
  # colunas, ordenação, e agora também o ai_score/100 do open_ended) em vez
  # de só is_correct — senão o crédito parcial dado na submissão original
  # era substituído por tudo-ou-nada só porque o quiz tinha uma questão
  # aberta pendente de correção por IA.
  def recompute_totals!
    weights = @attempt.activity.questions.pluck(:id, :weight).to_h

    weighted_correct = 0.0
    weighted_possible = 0.0
    correct_count = 0
    exercise_count = 0

    results_hash.each do |key, entry|
      next if entry["ai_pending"] || entry["ai_unavailable"]

      weight   = key.to_s.match?(/\A\d+\z/) ? (weights[key.to_i] || 1).to_f : 1.0
      fraction = entry.key?("credit_fraction") ? entry["credit_fraction"].to_f : (entry["is_correct"] ? 1.0 : 0.0)

      weighted_possible += weight
      exercise_count    += 1
      weighted_correct  += weight * fraction
      correct_count     += 1 if entry["is_correct"]
    end

    score = weighted_possible > 0 ? ((weighted_correct / weighted_possible) * 100).round(2) : 0

    @attempt.results_will_change!
    @attempt.results["score"]           = score
    @attempt.results["total_correct"]   = correct_count
    @attempt.results["total_questions"] = exercise_count
    @attempt.score = score
    @attempt.save!
  end
end
