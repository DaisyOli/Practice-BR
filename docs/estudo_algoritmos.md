# Estudo de algoritmos a partir deste app

Plano de estudo de algoritmos e estruturas de dados usando **o código deste
repositório** como material, em vez de exercícios abstratos.

A premissa: já existe raciocínio algorítmico neste app. O que falta é o
vocabulário formal para nomear, medir e comparar o que já está aqui. Cada
módulo pega um trecho real, dá o nome técnico ao que ele faz, e termina num
exercício que melhora o próprio app.

Ritmo sugerido: **um módulo por semana**, 2 a 3 sessões de 40 min. A ordem
importa — os módulos 1 e 2 sustentam o resto.

---

## Pré-requisito — Ler o próprio código

**Este módulo vem antes de tudo, e não tem nada de algoritmo.**

Boa parte deste app foi escrita em par com a IA e nunca foi lida de ponta a
ponta. Isso cria uma dependência que é o maior risco técnico do projeto: os
testes e o código têm o mesmo autor, então compartilham os mesmos pontos cegos.
Um teste escrito pela IA confirma que a IA fez o que ela achava que devia fazer
— não é revisão independente.

Prova concreta: `spec/models/sentence_ordering_spec.rb` tem 5 testes, e nenhum
cobre `process_words!`. Todos testam a *correção da resposta*; nenhum testa a
*geração do exercício*. O bug do módulo 1 mora exatamente nessa lacuna, e por
isso sobreviveu a 345 commits.

A habilidade a construir aqui não é escrever código. É **ler código que outra
pessoa escreveu e desconfiar dele**. É uma habilidade separada, e é a que
transforma "vibecoding" em engenharia.

**Método (o mesmo de compreensão leitora, que você já ensina):**

1. Escolha um arquivo pequeno do app. Comece por `app/models/sentence_ordering.rb`
   (55 linhas).
2. Leia sem pedir explicação para ninguém. Anote em português, linha por linha,
   o que você acha que cada trecho faz.
3. Marque com `?` tudo que você não entendeu — sem vergonha, o `?` é o dado
   mais útil da sessão.
4. Só então peça a correção da sua leitura. O objetivo não é a explicação: é
   descobrir **onde a sua leitura estava errada**, que é onde mora o aprendizado.

**Sequência sugerida, do menor para o maior:**

| # | Arquivo | Linhas | O que treina |
|---|---|---|---|
| 1 | `app/models/sentence_ordering.rb` | ~55 | callbacks, laços, o básico |
| 2 | `app/models/column_matching.rb` | ~40 | parsing de string, hash |
| 3 | `app/jobs/student_went_quiet_job.rb` | — | job, consulta, guarda |
| 4 | `app/services/student_dashboard_presenter.rb` | — | agregação, o padrão presenter |
| 5 | `app/models/user.rb` (só `current_streak` e vizinhos) | ~40 | a lógica mais densa do app |

**Critério de conclusão:** você consegue ler um arquivo novo do app e explicar
em voz alta o que ele faz, errando no máximo um ponto por arquivo.

**Não pule para o módulo 0 antes disto.** Big-O sobre código que você não lê é
vocabulário sem texto.

---

## Módulo 0 — Como se mede um algoritmo (Big-O)

**Código-fonte do estudo:** `app/models/user.rb` — `practice_days` e `current_streak`

Você já escreveu a versão otimizada sem saber o nome dela:

```ruby
def practice_days
  @practice_days ||= quiz_attempts
                     .pluck(:submitted_at, :created_at)
                     .map { |submitted, created| (submitted || created).in_time_zone.to_date }
                     .to_set
end
```

Duas decisões de complexidade num método de seis linhas:

1. **`.to_set`** — busca em `Set` é O(1) (tempo constante: não importa se tem
   10 ou 10.000 dias, a resposta sai no mesmo tempo). Em `Array` seria O(n)
   (varre a lista inteira). Como `current_streak` chama `days.include?` uma vez
   por dia do calendário, a diferença entre as duas versões é O(n) contra O(n²).
