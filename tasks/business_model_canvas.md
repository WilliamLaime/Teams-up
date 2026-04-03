# Business Model Canvas — teams-up.fit
> Généré le 03 avril 2026 — Version 1.0

---

## Vue d'ensemble

**Nom du produit** : teams-up.fit  
**Baseline** : *Trouve ton équipe. Complète la tienne.*  
**Stade** : Pré-lancement — MVP avancé, lancement prévu mai 2026  
**Marché cible initial** : Bordeaux Métropole → France  

---

## Les 9 blocs d'Osterwalder

---

### 1. SEGMENTS DE CLIENTÈLE

| Segment | Profil | Taille estimée (France) |
|---|---|---|
| **Le Joueur Solo** | Sportif amateur 18-35 ans qui cherche une équipe ou des partenaires pour pratiquer son sport (foot, padel, basket, tennis…) sans avoir de cercle social sportif établi | ~15 millions de pratiquants hors-club |
| **Le Capitaine / Organisateur** | Joueur qui organise des matchs récurrents et cherche à compléter son effectif, trouver des remplaçants, ou gérer ses équipes | ~4-6 millions d'organisateurs amateurs estimés |
| **La Joueuse** | Femme sportive qui cherche des sessions mixtes ou féminines dans un environnement sécurisé et bienveillant | Segment en croissance : +3-4 pts/an |
| **L'Étudiant Sportif** | 18-25 ans, fort usage mobile, pratique intensive, budget limité | ~800 000 étudiants actifs sportifs (dont ~100 000 à Bordeaux) |
| **Complexe Sportif** *(futur B2B)* | Salles et clubs qui veulent être visibles auprès des sportifs locaux | ~3 000-3 500 associations sportives sur Bordeaux Métropole |

---

### 2. PROPOSITION DE VALEUR

| Pour qui | Problème résolu | Ce que teams-up.fit apporte |
|---|---|---|
| Joueur Solo | Impossible de trouver une équipe spontanément, devoir appeler 10 personnes pour organiser un match | Matching instantané avec des équipes incomplètes, filtré par sport, niveau, ville et disponibilité |
| Capitaine | Il manque toujours 1 ou 2 joueurs pour un match, pas de solution simple pour recruter | Interface de gestion des candidatures, validation/rejet en 1 clic, liste d'attente automatique |
| Tous | Pas de moyen de savoir si quelqu'un est fiable avant de jouer avec lui | Système de réputation mutuelle (notes 5 étoiles), vote "Homme du Match", historique de matchs |
| Joueur engagé | Les apps sportives sont ennuyeuses, pas de motivation à revenir | Gamification RPG : XP, niveaux 1-10, achievements, attributs personnalisables |
| Femme sportive | Environnement parfois peu accueillant dans le sport amateur mixte | Option matchs féminins uniquement, communauté inclusive |

**Différenciateurs clés vs concurrents :**
- Seule app combinant matchmaking + chat intégré + gamification RPG sur le marché français
- Multi-sport (7 sports, extensible)
- Notation mutuelle (les deux joueurs doivent se noter — pas de manipulation)
- PWA : utilisable sur mobile sans télécharger une app

---

### 3. CANAUX DE DISTRIBUTION

| Phase | Canal | Objectif |
|---|---|---|
| **Phase 1 (0-6 mois)** | Bouche-à-oreille — réseau personnel de l'équipe fondatrice | Premiers 200-500 utilisateurs à Bordeaux |
| **Phase 1** | Instagram / TikTok — contenu organique sport | Notoriété gratuite, ciblage 18-30 ans |
| **Phase 1** | Groupes Facebook / WhatsApp sportifs locaux | Acquisition directe des communautés existantes |
| **Phase 2 (6-18 mois)** | Partenariats salles de sport / complexes sportifs | Distribution physique (QR codes, affiches, flyers) |
| **Phase 2** | Influenceurs sportifs micro-locaux (Bordeaux, puis Paris) | Crédibilité + acquisition rapide |
| **Phase 2** | SEO / contenu (blog sport, matchmaking) | Trafic organique long terme |
| **Phase 3 (18+ mois)** | App stores (PWA → React Native potentiel) | Audience mobile nationale |
| **Phase 3** | Partenariats fédérations/ligues amateur | Accès à leur base d'adhérents |

---

### 4. RELATIONS CLIENTS

| Mécanisme | Description |
|---|---|
| **Communauté gamifiée** | Système XP, niveaux, achievements — crée de l'attachement et de la fierté (profil publique visible) |
| **Chat intégré** | Group chat par match + messagerie privée — la plateforme devient le hub de communication sportive |
| **Réputation publique** | Notes, Homme du Match, statistiques — incitation à bien se comporter et à revenir |
| **Notifications temps réel** | Approbation, nouveau message, achievement débloqué — re-engage l'utilisateur sans effort marketing |
| **Self-service** | Création de match autonome, gestion de l'équipe, pas besoin de support |
| **Support** | Formulaire de contact (admin dashboard), réponse humaine pour les signalements |

