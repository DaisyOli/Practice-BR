# Procedimento de incidente de dados pessoais

> **Este documento existe para ser lido no pior dia.** Ele está em português
> porque quem executa é você, sob pressão. Os textos que **saem** daqui — a
> notificação à CNIL e o aviso às pessoas — estão prontos em francês no fim, para
> você não ter que redigir francês jurídico às 3 da manhã.
>
> Aplica-se aos dois apps da franquia. Ver `PROTECAO_DE_DADOS.md` e
> `REGISTRE_DES_TRAITEMENTS.md`.

---

## Cartão de emergência

Se algo aconteceu agora, faça nesta ordem e leia o resto depois.

1. **Contenha.** Corte o acesso, revogue a chave, tire a feature do ar. Sim, mesmo
   que derrube o app — um app fora do ar é um problema menor que um vazamento
   correndo.
2. **Não apague nada.** Logs, prints, emails: tudo é prova, e o art. 33(5) obriga a
   documentar. Não "limpe" nada para deixar bonito.
3. **Anote a hora.** Data e hora em que você teve certeza razoável de que houve
   violação. **É desse instante que os prazos contam**, não de quando terminou de
   consertar.
4. **Abra a seção [Prazos](#prazos---o-relógio)** e veja o que vence primeiro.

O prazo mais curto que te alcança é o **brasileiro: 3 dias úteis**. Não é o de 72
horas da CNIL, que é o mais famoso.

---

## O que é uma violação de dados pessoais

Não é "o app quebrou". É qualquer falha de segurança que leve a **destruição,
perda, alteração, divulgação ou acesso não autorizado** a dado pessoal — acidental
ou não. Os três tipos:

| Tipo | Exemplo no seu app |
|---|---|
| **Confidencialidade** | Um aluno consegue ver as respostas de outro |
| **Integridade** | Notas ou respostas alteradas por quem não devia |
| **Disponibilidade** | Banco perdido sem backup válido — perder dado também é violação |

### O que NÃO é violação

- Erro 500, exceção, bug que só quebra a tela
- Instabilidade curta, deploy com problema, app fora do ar por uma hora
- Tentativa de login que falhou, scanner batendo na porta, spam
- Um aluno esquecer a própria senha

**A dúvida honesta é sempre a mesma:** *algum dado pessoal saiu do lugar, sumiu ou
foi visto por quem não devia?* Se sim, é violação — mesmo que ninguém tenha agido
de má-fé, mesmo que tenha sido você mesma sem querer.

---

## Prazos — o relógio

O relógio **não** começa quando você desconfia. Começa quando você tem **certeza
razoável** de que houve violação envolvendo dado pessoal. Investigar um sinal
estranho por algumas horas antes de ter certeza é legítimo e esperado — o que não
pode é enrolar para não começar a contar.

| Para quem | Prazo | Contado de |
|---|---|---|
| **ANPD** (Brasil) | **3 dias úteis** | do conhecimento de que atingiu dado pessoal |
| **Titulares** (Brasil, LGPD) | **3 dias úteis** | idem |
| **CNIL** (França) | **72 horas** | idem |
| **Titulares** (RGPD, art. 34) | "sem demora injustificada" | só se houver **risco elevado** |

**O brasileiro vence primeiro** — 3 dias úteis pode ser menos que 72h se cair numa
sexta. Trabalhe com o prazo mais curto e você cumpre os dois.

> Existe um regime de prazo em dobro (6 dias úteis) para "agente de tratamento de
> pequeno porte" na Resolução CD/ANPD nº 2/2022. Você provavelmente se enquadra,
> **mas não conte com isso**: é regime pensado para agentes brasileiros, e apostar
> nele para ganhar 3 dias é o tipo de aposta que só se descobre errada depois.

**Notificação em fases é permitida, nos dois países.** Você pode registrar dentro do
prazo o que sabe — *"acesso indevido a aproximadamente X registros, investigação em
curso"* — e completar depois (a ANPD dá 20 dias úteis para complementar). **Nunca
perca o prazo esperando ter a resposta completa.** Incompleto no prazo é correto;
completo atrasado é infração.

---

## Fase 1 · Conter (primeira hora)

Objetivo: **parar o sangramento**, não entender o que houve.

- Chave ou credencial exposta → **revogue agora**, gere outra. Vale para
  `heroku config`, Stripe, Anthropic, OpenAI, Resend, Cloudinary, GitHub.
- Bug expondo dado de um aluno a outro → tire a rota do ar ou faça rollback do
  release. `heroku releases:rollback` é uma linha.
- Conta comprometida → troque a senha, ative 2FA, encerre as sessões ativas.
- Suspeita de acesso ao banco → troque as credenciais do Postgres (`heroku pg:credentials:rotate`).

Enquanto faz isso, **anote o que você fez e a que horas**. Isso vira o item
"medidas tomadas" da notificação, e é o que mostra que você agiu.

---

## Fase 2 · Avaliar

Responda estas cinco perguntas por escrito. Elas são exatamente o que as
autoridades pedem, então respondê-las já é metade da notificação.

1. **O que aconteceu?** Um parágrafo, sem jargão.
2. **Que dados?** Email, nome, nível, respostas de exercício, id de cliente
   Stripe... Seja específica. *(Senha não entra: o hash bcrypt não é legível.)*
3. **Quantas pessoas?** Número aproximado serve. Se não souber, estime e diga que é
   estimativa.
4. **Que consequência provável para elas?** Constrangimento? Fraude? Spam? Nenhuma
   consequência prática? Seja honesta nos dois sentidos — inflar também é errado.
5. **Desde quando e até quando** durou a exposição?

### Precisa notificar?

```
Houve violação de dado pessoal?
├── Não  → não notifica, mas REGISTRA (art. 33(5)). Anota e segue.
└── Sim  → ANPD e CNIL: notifique, salvo se for improvável que traga
           risco às pessoas. Na dúvida, notifique.
           │
           └── Há risco ELEVADO para as pessoas?
               ├── Não → autoridades só.
               └── Sim → avise TAMBÉM as pessoas afetadas, na língua delas.
```

**Regra prática:** notificar sem precisar não gera multa. Não notificar precisando,
gera. A assimetria é toda de um lado.

---

## Fase 3 · Notificar

**CNIL** — formulário em <https://notifications.cnil.fr/notifications/>. Só
controlador, e é online. Use o modelo em francês no fim deste documento.

**ANPD** — formulário de Comunicação de Incidente de Segurança (CIS), em
<https://www.gov.br/anpd/pt-br/canais_atendimento/agente-de-tratamento/comunicado-de-incidente-de-seguranca-cis>.

**Titulares** — email, na língua da pessoa (o `language` da conta). Em termos
simples, sem jurídiquês: o que houve, o que isso significa para ela, o que você
fez, e o que ela deve fazer (trocar senha, ficar atenta a email estranho). Modelo no
fim.

---

## Registro de violações (art. 33(5) do RGPD)

**Toda** violação entra aqui — inclusive as que você decidiu não notificar. Essa
obrigação não tem exceção, e a decisão de não notificar só se sustenta se estiver
escrita e fundamentada.

Crie uma entrada em `docs/incidentes/AAAA-MM-DD-descricao.md` com:

```markdown
# Incidente AAAA-MM-DD · [descrição curta]

- **Detectado em:** [data e hora, e como você descobriu]
- **Certeza razoável em:** [data e hora — é daqui que os prazos contam]
- **Natureza:** [confidencialidade | integridade | disponibilidade]
- **Dados atingidos:** [categorias]
- **Pessoas atingidas:** [número aproximado]
- **Causa:** [o que falhou]
- **Contenção:** [o que foi feito, a que horas]
- **Consequências prováveis:** [para as pessoas]
- **Notificado à CNIL?** [sim, em DD/MM às HH:MM | não, porque...]
- **Notificado à ANPD?** [idem]
- **Titulares avisados?** [idem]
- **Correção definitiva:** [commit, release]
- **O que muda para não repetir:** [teste, regra, processo]
```

A última linha é a que mais importa a longo prazo. Um incidente que não vira teste
volta.

---

## Cenários reais deste app

Não são hipóteses genéricas: são as formas pelas quais **este** app pode vazar
dado, em ordem de probabilidade.

### 1. Um aluno vê o dado de outro

O mais provável de todos, e o mais fácil de introduzir sem perceber — basta um
`find` sem escopo no lugar de um `current_user.quiz_attempts.find`.

**É violação de confidencialidade.** Avalie por quanto tempo esteve no ar e se
alguém de fato acessou (os logs do Heroku respondem). Se só existiu por 20 minutos
num deploy e ninguém bateu na rota, o risco é baixo — mas **registre** de todo
jeito.

*Prevenção que já existe:* as specs de `data_export` e de transcrição já testam
"não deixa um aluno ver o de outro". Ao criar rota nova com dado de aluno, copie
esse teste.

### 2. Credencial vazada

Chave de API num commit, `.env` num print de tela, `DATABASE_URL` colada num chat.
**Trate como violação sempre que a credencial dê acesso a dado pessoal** — e o
`DATABASE_URL` dá acesso a tudo.

Revogue primeiro, investigue depois. Chave da Anthropic ou da OpenAI vazada é
prejuízo financeiro; `DATABASE_URL` vazada é vazamento de todos os alunos.

### 3. Email para a pessoa errada

Um bug de mailer que manda a correção da Marie para o João. Parece pequeno e **é
violação** — dado pessoal entregue a quem não devia. Costuma ser de baixo risco e
não notificável, mas entra no registro.

### 4. Conta sua comprometida

GitHub, Heroku, Stripe, email. Aqui a violação é potencialmente total. 2FA em todas
é a defesa que evita a conversa inteira.

### 5. Perda de dados

Banco corrompido, backup que não restaura. **Perder é violação tanto quanto
vazar** — o RGPD trata perda de disponibilidade como violação. Vale testar a
restauração do backup uma vez, para descobrir num dia calmo se ela funciona.

### 6. Incidente num operador

Heroku, Anthropic, Stripe, Resend ou Cloudinary te avisa de um incidente deles. Eles
são operadores, **você continua sendo a controladora** — quem notifica a CNIL e a
ANPD é você. Guarde o comunicado que eles mandaram: ele é a sua prova de quando
você soube.

---

## Modelo · Notificação à CNIL (francês)

> Preencher os `[...]` e colar no formulário. Se um campo ainda não tem resposta,
> escreva *"en cours d'investigation"* — é melhor que atrasar.

```
Nature de la violation
[Décrire en quelques phrases : ce qui s'est passé, comment cela a été découvert,
la période pendant laquelle les données ont été exposées.]

Type de violation : [violation de confidentialité | d'intégrité | de disponibilité]

Catégories de personnes concernées
Élèves de la plateforme [et/ou professeurs].

Nombre approximatif de personnes concernées
Environ [N] personnes. [Préciser s'il s'agit d'une estimation.]

Catégories de données concernées
[Ex. : adresses email, prénoms, niveau de langue, réponses aux exercices.]
Les mots de passe ne sont pas concernés : ils ne sont conservés que sous forme de
hachage bcrypt et ne sont lisibles par personne.

Nombre approximatif d'enregistrements concernés
Environ [N] enregistrements.

Point de contact
Daisy Oliani, responsable du traitement — contato@practicebr.com
(aucun délégué à la protection des données n'est désigné, la désignation n'étant
pas obligatoire au sens de l'article 37.)

Conséquences probables
[Ex. : les données exposées ne comportent ni coordonnées bancaires ni données
sensibles au sens de l'article 9. Le risque principal est [...].]

Mesures prises ou envisagées
[Liste horodatée : ce qui a été fait pour contenir, corriger, et prévenir la
répétition. Ex. : « Le [date] à [heure], la fonctionnalité concernée a été retirée
de la production. Les identifiants ont été renouvelés le [date]. Un test
automatisé couvrant ce cas a été ajouté le [date]. »]

Mesures prises pour atténuer les conséquences pour les personnes
[Ex. : information des personnes concernées le [date] ; recommandation de changer
de mot de passe ; surveillance renforcée des accès pendant [durée].]
```

---

## Modelo · Aviso às pessoas (francês)

> Só quando houver **risco elevado** (RGPD art. 34) — mas a LGPD é mais exigente:
> se houver risco relevante, avise em 3 dias úteis. Na dúvida, avise.
>
> **Em termos simples, sem jurídiquês** — é uma exigência do art. 34, não um
> conselho de estilo.

```
Objet : Information importante concernant vos données sur Practice-BR

Bonjour,

Nous vous écrivons parce qu'un incident a touché vos données sur Practice-BR, et
nous préférons vous le dire directement.

Ce qui s'est passé
[Deux ou trois phrases, en langage courant. Ce qui a été exposé, quand, et pendant
combien de temps.]

Ce que cela signifie pour vous
[Concret. Ex. : « Votre adresse email et votre prénom ont pu être vus par une
autre personne inscrite sur la plateforme. Vos réponses aux exercices n'étaient
pas concernées. Aucune donnée bancaire n'est stockée sur nos serveurs. »]

Ce que nous avons fait
[Liste courte, avec les dates. Le fait d'avoir agi vite compte, et se dit.]

Ce que vous pouvez faire
[Si pertinent : changer de mot de passe, se méfier des emails inhabituels. S'il n'y
a rien à faire, dites-le — cela évite une inquiétude inutile.]

Nous restons à votre disposition à contato@practicebr.com pour toute question, et
vous pouvez à tout moment consulter ou télécharger vos données depuis la page
« Mes données » de votre compte.

Nous sommes sincèrement désolés.

Daisy Oliani
Practice-BR
```

**Versão portuguesa:** não é tradução. A LGPD (art. 48) exige comunicar ao titular
em prazo razoável — fixado em **3 dias úteis** pela Resolução CD/ANPD nº 15/2024 — e
o texto deve indicar que a **ANPD** é a autoridade, não a CNIL. O conteúdo mínimo é
o mesmo: o que houve, quais dados, riscos, e as medidas tomadas.

---

## Manutenção

- **Reler uma vez por ano**, ou depois de cada incidente real.
- **Reler quando entrar operador novo** — ele muda a lista de quem pode te avisar
  de um incidente que não é seu.
- Quando houver monitoramento de erro, acrescentar aqui **como o alerta chega** e
  quem olha. Hoje a detecção é manual, e este documento é o que existe no lugar da
  ferramenta.

O procedimento sozinho já vale: a maior parte dos erros graves em violação de dados
não é técnica, é de processo — perder o prazo, apagar prova, ou tentar redigir tudo
do zero no meio do pânico.