2. **`@... ||=`** (memoização) — calcula uma vez e reaproveita. Sem isso, cada
   chamada refaz a consulta ao banco.

**Conceitos a nomear:** O(1), O(n), O(n log n), O(n²). Notação assintótica. Por
que se ignora a constante. Custo amortizado.

**Exercício 0.1** — Troque `.to_set` por `.to_a` numa cópia do método, gere um
usuário com 2.000 dias de prática e meça os dois com `Benchmark.realtime`.
Escreva no seu caderno o número que saiu. Você nunca mais vai esquecer o que é O(n²).

**Exercício 0.2** — Qual é a complexidade de `current_streak` em função do
número de dias desde o primeiro treino? E se o aluno praticou 1 vez há 3 anos e
nunca mais? (Dica: olhe o `while cursor >= earliest`. Tem um problema aí.)

---

## Módulo 1 — Permutações, desarranjos, e um bug real

**Código-fonte do estudo:** `app/models/sentence_ordering.rb` — `process_words!`
e `app/models/column_matching.rb` — `shuffled_pairs`

Este módulo conserta um bug que está em produção agora.

```ruby
positions = (1..words.length).to_a.shuffle
```

`Array#shuffle` implementa **Fisher-Yates**, que sorteia uniformemente entre as
`n!` permutações possíveis. Uniformemente inclui a permutação identidade — a
que deixa tudo no lugar. Medido:

| Palavras na frase | Chance de sair já ordenada |
|---|---|
| 3 | 16,6% (1 em 6) |
| 4 | 4,2% |
| 5 | 0,9% |
| 8 | ~0% |

O mesmo vale para `column_matching`: a coluna da esquerda sai por
`.order(:position)` e a direita por `shuffled_pairs`. Se o sorteio devolver a
identidade, as duas colunas saem alinhadas e o exercício se responde sozinho.

O que se quer não é uma permutação qualquer, é um **desarranjo** (*derangement*):
permutação sem nenhum ponto fixo. O número de desarranjos de n elementos é
`D(n) ≈ n!/e`, o que dá um fato útil: sortear e rejeitar até dar certo custa em
média **e ≈ 2,7 tentativas**, independentemente de n. Para n pequeno, é a
solução mais simples e legível.

**Conceitos a nomear:** permutação, Fisher-Yates, ponto fixo, desarranjo,
algoritmo de Sattolo, amostragem por rejeição, valor esperado.

**Exercício 1.1** — Implemente `shuffled_positions(count)` que devolve um
desarranjo. Cuidado com o caso de borda: `sentence` valida `length: { minimum: 3 }`,
que são **3 caracteres, não 3 palavras** — então "Bonjour" é uma frase válida de
1 palavra, e desarranjo de 1 elemento não existe. Amostragem por rejeição sem
essa guarda é um laço infinito em produção.

```ruby
def shuffled_positions(count)
  return (1..count).to_a if count < 2

  base = (1..count).to_a
  loop do
    candidate = base.shuffle
    return candidate if candidate.each_with_index.none? { |p, i| p == i + 1 }
  end
end
```

**Exercício 1.2** — Faça o mesmo em `shuffled_pairs`, onde a comparação é contra
a ordem da coluna da esquerda.

**Exercício 1.3** — Escreva o spec que trava esse bug: rode o embaralhamento 500
vezes numa frase de 3 palavras e afirme que nenhuma saída é a identidade.

**Exercício 1.4** (teoria) — Implemente o algoritmo de Sattolo e explique por que
ele garante desarranjo em uma única passada, sem rejeição. Por que ele produz
menos desarranjos possíveis que a rejeição? (Resposta: Sattolo só gera
permutações cíclicas.) Isso importa aqui?

---

## Módulo 2 — Índices: a diferença entre procurar e consultar

