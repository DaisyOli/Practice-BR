<!--
  PT · Este é o "registre des traitements" exigido pelo RGPD art. 30 — a peça que a
  CNIL pede numa fiscalização e que, ao contrário das outras pendências, precisa
  estar pronta ANTES do pedido. Não é a política de privacidade: a política é para
  o titular ler, isto é para o auditor.

  O documento é 100% em francês de propósito (é assim que ele é entregue). As
  instruções de manutenção — quando atualizar, o que verificar — estão em
  docs/PROTECAO_DE_DADOS.md, que é o contrato em português.

  Serve também ao art. 37 da LGPD ("registro das operações de tratamento").
-->

# Registre des activités de traitement

**Practice-BR** · Article 30 du Règlement (UE) 2016/679 (RGPD)

| | |
|---|---|
| **Responsable du traitement** | Daisy Oliani, entrepreneur individuel |
| **Adresse** | 43 Clos des Cascades, 93160 Noisy-le-Grand, France |
| **SIRET** | 85 194 793 700 013 |
| **Contact données personnelles** | contato@practicebr.com |
| **Délégué à la protection des données** | Non désigné — la désignation n'est pas obligatoire au sens de l'article 37 (ni autorité publique, ni suivi systématique à grande échelle, ni traitement à grande échelle de données de l'article 9) |
| **Autorité de contrôle** | CNIL |
| **Registre créé le** | 31 juillet 2026 |
| **Dernière mise à jour** | 31 juillet 2026 |

**Sur l'exemption de l'article 30(5).** L'exemption prévue pour les organisations de
moins de 250 personnes ne s'applique pas ici : le traitement des données des élèves
n'est pas occasionnel mais régulier et continu. Le registre est donc tenu en
intégralité.

**Nature du service.** Practice-BR est une plateforme d'apprentissage du portugais :
un professeur y publie des activités, les élèves y répondent, et les réponses
rédigées sont corrigées par une intelligence artificielle puis relues par le
professeur. Le service est accessible sur abonnement, précédé d'une période d'essai
gratuite.

---

## Vue d'ensemble

| N° | Traitement | Base légale | Durée de conservation |
|---|---|---|---|
| 1 | Gestion des comptes et de l'accès | Contrat (art. 6.1.b) | Voir fiche 1 |
| 2 | Service pédagogique et suivi de la progression | Contrat (art. 6.1.b) | Supprimé avec le compte |
| 3 | Correction automatisée des réponses par IA | Contrat (art. 6.1.b) | Aucune conservation chez le sous-traitant |
| 4 | Transcription des réponses orales | Contrat (art. 6.1.b) | Enregistrement supprimé immédiatement |
| 5 | Abonnements et facturation | Contrat + obligation légale (art. 6.1.b et 6.1.c) | 10 ans (pièces comptables) |
| 6 | Communications et notifications | Contrat + consentement (art. 6.1.b et 6.1.a) | Jusqu'au retrait / suppression du compte |
| 7 | Sécurité, journalisation et prévention des abus | Intérêt légitime (art. 6.1.f) | 12 mois |
| 8 | Demandes d'exercice des droits | Obligation légale (art. 6.1.c) | 3 ans après la clôture de la demande |

**Catégories de personnes concernées**, communes à l'ensemble des traitements :
élèves, élèves en période d'essai, et professeurs. Aucune donnée relevant de
l'article 9 (santé, opinions, origine, orientation) n'est collectée.

---

## Fiche 1 · Gestion des comptes et de l'accès

**Finalité.** Créer et administrer le compte, authentifier l'utilisateur, gérer les
invitations envoyées par le professeur à ses élèves, et permettre la
réinitialisation du mot de passe.

**Base légale.** Exécution du contrat (art. 6.1.b).

**Personnes concernées.** Élèves, élèves en période d'essai, professeurs.

**Catégories de données.**

- Adresse email (identifiant de connexion)
- Prénom ou nom, facultatif
- Mot de passe, conservé uniquement sous forme de hachage bcrypt
- Rôle (élève, essai, professeur, administrateur)
- Langue de l'interface, niveau de portugais, parcours professionnel
- Jeton et dates d'invitation ; identité du professeur ayant invité
- Jeton de réinitialisation de mot de passe et sa date d'envoi
- Dates de création et de dernière modification du compte
- Période d'essai : date d'expiration et nombre d'activités déjà utilisées

**Destinataires.** Aucun, hormis l'hébergeur (Heroku) qui héberge la base de
données. Le professeur voit le nom, l'email et le niveau des élèves qu'il a invités.

**Transferts hors UE.** Oui — hébergement aux États-Unis. Voir la section
*Sous-traitants et transferts*.

**Durée de conservation.**

| Situation | Durée |
|---|---|
| Compte actif | Durée de la relation contractuelle |
| Abonnement en cours | Conservé — la relation contractuelle n'est pas terminée |
| Compte sans activité | Suppression **3 ans** après la dernière activité |
| Période d'essai non convertie | Suppression **12 mois** après l'expiration de l'essai |
| Demande de suppression par la personne | Immédiate, via `/excluir-conta` |

**« Dernière activité »** s'entend de la dernière tentative d'exercice enregistrée,
et non de la dernière connexion : c'est l'usage réel du service qui justifie la
conservation, pas l'ouverture d'une page.

**Avertissement préalable.** Aucune suppression pour inactivité n'intervient sans
prévenir : un email est envoyé **30 jours avant** l'échéance, dans la langue de la
personne, rappelant la date, le moyen de conserver le compte (refaire une activité)
et le lien de téléchargement de ses données. Reprendre une activité pendant ce délai
annule l'avertissement et fait repartir le décompte.

**Mise en œuvre.** La purge est automatique et quotidienne. La suppression est
effective et non un simple masquage : le compte et l'ensemble des données rattachées
sont effacés de la base dans une transaction unique, précédée de la résiliation de
l'abonnement lorsqu'il en existe un.

---

## Fiche 2 · Service pédagogique et suivi de la progression

**Finalité.** Afficher les activités, enregistrer les réponses des élèves, les
noter, permettre au professeur de commenter et de corriger, et restituer la
progression dans le temps.

**Base légale.** Exécution du contrat (art. 6.1.b).

**Personnes concernées.** Élèves, professeurs.

**Catégories de données.**

- Réponses aux exercices, y compris les textes rédigés librement par l'élève
- Notes obtenues, dates de début et d'envoi de chaque tentative
- Commentaires écrits par le professeur sur une tentative
- Évaluations données par l'élève à une activité (étoiles et commentaire)
- Compteur d'activités réalisées dans la journée, servant à la limite quotidienne
- Côté professeur : activités créées, brouillons, demandes de génération d'activité
  par IA et suggestions de thèmes

**Destinataires.** Le professeur de l'élève, qui accède aux réponses et aux notes de
ses élèves — c'est la finalité même du service. Hébergeur (Heroku).

**Transferts hors UE.** Oui — hébergement aux États-Unis.

**Durée de conservation.** Ces données sont rattachées au compte et suivent son sort
(fiche 1). Elles sont supprimées en même temps que lui.

---

## Fiche 3 · Correction automatisée des réponses par intelligence artificielle

**Finalité.** Évaluer automatiquement les réponses rédigées, attribuer une note et
produire un commentaire pédagogique, afin que l'élève reçoive un retour immédiat.

**Base légale.** Exécution du contrat (art. 6.1.b).

**Personnes concernées.** Élèves.

**Catégories de données transmises au sous-traitant.** Uniquement **le texte de la
réponse** et le critère d'évaluation de la question. Ne sont transmis **ni le nom,
ni l'adresse email, ni l'identifiant de compte** : le sous-traitant reçoit un texte
sans rattachement à une personne identifiée.

**Sous-traitant.** Anthropic (Claude), États-Unis. Les données transmises via l'API
commerciale ne sont pas utilisées pour l'entraînement des modèles.

**Décision individuelle automatisée (art. 22).** La note produite par l'IA n'est pas
une décision entièrement automatisée produisant des effets juridiques : elle est
consultable et **rectifiable par le professeur**, qui garde la main sur
l'évaluation. La politique de confidentialité indique explicitement à l'élève qu'il
peut demander le réexamen d'une correction par une personne. La version portugaise
de la politique le formule comme le droit de révision prévu à l'article 20 de la
LGPD.

**Durée de conservation.** La note et le commentaire produits sont conservés avec la
tentative, donc avec le compte (fiche 2). Aucune conservation durable chez le
sous-traitant.

---

## Fiche 4 · Transcription des réponses orales

**Finalité.** Convertir en texte une réponse enregistrée à l'oral, afin qu'elle
puisse être corrigée comme une réponse écrite.

**Base légale.** Exécution du contrat (art. 6.1.b).

**Personnes concernées.** Élèves.

**Catégories de données.** Enregistrement audio de la voix de l'élève ; texte issu
de la transcription ; statut technique du traitement.

**Sous-traitants.** OpenAI (Whisper) pour la transcription, États-Unis. Cloudinary
pour le stockage du fichier pendant le traitement, États-Unis.

**Durée de conservation.** L'enregistrement est **supprimé immédiatement après la
transcription**, y compris lorsque la transcription échoue — la suppression est
placée dans le bloc `ensure` du traitement, de sorte qu'aucun échec ne laisse un
fichier audio derrière lui. Seul le texte transcrit est conservé, avec le compte.

La voix étant une donnée particulièrement identifiante, cette suppression immédiate
est une mesure de minimisation délibérée : la plateforme ne constitue à aucun moment
une base d'enregistrements vocaux.

---

## Fiche 5 · Gestion des abonnements et facturation

**Finalité.** Gérer l'abonnement payant : souscription, statut, échéance,
interruption de l'accès en cas d'échec de paiement, résiliation.

**Base légale.** Exécution du contrat (art. 6.1.b) pour la gestion de l'abonnement ;
obligation légale (art. 6.1.c) pour la conservation des pièces comptables.

**Personnes concernées.** Élèves abonnés.

**Catégories de données.** Identifiant client et identifiant d'abonnement Stripe ;
statut de l'abonnement ; date de fin de période en cours ; date de début d'un
éventuel impayé.

**Les données de la carte bancaire ne transitent jamais par les serveurs de la
plateforme** : elles sont transmises directement à Stripe par le navigateur.

**Sous-traitant.** Stripe, États-Unis.

**Durée de conservation.** Les identifiants d'abonnement sont supprimés avec le
compte ; l'abonnement est résilié chez Stripe **avant** l'effacement du compte. Les
pièces comptables et les factures sont conservées **10 ans** par Stripe et par le
responsable du traitement, conformément à l'article L123-22 du code de commerce.
Cette conservation est une obligation légale : elle survit à la demande de
suppression, qui ne s'y étend pas.

---

## Fiche 6 · Communications et notifications

**Finalité.** Envoyer les emails nécessaires au service (invitation, mot de passe
oublié, fin de période d'essai, correction disponible) et, pour les personnes qui
l'ont accepté, des rappels d'entraînement par email et des notifications dans le
navigateur.

**Base légale.** Exécution du contrat (art. 6.1.b) pour les emails indispensables au
fonctionnement du service ; **consentement** (art. 6.1.a) pour les rappels et les
notifications, révocable à tout moment dans les préférences du compte.

**Personnes concernées.** Élèves, élèves en période d'essai, professeurs.

**Catégories de données.** Adresse email ; préférence de rappel hebdomadaire ;
adresse technique d'abonnement aux notifications du navigateur et ses clés de
chiffrement ; dates du dernier rappel de fin d'essai et de la dernière relance
d'inactivité, qui servent à ne pas répéter un envoi.

**Sous-traitant.** Resend, pour l'acheminement des emails.

**Durée de conservation.** Jusqu'au retrait du consentement ou à la suppression du
compte. L'abonnement aux notifications est supprimé dès que le navigateur le révoque
ou que l'envoi échoue durablement.

---

## Fiche 7 · Sécurité, journalisation et prévention des abus

**Finalité.** Maintenir la plateforme disponible et sûre, diagnostiquer les erreurs,
et prévenir la fraude et l'usage abusif.

**Base légale.** Intérêt légitime (art. 6.1.f) : faire fonctionner et protéger le
service. L'intérêt des personnes est préservé par la minimisation décrite
ci-dessous.

**Personnes concernées.** Toute personne se connectant à la plateforme.

**Catégories de données.** Journaux techniques de l'hébergeur : adresse IP,
horodatage, chemin appelé, code de réponse.

**Minimisation.** Les journaux applicatifs sont configurés pour **ne pas contenir de
données personnelles** : le niveau de journalisation en production exclut le détail
des requêtes en base, les paramètres sensibles sont filtrés, et les messages écrits
par l'application désignent une personne par son identifiant numérique interne et
jamais par son adresse email.

**Sous-traitant.** Heroku (Salesforce), hébergeur.

**Durée de conservation.** 12 mois au maximum, selon la rotation des journaux de
l'hébergeur.

---

## Fiche 8 · Gestion des demandes d'exercice des droits

**Finalité.** Recevoir, instruire et tracer les demandes d'accès, de rectification,
de suppression, d'opposition, de limitation et de portabilité.

**Base légale.** Obligation légale (art. 6.1.c) — chapitre III du RGPD.

**Personnes concernées.** Toute personne exerçant un droit.

**Catégories de données.** Identité du demandeur, contenu de la demande,
correspondance échangée, date et nature de la réponse apportée.

**Modalités.** Deux droits s'exercent directement dans l'application, sans
intervention humaine ni délai :

| Droit | Chemin |
|---|---|
| Accès (art. 15) | `/meus-dados` — récapitulatif lisible des données détenues |
| Portabilité (art. 20) | `/meus-dados/download` — export JSON, format structuré et lisible par machine |
| Effacement (art. 17) | `/excluir-conta` — suppression effective, précédée de la résiliation de l'abonnement |

Les autres droits s'exercent par email à contato@practicebr.com, avec une réponse
dans un délai d'un mois (RGPD) et de 15 jours lorsque la LGPD s'applique.

**Durée de conservation.** 3 ans après la clôture de la demande, au titre de la
preuve du respect des obligations.

---

## Sous-traitants et transferts hors Union européenne

Tous les sous-traitants ci-dessous traitent des données sur des serveurs situés aux
**États-Unis**. Chacun présente les garanties contractuelles prévues au chapitre V
du RGPD, sous la forme d'un accord de traitement (DPA) incorporé à ses conditions de
service.

| Sous-traitant | Finalité | Données transmises | DPA vérifié |
|---|---|---|---|
| Heroku (Salesforce) | Hébergement de l'application et de la base de données | L'ensemble des données de la plateforme | 31/07/2026 — DPA Salesforce couvrant Heroku |
| Anthropic (Claude) | Correction des réponses écrites, génération d'activités | Texte de la réponse et critère d'évaluation, sans donnée identifiante | 30/07/2026 |
| OpenAI (Whisper) | Transcription des réponses orales | Enregistrement audio | 31/07/2026 |
| Stripe | Traitement des paiements et facturation | Email, identifiants d'abonnement, données de carte transmises directement par le navigateur | 30/07/2026 |
| Resend | Acheminement des emails de la plateforme | Adresse email et contenu du message | 31/07/2026 |
| Cloudinary | Stockage des images et des fichiers audio | Fichiers déposés, dont l'audio temporaire | 31/07/2026 |

**Resend** et **OpenAI** sont par ailleurs certifiés au titre du **EU-US Data
Privacy Framework**. Les clauses contractuelles types de la décision (UE) 2021/914
sont incorporées par référence aux addenda de Cloudinary et de Salesforce (Heroku),
ce dernier y ajoutant ses règles d'entreprise contraignantes (BCR) de
sous-traitant.

**Aucune donnée n'est vendue, cédée ou transmise à des fins publicitaires.**

Un sous-traitant nouveau n'est mis en production qu'après avoir été ajouté à ce
registre, à la table des sous-traitants de la politique de confidentialité, et après
vérification de son DPA.

---

## Mesures de sécurité

Applicables à l'ensemble des traitements :

- **Chiffrement en transit** — la totalité du trafic est servie en HTTPS.
- **Mots de passe** — stockés sous forme de hachage bcrypt ; ils ne sont lisibles par
  personne, y compris par le responsable du traitement.
- **Accès à la base de données** — restreint au responsable du traitement et à
  l'application ; identifiants gérés par des variables d'environnement, jamais versionnés.
- **Cloisonnement des rôles** — un élève n'accède qu'à ses propres données ; un
  professeur n'accède qu'aux élèves qu'il a invités ; la suppression d'une activité
  est réservée à l'administrateur.
- **Aucune ressource tierce dans les pages** — polices, icônes et bibliothèques sont
  servies depuis le domaine de la plateforme. Ouvrir une page de Practice-BR ne
  communique l'adresse IP de l'utilisateur à aucune autre société. Aucun traceur,
  aucun cookie publicitaire, aucun outil de mesure d'audience tiers.
- **Journaux sans données personnelles** — voir fiche 7.
- **Minimisation envers l'IA** — voir fiche 3.
- **Sauvegardes** — sauvegardes automatiques de l'hébergeur. Une donnée supprimée
  peut subsister dans une sauvegarde jusqu'à la rotation de celle-ci ; les
  sauvegardes ne sont jamais consultées à d'autres fins que la restauration après
  incident.

**Limite connue et assumée.** La plateforme ne dispose pas encore d'un outil de
détection et d'alerte sur incident. La notification à la CNIL dans les 72 heures
(art. 33) repose donc aujourd'hui sur la constatation manuelle. La mise en place
d'une supervision des erreurs est identifiée comme le prochain chantier de sécurité.

---

## Ce que la plateforme ne fait pas

Précisions utiles à une vérification, car chacune de ces absences supprime une
obligation qui, sinon, s'appliquerait :

- Aucune donnée sensible au sens de l'article 9 n'est collectée.
- Aucun profilage publicitaire, aucune décision automatisée produisant des effets
  juridiques au sens de l'article 22 (voir fiche 3).
- Aucun cookie non essentiel — d'où l'absence de bandeau de consentement.
- Aucune géolocalisation, aucun suivi comportemental entre sites.
- Aucune donnée n'est collectée auprès de tiers : tout provient de la personne
  elle-même.

---

## Historique des mises à jour

| Date | Modification |
|---|---|
| 31/07/2026 | Création du registre. Huit traitements recensés. Durées de conservation fixées pour les comptes inactifs (3 ans) et les périodes d'essai non converties (12 mois), avec avertissement 30 jours avant. Purge automatique quotidienne mise en place le même jour, et durées reprises dans la section 7 de la politique de confidentialité. |
