# 📚 Guia de estudo: tirar dado de dentro do código

Feito em 11/08/2026, junto com a tela "A voz das IAs".

Este documento sai de uma feature real do seu app: os prompts das IAs deixaram de
ser constantes Ruby e viraram texto editável pela tela. É a segunda vez que a
gente faz esse movimento — a primeira foi a meta do agente, no dia anterior — e é
por isso que dá pra tirar um padrão dele, e não só um caso.

---

## Parte 1 — O padrão: constante → dado

### 1.1 O sintoma que denuncia

Sempre que você precisa de um **deploy para mudar uma decisão**, e não para mudar
um comportamento, tem uma constante querendo virar dado.

Repare na diferença:

| | |
|---|---|
| "quero que o botão fique verde" | mudança de comportamento → deploy é o certo |
| "quero que o A1 ganhe nota mais alta" | mudança de **decisão** → deploy é sintoma |

A segunda é uma opinião pedagógica sua, que muda com o que você observa nos
alunos. Ela não deveria passar por PR nenhum.

### 1.2 As quatro peças

Todo movimento desses tem as mesmas quatro peças:

```
1. o padrão      → fica no código, como constante
2. a tabela      → guarda só o que foi REESCRITO
3. o leitor      → devolve o reescrito, e cai no padrão quando não há
4. o validador   → impede que a reescrita quebre quem depende dela
```

No seu app:

| peça | meta do agente (ontem) | prompts das IAs (hoje) |
|---|---|---|
| padrão | `TARGET` no controller | `SYSTEM_PROMPT` nos serviços |
| tabela | `content_targets` | `ai_prompts` |
| leitor | `ContentTarget.goals` | `AiPrompt.body_for` |
| validador | `goal > 0` | marcadores de contrato |

### 1.3 Semear ou não semear

Aqui as duas features **divergem de propósito**, e a diferença ensina.

A migration do `ContentTarget` **semeia**: ela insere A1 30, A2 30, B1 30, B2 20.
Precisava, porque sem linha na tabela não existiria meta nenhuma e a tela abriria
vazia — o padrão não tinha onde morar a não ser no banco.

A migration do `AiPrompt` **não semeia nada**. Ela cria duas tabelas vazias e
acabou. Porque aqui o padrão continua morando no código, e o leitor sabe cair
nele.

Três coisas que isso compra:

1. o deploy não muda uma vírgula, sem precisar copiar 282 linhas de prompt para
   dentro de um `INSERT`;
2. prompt que você nunca editou **continua acompanhando o código** — se a gente
   melhorar o texto num commit futuro, você recebe a melhoria;
3. apagar a linha é o botão de "voltar ao original de fábrica", de graça.

> **A pergunta que decide:** o padrão consegue viver no código? Se sim, não
> semeie. Se o padrão só faz sentido como dado (uma meta, um preço), semeie.

---

## Parte 2 — A armadilha da interpolação

Esta parte é a mais técnica do documento, e é a que eu mais quero que você leia,
porque foi um bug de verdade evitado por pouco.

### 2.1 O problema

Dois prompts têm buracos a preencher. O da correção precisava encaixar a régua do
nível do aluno:

```ruby
<<~PROMPT
  Você é um avaliador...

  #{expectations}      ← o buraco
  Regras gerais:
PROMPT
```

Aquele `#{}` é **interpolação de Ruby**, e ela acontece quando o arquivo `.rb` é
lido. Um texto que vem do banco nunca passa por lá: ele chega como string comum,
e `#{expectations}` seria só... o texto literal `#{expectations}`.

### 2.2 A solução óbvia, e por que ela explode

Ruby tem a ferramenta pronta para isso — `format` com `%{}`:

```ruby
format("Olá, %{nome}!", nome: "Daisy")   # => "Olá, Daisy!"
```

Então bastaria trocar `#{expectations}` por `%{expectations}` e chamar `format`.

**E o app quebraria**, por causa de uma frase que está no seu prompt de correção:

> "(um 70 vale 70% da questão, não é 'aprovado')"

Aquele `%` solto, seguido de espaço, o `format` tenta ler como início de uma
instrução de formatação. Resultado: `ArgumentError`, e a correção de todo aluno
morre.

Dava pra escapar, escrevendo `70%%`. Mas repare no que isso significa: **você
passaria a ter que escrever `%%` toda vez que quisesse dizer "por cento"** numa
caixa de texto onde você só quer escrever português. Uma regra de sintaxe
vazando para quem não deveria nem saber que existe sintaxe ali.

### 2.3 A saída

Substituição explícita, com um marcador que ninguém digita por acidente:

```ruby
texto.gsub("{{expectations}}", regua_do_nivel)
```

Nada a escapar, nada a explicar, e o `%` volta a ser só um `%`.

> **A lição maior:** quando a ferramenta pronta obriga o *usuário* a conhecer a
> sintaxe dela, ela é a ferramenta errada. Escreva as três linhas à mão.