**Código-fonte do estudo:** `app/models/sentence_ordering.rb` — `word_results`

```ruby
correct_order.each_with_index.map do |correct_word, index|
  given_id   = word_ids_in_order[index]
  given_word = given_id && words.find { |w| w.id == given_id.to_i }
  ...
end
```

Tem um `.find` (varredura linear, O(n)) **dentro** de um `.map` (O(n)). Isso é
O(n²) — o laço aninhado clássico.

A lição honesta deste módulo é dupla, e a segunda metade importa mais:

1. Dá para transformar em O(n) construindo um índice: `words.index_by(&:id)`,
   e trocar o `.find` por uma busca em Hash, O(1).
2. **Aqui não faz a menor diferença.** Uma frase tem 10 palavras. 10² = 100
   operações, em microssegundos. Trocar por causa da notação é otimização
   prematura.

Saber calcular O(n²) é metade da habilidade. A outra metade é saber que n é 10 e
seguir a vida. Quem só tem a primeira metade otimiza o que não importa e deixa
passar o que importa — que é o módulo 3.

**Conceitos a nomear:** varredura linear, tabela hash, função de hash, colisão,
índice, laço aninhado, otimização prematura, a diferença entre n pequeno e n grande.

**Exercício 2.1** — Reescreva `word_results` com `index_by`. Meça os dois com 10
palavras e depois com 10.000. Onde as curvas se cruzam?

**Exercício 2.2** — Explique por que `Hash` é O(1) em média mas O(n) no pior
caso. O que é preciso acontecer para cair no pior caso?

---

## Módulo 3 — Onde a complexidade realmente dói: o banco

**Código-fonte do estudo:** `app/services/activities_index_service.rb`

É aqui que Big-O sai do exercício e vira conta de Heroku. Três coisas concretas
neste arquivo:

**a) `includes(:activity_ratings)`** — resolve o problema N+1. Sem ele, listar 9
atividades faz 1 consulta para as atividades e mais 9 para as avaliações. Com
ele, 2 consultas. O padrão N+1 é a causa número um de lentidão em Rails.

**b) A busca por título:**

```ruby
activities.where("title ILIKE ?", "%#{@params[:search]}%")
```

Um índice B-tree (a estrutura padrão do Postgres) é uma **árvore ordenada**.
Ele serve para prefixo (`"abc%"`), porque sabe onde começar a descer na árvore.
Com `%` na frente, não há prefixo para procurar, e o Postgres **varre a tabela
inteira** — O(n) linha por linha. Hoje, com poucas atividades, é irrelevante.
Com 50.000, é meio segundo por tecla digitada.

A solução tem nome: índice **GIN com `pg_trgm`** (trigramas — quebra o texto em
pedaços de 3 letras e indexa os pedaços). Não é para fazer agora. É para saber
que existe e reconhecer o dia em que a busca ficar lenta.

**c) A ordenação por tentativas:**

```ruby
activities.left_joins(:quiz_attempts).group('activities.id').order('COUNT(quiz_attempts.id) DESC')
```

Agregação com `GROUP BY` + `ORDER BY COUNT`. O banco não consegue usar índice
para ordenar por uma coluna que ele mesmo calcula na hora — ele precisa agrupar
tudo primeiro e só depois ordenar. Isso é O(n log n) sobre o total de tentativas.

**Conceitos a nomear:** N+1, índice B-tree, varredura sequencial (*seq scan*),
seletividade, `EXPLAIN ANALYZE`, índice GIN, trigrama, agregação, custo de `ORDER BY`.

**Exercício 3.1** — Rode `EXPLAIN ANALYZE` nas três consultas acima no seu
Postgres local. Aprenda a ler duas linhas: `Seq Scan` versus `Index Scan`. Esta é
a ferramenta de diagnóstico mais útil deste plano inteiro.

**Exercício 3.2** — Rode o app local com `ActiveRecord::Base.logger` no console e
conte as consultas ao abrir a lista de atividades em modo grid. Bate com o que
você esperava?

