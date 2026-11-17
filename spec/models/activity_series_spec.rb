require 'rails_helper'

# Pílulas em série (ponto 1.4, 17/11/2026).
RSpec.describe Activity, "série de pílulas" do
  let(:original) { create(:activity, :B1, draft: false) }

  def parte(posicao, draft: false)
    create(:activity, :B1, draft: draft, pill: true, source_activity: original, series_position: posicao)
  end

  it "numera as partes publicadas" do
    p1, p2, p3 = parte(1), parte(2), parte(3)

    expect(p1.series_label).to eq("Parte 1 de 3")
    expect(p3.series_label).to eq("Parte 3 de 3")
    expect(p2).to be_series
  end

  it "parte em rascunho não conta para o aluno, mas conta para a professora" do
    p1 = parte(1)
    parte(2, draft: true)

    expect(p1.series_label).to be_nil # só uma publicada: nada de "Parte 1 de 1"
    expect(p1.series_label(published_only: false)).to eq("Parte 1 de 2")
  end

  it "parte descartada não deixa buraco na conta" do
    parte(1)
    p3 = parte(3) # a 2 foi descartada na revisão

    expect(p3.series_label).to eq("Parte 2 de 2")
  end

  it "fora de série não tem rótulo" do
    expect(original).not_to be_series
    expect(original.series_label).to be_nil
  end

  it "apagar a original não apaga as pílulas, só desfaz o vínculo" do
    p1 = parte(1)
    original.destroy!

    expect(p1.reload.source_activity_id).to be_nil
  end
end
