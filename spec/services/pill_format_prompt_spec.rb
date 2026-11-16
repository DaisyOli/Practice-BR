require 'rails_helper'

# O formato pílula (decidido em 15/11/2026) mora no texto dos prompts de geração.
# Estes testes só garantem que as regras não se percam numa edição futura —
# quem garante que a IA obedece é a revisão do rascunho.
RSpec.describe "Formato pílula nos prompts de geração" do
  let(:sistema) { ActivityGenerationService::SYSTEM_PROMPT }

  it "pede 3 a 5 exercícios fechados e um desafio de escrita no fim" do
    expect(sistema).to include("FORMATO PÍLULA")
    expect(sistema).to include("3 a 5 exercícios fechados")
    expect(sistema).to include("DESAFIO DE ESCRITA")
  end

  it "limita o texto por nível" do
    expect(sistema).to include("A1: 60 palavras · A2: 90 · B1: 130 · B2: 180")
  end

  # A geração de teste de 16/11 usou 4 tipos em 4 exercícios: a regra estava
  # só num item lá embaixo, fora do bloco da pílula.
  it "não pede mais variedade do que cabe numa pílula" do
    expect(sistema).not_to include("use pelo menos 3 tipos de exercício diferentes")
    expect(sistema).to include("2 ou 3 tipos de exercício fechado, nunca mais")
    expect(sistema).to include("3 a 5 exercícios fechados, de 2 ou 3 tipos")
  end

  it "não traz exemplo que contradiga o limite de lacunas" do
    expect(sistema).not_to include("Exemplo com 3 lacunas")
    expect(sistema).to include("na pílula, no máximo 2")
  end

  # Decisão da Daisy (16/11): na pílula, o verbo entre parênteses ajuda. O
  # prompt antigo proibia em três lugares e usava isso como "exemplo ruim".
  it "libera o verbo entre parênteses, sem regra antiga dizendo o contrário" do
    expect(sistema).to include("PISTA ENTRE PARÊNTESES — liberada na pílula")
    expect(sistema).not_to include("Não dê o verbo entre parênteses")
    expect(sistema).not_to include("Use pistas entre parênteses SOMENTE")
    expect(sistema).not_to include("Exemplo RUIM: \"Ana _____ ao mercado ontem.")
  end

  it "não manda misturar pontos gramaticais, porque a pílula tem um objetivo só" do
    expect(sistema).not_to include("Misture diferentes pontos gramaticais")
  end

  # Na mesma geração de teste, a descrição mandava assistir ao vídeo de um
  # cozinheiro que não existia: o pedido falava em "vídeo curto" como cena.
  it "só manda assistir ou ouvir quando o pedido traz a transcrição" do
    expect(sistema).to include('Escreva "assista" ou "ouça"')
    expect(sistema).to include("SOMENTE se o pedido trouxer a transcrição de um vídeo ou áudio de verdade")
  end

  it "o prompt do vídeo trabalha um trecho curto, não o vídeo inteiro" do
    prompt = ActivityFromVideoService.new(youtube_url: "https://youtu.be/abcdefghijk",
                                          transcript: "texto", teacher: nil).send(:build_prompt)

    expect(prompt).to include("de 1 a 3 minutos")
    expect(prompt).not_to include("entre 5 e 8 exercícios")
  end
end
