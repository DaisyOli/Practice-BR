# Practice · Proteção de Dados (RGPD + LGPD)

> **In English, in short.** This is the data-protection contract for the Practice
> apps. The controller is established in France, so the **GDPR** applies to every
> app in the franchise regardless of where users are (Art. 3(1)); Brazil's **LGPD**
> applies on top wherever there are Brazilian data subjects. The rules that keep
> this from regressing: no third-party CDNs (self-hosted fonts, icons and JS, which
> is what makes a cookie banner unnecessary); no personal data in production logs;
> AI grading receives the answer text only, never a name or an email; audio is
> deleted right after transcription; every new processor must be added to the
> policy table before shipping; and legal copy is written in French first. The
> privacy policy exists in three versions that are **not translations of each
> other** — FR and EN follow the GDPR, PT follows the LGPD, and they diverge on
> response deadlines, the list of data subject rights, the right to human review of
> an automated decision, and the age of a minor. Open items are listed at the
> bottom, under *Estado atual e pendências*.
>
> The rest of this document is in Portuguese, like the rest of this codebase.

Contrato de privacidade compartilhado pelos apps da franquia Practice
(**practice-br**, **practice-fr**, e os que vierem). Este arquivo é **portável**:
copie-o tal qual para cada app da franquia e ajuste só a seção
"[O que muda de app para app](#o-que-muda-de-app-para-app)".

Escrito em 2026-07-29, junto com a primeira rodada de adequação.

---

## Qual lei se aplica

Duas leis, e elas **se somam** — não é uma ou outra.

**RGPD (europeu).** Aplica-se pelo **Art. 3(1)**: o regulamento vale para o
tratamento feito no contexto das atividades de um estabelecimento na União
Europeia, *independentemente de onde estão os titulares*. A Practice é operada da
França (SIRET francês), então **o RGPD alcança todos os apps da franquia**, mesmo
os que não tenham um único usuário europeu. A autoridade de controle é a **CNIL**.

**LGPD (brasileira).** Aplica-se pelo **art. 3º** quando há titulares no Brasil —
alunos ou professores. A autoridade é a **ANPD**.

Consequência prática: **todo app da franquia precisa cumprir o RGPD**; os que
tiverem público brasileiro cumprem a LGPD também.

### Por que a política tem versões e não traduções

As duas leis se parecem (a LGPD foi desenhada olhando o RGPD), mas divergem em
pontos que aparecem no texto:

| | RGPD (versões FR e EN) | LGPD (versão PT) |
|---|---|---|
| Autoridade | CNIL | ANPD (e CNIL, por operarmos da França) |
| Prazo de resposta | um mês | **15 dias** (art. 19) |
| Lista de direitos | 5 itens | **9 itens** do art. 18 (inclui anonimização, bloqueio, saber com quem compartilhamos) |
| Decisão automatizada | indireto | **direito explícito de revisão** (art. 20) — é o que cobre a correção por IA |
| Criança | menor de 15 (idade digital na França) | **menor de 12**, com consentimento específico e em destaque (art. 14) |
| Terceiros | *sous-traitants* | **operadores** |
| Transferência internacional | garantias contratuais | art. 33, garantias contratuais |

Por isso **trocar de idioma na página troca de regime jurídico**. Nunca "traduza"
uma versão para criar outra.

---

## Regras de ouro

Estas são invariantes. Quebrar qualquer uma reabre um problema que já foi
resolvido.

### 1. Zero CDN no layout

Nenhuma tag `<link>` ou `<script>` apontando para fora do nosso domínio. Fontes,
ícones e bibliotecas são **auto-hospedados**.

O motivo: cada tag externa faz o navegador do aluno contatar um terceiro — e
entregar o IP dele — **antes de qualquer consentimento**. Carregar Google Fonts
por CDN já rendeu condenação na Alemanha e é ponto de atenção da CNIL.

Isso é o que dispensa o banner de cookies: sem tracker e sem CDN, só sobram
cookies estritamente necessários.

```
app/assets/fonts/                        ← .woff2 das fontes da franquia
app/assets/stylesheets/_fonts.scss       ← @font-face gerado
app/assets/stylesheets/vendor/           ← CSS de bibliotecas (bootstrap-icons…)
vendor/javascript/                       ← JS de bibliotecas
scripts/fetch_fonts.rb                   ← regenera as fontes
```

Para regerar as fontes (mudou peso, família, subset):

