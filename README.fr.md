### [Practice BR](https://github.com/DaisyOli/Practice-BR)

[![English](https://img.shields.io/badge/English-8B949E)](README.md) [![Français](https://img.shields.io/badge/Fran%C3%A7ais-0969DA)](README.fr.md)

[![CI](https://github.com/DaisyOli/practice-br/actions/workflows/ci.yml/badge.svg)](https://github.com/DaisyOli/practice-br/actions/workflows/ci.yml)

Une plateforme propulsée par l'IA où des professeurs de portugais créent des exercices interactifs, et où les élèves s'entraînent avec un retour instantané et personnalisé. Pensée aussi pour la formation professionnelle : les élèves financés via OPCO / CPF bénéficient d'heures de pratique mesurées et d'attestations de formation imprimables.

En bêta privée sur [app.practicebr.com](https://app.practicebr.com), testée par de vrais professeurs et élèves. Conçue et déployée en solo — du premier commit à la mise en production sur Heroku — comme premier projet Rails après le bootcamp Le Wagon, et qui a largement dépassé ce point de départ depuis.

---

## Fonctionnalités

**Pour les professeurs :**
- Créez des activités en quelques minutes — ou laissez l'IA faire le gros du travail :
  - **Générez une activité complète à partir d'un prompt** (énoncé, explication et questions), propulsé par Claude — exécuté en tâche de fond avec un écran d'attente animé, pour que le professeur ne reste jamais bloqué sur une requête en cours
  - **Générez une activité à partir d'une vidéo YouTube** : la transcription est récupérée et transformée en questions de compréhension
- Six types d'exercices : choix multiple, texte à trous, question ouverte, remise en ordre de phrases, remise en ordre de paragraphes et appariement de colonnes
- Relisez les brouillons générés par l'IA avant publication — l'IA propose, le professeur dispose
- Invitez des élèves par email — chaque élève est rattaché à son professeur
- Tableau de bord avec répartition par niveau (CECR A1–C1) et par compétence, corrections en attente et activité des élèves

**Pour les élèves :**
- Des activités filtrées par niveau et par compétence — compréhension orale (CO), compréhension écrite (CE) et expression écrite (EE)
- Correction instantanée avec retour question par question ; les propositions à choix multiple sont mélangées à chaque tentative pour éviter le biais de position
- **Réponses ouvertes corrigées par l'IA**, avec un retour constructif rédigé en portugais — le niveau d'exigence de la correction suit le niveau CECR, indulgent en A1, exigeant en C1
- **Répondez à l'oral** : les enregistrements audio sont transcrits avec Whisper
- Tableau de bord de progression avec suivi par compétence, recherche et notation des activités
- Installable comme PWA, avec notifications push pour les nouvelles activités

**Pour les élèves en parcours professionnel (OPCO / eCPF) :**
- En France, la formation en langues est souvent financée par la formation professionnelle — l'OPCO de l'employeur ou le compte personnel de formation (CPF). Les financeurs exigent une preuve que la formation a réellement eu lieu, et c'est cette preuve qui permet à un professeur d'accueillir des élèves financés
- Le professeur marque l'élève comme OPCO ou eCPF dès l'invitation par email ; un badge dédié suit ensuite l'élève sur le tableau de bord du professeur comme sur son propre profil
- Un clic génère une **attestation de formation imprimable** par élève, avec des heures calculées à partir du temps de pratique réellement mesuré — de l'ouverture d'une activité à sa soumission — plutôt que déclarées à la main

**Sous le capot :**
- Parcours essai-vers-abonnement avec Stripe (checkout + webhooks)
- Emails de rappel hebdomadaires (Resend + cron GoodJob) et suggestions quotidiennes de vidéos YouTube par professeur
- **Interface en portugais uniquement, par choix** — l'immersion pendant la pratique. La langue de la personne (FR / EN / PT) est réservée à tout ce qui se passe *hors* de l'application : emails, politique de confidentialité, fin d'essai et facturation. Ce sont les moments où comprendre ne doit pas dépendre d'un effort

---

## Stack technique

| Couche | Technologie |
|-------|-----------|
| Backend | Ruby 3.3.5, Rails 7.1 |
| Base de données | PostgreSQL |
| Frontend | Hotwire (Turbo + Stimulus), Tailwind CSS + DaisyUI |
| IA | Anthropic Claude — Opus pour la génération d'activités, Haiku pour la correction ; OpenAI Whisper (reconnaissance vocale) |
| Tâches de fond | GoodJob (adossé à Postgres, mode async) |
| Authentification | Devise + Devise Invitable |
| Paiements | Abonnements Stripe + webhooks |
| Médias & email | Cloudinary, Unsplash, YouTube Data API, Resend |
| Tests & CI | RSpec, FactoryBot, SimpleCov, GitHub Actions |
| Déploiement | Heroku (avec PWA + web push en production) |
| Supervision | Sentry (région UE, erreurs uniquement — ni tracing, ni logs) |

---

## Notes d'architecture

- Les **service objects** gardent les contrôleurs légers : la soumission de quiz et la correction par IA, la génération d'activités (par prompt ou par vidéo), la transcription, les notifications push et les analytics vivent chacun dans leur propre service sous `app/services`.
- **Les deux pipelines d'IA tournent en tâche de fond** (GoodJob, adossé à Postgres — pas de Redis) : la génération d'activités et la correction des réponses sont mises en file plutôt que de bloquer la requête, avec retry + dégradation gracieuse quand l'IA est indisponible, et l'interface se met à jour toute seule via un contrôleur Stimulus qui interroge le serveur, sans recharger la page.
- **Choix de modèle piloté par le coût** : Claude Opus génère les activités — faible volume, exigeant en qualité, guidé par une grille de qualité intégrée au prompt système — tandis que Claude Haiku corrige les réponses des élèves, un flux à bien plus haut volume. Même pipeline, modèle différent selon l'économie de chaque tâche.
- **Interface rendue côté serveur avec Hotwire** — pas de SPA, pas de couche API à maintenir ; Turbo gère l'interactivité.
- **Accès par rôle** (admin / professeur / élève / essai) appliqué au niveau des contrôleurs, chaque élève étant rattaché au professeur qui l'a invité.
- **Dégradation gracieuse** : les intégrations IA, YouTube et Unsplash sont optionnelles — la plateforme fonctionne sans leurs clés d'API.
- **Protection des données sous deux régimes juridiques (RGPD + LGPD brésilienne)** : aucun CDN tiers — polices, icônes et bibliothèques sont auto-hébergées, donc aucune adresse IP de visiteur n'atteint une société extérieure avant consentement, ce qui supprime du même coup le besoin d'un bandeau cookies ; les données personnelles sont tenues hors des logs de production ; la correction par IA ne reçoit que le texte de la réponse, jamais un nom ni un email. La politique de confidentialité est choisie côté serveur à partir de l'en-tête `Accept-Language`, en trois versions qui ne sont *pas* des traductions l'une de l'autre : FR et EN suivent le RGPD, PT suit la LGPD brésilienne, et les deux divergent sur les délais de réponse, la liste des droits, le droit à une révision humaine d'une décision automatisée et l'âge de la minorité. Les décisions, les règles qui les empêchent de régresser et ce qui reste ouvert — export des données, suppression du compte en un clic, politique de conservation — sont suivis dans [`docs/PROTECAO_DE_DADOS.md`](docs/PROTECAO_DE_DADOS.md). Aucun sous-traitant nouveau n'atteint la production avant d'être inscrit à trois endroits : les tableaux des politiques, le registre des traitements de l'article 30 ([`docs/REGISTRE_DES_TRAITEMENTS.md`](docs/REGISTRE_DES_TRAITEMENTS.md)) et le tableau des DPA — et un test échoue s'il manque à l'un d'eux, car un document de conformité qui se périme ne casse rien : il se met simplement à mentir.
- **Une supervision des erreurs qui ne défait pas ce travail** : les erreurs de production partent vers Sentry, fixé à sa **région UE**, où les données d'erreur sont donc stockées dans l'Union. L'intégration reste inerte tant que `SENTRY_DSN` n'est pas défini — développement et test n'émettent jamais rien vers l'extérieur, et la production se coupe sans déploiement. Les données personnelles sont retirées en trois couches : envoi des données personnelles désactivé par défaut (ni IP, ni cookies, ni corps de requête), réutilisation des filtres de paramètres déjà en place pour les logs plutôt qu'une seconde liste que l'on oublierait de tenir à jour, et un dernier passage sur le *texte* de l'exception, où un email peut se trouver au milieu d'une phrase, hors de portée de tout filtre de paramètre. Le tracing de performance est volontairement désactivé, et `traces_sample_rate` vaut `nil` plutôt que `0.0` : `0.0` est un taux *valide*, le SDK enregistre donc malgré tout chaque souscripteur d'instrumentation Rails et modifie `ActiveSupport::Notifications` avant d'écarter 100 % des échantillons — tout le coût, aucune donnée, sur un dyno dont les 512 Mo sont déjà partagés avec l'exécution des tâches de fond.

## Feuille de route technique

Ce qu'il reste à faire, par ordre de priorité :

- [x] Sortir la correction par IA du cycle de requête (tâches de fond GoodJob + mise à jour asynchrone de l'interface)
- [x] Sortir la génération d'activités par IA du cycle de requête aussi (tâche de fond + mise à jour asynchrone de l'interface)
- [x] Terminer la migration des vues Bootstrap restantes vers Tailwind/DaisyUI
- [x] Regrouper les actions `clear_*` répétitives en une seule action paramétrée
- [ ] Améliorer la couverture de tests (request specs) sur les parcours facturation et soumission de quiz
- [ ] Extraire choix multiple et texte à trous dans leurs propres modèles — pour l'instant ce sont des champs sur `Question`, contrairement aux quatre autres types d'exercices, qui ont chacun leur propre modèle. Report volontaire : le parcours de quiz est le chemin le plus critique de l'app, donc ça attend un sprint dédié, planifié avec soin

---

## Lancer le projet en local

**Prérequis :** Ruby 3.3.5, PostgreSQL, Bundler, Yarn

```bash
git clone https://github.com/DaisyOli/practice-br.git
cd practice-br

bundle install
yarn install

# Créer et migrer la base de données
bin/rails db:create db:migrate db:seed

# Lancer le serveur + le watcher Tailwind
bin/dev
```

Ouvrez `http://localhost:3000` dans votre navigateur.

**Variables d'environnement** — créez un fichier `.env` à la racine du projet :

```
DB_USERNAME=your_postgres_username
DB_PASSWORD=your_postgres_password
```

Des clés optionnelles activent les intégrations : `ANTHROPIC_API_KEY` (génération et correction par IA), `OPENAI_API_KEY` (réponses vocales), `STRIPE_SECRET_KEY`, `YOUTUBE_API_KEY`, `UNSPLASH_ACCESS_KEY`.

## Lancer les tests

```bash
bundle exec rspec
```

La suite tourne aussi à chaque push via GitHub Actions.
