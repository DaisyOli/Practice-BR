require 'rails_helper'

# Regressão: um Short do YouTube caía num `if` sem `else` e o partial não
# renderizava nada. A seção "VÍDEO" da atividade aparecia como uma caixa vazia,
# e a professora achava que o link tinha se perdido — ele estava salvo o tempo
# todo. A regra que este spec protege é: este partial nunca renderiza vazio.
RSpec.describe "activities/_video_embed", type: :view do
  def embed(url)
    render partial: "activities/video_embed", locals: { url: url, link_label: "Assistir vídeo" }
    rendered
  end

  ID = "dQw4w9WgXcQ".freeze

  describe "links do YouTube" do
    {
      "watch?v="            => "https://www.youtube.com/watch?v=#{ID}",
      "youtu.be"            => "https://youtu.be/#{ID}",
      "youtu.be com ?si="   => "https://youtu.be/#{ID}?si=abc123",
      "embed"               => "https://www.youtube.com/embed/#{ID}",
      "watch com &list="    => "https://www.youtube.com/watch?v=#{ID}&list=PLxyz",
      "watch com ?app= antes do v=" => "https://www.youtube.com/watch?app=desktop&v=#{ID}",
      "celular (m.youtube)" => "https://m.youtube.com/watch?v=#{ID}",
      "Short"               => "https://www.youtube.com/shorts/#{ID}",
      "Short com ?feature=" => "https://youtube.com/shorts/#{ID}?feature=share",
      "live"                => "https://www.youtube.com/live/#{ID}",
      "com espaço em volta"  => "  https://youtu.be/#{ID}  "
    }.each do |nome, url|
      it "monta o player para #{nome}" do
        expect(embed(url)).to include("https://www.youtube.com/embed/#{ID}")
      end
    end
  end

  describe "links do Vimeo" do
    it "monta o player" do
      expect(embed("https://vimeo.com/123456789")).to include("player.vimeo.com/video/123456789")
    end

    # Vídeo não listado: sem o hash em ?h= o player do Vimeo responde 404
    it "leva junto o hash do vídeo não listado" do
      expect(embed("https://vimeo.com/123456789/abc123")).to include("player.vimeo.com/video/123456789?h=abc123")
    end
  end

  # review_draft e resolve_quiz (a tela do aluno) renderizam sem link_label
  describe "sem o local link_label" do
    def embed_sem_label(url)
      render partial: "activities/video_embed", locals: { url: url }
      rendered
    end

    it "monta o player do mesmo jeito" do
      expect(embed_sem_label("https://www.youtube.com/shorts/#{ID}")).to include("youtube.com/embed/#{ID}")
    end

    it "e também avisa em vez de ficar vazio" do
      expect(embed_sem_label("https://www.youtube.com/@canal")).to include(I18n.t('activities.video_embed_failed'))
    end
  end

  it "toca arquivo de vídeo direto" do
    expect(embed("https://exemplo.com/aula.mp4")).to include("<video", "aula.mp4")
  end

  describe "quando não dá para montar o player" do
    [
      "https://www.youtube.com/@umcanalqualquer",
      "https://www.youtube.com/",
      "https://exemplo.com/pagina",
      ""
    ].each do |url|
      it "mostra aviso em vez de caixa vazia — #{url.presence || '(vazio)'}" do
        saida = embed(url)
        expect(saida.strip).not_to be_empty
        expect(saida).to include(I18n.t('activities.video_embed_failed'))
      end
    end

    it "deixa o link original clicável para a professora não achar que perdeu" do
      expect(embed("https://www.youtube.com/@umcanalqualquer"))
        .to include('href="https://www.youtube.com/@umcanalqualquer"')
    end
  end
end