---

### 5. SOURCES DE REVENUS

| Phase | Source | Modèle | Prix estimé | Timeline |
|---|---|---|---|---|
| **Phase 1** | Gratuit | — | 0 € | Mois 1-6 |
| **Phase 2** | Abonnement "Capitaine Premium" | Freemium mensuel | 4,99 €/mois ou 39,99 €/an | Mois 7+ |
| **Phase 2** | Abonnement annuel Premium | Annuel (remise 33%) | 39,99 €/an | Mois 7+ |
| **Phase 3** | Pack visibilité "Salle Partenaire" | B2B mensuel | 99-299 €/mois | Mois 18+ |
| **Phase 3** | Commission sur matchs payants | % transaction (future) | 8-12% | Mois 24+ |

**Ce qu'apporte le "Capitaine Premium" :**
- Création de matchs illimitée (free : 3/mois)
- Match mis en avant dans les résultats de recherche
- Statistiques avancées de ses participants
- Badge "Capitaine Premium" sur le profil
- Export liste des participants (CSV)

**Projections de revenus simplifiées :**

| Période | Utilisateurs | Premium (3-5%) | CA Mensuel estimé |
|---|---|---|---|
| Mois 12 | ~2 000 | ~60 | ~300 € |
| Mois 18 | ~5 000 | ~200 | ~1 000 € |
| Mois 24 | ~15 000 | ~750 + B2B | ~5 000-8 000 € |
| Mois 36 | ~30 000 | ~2 000 + B2B | ~15 000-20 000 € |

---

### 6. RESSOURCES CLÉS

| Type | Ressource |
|---|---|
| **Technologie** | Plateforme Rails 8 + PostgreSQL + ActionCable (temps réel) + PWA |
| **Données** | Base de données venues sportives (France, Nominatim/OSM), profils utilisateurs |
| **Marque** | teams-up.fit — nom de domaine, identité visuelle, logo |
| **Équipe** | 4 fondateurs profils tech/design — compétences full-stack |
| **Communauté** | Base d'utilisateurs premiers (réseau Bordeaux) — valeur réseau croissante |
| **Infrastructure** | Kamal (déploiement Docker), Cloudinary (médias), SolidQueue (jobs async) |

---

### 7. ACTIVITÉS CLÉS

| Catégorie | Activité |
|---|---|
| **Développement produit** | Itérations hebdomadaires, correction bugs, nouvelles fonctionnalités, intégration Stripe |
| **Animation communauté** | Modération, réponse aux retours utilisateurs, animation réseaux sociaux |
| **Acquisition** | Contenu organique social, partenariats locaux, présence événements sportifs |
| **Rétention** | Gamification, notifications, nouvelles saisons d'achievements, événements spéciaux |
| **Opérations** | Monitoring infra, sécurité, RGPD, traitement des signalements |
| **Business development** | Prospection salles de sport, clubs, fédérations pour partenariats B2B |

---

### 8. PARTENAIRES CLÉS

| Partenaire | Rôle | Bénéfice mutuel |
|---|---|---|
| **Complexes sportifs locaux** | Distribution physique, venues dans la base de données | Visibilité auprès de sportifs locaux actifs |
| **Clubs amateurs** | Ambassadeurs, premiers utilisateurs organisés | Outil gratuit de gestion de matchs pour leurs membres |
| **Influenceurs sportifs locaux** | Acquisition organique, crédibilité | Rémunération en nature ou commission |
| **Fédérations sportives** | Légitimité, accès aux licenciés (future) | Digitalisation de leur communauté amateur |
| **Cloudinary** | Hébergement médias (avatars, bannières) | Infrastructure critique |
| **Google** | OAuth2 — connexion simplifiée | Réduction friction inscription |
| **Universités (Bordeaux)** | Accès communauté étudiante sportive | ~100 000 étudiants potentiels |

---

### 9. STRUCTURE DE COÛTS

| Poste | Coût estimé | Fréquence |
|---|---|---|
| **Hébergement serveur** (VPS Kamal) | 50-100 € | Mensuel |
| **Cloudinary** (médias) | 25-50 € | Mensuel |
| **Nom de domaine** | 15 € | Annuel |
| **Outils SaaS** (email, monitoring) | 30-50 € | Mensuel |
| **Marketing digital** (boost social) | 0-200 € | Mensuel (phase 2) |
| **Événements / partenariats** | 0-500 € | Ponctuel |
| **Frais juridiques** (CGU, RGPD) | 500-1 500 € | One-shot |
| **Total coûts fixes (Phase 1)** | **~125-200 €/mois** | |
| **Total coûts Phase 2** | **~400-600 €/mois** | |

Structure de coûts très légère en phase 1 — pas de masse salariale (équipe fondatrice), infrastructure moderne et peu coûteuse (Rails + Kamal auto-hébergé).

**Seuil de rentabilité** : atteint dès ~100 abonnés Premium actifs (~500 €/mois de CA).

---

*Document généré pour usage stratégique interne — teams-up.fit — Avril 2026*
