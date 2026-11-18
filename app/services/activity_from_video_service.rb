# Gera atividade a partir de um vídeo do YouTube e da transcrição colada pela
# professora. Dois modos, escolhidos no formulário (17/11/2026):
#
#   pills (padrão) → uma SÉRIE de pílulas, cada uma com o seu trecho do vídeo
#                    (video_start/video_end). A quantidade é da professora (2 a
#                    5) ou da IA (1 a 3). Exige a transcrição com tempos.
#   whole          → uma pílula só sobre o vídeo inteiro, sem cortar: para
#                    vídeos curtos, de até uns 4 minutos.
#
# Antes havia um modo só: uma pílula sobre UM trecho, e o resto do vídeo se
# perdia. O modo pills cobre esse caso (a IA escolhe 1).
class ActivityFromVideoService
  # Era 8.000. A transcrição com marcações de tempo é mais comprida, e com 8.000
  # a IA só enxergava os primeiros minutos do vídeo para escolher o trecho.
  # 20.000 caracteres cobrem uns 20 minutos de fala (cerca de US$ 0,03 a mais).
  MAX_TRANSCRIPT_CHARS = 20_000
  MODES      = %w[pills whole].freeze
  PILL_RANGE = (2..5)

  # Para saber se a transcrição veio com os tempos ("0:05", "1:23", "1:02:15").
  TIMESTAMP = /(?:^|\s)\d{1,2}:\d{2}(?::\d{2})?(?=\s|$)/

  # 5 pílulas numa resposta passam do que cabe com folga numa chamada comum;
  # com streaming não há risco de tempo esgotado (ver LevelPathAgent).
  MAX_TOKENS = 32_000

  def self.timestamps?(text)
    text.to_s.match?(TIMESTAMP)
  end

  def initialize(youtube_url:, transcript:, teacher:, level_hint: nil, mode: "pills", pill_count: nil)
    @youtube_url = youtube_url.to_s.strip
    @transcript  = VideoTranscript.clean(transcript)[0, MAX_TRANSCRIPT_CHARS]
    @teacher     = teacher
    @level_hint  = level_hint.presence || "adequado ao vocabulário e estruturas do vídeo (infira o nível CEFR)"
    @mode        = MODES.include?(mode.to_s) ? mode.to_s : "pills"
    @pill_count  = pill_count.to_i if PILL_RANGE.cover?(pill_count.to_i) # nil = a IA decide
  end

  def call
    if @transcript.blank?
      return { success: false, error: "A transcrição está vazia. Cole o texto da transcrição do vídeo." }
    end
    if @mode == "pills" && !self.class.timestamps?(@transcript)
      return { success: false, error: "Para dividir em pílulas, cole a transcrição com os tempos (0:05, 1:23...): é com eles que cada pílula ganha o seu trecho." }
    end

    @mode == "whole" ? generate_whole : generate_series
  end

  def build_prompt
    @mode == "whole" ? whole_prompt : series_prompt
  end

  private

  def video_url
    svc = YoutubeTranscriptService.new(@youtube_url)
    "https://www.youtube.com/watch?v=#{svc.video_id}" if svc.valid?
  end

  # Vídeo inteiro: o caminho da geração comum, e o vídeo toca sem corte, mesmo
  # que a IA mande tempos.
  #
  # Sem release_connection aqui: rodamos dentro do AiActivityGenerationJob,
  # cujo advisory lock de sessão vive nesta conexão. Liberá-la fazia o job
  # ser reexecutado e a atividade sair em duplicata (ver ActivityGenerationService#call).
  def generate_whole
    result = ActivityGenerationService.new(prompt: build_prompt, teacher: @teacher).call
    return result unless result[:success]

    updates = { explanation_is_transcript: true, video_start_seconds: nil, video_end_seconds: nil }
    url = video_url
    updates[:video_url] = url if url
    result[:activity].update(updates)

    { success: true, activity: result[:activity] }
  end

  def generate_series
    generator = ActivityGenerationService.new(prompt: nil, teacher: @teacher)
    pills = Array(generator.parse_response(call_api)["pills"]).select { |p| p.is_a?(Hash) }.first(PILL_RANGE.max)
    return { success: false, error: I18n.t('ai.errors.invalid_format') } if pills.empty?

    base = { explanation_is_transcript: true, level: pills.first["level"] }
    url = video_url
    base[:video_url] = url if url
    generator.build_series(pills, base: base, prefix: "video")
  rescue Anthropic::Errors::RateLimitError, Anthropic::Errors::APITimeoutError, Anthropic::Errors::APIConnectionError
    raise # temporários: o AiActivityGenerationJob põe de volta na fila
  rescue Anthropic::Errors::APIStatusError => e
    Rails.logger.error "ActivityFromVideoService API error: #{e.message}"
    { success: false, error: I18n.t('ai.errors.api', message: e.message) }
  rescue JSON::ParserError
    { success: false, error: I18n.t('ai.errors.invalid_format') }
  rescue => e
    Rails.logger.error "ActivityFromVideoService error: #{e.class}: #{e.message}"
    { success: false, error: e.message.start_with?("A resposta da IA") ? e.message : I18n.t('ai.errors.generic') }
  end

  def call_api
    message = Anthropic::Client.new.messages.stream(
      model:      "claude-opus-4-8",
      max_tokens: MAX_TOKENS,
      thinking:   { type: "adaptive" },
      system:     AiPrompt.body_for("activity_generation.system"),
      messages:   [{ role: "user", content: build_prompt }]
    ).accumulated_message

    raise "A resposta da IA foi recusada." if message.stop_reason.to_s == "refusal"
    raise "A resposta da IA veio cortada. Tente de novo." if message.stop_reason.to_s == "max_tokens"

    text = message.content.find { |block| block.type.to_s == "text" }&.text
    raise "A resposta da IA veio vazia." if text.blank?

    text
  end

  def quantity
    @pill_count ? "exatamente #{@pill_count}" : "de 1 a 3 (decida pelo que o vídeo oferece de bom; vídeo curto pode render uma só)"
  end

  def series_prompt
    <<~PROMPT
      Crie uma SÉRIE DE PÍLULAS de português brasileiro a partir da transcrição de vídeo abaixo.

      Nível desejado: #{@level_hint}

      TRANSCRIÇÃO DO VÍDEO:
      #{@transcript}

      INSTRUÇÕES ESPECÍFICAS PARA A SÉRIE:
      - Escolha #{quantity} trechos do vídeo, de 1 a 3 minutos cada, em ordem e sem sobreposição: as partes que funcionam melhor sozinhas. Não precisa cobrir o vídeo inteiro.
      - Cada trecho vira uma pílula no FORMATO PÍLULA (3 a 5 exercícios fechados + 1 open_ended no fim, o desafio de escrita opcional), com o conteúdo real daquele trecho. Ela precisa funcionar sozinha: quem chegar direto na segunda entende sem ter feito a primeira.
      - TRECHO NO PLAYER: cada pílula tem os campos "video_start" (a marcação da primeira fala do trecho) e "video_end" (a marcação da primeira fala DEPOIS do trecho), no formato m:ss, por exemplo "video_start": "1:20", "video_end": "3:45". Use apenas marcações que aparecem na transcrição.
      #{shared_rules}
      - Todas as pílulas no mesmo nível. O título de cada pílula começa pelo MESMO nome curto da série, seguido de dois-pontos e do título próprio da pílula, com até 80 caracteres no total. Exemplo: "A invenção do orelhão: A jornada de Chu Ming Silveira" e "A invenção do orelhão: Um desafio contra o barulho". Sem "Parte 1" ou numeração: a plataforma numera a série.

      FORMATO DA RESPOSTA
      Somente JSON, sem texto antes ou depois: {"pills": [pílula 1, pílula 2, ...]}. Cada pílula é um objeto no SCHEMA DO JSON das instruções (title, description, level, explanation_text, statement, exercises), mais "video_start" e "video_end".
    PROMPT
  end

  def whole_prompt
    <<~PROMPT
      Crie uma atividade de português brasileiro baseada na transcrição de vídeo abaixo.

      Nível desejado: #{@level_hint}

      TRANSCRIÇÃO DO VÍDEO:
      #{@transcript}

      INSTRUÇÕES ESPECÍFICAS PARA ATIVIDADE BASEADA EM VÍDEO:
      - VÍDEO INTEIRO: a pílula é sobre o vídeo todo, sem escolher trecho. Crie 3 a 5 exercícios fechados + 1 open_ended no fim (o desafio de escrita opcional), cobrindo o essencial do vídeo. Não inclua "video_start" nem "video_end".
      #{shared_rules}
    PROMPT
  end

  def shared_rules
    <<~RULES.strip
      - O campo "explanation_text" deve conter a transcrição limpa do trecho (ou do vídeo, se for o vídeo inteiro): remova timestamps e marcadores de tempo, mas mantenha o conteúdo falado original com fidelidade. Este texto aparecerá recolhido como "Ver transcrição" na interface do aluno — não o reescreva como texto literário. Por ser apoio do vídeo, ele não segue o limite de palavras do texto-base.
      - Use vocabulário e expressões que aparecem na transcrição nas questões
      - A "description" deve mencionar o tema do vídeo e o que o aluno vai praticar
      - O campo "statement" (enunciado, exibido antes dos exercícios) deve instruir o aluno a ASSISTIR AO VÍDEO — por exemplo: "Assista ao vídeo e responda às questões." NUNCA escreva "leia a transcrição" no enunciado: o vídeo é o material principal e a transcrição fica só como apoio recolhido
      - Nos enunciados das QUESTÕES individuais (o "content" de cada exercício), não repita "assista ao vídeo" — o player já fica integrado à atividade; foque no conteúdo
    RULES
  end
end
