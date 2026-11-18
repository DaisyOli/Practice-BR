# A transcrição que a professora cola do YouTube (⋮ → Abrir transcrição).
#
# Na cópia, o YouTube cola cada tempo no texto do leitor de tela e na própria
# fala, sem espaço: "6:126 minutos e 12 segundoso orelhão" é "6:12" + "6
# minutos e 12 segundos" + "o orelhão". Com isso, os tempos não eram
# reconhecidos, e a geração em pílulas recusava a transcrição (relato da Daisy,
# 18/11/2026). Aqui, cada tempo volta para o começo de uma linha, sem o texto
# do leitor de tela: "6:12 o orelhão".
#
# O texto do leitor de tela muda com a língua do YouTube de quem copia; por
# isso a regra cobre português, francês, inglês e espanhol. Limpar duas vezes
# dá o mesmo resultado.
module VideoTranscript
  TIME  = /\d{1,2}:\d{2}(?::\d{2})?/
  UNIT  = /(?:horas?|heures?|hours?|minutos?|minutes?|segundos?|secondes?|seconds?)/
  LABEL = /\d+\s#{UNIT}(?:(?:,\s*|\s+(?:e|et|and|y)\s+)\d+\s#{UNIT})*/
  # "6:12" + "6 minutos e 12 segundos", grudados
  GLUED_LABEL = /(#{TIME})#{LABEL}/
  # "6:12o orelhão": tempo grudado na fala, sem o texto do leitor de tela
  GLUED_SPEECH = /^(#{TIME})(?=\p{L})/

  def self.clean(text)
    text.to_s
        .gsub(GLUED_LABEL) { "\n#{Regexp.last_match(1)} " }
        .gsub(GLUED_SPEECH) { "#{Regexp.last_match(1)} " }
        .gsub(/[ \t]{2,}/, " ")
        .gsub(/[ \t]*\n[ \t]*/, "\n")
        .gsub(/\n{2,}/, "\n")
        .strip
  end
end
