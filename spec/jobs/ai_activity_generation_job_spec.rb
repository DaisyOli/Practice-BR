require 'rails_helper'

RSpec.describe AiActivityGenerationJob, type: :job do
  let(:teacher) { create(:user, :teacher) }

  it "marca done e liga a activity quando o service tem sucesso" do
    generation = AiGeneration.create!(teacher: teacher, kind: "prompt", request_params: { "prompt" => "verbos" })
    activity = create(:activity, teacher: teacher)
    allow(ActivityGenerationService).to receive(:new)
      .with(prompt: "verbos", teacher: teacher)
      .and_return(instance_double(ActivityGenerationService, call: { success: true, activity: activity }))

    described_class.perform_now(generation.id)

    generation.reload
    expect(generation.status).to eq("done")
    expect(generation.activity).to eq(activity)
  end

  it "usa o service de vídeo para kind video" do
    generation = AiGeneration.create!(teacher: teacher, kind: "video", request_params: {
      "youtube_url" => "https://youtu.be/abc", "transcript" => "texto longo", "level_hint" => "B1"
    })
    service = instance_double(ActivityFromVideoService, call: { success: false, error: "transcrição ilegível" })
    allow(ActivityFromVideoService).to receive(:new)
      .with(youtube_url: "https://youtu.be/abc", transcript: "texto longo", teacher: teacher, level_hint: "B1")
      .and_return(service)

    described_class.perform_now(generation.id)

    generation.reload
    expect(generation.status).to eq("failed")
    expect(generation.error_message).to eq("transcrição ilegível")
  end

  it "kind agent escolhe o prompt do template e marca done" do
    generation = AiGeneration.create!(teacher: teacher, kind: "agent", request_params: { "level" => "A1" })
    activity = create(:activity, teacher: teacher)
    allow(ActivityPromptTemplates).to receive(:pick)
      .with("A1", existing_count: kind_of(Integer))
      .and_return("prompt do template A1")
    allow(ActivityGenerationService).to receive(:new)
      .with(prompt: a_string_including("prompt do template A1"), teacher: teacher)
      .and_return(instance_double(ActivityGenerationService, call: { success: true, activity: activity }))

    described_class.perform_now(generation.id)

    generation.reload
    expect(generation.status).to eq("done")
    expect(generation.activity).to eq(activity)
  end

  it "kind agent lista as atividades existentes do nível no prompt (anti-repetição)" do
    create(:activity, teacher: teacher, level: "A1", ai_generated: true, title: "Cafezinho no Balcão")
    generation = AiGeneration.create!(teacher: teacher, kind: "agent", request_params: { "level" => "A1" })
    activity = create(:activity, teacher: teacher)
    allow(ActivityPromptTemplates).to receive(:pick).and_return("prompt base")

    captured_prompt = nil
    allow(ActivityGenerationService).to receive(:new) do |prompt:, teacher:|
      captured_prompt = prompt
      instance_double(ActivityGenerationService, call: { success: true, activity: activity })
    end

    described_class.perform_now(generation.id)

    expect(captured_prompt).to include("prompt base")
    expect(captured_prompt).to include("DIFERENTE")
    expect(captured_prompt).to include("Cafezinho no Balcão")
  end

  it "erro inesperado vira failed com mensagem genérica" do
    generation = AiGeneration.create!(teacher: teacher, kind: "prompt", request_params: { "prompt" => "x" })
    allow(ActivityGenerationService).to receive(:new).and_raise(StandardError, "boom")

    described_class.perform_now(generation.id)

    expect(generation.reload.status).to eq("failed")
    expect(generation.error_message).to eq(I18n.t('ai.errors.generic'))
  end

  # Regressão: o GoodJob reencontra sozinho um job "running" cujo processo
  # morreu no meio (deploy, R12). Reprocessar do zero duplicaria a atividade
  # e gastaria a geração de IA de novo — precisa falhar limpo, sem chamar o
  # service de novo, pra professora só clicar em "tentar de novo".
  it "não reprocessa uma geração já 'running' (processo anterior derrubado no meio) e marca failed" do
    generation = AiGeneration.create!(teacher: teacher, kind: "prompt", request_params: { "prompt" => "verbos" },
                                       status: "running")
    expect(ActivityGenerationService).not_to receive(:new)

    described_class.perform_now(generation.id)

    generation.reload
    expect(generation.status).to eq("failed")
    expect(generation.error_message).to eq(I18n.t('ai.errors.interrupted'))
    expect(generation.activity).to be_nil
  end

  # Um rate limit temporário TAMBÉM deixa o status em "running" até o rescue
  # rodar — precisa voltar pra "queued" nesse caminho, senão a proteção acima
  # (contra processo derrubado) impediria o próprio retry_on de funcionar.
  it "erro temporário (rate limit) volta o status pra 'queued' e deixa o retry_on reagendar" do
    generation = AiGeneration.create!(teacher: teacher, kind: "prompt", request_params: { "prompt" => "verbos" })
    allow(ActivityGenerationService).to receive(:new).and_raise(
      Anthropic::Errors::RateLimitError.new(url: URI("https://api.anthropic.com/v1/messages"),
                                             status: 429, headers: {}, body: nil, request: nil, response: nil)
    )

    expect { described_class.perform_now(generation.id) }
      .to have_enqueued_job(described_class).with(generation.id)

    expect(generation.reload.status).to eq("queued")
  end

  it "depois do reset pra 'queued', a próxima tentativa roda normalmente (não trava como 'interrompida')" do
    generation = AiGeneration.create!(teacher: teacher, kind: "prompt", request_params: { "prompt" => "verbos" },
                                       status: "queued")
    activity = create(:activity, teacher: teacher)
    allow(ActivityGenerationService).to receive(:new)
      .and_return(instance_double(ActivityGenerationService, call: { success: true, activity: activity }))

    described_class.perform_now(generation.id)

    generation.reload
    expect(generation.status).to eq("done")
    expect(generation.activity).to eq(activity)
  end
end
