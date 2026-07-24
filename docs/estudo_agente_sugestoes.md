# 📚 Guia de estudo: o que faz de algo um "agente de IA" de verdade

*Documento de estudo para a Daisy — escrito em 2026-07-24, antes de reconstruir
"Sugestões do Dia" como um agente de verdade.*
*Companheiro do plano de implementação (ver conversa/plano aprovado).*

---

## Parte 1 — Os conceitos, um por um

### 1.1 O que NÃO é um agente

O `DailyVideoSuggestionsService` que já existe no seu código faz uma única
chamada para o Claude: manda um prompt, recebe um JSON, acabou. Isso é
apenas **usar uma IA** — não é um agente. É a diferença entre perguntar pra
alguém "me dá uma ideia" e contratar alguém pra investigar o problema,
decidir o que precisa saber, ir atrás dessa informação, e só então te dar
uma resposta fundamentada.

> 🧑‍🏫 Analogia de professora: pedir uma sugestão de aula pra um colega que
> só conhece o assunto de ouvido é uma coisa. Pedir pra um colega que primeiro
> abre o diário de classe, vê o que você já ensinou esse mês, confere as notas
> das últimas provas, e SÓ DEPOIS sugere a próxima aula — isso é outra coisa
> completamente diferente. O segundo colega é o "agente".

### 1.2 Tool use (uso de ferramentas) — o mecanismo central

É isso que separa "IA que responde" de "IA que investiga". Você dá ao Claude
uma lista de **ferramentas** (funções do seu próprio código, ex:
`buscar_temas_recentes`, `buscar_avaliacoes`) descritas em JSON. A cada
rodada, o Claude pode responder de duas formas:

1. "Quero chamar a ferramenta X com estes parâmetros" — seu código executa
   a função de verdade (uma query no banco, por exemplo) e devolve o
   resultado pro Claude.
2. "Já tenho o que preciso, aqui está minha resposta final."

Isso se repete em loop até o Claude decidir que já sabe o suficiente. O nome
técnico do padrão é **tool use** ou **function calling** — é a base de
praticamente todo "agente de IA" que existe hoje (incluindo o Claude Code que
está te ajudando agora: cada vez que eu leio um arquivo ou rodo um comando,
é exatamente esse mecanismo).

> 🧑‍🏫 Analogia de professora: é como dar pro estagiário um molho de chaves
> específicas (armário de notas, arquivo de planos de aula) em vez de contar
> pra ele tudo de cor antes de ele perguntar. Ele só abre o armário que
> precisa, quando precisa.

### 1.3 Grounding (aterramento em dados reais)

"Grounding" é o termo pra quando a resposta da IA é amarrada em dados reais
do seu sistema, em vez de vir só do conhecimento genérico do modelo. O seu
`AiActivityGenerationJob` já faz uma forma simples disso: ele busca os
últimos 20 títulos de atividade do professor e cola no prompt, dizendo "não
repita isso". É grounding rudimentar (dados colados manualmente no texto).

Com tool use, o grounding fica mais rico: em vez de você decidir de antemão
o que colar no prompt, o próprio Claude decide o que precisa consultar. Ele
pode, por exemplo, notar que já tem tema suficiente pro nível A1 e resolver
sozinho checar o B1 em vez disso.

### 1.4 O "loop agente" (ReAct: pensar → agir → observar)

O padrão mais comum tem esse nome estranho, ReAct (*reasoning + acting*), mas
a ideia é simples — o modelo alterna entre três passos:

1. **Pensar**: "o que eu sei, o que eu preciso descobrir?"
2. **Agir**: chamar uma ferramenta
3. **Observar**: ler o resultado e decidir se já basta ou se precisa de mais

Repete até ter confiança na resposta final. É exatamente esse loop que vamos
implementar no serviço novo.

### 1.5 Human-in-the-loop (seu app já faz isso!)

Você já usa esse conceito sem saber o nome: a IA gera um **rascunho**
(`draft: true`), e só vira atividade publicada quando você revisa e aprova.
Isso é "human-in-the-loop" — a IA propõe, o humano dispõe. É uma frase forte
pra entrevista: mostra que você pensa em confiabilidade, não só em automação
cega.

### 1.6 LLM-as-judge (pra guardar pro futuro)

Quando um segundo modelo (ou o mesmo modelo numa segunda passada) avalia o
que o primeiro gerou, chama-se "LLM como juiz". A versão mais robusta usa um
modelo de **fornecedor diferente** como juiz, porque um modelo tende a não
enxergar os próprios pontos cegos — é difícil ser crítico do seu próprio
trabalho. Essa é a peça que você decidiu adiar (ver a conversa de hoje) até
ter mais alunos pagantes e resolver prioridades de infra — mas agora você já
sabe o nome certo pra pesquisar quando for a hora.

---

## Parte 2 — Como isso se aplica ao seu código

| Conceito | Onde já existe (parcial) | O que vamos construir |
|---|---|---|
| Grounding simples | `AiActivityGenerationJob` (últimos 20 títulos colados no prompt) | Expandir pra avaliações e histórico completo |
| Rubrica de qualidade | `ActivityGenerationService::SYSTEM_PROMPT` | Reaproveitar 100% — não reinventar |
| Human-in-the-loop | `draft: true` + tela de revisão | Reaproveitar 100% |
| Tool use / loop agente | **Não existe ainda** | Construir do zero no novo serviço de sugestões |
| LLM-as-judge cross-provider | **Não existe, decidido adiar** | Guardado pra quando houver mais alunos pagantes |

O ponto central: seu agente de conteúdo (`ActivityGenerationService`) já é
ótimo em **escrever** uma atividade seguindo a rubrica. O que falta é um
agente que decida **o que** sugerir antes disso — e essa decisão é o
trabalho de investigação (tool use) que o serviço antigo de vídeo nunca fez.

---

## Vocabulário pra usar em entrevista ou post de LinkedIn

- **"Agentic AI" / "agente com tool use"** — não é só chamar uma API de IA,
  é dar ferramentas pro modelo investigar antes de responder.
- **"Grounding"** — fundamentar a resposta em dados reais do sistema, não só
  no conhecimento geral do modelo.
- **"ReAct loop"** — o padrão pensar → agir → observar que faz o agente
  decidir sozinho quantos passos de investigação precisa.
- **"Human-in-the-loop"** — a IA propõe, o humano decide o que publicar.
- **"LLM-as-judge"** — usar um segundo modelo pra revisar/criticar a saída
  do primeiro (você já registrou essa peça pro futuro).

Frase pronta pra usar depois que a feature estiver no ar: *"Construí um
agente que decide o que sugerir consultando o catálogo real de atividades,
as avaliações dos alunos e os erros mais comuns — não gera ideias no vácuo,
ele investiga antes de responder."*