O teste que trava isso está em `spec/models/ai_prompt_spec.rb`, e ele falha de
propósito se alguém trocar o `gsub` por `format`:

```ruby
it "não quebra com o '%' que existe no texto da correção" do
  expect(AiGradingService::SYSTEM_FRAME).to include("70%")
  expect { AiPrompt.render("ai_grading.system", expectations: "...") }.not_to raise_error
end
```

---

## Parte 3 — Contrato de máquina dentro de texto humano

### 3.1 O achado

Investigando pra fazer esta feature, apareceu uma coisa que muda o desenho todo:
**todo prompt do seu app carrega um contrato de máquina escrito dentro do texto.**

| prompt | o que o código depende |
|---|---|
| geração | o `SCHEMA DO JSON` — o `build_activity` lê `title`, `description`, `level`, `exercises`, `type` |
| correção | a última linha, `{"score": ..., "feedback": ...}` |
| agente do dia | a menção a `propose_suggestion`, a ferramenta que ele precisa chamar |

Apagar a última linha do prompt de correção não dá erro nenhum na hora. Dá erro
**na próxima resposta de aluno**: o `JSON.parse` levanta exceção, e ele vê
"formato inválido" no lugar da nota.

### 3.2 Por que isso é um conceito, e não um detalhe

Isso tem nome fora do seu app: é a diferença entre **conteúdo** e **contrato**.

O texto de um prompt parece 100% conteúdo — é português, é opinião pedagógica, é
seu. Mas alguns pedaços dele são, na verdade, uma API: um acordo entre dois
programas sobre o formato da conversa.

Uma caixa de texto que deixa você editar as duas coisas sem distinguir uma da
outra é uma armadilha educada.

### 3.3 O que a tela faz com isso

Duas defesas, e nenhuma delas impede você de reescrever:

1. **Mostra** os marcadores obrigatórios num quadro azul acima do editor, antes
   de você começar.
2. **Recusa** o save que apagou algum, com o motivo em português — e devolve o
   texto que você escreveu, sem perder a reescrita.

O que ela **não** faz: limitar o que você escreve à volta deles. A régua de cada
nível não tem marcador nenhum, porque nenhuma palavra dela é lida por código —
ali você é livre.

---

## Parte 4 — O front

### 4.1 O `disconnect()` que não é enfeite

O `prompt_editor_controller.js` registra um aviso de "você tem alterações não
salvas" ao sair da página:

```js
connect() {
  window.addEventListener("beforeunload", this.guard)
}

disconnect() {
  window.removeEventListener("beforeunload", this.guard)
}
```

O `disconnect()` parece opcional. Não é — e você já foi mordida por essa família
de bug.

O Turbo troca a página **sem recarregar o navegador**. Sem o `removeEventListener`,
o aviso registrado nesta tela sobreviveria à navegação e passaria a barrar a saída
de *outras* telas, sem ninguém entender por quê. É primo direto do bug que deixou
o toast do seu app mudo por um mês: lá o problema era um evento disparado antes
do ouvinte existir; aqui seria um ouvinte que existe depois da tela morrer.

> Regra: **todo `addEventListener` no `connect()` pede um `removeEventListener`
> no `disconnect()`.** Sempre. Sem exceção.

### 4.2 O detalhe do ponto na URL

A chave de um prompt é `ai_grading.expectations.A1`. Numa rota Rails, o ponto é
lido como separador de formato — `.json`, `.html`. Sem tratamento, o Rails leria
`.A1` como "formato A1" e a chave chegaria truncada.

```ruby
resources :ai_prompts, param: :key, constraints: { key: %r{[^/]+} }
```

A constraint diz "engula tudo menos a barra". O spec da tela usa justamente uma
chave com pontos, de propósito — se alguém remover a constraint, é ele que cai.

---

## Parte 5 — Como estudar isto

Na ordem, e sem pressa:

1. **`db/migrate/20260811120000_create_ai_prompts.rb`** — comece pela migration
   que não semeia, e leia o comentário do porquê.
2. **`app/models/ai_prompt.rb`** — o `body_for` (três linhas, o coração) e o
   `render`. Pule o registro na primeira leitura.
3. **`spec/models/ai_prompt_spec.rb`, bloco "o chão"** — o teste que prova que
   não existe estado sem prompt.
4. **`app/javascript/controllers/prompt_editor_controller.js`** — é curto, e o
   `disconnect()` vale por si.

## O que fica em aberto

- **O botão de testar** não entrou nesta versão. A ideia era rodar o prompt novo
  contra respostas reais e comparar as distribuições antes de salvar; você achou
  que não valia o esforço agora. Fica anotado porque a medição de 11/08 mostrou
  que ajustar régua no escuro tem limite: o conserto de julho subiu a média de 60
  para 79 e mesmo assim a reclamação voltou.
- **Trocar de modelo pela tela** (Opus ↔ Haiku) ficou de fora de propósito:
  mudaria o custo por aluno, e isso não é decisão de caixa de texto.