```bash
ruby scripts/fetch_fonts.rb   # baixa os .woff2 e reescreve _fonts.scss
```

Ao adicionar uma biblioteca nova: baixe o arquivo, guarde em `vendor/javascript/`
ou `app/assets/stylesheets/vendor/`, e confira o hash quando o CDN publicar um
`integrity`.

### 2. Nada de dado pessoal nos logs

- `log_level` de produção **nunca** em `debug` — em debug o Rails loga cada query
  com os valores, ou seja, email de aluno e o texto das respostas.
- Mesmo em `info` o Rails escreve `Parameters: {...}` de todo POST. Por isso
  `config/initializers/filter_parameter_logging.rb` filtra os parâmetros que
  carregam dado pessoal.

Cuidado com o nome do parâmetro: o casamento é **por conteúdo da chave**.
`:answers` não filtra um parâmetro chamado `answer`. Confira o nome real no
controller antes de confiar no filtro.

E cuidado maior: **`filter_parameters` só alcança parâmetros de requisição.**
Ele não sabe nada sobre `Rails.logger` escrito à mão. Isto continua indo inteiro
para o log, filtro ou não:

```ruby
Rails.logger.info "Aluno #{user.email} ativou assinatura"   # ❌
Rails.logger.info "Assinatura ativada · user ##{user.id}"   # ✅
```

Foi assim que emails de aluno seguiram nos logs por um tempo depois de o filtro
já estar no ar. **Em log, identifique pessoa por `id`** — serve igual para
depurar e não é dado identificável fora do nosso banco.

Para depurar um problema pontual em produção:

```bash
heroku config:set RAILS_LOG_LEVEL=debug -a <app>   # e volte pra info depois
```

### 3. Mandar para a IA só o mínimo

Os serviços de correção enviam **apenas o texto da resposta** e o critério de
avaliação. Nome e email do aluno não vão. Isso está descrito na política — se
mudar o payload, a política mente.

### 4. Áudio é descartável

A gravação serve só para gerar a transcrição e é apagada em seguida
(`purge_later` no `ensure` do job, para apagar também quando falha). Só o texto
fica.

### 5. Todo terceiro novo entra em três lugares

Adicionou Stripe, um serviço de email, um storage? **Antes** de ir para produção
ele vira:

1. uma linha em `_privacy_subprocessors.html.erb` — a tabela é um partial
   compartilhado pelas versões justamente para não desatualizar num idioma e não
   no outro;
2. uma linha na tabela de sous-traitants do `REGISTRE_DES_TRAITEMENTS.md`, e uma
   menção na fiche do tratamento que o usa;
3. uma linha na tabela de DPAs deste arquivo, com a cópia datada guardada.

Esquecer o item 2 é o mais fácil, porque o registre não aparece em lugar nenhum
do app — nada quebra, ele só fica mentindo.

### 6. Texto legal nasce em francês

Aviso de consentimento, política, mensagem sobre dados: escreva primeiro em
francês (é quem audita), depois derive as outras versões — lembrando que a
portuguesa segue a LGPD e não é tradução.

---

## Onde está cada coisa

```
docs/REGISTRE_DES_TRAITEMENTS.md              → registro do art. 30 (para a CNIL, não pro titular)
config/routes.rb                              → GET /confidentialite (pública)
app/controllers/home_controller.rb            → #privacy + escolha de idioma
app/views/home/privacy.html.erb               → casca: título, data, seletor
app/views/home/_privacy_fr.html.erb           → RGPD (versão de referência)
app/views/home/_privacy_en.html.erb           → RGPD
app/views/home/_privacy_pt.html.erb           → LGPD (não é tradução)
app/views/home/_privacy_subprocessors.html.erb → tabela compartilhada
app/views/shared/_footer.html.erb             → link global
```

Os direitos do titular que são exercíveis pela própria pessoa:

```
GET  /meus-dados            → data_exports#new       resumo legível (acesso)
GET  /meus-dados/download   → data_exports#download  JSON (portabilidade)
     app/services/data_export_service.rb             o que entra na exportação
GET  /excluir-conta         → account_deletions#new  confirmação
DELETE /users               → users/registrations#destroy  apaga + cancela Stripe
     app/services/account_deletion_service.rb        o COMO da exclusão (transação + Stripe)
```

