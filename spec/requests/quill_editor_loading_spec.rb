require 'rails_helper'

# Regressão dupla, dos dois lados do mesmo erro.
#
# O editor de texto (Quill) era carregado por CDN dentro de um `content_for :head`
# das telas que usam o editor. Numa navegação do Turbo isso não funciona: o
# `mergeHead` do Turbo espera as folhas de estilo novas, mas anexa os <script>
# novos sem await. O <body> novo já rodava chamando `new Quill(...)` antes do
# arquivo terminar de baixar, dava ReferenceError, e o campo "Enunciado da
# Questão" simplesmente não aparecia — a professora não tinha onde escrever.
#
# A correção foi hospedar o Quill junto com o resto e carregá-lo no layout, onde
# a tag é idêntica entre páginas e o Turbo nem precisa recarregar. Isso também
# devolve a regra do RGPD que o layout documenta: nenhuma requisição a terceiro.
RSpec.describe "carregamento do editor de texto", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:teacher)  { create(:user, :teacher) }
  let(:activity) { create(:activity, teacher: teacher) }

  it "serve o Quill do próprio app, pelo layout" do
    sign_in teacher
    get activity_path(activity)

    head = response.body[/<head>.*?<\/head>/m]
    expect(head).to match(%r{<script src="/assets/quill\.min[^"]*\.js"})
  end

  it "não pede o editor a nenhum CDN" do
    sign_in teacher
    get activity_path(activity)

    expect(response.body).not_to include("cdn.quilljs.com")
  end

  # A regra vale para o app inteiro, não só para esta tela: o comentário no topo
  # do layout diz que nada carrega de terceiro, e foi exatamente uma tag que
  # sobrou numa view que quebrou o editor.
  it "nenhuma view carrega script ou folha de estilo de fora" do
    externas = Dir.glob(Rails.root.join("app/views/**/*.erb")).filter_map do |arquivo|
      conteudo = File.read(arquivo)
      tags = conteudo.scan(%r{<(?:script|link)[^>]*(?:src|href)="(https?://[^"]+)"}).flatten
      # O player embutido de vídeo é um <iframe> do YouTube/Vimeo, não entra aqui:
      # ele só existe quando a professora escolhe colar um link de vídeo.
      "#{arquivo.sub(Rails.root.to_s + '/', '')}: #{tags.join(', ')}" if tags.any?
    end

    expect(externas).to be_empty, "views carregando de fora:\n#{externas.join("\n")}"
  end
end
