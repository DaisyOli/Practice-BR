require 'rails_helper'

# A transcrição copiada do YouTube (relato da Daisy, 18/11/2026): cada tempo
# vem grudado no texto do leitor de tela e na fala, e a geração em pílulas
# recusava a transcrição por "não ter tempos".
RSpec.describe VideoTranscript do
  # Copiado do print dela, letra por letra.
  let(:copia_do_youtube) do
    <<~TEXTO
      6:126 minutos e 12 segundoso orelhão continua sendo celebrado como esse exemplo perfeito
      6:216 minutos e 21 segundospessoas. E a história do orelhão deixa a gente com uma pulga atrás da orelha.
      6:296 minutos e 29 segundosum semáforo, talvez vha a pena olhar de novo.
    TEXTO
  end

  it "devolve cada tempo no começo da linha, sem o texto do leitor de tela" do
    expect(described_class.clean(copia_do_youtube)).to eq(<<~TEXTO.strip)
      6:12 o orelhão continua sendo celebrado como esse exemplo perfeito
      6:21 pessoas. E a história do orelhão deixa a gente com uma pulga atrás da orelha.
      6:29 um semáforo, talvez vha a pena olhar de novo.
    TEXTO
  end

  it "com a limpeza, os tempos passam a ser reconhecidos (antes não eram)" do
    expect(ActivityFromVideoService.timestamps?(copia_do_youtube)).to be(false)
    expect(ActivityFromVideoService.timestamps?(described_class.clean(copia_do_youtube))).to be(true)
  end

  it "separa os tempos mesmo quando a cópia vem numa linha só" do
    colada = "0:088 segundoscom o caixa do supermercado.  E cada vez menos 0:1212 segundosconversas longas"

    expect(described_class.clean(colada)).to eq("0:08 com o caixa do supermercado. E cada vez menos\n0:12 conversas longas")
  end

  it "entende horas, minuto no singular e o YouTube em francês, inglês e espanhol" do
    colada = "1:02:151 hora, 2 minutos e 15 segundosOlá 1:001 minutoTchau " \
             "0:055 secondesBonjour 2:022 minutes et 2 secondesSalut 0:077 secondsHi " \
             "3:153 minutes, 15 secondsHey 2:002 minutos y 3 segundosHola"

    expect(described_class.clean(colada).lines.map(&:strip)).to eq(
      ["1:02:15 Olá", "1:00 Tchau", "0:05 Bonjour", "2:02 Salut", "0:07 Hi", "3:15 Hey", "2:00 Hola"]
    )
  end

  it "tempo grudado na fala, sem o texto do leitor de tela" do
    expect(described_class.clean("0:05Olá, pessoal\n0:09hoje vamos")).to eq("0:05 Olá, pessoal\n0:09 hoje vamos")
  end

  it "não mexe numa transcrição que já veio certa" do
    certa = "0:05 Olá, pessoal\n1:23 hoje vamos falar de 2 minutos de receita"

    expect(described_class.clean(certa)).to eq(certa)
  end

  it "limpar duas vezes dá o mesmo resultado" do
    uma_vez = described_class.clean(copia_do_youtube)

    expect(described_class.clean(uma_vez)).to eq(uma_vez)
  end

  it "aceita vazio e nil" do
    expect(described_class.clean(nil)).to eq("")
    expect(described_class.clean("   ")).to eq("")
  end
end