**A exclusão tem um caminho só.** `AccountDeletionService` é usado tanto pelo
pedido da pessoa quanto pela retenção automática. Isso é de propósito: já
aconteceu de conta ser apagada sem cancelar a assinatura, e o cartão seguir sendo
cobrado de quem não tinha mais como entrar e cancelar. Duas cópias dessa lógica
significam essa correção existir num caminho e faltar no outro. **Não reimplemente
exclusão em lugar nenhum** — chame o serviço.

**Ao criar uma tabela que guarde dado ligado a uma pessoa, são três passos:**
`dependent: :destroy` na associação (senão a exclusão quebra por chave
estrangeira), inclusão no `DataExportService` (senão a exportação fica
incompleta) e a linha na política. A spec de cobertura em
`spec/requests/data_export_spec.rb` falha se o segundo for esquecido.

**A escolha do idioma acontece no servidor**, pelo `Accept-Language`, não em
JavaScript — o texto certo precisa estar no HTML para um auditor, um leitor de
tela ou um buscador. `?lang=fr|en|pt` força uma versão. A resposta manda
`Vary: Accept-Language` para nenhum cache servir a versão errada.

Para adicionar um idioma: crie `_privacy_<código>.html.erb`, acrescente o código
em `PRIVACY_LANGS` e o rótulo no seletor. O `hreflang` se atualiza sozinho.

---

## Como a retenção funciona

Guardar dado para sempre viola o art. 5.1.e do RGPD, e é o que a plataforma fazia
até 2026-07-31. Agora `AccountRetentionJob` roda todo dia às 3h30 e apaga conta
abandonada.

```
app/jobs/account_retention_job.rb        a varredura (avisa → espera → apaga)
app/models/user.rb                       os prazos e quem é candidato
app/mailers/retention_mailer.rb          o aviso, nos três idiomas
spec/jobs/account_retention_job_spec.rb  metade dos testes prova quem NÃO é apagado
```

| Situação | Prazo |
|---|---|
| Conta sem atividade | 3 anos depois da última tentativa de quiz |
| Trial que nunca converteu | 12 meses depois de `trial_expires_at` |
| Assinatura em curso (`active`, `canceling`, `past_due`) | não apaga — contrato em curso é base legal |
| Professora, admin | não apaga, nunca |

**"Última atividade" é a `quiz_attempts.created_at` mais recente, não o login.**
O `:trackable` do Devise não está ativado, mas essa nem é a razão principal:
login mede aba aberta, tentativa mede uso de verdade.

**Ninguém é apagado sem aviso.** O job manda um email 30 dias antes e só apaga
quando esse aviso tem 30 dias completos. Se a pessoa voltar a praticar no meio,
`retention_warning_sent_at` volta a `nil` e a contagem recomeça. São três estados,
não dois — mexer nisso sem entender isso apaga gente cedo demais.

**A armadilha que quase passou:** o papel `trial` não quer dizer "nunca
converteu". O aluno volta a ser `trial` quando cancela a assinatura, e o
`trial_expires_at` dele continua sendo o do teste original, de anos atrás. Usar só
o papel apagaria um ex-aluno pagante em 12 meses, pelo prazo de quem nunca pagou.
Daí `never_converted_trial?` olhar também o `stripe_customer_id`. Tem teste pra
isso.

**Ao mudar qualquer prazo, mude em três lugares:** as constantes no `User`, a
fiche 1 do `REGISTRE_DES_TRAITEMENTS.md` e a seção 7 das **três** versões da
política. Apagar num prazo diferente do que a política promete é pior do que não
apagar.

---

## Identificação legal

A seção 1 de **todas** as versões precisa trazer a identificação completa da
responsável pelo tratamento: nome, forma jurídica, endereço e SIRET. É o primeiro
item que uma auditoria confere, e sem endereço completo (com código postal e
comuna) ele não cumpre a função.

O texto vive nas views da política — `_privacy_fr`, `_privacy_en`, `_privacy_pt`,
seção 1. Está deliberadamente **só lá**, e não repetido neste documento: o
repositório é público, e não há razão para o endereço residencial aparecer em mais
lugares do que a lei exige. Ao alterar, altere nas três versões.

Contato: `contato@practicebr.com` (BR) · `contact@practicefr.com` (FR)

---

## O que muda de app para app

