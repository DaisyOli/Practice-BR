# "✂️ Adaptar em pílulas" (ponto 1.4 da reformulação, 17/11/2026): a IA
# transforma uma atividade longa em 1 a 3 pílulas rascunho, em série. A original
# fica intacta (arquivar é o ponto 1.5); as pílulas vão para "Rascunhos
# aguardando revisão".
#
# O prompt de sistema é o mesmo da geração, onde moram as regras da pílula. O
# pedido é próprio: a atividade original inteira, exercícios incluídos, para a
# IA reaproveitar o que a professora já escreveu e revisou. As instruções desse
# pedido são editáveis em "A voz das IAs" (activity_adaptation.instructions).
#
# Roda dentro do AiActivityGenerationJob, como as outras gerações.
class AdaptIntoPillsService
  MAX_PILLS = 3

  INSTRUCTIONS = <<~PROMPT
    Você vai ADAPTAR uma atividade longa que já existe para o FORMATO PÍLULA das instruções. A atividade original está abaixo, com todos os exercícios que a professora escreveu e revisou.

    {{original}}

    COMO ADAPTAR
    - Divida em 1 a 3 pílulas. Faça mais de uma só quando o conteúdo pedir: texto longo, mais de um ponto gramatical, ou partes diferentes do vídeo. Cada pílula segue o FORMATO PÍLULA: 3 a 5 exercícios fechados de 2 ou 3 tipos, 1 desafio de escrita no fim e texto dentro do limite de palavras do nível.
    - Todas as pílulas ficam no nível {{nivel}}.
    - Cada pílula cobre UMA parte da original, em ordem e sem repetir o conteúdo de outra. O explanation_text dela é só a sua parte, cortada ou resumida para caber no limite. Ela precisa funcionar sozinha: quem chegar direto na segunda pílula entende sem ter feito a primeira.
    - REAPROVEITE os exercícios da original sempre que servirem à parte: copie, encurte (até 2 lacunas, 3 ou 4 pares, 3 ou 4 frases para ordenar) ou simplifique. Crie exercício novo só quando faltar.
    - Desafio de escrita (o open_ended no fim): aproveite a pergunta aberta da original se ela couber na parte; senão, crie uma ligada à parte.
    - Cada pílula tem título próprio, sem "Parte 1" ou numeração: a plataforma numera a série.
    {{video}}

    FORMATO DA RESPOSTA
    Somente JSON, sem texto antes ou depois: {"pills": [pílula 1, pílula 2, ...]}. Cada pílula é um objeto no SCHEMA DO JSON das instruções (title, description, level, explanation_text, statement, exercises).
  PROMPT

  # Parte técnica, fora do texto editável: são os campos que o app lê.
  VIDEO_RULES = <<~TXT
    - A atividade tem vídeo. Cada pílula usa UM trecho dele, em ordem e sem sobreposição, e ganha os campos "video_start" e "video_end" (m:ss, tirados das marcações de tempo da transcrição abaixo; o fim é a marcação da primeira fala depois do trecho). O explanation_text é a transcrição limpa desse trecho, sem os tempos, e o enunciado manda assistir ao vídeo.
  TXT

  def initialize(source:, teacher:, transcript: nil)
    @source     = source
    @teacher    = teacher
    @transcript = transcript.to_s.strip.first(ActivityFromVideoService::MAX_TRANSCRIPT_CHARS).presence
  end

  def call
    return failure("A atividade original não existe mais.") if @source.nil?
    return failure("Esta atividade já é uma pílula.") if @source.pill?
    if @source.video_url.present? && @transcript.nil?
      return failure("Cole a transcrição do vídeo com os tempos, para cada pílula ganhar o seu trecho.")
    end

    generator = ActivityGenerationService.new(prompt: nil, teacher: @teacher)
    pills     = Array(generator.parse_response(call_api)["pills"]).select { |p| p.is_a?(Hash) }.first(MAX_PILLS)
    return failure(I18n.t('ai.errors.invalid_format')) if pills.empty?

    build_series(generator, pills)
  rescue Anthropic::Errors::RateLimitError, Anthropic::Errors::APITimeoutError, Anthropic::Errors::APIConnectionError
    raise # temporários: o AiActivityGenerationJob põe de volta na fila
  rescue Anthropic::Errors::APIStatusError => e
    Rails.logger.error "AdaptIntoPillsService API error: #{e.message}"
    failure(I18n.t('ai.errors.api', message: e.message))
  rescue JSON::ParserError
    failure(I18n.t('ai.errors.invalid_format'))
  rescue => e
    Rails.logger.error "AdaptIntoPillsService error: #{e.class}: #{e.message}"
    failure(e.message.start_with?("A resposta da IA") ? e.message : I18n.t('ai.errors.generic'))
  end

  # O pedido inteiro, separado para os testes conferirem o que a IA recebe.
  def user_prompt
    AiPrompt.render("activity_adaptation.instructions",
                    original: original_dump,
                    nivel:    @source.level,
                    video:    video_block)
  end

  private

  def call_api
    # Uma resposta com até 3 pílulas é bem maior que a de uma atividade: 16 mil
    # tokens dão folga sem exigir streaming.
    message = Anthropic::Client.new.messages.create(
      model: "claude-opus-4-8",
      max_tokens: 16_000,
      thinking: { type: "adaptive" },
      system: AiPrompt.body_for("activity_generation.system"),
      messages: [{ role: "user", content: user_prompt }]
    )

    raise "A resposta da IA foi recusada." if message.stop_reason == :refusal
    raise "A resposta da IA veio cortada. Tente de novo." if message.stop_reason == :max_tokens

    text = message.content.find { |block| block.type == :text }&.text
    raise "A resposta da IA veio vazia." if text.blank?

    text
  end

  # Tudo ou nada: se uma pílula não monta, as anteriores são apagadas, para
  # não sobrar uma série pela metade nos rascunhos.
  def build_series(generator, pills)
    created = []
    pills.each.with_index(1) do |data, position|
      result = generator.build_from(data, series_attributes(position))
      unless result[:success]
        created.each(&:destroy)
        return failure("A pílula #{position} não pôde ser montada: #{result[:error]}")
      end
      created << result[:activity]
    end

    { success: true, activity: created.first, activities: created }
  end

  def series_attributes(position)
    attrs = { level: @source.level, source_activity: @source, series_position: position }
    attrs[:media_url] = @source.media_url if @source.media_url.present?
    if @source.video_url.present?
      attrs[:video_url]                 = @source.video_url
      attrs[:explanation_is_transcript] = true
    end
    attrs
  end

  def video_block
    return "" if @source.video_url.blank?

    "#{VIDEO_RULES}\nTRANSCRIÇÃO COM TEMPOS:\n#{@transcript}"
  end

  # A atividade original em texto, do jeito que a IA lê melhor: campo por
  # campo, e cada exercício com o tipo do SCHEMA, para ela saber como copiar.
  def original_dump
    linhas = ["ATIVIDADE ORIGINAL", "Título: #{@source.title}", "Nível: #{@source.level}",
              "Descrição: #{@source.description}"]
    linhas << "Enunciado: #{plain(@source.statement)}" if @source.statement.present?
    material = []
    material << "vídeo do YouTube" if @source.video_url.present?
    material << "imagem" if @source.media_url.present? || @source.image_file.attached?
    material << "áudio" if @source.audio_file.attached?
    linhas << "Material: #{material.join(', ')}" if material.any?
    if @source.explanation_text.present?
      linhas << "Texto-base:" << plain(@source.explanation_text)
    end

    exercicios = exercise_lines
    linhas << "" << "Exercícios da original (#{exercicios.size}):" << exercicios.join("\n")
    linhas.join("\n")
  end

  def exercise_lines
    linhas = []
    @source.questions.open_ended_last.each do |q|
      linhas << case q.question_type
                when "multiple_choice"
                  "[multiple_choice] #{plain(q.content)} · opções: #{Array(q.options).join(' | ')} · certa: #{q.correct_answer}"
                when "fill_in_blank"
                  "[fill_in_blank] #{plain(q.content)} · respostas: #{q.all_correct_answers.join(' / ')}"
                else
                  "[open_ended] #{plain(q.content)}"
                end
    end
    @source.sentence_orderings.each do |so|
      linhas << "[sentence_ordering] frase certa: #{so.sentence}"
    end
    @source.paragraph_orderings.includes(:paragraph_sentences).each do |po|
      frases = po.paragraph_sentences.sort_by(&:correct_position).map(&:sentence)
      linhas << "[paragraph_ordering] frases na ordem certa: #{frases.each_with_index.map { |f, i| "#{i + 1}) #{f}" }.join(' ')}"
    end
    @source.column_matchings.includes(:matching_pairs).each do |cm|
      pares = cm.matching_pairs.map { |p| "#{p.left_item} ↔ #{p.right_item}" }
      linhas << "[column_matching] pares: #{pares.join('; ')}"
    end
    linhas.each_with_index.map { |linha, i| "#{i + 1}. #{linha}" }
  end

  def plain(text)
    ActionView::Base.full_sanitizer.sanitize(text.to_s).strip
  end

  def failure(message)
    { success: false, error: message }
  end
end
