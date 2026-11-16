class ActivityFromVideoService
  MAX_TRANSCRIPT_CHARS = 8000

  def initialize(youtube_url:, transcript:, teacher:, level_hint: nil)
    @youtube_url = youtube_url.to_s.strip
    @transcript  = transcript.to_s.strip[0, MAX_TRANSCRIPT_CHARS]
    @teacher     = teacher
    @level_hint  = level_hint.presence || "adequado ao vocabulário e estruturas do vídeo (infira o nível CEFR)"
  end

  def call
    if @transcript.blank?
      return { success: false, error: "A transcrição está vazia. Cole o texto da transcrição do vídeo." }
    end

    svc = YoutubeTranscriptService.new(@youtube_url)
    has_video = svc.valid?

    # Sem release_connection aqui: rodamos dentro do AiActivityGenerationJob,
    # cujo advisory lock de sessão vive nesta conexão. Liberá-la fazia o job
    # ser reexecutado e a atividade sair em duplicata (ver ActivityGenerationService#call).
    result = ActivityGenerationService.new(
      prompt:  build_prompt,
      teacher: @teacher
    ).call

    return result unless result[:success]

    updates = { explanation_is_transcript: true }
    updates[:video_url] = "https://www.youtube.com/watch?v=#{svc.video_id}" if has_video
    result[:activity].update(updates)

    { success: true, activity: result[:activity] }
  end

  private

  def build_prompt
    <<~PROMPT
      Crie uma atividade de português brasileiro baseada na transcrição de vídeo abaixo.

      Nível desejado: #{@level_hint}

      TRANSCRIÇÃO DO VÍDEO:
      #{@transcript}

      INSTRUÇÕES ESPECÍFICAS PARA ATIVIDADE BASEADA EM VÍDEO:
      - Leia a transcrição e identifique o tema, vocabulário e estruturas gramaticais principais
      - O campo "explanation_text" deve conter a transcrição limpa do trecho escolhido: remova timestamps e marcadores de tempo, mas mantenha o conteúdo falado original com fidelidade. Este texto aparecerá recolhido como "Ver transcrição" na interface do aluno — não o reescreva como texto literário
      - FORMATO PÍLULA: escolha UM trecho do vídeo, de 1 a 3 minutos, que funcione sozinho, e baseie tudo nele. Crie 3 a 5 exercícios fechados + 1 open_ended no fim (o desafio de escrita opcional), com o conteúdo real desse trecho
      - O "explanation_text" deve conter só a transcrição desse trecho, não a do vídeo inteiro
      - Use vocabulário e expressões que aparecem na transcrição nas questões
      - A "description" deve mencionar o tema do vídeo e o que o aluno vai praticar
      - O campo "statement" (enunciado, exibido antes dos exercícios) deve instruir o aluno a ASSISTIR AO VÍDEO — por exemplo: "Assista ao vídeo e responda às questões." NUNCA escreva "leia a transcrição" no enunciado: o vídeo é o material principal e a transcrição fica só como apoio recolhido
      - Nos enunciados das QUESTÕES individuais (o "content" de cada exercício), não repita "assista ao vídeo" — o player já fica integrado à atividade; foque no conteúdo
    PROMPT
  end
end