| | practice-br | practice-fr |
|---|---|---|
| Ensina | português | francês |
| Público | sobretudo francófonos (alunos majoritariamente franceses) | **brasileiro** (+ professores de FLE com CPF, no futuro) |
| Lei que manda | RGPD | RGPD **+ LGPD** |
| Versão PT | reserva (só vira obrigação se houver professor no Brasil) | **essencial** |
| Operadores | Heroku, Anthropic, OpenAI, Stripe, Resend, Cloudinary | Heroku, Anthropic, Resend |
| Tem áudio | sim (Whisper) | não |
| Tem pagamento | sim (Stripe) | não |
| Seção extra | — | formações financiadas (OPCO/CPF) |

Sobre a seção de formações financiadas: a plataforma **produz** a declaração de
assiduidade, mas **não envia nada** a organismo nenhum — quem entrega é o
professor, fora do app. O texto precisa dizer isso, e precisa ser relido quando o
fluxo for usado de verdade pela primeira vez.

---

## Contratos com os operadores (DPA)

O RGPD (art. 28) e a LGPD exigem contrato com quem trata dados em nosso nome. A
surpresa aqui é que, na maioria dos casos, **não há nada para assinar**: os DPAs
se incorporam automaticamente aos termos de serviço quando você usa o produto.
Não existe botão no painel.

O que a *accountability* pede não é a assinatura — é a **prova**. Guarde um PDF
datado da versão em vigor quando você conferiu, porque esses textos são
atualizados unilateralmente (o da Stripe mudou em 18/11/2025).

