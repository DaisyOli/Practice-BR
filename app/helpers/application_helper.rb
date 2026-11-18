module ApplicationHelper
  COMPETENCY_META = {
    co: { abbr: 'CO', icon: '🎧', label: 'Compreensão Oral',    color: 'var(--sky)', bg: 'var(--sky-tint)', bar: 'var(--sky-bright)' },
    ce: { abbr: 'CE', icon: '📖', label: 'Compreensão Escrita', color: 'var(--amber-ink)', bg: 'var(--amber-tint)', bar: 'var(--amber)' },
    ee: { abbr: 'EE', icon: '✍️', label: 'Expressão Escrita',   color: 'var(--success-deep)', bg: 'var(--success-tint)', bar: 'var(--success)' },
  }.freeze

  CEFR_COLORS = {
    'A1' => { bg: 'var(--brand-tint)', text: 'var(--brand-deep)', border: 'var(--brand-bright)', bar: 'var(--brand-bright)', label: 'Iniciante' },
    'A2' => { bg: 'var(--info-tint)', text: 'var(--info-deep)', border: 'var(--info)', bar: 'var(--info)', label: 'Básico' },
    'B1' => { bg: 'var(--violet-tint)', text: 'var(--violet-deep)', border: 'var(--violet)', bar: 'var(--violet)', label: 'Intermediário' },
    'B2' => { bg: 'var(--warning-tint)', text: 'var(--warning-ink)', border: 'var(--warning)', bar: 'var(--warning)', label: 'Avançado' },
    'C1' => { bg: 'var(--neutral-tint)', text: 'var(--ink)', border: 'var(--neutral-ink)', bar: 'var(--neutral-ink)', label: 'Proficiente' },
  }.freeze

  PROFESSIONAL_COLORS = {
    'OPCO' => { bg: 'var(--info-tint)', text: 'var(--info)', border: 'var(--info-border)' },
    'eCPF' => { bg: 'var(--violet-tint)', text: 'var(--violet)', border: 'var(--violet-border)' },
  }.freeze

  def cefr_colors(level)
    CEFR_COLORS[level] || CEFR_COLORS['A1']
  end

  def format_training_duration(total_minutes)
    return "—" if total_minutes.nil? || total_minutes == 0
    h = total_minutes / 60
    m = total_minutes % 60
    h > 0 ? "#{h}h #{m.to_s.rjust(2, '0')}min" : "#{m}min"
  end

  def professional_badge_html(user)
    return '' if user.professional_type.blank?
    c = PROFESSIONAL_COLORS[user.professional_type] || { bg: 'var(--neutral-tint)', text: 'var(--neutral-ink)', border: 'var(--line)' }
    content_tag(:span, user.professional_type,
      style: "font-family:'DM Mono',monospace; font-size:0.68rem; font-weight:700; letter-spacing:0.04em; " \
             "background:#{c[:bg]}; color:#{c[:text]}; border:1.5px solid #{c[:border]}; " \
             "padding:2px 8px; border-radius:20px; flex-shrink:0;")
  end

  def activity_competencies(activity, open_ended_ids = Set.new, av_activity_ids = Set.new)
    comps = []
    has_av = activity.video_url.present? || av_activity_ids.include?(activity.id)
    comps << (has_av ? :co : :ce)
    comps << :ee if open_ended_ids.include?(activity.id)
    comps
  end

  # "~5 min · 4 exercícios" (ponto 2.2), para os lugares de uma linha só. Os
  # cartões com ícones usam students/_activity_size.
  def activity_size_text(activity)
    "~#{activity.estimated_minutes} min · #{pluralize(activity.exercise_count, 'exercício', plural: 'exercícios')}"
  end

  def activity_media_badge(activity)
    if activity.image_file.attached? || (activity.media_url.present? && !activity.media_url.match?(/youtube\.com|youtu\.be/))
      { icon: 'bi-image', label: 'Imagem' }
    elsif activity.video_url.present? || activity.video_file.attached?
      { icon: 'bi-play-circle', label: 'Vídeo' }
    elsif activity.audio_file.attached?
      { icon: 'bi-music-note-beamed', label: 'Áudio' }
    else
      { icon: 'bi-journal-text', label: 'Texto' }
    end
  end

  def activity_cover(activity)
    if activity.image_file.attached?
      { type: :image, url: rails_blob_path(activity.image_file, disposition: 'inline') }
    elsif activity.media_url.present? && !activity.media_url.match?(/youtube\.com|youtu\.be/)
      { type: :image, url: activity.media_url }
    elsif activity.video_url.present?
      yt = activity.video_url.match(/(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})/)
      yt ? { type: :image, url: "https://img.youtube.com/vi/#{yt[1]}/hqdefault.jpg" } : { type: :gradient, icon: 'bi-play-circle' }
    elsif activity.video_file.attached?
      { type: :gradient, icon: 'bi-play-circle' }
    elsif activity.audio_file.attached?
      { type: :gradient, icon: 'bi-music-note-beamed' }
    elsif activity.unsplash_cover_url.present?
      { type: :image, url: activity.unsplash_cover_url, credit: activity.unsplash_cover_credit }
    else
      { type: :gradient, icon: 'bi-journal-text' }
    end
  end
end