---

## Módulo 4 — Algoritmos gulosos (greedy)

**Código-fonte do estudo:** `app/models/user.rb` — `current_streak`

```ruby
shields = Hash.new(0)
while cursor >= earliest
  if days.include?(cursor)
    streak += 1
  else
    week = cursor.strftime('%G-%V')
    break if shields[week] >= STREAK_SHIELDS_PER_WEEK
    shields[week] += 1
  end
  cursor -= 1
end
```

Isto é um **algoritmo guloso com orçamento**: caminha para trás e gasta o escudo
da semana assim que encontra uma falta, sem nunca reconsiderar. Gastar o escudo
na primeira falta que aparece é sempre a melhor jogada? Aqui sim, e vale a pena
saber demonstrar por quê — é o tipo de argumento ("propriedade da escolha
gulosa") que aparece em entrevista.

**Conceitos a nomear:** algoritmo guloso, propriedade da escolha gulosa,
subestrutura ótima, quando guloso falha e é preciso programação dinâmica,
invariante de laço.

**Exercício 4.1** — Enuncie a invariante do laço: o que é sempre verdade sobre
`streak` e `shields` no início de cada volta?

**Exercício 4.2** — Mude a regra para "2 escudos por mês" em vez de "1 por
semana". O guloso continua ótimo? Construa um contraexemplo ou argumente que não
existe.

**Exercício 4.3** — O laço vai até `earliest`, que pode ser anos atrás, mesmo
depois de a ofensiva já ter sido quebrada. Reescreva para parar cedo. Qual a
complexidade antes e depois?

---

## Módulo 5 — O inventário formal

Fechar as lacunas de vocabulário, cada uma ancorada em algo que já existe aqui.

| Estrutura | Onde já aparece no app | O que estudar |
|---|---|---|
| Array | qualquer `.to_a` | acesso O(1), inserção no meio O(n) |
| Hash / Set | `practice_days`, `shields` | hashing, colisão, O(1) médio |
| Fila (queue) | jobs do GoodJob | FIFO, produtor/consumidor |
| Pilha (stack) | a call stack de qualquer erro | LIFO, recursão |
| Árvore | índice B-tree do Postgres, o DOM | altura, balanceamento, O(log n) |
| Grafo | `activity → questions → attempts` | busca em largura e profundidade |

**Conceitos que faltam e não têm âncora no app** (estes vão ter que ser
abstratos mesmo — são os que caem em entrevista): ordenação (merge sort, quick
sort), busca binária, recursão e memoização, programação dinâmica, filas de
prioridade.

**Exercício 5.1** — Implemente busca binária do zero, sem consultar nada. Depois
descubra os dois bugs clássicos que quase todo mundo comete na primeira vez
(o cálculo do meio e a condição de parada).

---

## Como estudar isto

**Faça:** o exercício antes de ler a resposta; um módulo por semana sem pular;
anote em português o que entendeu, com suas palavras. Todo exercício deste plano
que muda código merece um spec — você já tem 63 arquivos de spec, o hábito existe.

**Não faça:** LeetCode antes do módulo 5. Sem o vocabulário, é decoreba e
frustração. Depois do módulo 5, aí sim, e vira só treino de aplicar o que você
já entende.

**Material de apoio:** *Grokking Algorithms* (Aditya Bhargava) — ilustrado,
curto, feito para quem programa mas não estudou CS. É o único livro necessário
para os módulos 0 a 5.

---

## O que já foi feito

- [ ] Pré-requisito — Ler o próprio código **(começa aqui)**
- [ ] Módulo 0 — Big-O
- [ ] Módulo 1 — Permutações e desarranjos **(conserta bug em produção)**
- [ ] Módulo 2 — Índices e hash
- [ ] Módulo 3 — Complexidade no banco
- [ ] Módulo 4 — Algoritmos gulosos
- [ ] Módulo 5 — Inventário formal