| Operador | DPA | Verificado |
|---|---|---|
| Stripe | Incorporado ao Services Agreement: *"forms part of the Agreement"*. Sem assinatura separada. [stripe.com/legal/dpa](https://stripe.com/legal/dpa) · subprocessadores em [/legal/service-providers](https://stripe.com/legal/service-providers) | 2026-07-30 ✅ |
| Anthropic | Incorporado por referência às Commercial Terms: *"processed in accordance with the Anthropic Data Processing Addendum, which is incorporated into these Terms by reference"*. [anthropic.com/legal/data-processing-addendum](https://www.anthropic.com/legal/data-processing-addendum) | 2026-07-30 ✅ |
| Resend | Vinculação automática, sem assinatura: *"This Addendum shall become legally binding upon Customer entering into the Agreement or upon execution of this Addendum."* Certificada no EU-US Data Privacy Framework, com SCCs de reserva. Versão de 2025-12-31. [resend.com/legal/dpa](https://resend.com/legal/dpa) · subprocessadores em [/legal/subprocessors](https://resend.com/legal/subprocessors) | 2026-07-31 ✅ |
| OpenAI | Incorporado por referência aos Business Terms do uso pago da API — mesma mecânica de Anthropic e Stripe, sem assinatura separada. Certificada no EU-US Data Privacy Framework (reconfirmado em junho/2026). [openai.com/policies/data-processing-addendum](https://openai.com/policies/data-processing-addendum/) | 2026-07-31 ✅ |
| Cloudinary | *"forms part of the Cloudinary Subscription Agreement"*, com as SCCs da Decisão (UE) 2021/914 incorporadas por referência. Versão de junho/2026. [cloudinary.com/gdpr/dpa](https://cloudinary.com/gdpr/dpa) (redireciona pro PDF datado) | 2026-07-31 ✅ |
| Heroku (Salesforce) | **Não existe DPA específico da Heroku** — a palavra é da própria Heroku: *"there is not a Heroku specific DPA (we have a DPA that covers all service offered by Salesforce, including Heroku)"*. O documento é o [DPA da Salesforce](https://www.salesforce.com/company/legal/agreements/) (revisão de abril/2026), que incorpora por referência as BCR de processador e as SCCs. **Falta confirmar se basta o aceite dos termos ou se pede contra-assinatura** — a Salesforce bloqueia leitura automatizada do PDF, então essa parte tem que ser olhada por gente. [Artigo da Heroku](https://help.heroku.com/B4E5QFQQ/where-do-i-get-copy-of-dpa-from-heroku) | 2026-07-31 ⚠️ parcial |

Ao adicionar um operador novo, este é o terceiro passo (depois de entrar na
tabela da política e no registro do art. 30): achar o DPA, salvar cópia datada,
anotar aqui.

**O que falta, e que só você pode fazer:** salvar o **PDF datado** de cada um dos
seis. A conferência acima é a leitura do texto em vigor hoje; a prova que a
*accountability* pede é a cópia. Todos os links levam ao PDF ou têm botão de
imprimir. E olhar o DPA da Salesforce com olho humano, pela razão da linha acima.

## Estado atual e pendências

Feito em 2026-07-29, nos dois apps:

- [x] Zero CDN (fontes, ícones e bibliotecas auto-hospedados)
- [x] Logs sem dado pessoal (`log_level` + `filter_parameters`)
- [x] Política pública, linkada no rodapé e nas telas de criação de conta

Pendente, em ordem de risco:

- [x] ~~**Exportação de dados**~~ — feita em 2026-07-30 no practice-br: `/meus-dados` mostra
      o resumo (direito de acesso) e `/meus-dados/download` entrega JSON (portabilidade).
      Uma spec de guarda-chuva quebra se alguém criar tabela com `user_id` e esquecer de
      incluir. **Falta portar pro practice-fr.**
- [x] ~~**Exclusão de conta de verdade**~~ — feito em 2026-07-30 no practice-br:
      `/excluir-conta` com confirmação, `Users::RegistrationsController` cancelando a
      assinatura **antes** de apagar, e abortando se o Stripe falhar. Professora não se
      auto-exclui (as atividades dela são conteúdo da plataforma, não dado pessoal).
      **Falta portar pro practice-fr** — lá não há Stripe, então é bem mais simples.
- [x] ~~**Política de retenção**~~ — feita em 2026-07-31. Prazos: conta sem atividade some
      depois de **3 anos**, trial que nunca converteu some **12 meses** depois de o teste
      expirar, peça contábil fica **10 anos** (obrigação legal, sobrevive ao pedido de
      exclusão). Assinatura em curso segura a conta. Ver a seção *Como a retenção funciona*.
      **Falta portar pro practice-fr.**
- [ ] **DPAs** — os seis conferidos em 2026-07-30/31: todos se incorporam automaticamente aos
      termos, **nada a assinar**. Falta (a) guardar a cópia datada de cada um, que é a prova
      que a *accountability* pede, e (b) olhar o da Salesforce/Heroku com olho humano — é o
      único cuja mecânica de aceite não deu para confirmar, porque a Salesforce bloqueia
      leitura automatizada. Ver a tabela acima.
- [ ] **Idade mínima** — nenhum dos apps pergunta idade
- [ ] **Detecção de incidente** — sem monitoramento de erro não há como notificar em 72h (RGPD) ou em prazo razoável (LGPD art. 48)
- [x] ~~**Registre des traitements (RGPD art. 30)**~~ — escrito em 2026-07-31, em francês, em
      `docs/REGISTRE_DES_TRAITEMENTS.md`. Oito tratamentos: contas, serviço pedagógico,
      correção por IA, transcrição de áudio, assinatura, comunicações, segurança/logs e
      pedidos de exercício de direitos. Serve também ao art. 37 da LGPD.
      É uma peça **separada** da política — a política é para o titular ler, o registre é para
      a CNIL pedir numa fiscalização — e **precisa continuar de pé**: quando mudar finalidade,
      operador ou prazo, ele muda junto. A isenção do art. 30(5) para organizações com menos
      de 250 pessoas não se aplica aqui, porque o tratamento é regular e não ocasional.

---

## Histórico

- **2026-07-31** — Escrito o `REGISTRE_DES_TRAITEMENTS.md` (art. 30), em francês.
  Montá-lo revelou que os prazos de conservação nunca tinham sido decididos — e a
  decisão virou código no mesmo dia: `AccountRetentionJob` apaga conta abandonada
  com aviso 30 dias antes, e a seção 7 das três versões da política passou a
  declarar os prazos. De quebra, a exclusão virou `AccountDeletionService`, para o
  pedido da pessoa e a purga automática não divergirem.
- **2026-07-30** — Direitos exercíveis pelo próprio aluno: `/meus-dados` (acesso e
  portabilidade) e `/excluir-conta` (exclusão real, com a assinatura cancelada na
  Stripe antes). DPAs de Stripe e Anthropic conferidos.
- **2026-07-29** — Primeira adequação. Removidos 5 CDNs do practice-br e 2 do
  practice-fr; `log_level` de produção do BR voltou de `debug` para `info`;
  criadas as políticas nos dois apps (FR/EN sob RGPD, PT sob LGPD). Descoberto e
  corrigido, de passagem: ícone `bi-align-left` inexistente no BR e remetente de
  email com domínio errado no FR.
