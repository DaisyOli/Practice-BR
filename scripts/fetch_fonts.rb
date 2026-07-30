#!/usr/bin/env ruby
# Baixa as fontes do Google e gera o @font-face local.
require "net/http"
require "uri"
require "fileutils"

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
FONT_DIR = "/home/daisyoli/code/exercise_app/app/assets/fonts"
CSS_OUT  = "/home/daisyoli/code/exercise_app/app/assets/stylesheets/_fonts.scss"
KEEP_SUBSETS = %w[latin latin-ext].freeze

URL = "https://fonts.googleapis.com/css2?family=Raleway:wght@400;500;600;700;800&family=Plus+Jakarta+Sans:wght@400;500;600;700&family=DM+Mono:wght@400;500&display=swap"

def get(url, ua: nil)
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = ua if ua
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  raise "HTTP #{res.code} em #{url}" unless res.code == "200"
  res.body
end

FileUtils.mkdir_p(FONT_DIR)
css = get(URL, ua: UA)

# A CSS do Google vem como: /* subset */\n@font-face { ... }
blocks = css.scan(%r{/\*\s*([\w-]+)\s*\*/\s*(@font-face\s*\{.*?\})}m)
raise "Nada casou — formato da CSS mudou?" if blocks.empty?

out = []
out << "// Fontes auto-hospedadas (Raleway, Plus Jakarta Sans, DM Mono)."
out << "// Geradas a partir da API do Google Fonts, mas servidas do nosso domínio:"
out << "// carregar do fonts.gstatic.com envia o IP do visitante pro Google sem consentimento."
out << "// Para atualizar, rode scripts/fetch_fonts.rb."
out << ""

downloaded = 0
blocks.each do |subset, block|
  next unless KEEP_SUBSETS.include?(subset)

  remote = block[/src:\s*url\((https:\/\/[^)]+)\)/, 1]
  next unless remote

  family = block[/font-family:\s*'([^']+)'/, 1]
  weight = block[/font-weight:\s*(\d+)/, 1]
  style  = block[/font-style:\s*(\w+)/, 1] || "normal"

  filename = "#{family.downcase.gsub(/\s+/, '-')}-#{weight}-#{subset}.woff2"
  File.binwrite(File.join(FONT_DIR, filename), get(remote))
  downloaded += 1

  local_block = block.sub(/src:\s*url\(https:\/\/[^)]+\)/, %[src: font-url("#{filename}")])
  out << "/* #{family} #{weight} #{style} — #{subset} */"
  out << local_block
  out << ""
end

File.write(CSS_OUT, out.join("\n"))
puts "#{downloaded} arquivos .woff2 baixados em #{FONT_DIR}"
puts "CSS gerada em #{CSS_OUT}"
