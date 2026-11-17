# Converte entre o tempo que a gente lê no YouTube ("1:20", "1:02:15") e
# segundos (80, 3735), para o trecho de vídeo da pílula.
module VideoTimestamp
  # "1:20" → 80 · "1:02:15" → 3735 · "95" → 95 · "" → nil · "abc" → :invalid
  #
  # :invalid em vez de nil para quem chama saber a diferença entre "não
  # preencheu" e "preencheu errado", e avisar a professora.
  def self.parse(value)
    text = value.to_s.strip
    return nil if text.empty?

    if (m = text.match(/\A(?:(\d+):)?(\d{1,2}):([0-5]\d)\z/))
      hours, minutes, seconds = m[1].to_i, m[2].to_i, m[3].to_i
      return :invalid if m[1] && minutes > 59

      hours * 3600 + minutes * 60 + seconds
    elsif text.match?(/\A\d+\z/)
      text.to_i
    else
      :invalid
    end
  end

  # 80 → "1:20" · 3735 → "1:02:15" · nil → nil
  def self.to_label(seconds)
    return nil if seconds.nil?

    hours, rest      = seconds.to_i.divmod(3600)
    minutes, seconds = rest.divmod(60)
    hours.positive? ? "%d:%02d:%02d" % [hours, minutes, seconds] : "%d:%02d" % [minutes, seconds]
  end
end
