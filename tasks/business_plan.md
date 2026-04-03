# BUSINESS PLAN
# teams-up.fit

**Plateforme de matchmaking sportif communautaire**

---

*Fondateurs : Équipe teams-up.fit (4 personnes)*  
*Date de rédaction : Avril 2026*  
*Version : 1.0 — Confidentiel*  
*Contact : teams-up.fit*

---

## TABLE DES MATIÈRES

1. Executive Summary
2. Le Problème
3. La Solution — teams-up.fit
4. Étude de Marché
5. Proposition de Valeur & Offre
6. Business Model
7. Stratégie Go-to-Market
8. Plan Opérationnel
9. Plan Financier
10. Annexes

---

## 1. EXECUTIVE SUMMARY

teams-up.fit est une application web de matchmaking sportif qui permet à tout sportif amateur de trouver une équipe à rejoindre ou de recruter les joueurs manquants pour compléter son effectif. Le produit couvre sept sports majeurs — football, tennis, padel, basketball, handball, volleyball et badminton — et s'adresse à l'ensemble des pratiquants amateurs français, soit un marché potentiel de 38 à 40 millions de personnes.

Le problème que nous résolvons est quotidien et frustrant : organiser un match ou trouver des partenaires de jeu est chronophage, dépend de réseaux sociaux désorganisés (groupes WhatsApp, posts Facebook) et n'offre aucune garantie sur le niveau ou la fiabilité des participants. teams-up.fit apporte une réponse structurée : un matching filtré par sport, niveau officiel, ville et disponibilité, combiné à un système de réputation mutuelle et à un espace de communication intégré.

Le produit est aujourd'hui un MVP techniquement avancé, prêt pour son lancement commercial prévu en mai 2026 sur Bordeaux Métropole. Il est développé en Ruby on Rails 8, dispose d'une architecture temps réel (ActionCable, Turbo Streams), d'une Progressive Web App installable sur mobile, et d'un système de gamification complet (niveaux XP, achievements, attributs RPG) qui différencie radicalement l'expérience utilisateur de toute solution existante sur le marché.

L'équipe fondatrice est composée de quatre profils complémentaires orientés tech et design, ayant conçu et développé l'intégralité de la plateforme. La stratégie de mise sur le marché repose sur une acquisition organique initiale (bouche-à-oreille, réseaux sociaux, micro-influenceurs sportifs locaux), suivie de partenariats avec les complexes sportifs et clubs amateurs de Bordeaux, puis d'une extension progressive vers Paris et la France entière.

Le modèle de revenus adopte une logique freemium éprouvée dans le secteur des plateformes communautaires. La phase de lancement (six premiers mois) est entièrement gratuite pour maximiser l'adoption. À partir du septième mois, un abonnement "Capitaine Premium" à 4,99 euros par mois sera proposé aux organisateurs de matchs souhaitant des fonctionnalités avancées. À partir de la deuxième année, des partenariats B2B avec les salles de sport compléteront les revenus. L'infrastructure étant très légère (moins de 200 euros de coûts fixes mensuels en phase 1), le point d'équilibre est atteint dès 100 abonnés actifs.

L'ambition à trois ans est d'atteindre 30 000 utilisateurs actifs sur la France, un chiffre d'affaires annuel de 200 000 à 250 000 euros et de s'imposer comme la référence du matchmaking sportif amateur francophone.

---

## 2. LE PROBLÈME

### Une réalité universelle, jamais vraiment résolue

Chaque week-end en France, des millions de sportifs amateurs font face au même problème : il manque un joueur. Ou, à l'inverse, un joueur cherche une équipe. Le football à cinq se joue à neuf, mais il en faut dix. Le padel est un sport de quatre joueurs, mais l'ami s'est désisté à la dernière minute. On voudrait jouer au basket ce soir, mais les habituels sont absents.

Ce problème, banal en apparence, représente une friction quotidienne pour les 38 à 40 millions de sportifs amateurs français. La solution actuelle est toujours la même : appeler ou envoyer des messages à ses contacts, poster dans un groupe WhatsApp, espérer que quelqu'un se libère. C'est lent, inefficace, et surtout limité au cercle social existant. Impossible de toucher un inconnu fiable qui partage le même sport, le même niveau et la même disponibilité.

### Les solutions existantes échouent

Les applications sportives disponibles aujourd'hui ne résolvent pas ce problème central. Playtomic est excellent pour réserver un terrain de padel ou de tennis, mais ce n'est pas un outil de matchmaking entre joueurs — on réserve un court, pas une équipe. Decathlon Go et des plateformes similaires proposent des fonctionnalités de recherche de partenaires, mais l'expérience est basique, peu engageante et sans système de confiance. Les groupes Facebook ou Meetup sont des solutions généralistes qui manquent de structure : pas de filtrage par niveau, pas de gestion des candidatures, pas de réputation.

Le résultat est que la coordination sportive amateur reste, en 2026, principalement analogique. Les équipes se forment et se gèrent par messageries individuelles. Les organisateurs perdent du temps à vérifier les niveaux et à gérer les désistements. Les nouveaux arrivants dans une ville — étudiants, jeunes actifs mobiles — ne trouvent pas facilement où s'intégrer sportivement.

### Un pain point amplifié par des tendances structurelles

Ce problème est appelé à s'amplifier. L'urbanisation croissante et la mobilité professionnelle des 20-35 ans signifient que de plus en plus de sportifs n'ont pas de réseau sportif établi dans leur ville. La montée du sport individuel reconverti en sport collectif spontané (padel, running en groupe, basket-ball de rue) crée une demande massive pour des rencontres ad hoc organisées de façon fiable. Et la génération Z, native du digital, attend des solutions mobiles immédiates pour tous ses besoins de coordination.

---

## 3. LA SOLUTION — teams-up.fit

### Un outil de matching, pas juste une liste de matchs

teams-up.fit est une plateforme web (accessible aussi en Progressive Web App installable sur mobile) qui permet à deux types d'utilisateurs d'interagir : d'un côté, des équipes ou des organisateurs qui ont créé un match et cherchent à compléter leur effectif ; de l'autre, des joueurs individuels qui cherchent un match à rejoindre.

L'organisateur crée son match en précisant le sport, le format (5v5, 2v2, libre…), la date, le lieu, le niveau requis (selon la grille officielle de la fédération concernée — FFT pour le tennis, FFP pour le padel, FFBad pour le badminton), le nombre de joueurs recherchés et un éventuel prix indicatif par joueur (frais de terrain à partager). Il choisit si les candidatures sont validées automatiquement ou manuellement. Le match est alors visible par tous les joueurs de la plateforme, filtrés automatiquement en fonction de leurs préférences (ville, sport actif, niveau).

Le joueur parcourt les matchs disponibles, filtre par sport, niveau, date, heure et ville, et postule à celui qui l'intéresse avec un message optionnel. Il est immédiatement informé de la décision de l'organisateur. Si le match est complet, il peut s'inscrire en liste d'attente et est promu automatiquement si une place se libère.

### La confiance au cœur du système

La grande innovation de teams-up.fit par rapport aux solutions existantes est son système de réputation mutuelle. Après chaque match, les participants peuvent se noter mutuellement (1 à 5 étoiles, avec un commentaire). La particularité : la note n'est affichée publiquement que si les deux joueurs se sont notés. Ce mécanisme de réciprocité élimine les faux avis et les comportements stratégiques. Il crée un vrai signal de confiance : un joueur avec 50 avis mutuels à 4,8 étoiles est objectivement fiable.

Les participants peuvent également voter pour le "Homme du Match" dans les sept jours suivant la fin du match. Ce vote alimenté la progression du profil du joueur récompensé.

### Une expérience engageante grâce à la gamification

teams-up.fit intègre un système de progression RPG complet qui n'existe dans aucune application sportive comparable sur le marché français. Chaque utilisateur accumule des points d'expérience (XP) en jouant des matchs, en envoyant des messages, en laissant des avis, en complétant son profil. Ces XP lui permettent de progresser à travers dix niveaux (du bronze à l'élite), de débloquer des achievements (plus de 25 récompenses disponibles au lancement) et d'investir des points de statistiques dans huit attributs caractérisant son style de jeu (attaque, défense, vitesse, endurance, précision, tactique, travail d'équipe, mental).

Cette mécanique de jeu transforme chaque interaction avec la plateforme en un micro-événement valorisant. Elle crée de l'attachement, de la récurrence et de la fierté — autant de vecteurs de rétention naturelle qui ne dépendent pas de dépenses marketing.

### La communication intégrée

Chaque match dispose de son propre chat de groupe, accessible à tous les participants approuvés. Un système de messagerie privée permet également aux utilisateurs d'échanger en dehors des matchs. Ces conversations apparaissent dans un bandeau latéral persistant, accessible depuis toutes les pages de l'application. Les notifications en temps réel (ActionCable) alertent immédiatement les utilisateurs des nouvelles candidatures, approbations, messages et achievements débloqués.

### Le parcours utilisateur de bout en bout

Un utilisateur s'inscrit en quelques secondes via son adresse email ou son compte Google. Il configure son profil, indique ses sports de prédilection et son niveau pour chacun, sélectionne sa ville de pratique et ses terrains favoris. Ces préférences alimentent un algorithme de pré-filtrage qui lui affiche automatiquement les matchs les plus pertinents dès sa première connexion. Il postule, joue, note, progresse — et revient.

---

## 4. ÉTUDE DE MARCHÉ

### 4.1 Taille du marché — le sport amateur en France

La France est l'un des pays européens où la pratique sportive amateur est la plus développée. Selon l'INJEP (Institut National de la Jeunesse et de l'Éducation Populaire) et le Ministère des Sports, entre 66 et 70 % des Français de 15 ans et plus déclarent pratiquer une activité physique ou sportive au moins une fois par semaine, soit 38 à 40 millions de pratiquants réguliers sur une population de 68 millions d'habitants (données 2022-2023). Parmi eux, 16 millions sont licenciés dans une fédération sportive, et 15 à 17 millions pratiquent de façon libre et informelle — ce dernier segment représente le cœur de la cible de teams-up.fit.

Les sports les plus pertinents pour la plateforme cumulent plusieurs millions de pratiquants : le football (1,8 million de licenciés FFF, mais plusieurs millions de pratiquants non licenciés), le tennis (1,1 million de licenciés FFT), le padel (300 000 à 400 000 pratiquants en 2024 et en forte croissance), le basketball (490 000 licenciés FFBB), le handball (430 000), le volleyball (280 000) et le badminton (280 000 licenciés FFBad). Le marché adressable immédiat — les pratiquants de ces sept sports en France — représente entre 4 et 6 millions de personnes.

### 4.2 Le padel, moteur de croissance exceptionnel

Le padel constitue un cas d'étude particulièrement favorable pour teams-up.fit. Ce sport a connu en France une croissance sans précédent : d'environ 200 courts en 2019, le pays est passé à plus de 2 000 courts en 2024, soit une multiplication par dix en cinq ans. Le nombre de pratiquants est passé de quelques dizaines de milliers à plus de 300 000 à 400 000 en 2024. La France se classe désormais dans le top 5 mondial du padel. Cette dynamique crée un besoin massif de matchmaking : les joueurs de padel sont souvent seuls ou en duo, et ont besoin de trouver des partenaires ou des adversaires de niveau équivalent pour remplir leurs courts. teams-up.fit, avec son système de niveaux FFP intégré, répond précisément à ce besoin.

### 4.3 Le marché de la sport-tech

Le marché mondial des applications sportives et de fitness est estimé à 14,7 milliards de dollars en 2023, avec une croissance annuelle (CAGR) de 17 à 22 % projetée jusqu'en 2030 (Grand View Research, Statista). En Europe, ce marché représente 3 à 4 milliards d'euros, dont 500 à 800 millions en France toutes catégories confondues. Le segment spécifique du booking et du matchmaking sportif en ligne connaît une croissance encore plus rapide, estimée à 25-30 % par an sur la période 2022-2026.

Les données de comportement digital confirment cette tendance : 64 % des 18-35 ans utilisent une application mobile liée au sport (Eurobaromètre 2022), et l'adoption des apps de réservation sportive a progressé de 35 % entre 2020 et 2023. La dimension sociale du sport est un facteur déterminant : selon l'Eurobaromètre 2022, 72 % des sportifs amateurs citent la pratique avec d'autres personnes comme un facteur de motivation clé dans leur activité physique.

**Estimation TAM / SAM / SOM :**

Le marché total adressable (TAM) du matchmaking sportif en France est estimé à 1,5 à 2 milliards d'euros, en croisant le nombre de pratiquants amateurs, le taux de digitalisation et un panier annuel potentiel. Le marché adressable à court terme (SAM), limité aux pratiquants des sept sports couverts ayant un profil digital actif, est estimé à 150 à 300 millions d'euros. La part de marché réaliste à trois ans pour teams-up.fit (SOM), en ciblant Bordeaux puis la France, est évaluée entre 3 et 15 millions d'euros selon les scénarios de croissance.

Ces estimations sont des ordres de grandeur destinés à cadrer l'ambition du projet. Les projections financières ci-après reposent sur des hypothèses bottom-up plus conservatrices.

### 4.4 Profil démographique de la cible

Le sportif amateur français cible de teams-up.fit se caractérise ainsi (sources : INJEP 2022, Eurobaromètre Sport 2022) : majoritairement entre 18 et 34 ans (74 % des 18-34 ans pratiquent un sport régulièrement), pratique 2 à 3 fois par semaine, dépense en moyenne 770 euros par an liés à son activité sportive, et dans 78 % des cas utilise au moins une application mobile en lien avec le sport. La tranche des cadres et professions supérieures est surreprésentée (82 % de pratiquants réguliers). La part des femmes progresse de 3 à 4 points de pourcentage par an depuis 2018.

Ce profil correspond précisément à l'utilisateur type de teams-up.fit : jeune, urbain, digital-native, avec un pouvoir d'achat suffisant pour envisager un abonnement modeste, et une attente élevée en termes d'expérience utilisateur.

### 4.5 Analyse concurrentielle

Le marché du matchmaking sportif amateur en France est actuellement fragmenté et sous-servi. Aucun acteur ne propose une solution combinant toutes les fonctionnalités de teams-up.fit.

**Playtomic** est le leader européen du booking de terrains de padel et de tennis, présent dans plus de 45 pays avec environ 6 millions d'utilisateurs enregistrés (estimation 2023-2024) et une levée de série C de 65 millions d'euros en 2022. Son modèle repose sur la réservation de terrains (SaaS pour clubs + commission 10-15 %) et non sur le matchmaking entre joueurs. La dimension sociale et communautaire est absente. teams-up.fit ne cherche pas à concurrencer Playtomic sur la réservation, mais à compléter l'usage : trouver des adversaires ou des partenaires pour remplir le terrain que l'on a réservé.

**Sport Heroes** est une startup française spécialisée dans les défis sportifs d'entreprise (B2B), avec environ 1 million d'utilisateurs sur sa plateforme. Son marché est le CSR et le bien-être au travail, pas le sport amateur communautaire.

**Decathlon Go** propose des fonctionnalités basiques de recherche de partenaires sportifs, sans système de réputation, sans gamification et sans communication intégrée. L'expérience est perçue comme un outil utilitaire, pas une communauté.

**Padelway** est une petite application française spécialisée padel avec moins de 50 000 utilisateurs en France. Monosport et peu gamifiée.

**Sportiw** se positionne sur le recrutement sportif amateur/semi-professionnel, pas sur l'organisation de matchs spontanés.

En résumé, teams-up.fit se positionne sur un blanc du marché français : le matchmaking multi-sports, communautaire, gamifié, avec réputation intégrée. C'est une position défendable à court terme et différenciante à moyen terme.

---

## 5. PROPOSITION DE VALEUR & OFFRE

### 5.1 La plateforme — fonctionnalités au lancement

teams-up.fit est développée en Ruby on Rails 8.1 avec une architecture moderne. Au moment du lancement, la plateforme offre un ensemble de fonctionnalités complet et cohérent.

La gestion des matchs couvre l'intégralité du cycle de vie d'une session sportive : création avec paramétrage avancé (sport, format, niveau par grille officielle, date, lieu, nombre de joueurs, prix indicatif, validation manuelle ou automatique, visibilité publique ou privée), découverte via un moteur de recherche et de filtrage multi-critères avec pré-filtrage intelligent basé sur les préférences de l'utilisateur, gestion des candidatures avec approbation/rejet, liste d'attente automatique, chat de groupe en temps réel, export calendrier (format iCS), et indicateur d'urgence pour les matchs dans les deux prochaines heures.

Les profils utilisateurs sont riches et évolutifs : avatar hébergé sur Cloudinary, biographie, sport(s) pratiqués avec niveau et position pour chacun, terrains favoris, ville de prédilection, statistiques publiques (matchs joués, note moyenne, votes "Homme du Match"), et deux vues de profil — une vue "jeu" avec le système XP complet, et une vue simplifiée.

Le réseau social permet d'envoyer et d'accepter des demandes d'amis, de consulter les profils publics, d'échanger des messages privés en temps réel, et de recevoir des notifications instantanées pour toutes les actions importantes.

La gamification complète le tableau : 10 niveaux de progression XP (du bronze à l'élite), 25 achievements débloquables dans trois catégories (matchs, social, profil), et 8 attributs RPG personnalisables via des points gagnés à chaque montée de niveau.

La sécurité et la confiance sont des priorités : confirmation d'email obligatoire, connexion Google OAuth2, politique de mot de passe stricte, CAPTCHA hCaptcha sur les formulaires sensibles, limitation du débit (rack-attack), journalisation de sécurité et conformité RGPD.

### 5.2 La différenciation technique

Plusieurs choix techniques constituent des avantages compétitifs durables. La Progressive Web App permet une installation sur l'écran d'accueil du téléphone sans passer par les app stores, réduisant le coût d'acquisition mobile. L'architecture temps réel (ActionCable + Turbo Streams) offre une expérience réactive sans rechargement de page. Le système de niveaux officiels par fédération (FFT, FFP, FFBad) crée une référence commune et légitime entre joueurs. Enfin, la notation mutuelle obligatoire — les deux parties doivent se noter pour que la note soit affichée — est un mécanisme anti-manipulation inédit dans le secteur.

---

## 6. BUSINESS MODEL

### 6.1 Stratégie de monétisation

Le modèle de revenus de teams-up.fit repose sur une progression en trois phases, adaptée à la réalité d'une plateforme communautaire en amorçage.

**Phase 1 — Construction de la masse critique (mois 1 à 6) :** la plateforme est entièrement gratuite. L'objectif est d'atteindre un seuil critique d'utilisateurs à Bordeaux permettant d'activer les effets de réseau — une plateforme de matchmaking sportif n'a de valeur que si elle dispose d'un volume suffisant de matchs et de joueurs disponibles. Toutes les ressources sont dédiées à l'acquisition.

**Phase 2 — Freemium (à partir du mois 7) :** introduction d'un abonnement "Capitaine Premium" à 4,99 euros par mois ou 39,99 euros par an. Cet abonnement s'adresse aux organisateurs réguliers et inclut la création illimitée de matchs (le plan gratuit sera limité à trois créations par mois), la mise en avant des matchs dans les résultats de recherche, des statistiques avancées sur les participants, un badge de crédibilité "Capitaine Premium" visible sur le profil et l'export des données participants. Le taux de conversion attendu, basé sur les benchmarks des plateformes communautaires sportives, est de 3 à 5 % des utilisateurs actifs.

**Phase 3 — B2B & commission (à partir du mois 18) :** les complexes sportifs peuvent souscrire un "Pack Salle Partenaire" mensuel entre 99 et 299 euros selon le niveau de visibilité souhaité (featured dans les résultats de recherche par ville, badge partenaire sur leurs venues, statistiques d'engagement). Une commission sur les matchs à entrée payante (lorsque Stripe sera intégré) complétera ces revenus à partir de la troisième année.

### 6.2 Indicateurs économiques unitaires

**ARPU (Average Revenue Per User — revenu moyen par utilisateur) :** avec un taux de conversion à 4 % et un prix de 4,99 euros par mois, l'ARPU global (base totale) est de 0,20 euro par mois, soit 2,40 euros par an. L'ARPU des utilisateurs payants est de 4,99 euros par mois.

**CAC (Cost of Acquisition Customer — coût d'acquisition client) :** en phase 1, le CAC est quasi nul (acquisition organique). En phase 2, avec un budget marketing de 200 à 500 euros par mois pour 100 à 200 nouveaux utilisateurs, le CAC est estimé à 1 à 5 euros. Le CAC d'un abonné Premium est estimé à 25 à 50 euros en phase 2.

**LTV (Lifetime Value — valeur vie client) :** en supposant une durée de rétention moyenne de 12 mois pour un abonné Premium, la LTV est de 4,99 × 12 = 59,88 euros. Le ratio LTV/CAC (>1 pour un modèle viable) est donc très favorable : 59,88 / 25-50 = 1,2 à 2,4.

**Churn rate (taux d'attrition) :** pour une plateforme communautaire sportive, un churn mensuel cible de 5 à 8 % est réaliste. La gamification et la réputation accumulée créent des freins naturels au départ — un utilisateur avec 50 avis mutuels, des achievements et des amis actifs a une forte raison de rester.

---

## 7. STRATÉGIE GO-TO-MARKET

### 7.1 Phase 1 — Bordeaux First (mois 1 à 6)

La stratégie de lancement est délibérément locale et concentrée. Bordeaux Métropole, avec ses 800 000 habitants, ses 350 000 sportifs amateurs estimés, sa population étudiante dynamique d'environ 100 000 personnes et sa forte croissance du padel, constitue un terrain d'expérimentation idéal. La densité de la ville permet d'atteindre rapidement un seuil critique de matchs disponibles.

L'acquisition initiale repose sur trois leviers gratuits. Le premier est le réseau personnel des quatre fondateurs, activé intensément dès le premier jour. L'objectif est d'atteindre 200 à 300 utilisateurs engagés dans les deux premiers mois, en s'appuyant sur les cercles sportifs existants de l'équipe. Le deuxième levier est la production de contenu sur Instagram et TikTok : courtes vidéos documentant des matchs, présentant la gamification, mettant en scène des "Homme du Match". Ce contenu organique cible les 18-30 ans sportifs bordelais. Le troisième levier est la présence directe dans les communautés existantes : groupes Facebook sportifs bordelais, serveurs Discord, groupes WhatsApp de padel.

Un premier partenariat avec un ou deux complexes sportifs locaux sera recherché dès le lancement — en échange d'une visibilité gratuite sur la plateforme, le complexe parle de teams-up.fit à ses abonnés. Ce partenariat de lancement ne sera pas monétisé, mais servira à valider le modèle B2B pour la phase suivante.

### 7.2 Phase 2 — Accélération (mois 7 à 18)

Avec une base d'au moins 1 000 à 2 000 utilisateurs actifs à Bordeaux, la phase 2 introduit les premiers leviers payants. Un budget marketing de 200 à 500 euros par mois sera alloué à des partenariats avec 3 à 5 micro-influenceurs sportifs bordelais (10 000 à 50 000 abonnés), ciblant notamment les communautés padel, basket-ball et football à cinq.

La roadmap produit de cette phase inclut l'intégration de Stripe pour les paiements (activation de la commission sur les matchs à entrée payante), le lancement de l'abonnement Capitaine Premium, et le début de la prospection commerciale auprès des complexes sportifs pour les Packs Salle Partenaire.

Les premières "Team Nights" — des soirées sportives organisées en partenariat avec une salle, exclusivement réservées aux utilisateurs teams-up.fit — seront organisées pour créer un moment communautaire fort, générer du contenu organique et fidéliser les utilisateurs les plus actifs.

### 7.3 Phase 3 — Extension nationale (mois 19 à 36)

Fort d'une preuve de concept à Bordeaux (10 000 à 15 000 utilisateurs, modèle de revenus validé), teams-up.fit s'attaque à Paris et aux grandes métropoles françaises (Lyon, Toulouse, Marseille, Nantes). La stratégie de déploiement réplique le modèle bordelais : partenariats locaux en amont, activation des communautés sportives existantes, micro-influenceurs locaux.

Une application mobile native (React Native) pourra être envisagée à ce stade si le budget le permet, pour accéder aux canaux d'acquisition des stores et améliorer l'expérience mobile. En parallèle, une stratégie de contenu SEO (guides pratiques "Comment trouver un partenaire de padel à Paris", "Les meilleurs terrains de foot à 5 à Lyon"…) alimentera un trafic organique croissant sans coût d'acquisition incrémental.

Des partenariats avec des ligues amateurs, des clubs universitaires et des fédérations régionales permettront d'accéder à des bases d'adhérents préqualifiées.

### 7.4 Rétention

La rétention est intégrée au design produit, pas ajoutée après coup. La gamification (progresser dans les niveaux, débloquer des achievements, construire sa réputation) crée une incitation intrinsèque à revenir jouer. Le réseau social (amis, messagerie privée) crée des liens qui retiennent l'utilisateur même entre deux matchs. Les notifications temps réel réactivent les utilisateurs inactifs. La récurrence naturelle du sport — les gens jouent toutes les semaines — est le meilleur moteur de rétention. L'objectif est un taux de rétention à 30 jours supérieur à 40 % dès la fin de la phase 1.

---

## 8. PLAN OPÉRATIONNEL

### 8.1 L'équipe fondatrice

L'équipe de teams-up.fit est composée de quatre personnes aux profils tech et design complémentaires. Cette configuration est typique des startups en phase d'amorçage où le produit prime : l'équipe a conçu et développé l'intégralité de la plateforme sans ressources externes.

Le point de vigilance est l'absence de profil business dédié dans l'équipe actuelle. À mesure que la plateforme grandit, un renfort commercial et marketing sera nécessaire — soit par le développement interne des compétences de l'un des fondateurs vers ces domaines, soit par un premier recrutement.

### 8.2 Organisation et roadmap produit

La cadence de développement actuelle est itérative, avec des livraisons régulières de nouvelles fonctionnalités et de corrections. La roadmap produit pour les 12 prochains mois est organisée ainsi :

Le premier trimestre post-lancement (mai-juillet 2026) est consacré à la stabilisation et à la collecte de retours utilisateurs réels. Les premiers indicateurs d'engagement (taux de création de matchs, taux de candidatures, rétention à 7 et 30 jours) guideront les itérations produit. L'intégration de Stripe pour les paiements et le lancement du Capitaine Premium seront les priorités techniques de ce trimestre.

Le deuxième trimestre (août-octobre 2026) sera dédié à l'amélioration du système de matching (suggestions personnalisées, notifications proactives "Un match vous correspond"), à l'enrichissement de la gamification (nouvelles saisons d'achievements, challenges communautaires), et au développement des outils B2B pour les salles partenaires.

Le troisième trimestre (novembre 2026-janvier 2027) verra la préparation de l'extension vers Paris : adaptation de la base de données venues pour Île-de-France, campagnes d'acquisition ciblées, premiers recrutements si les revenus le permettent.

### 8.3 Stack technique

La plateforme repose sur une architecture moderne, performante et maintainable. Le backend est développé en Ruby on Rails 8.1.3 avec PostgreSQL comme base de données principale (incluant la recherche full-text via pg_search). Le temps réel est géré par ActionCable et Turbo Rails. Le stockage des médias est délégué à Cloudinary via Active Storage. Les tâches asynchrones sont gérées par SolidQueue. Le déploiement est containerisé avec Kamal (Docker), ce qui simplifie la mise à l'échelle. Le frontend utilise Bootstrap 5.3, Stimulus et Importmap — sans bundler JavaScript, réduisant la complexité de build.

Cette stack est à la fois productive (Rails permet un développement rapide), robuste (PostgreSQL, Redis, ActionCable sont des technologies éprouvées) et économique à opérer (coûts d'infrastructure inférieurs à 150 euros par mois en phase 1).

### 8.4 Conformité RGPD

La plateforme collecte des données personnelles (email, prénom, nom, téléphone, localisation, photo). Une politique de confidentialité et des conditions générales d'utilisation seront rédigées avant le lancement. Les mécanismes techniques de suppression de compte et d'export de données sont prévus dans la roadmap Q1 post-lancement.

---

## 9. PLAN FINANCIER

### 9.1 Hypothèses clés

Le plan financier repose sur les hypothèses suivantes, construites à partir de benchmarks sectoriels et adaptées à la réalité du projet.

En termes de croissance utilisateurs : 500 utilisateurs à fin de l'année 1 (6 mois de lancement), 5 000 à fin de l'année 2 (Bordeaux consolidé + début extension), 25 000 à fin de l'année 3 (présence nationale établie). Ces chiffres sont volontairement conservateurs pour la France — à titre de comparaison, des applications communautaires sportives similaires ont atteint 10 000 utilisateurs en 6 à 12 mois dans des marchés équivalents.

En termes de conversion Premium : 0 % en Phase 1 (gratuit), 3 % à partir du mois 7, 4 % en année 2, 5 % en année 3. Ces taux sont inférieurs aux benchmarks freemium standard (généralement 2 à 7 %) pour rester prudents.

En termes de B2B (Packs Salle Partenaire) : 0 partenaire en année 1, 5 partenaires à 149 euros/mois en milieu d'année 2, 20 partenaires en année 3 à un prix moyen de 199 euros/mois.

Coûts d'infrastructure : 150 euros/mois en année 1, 300 euros/mois en année 2 (scaling), 600 euros/mois en année 3.

### 9.2 Compte de résultat prévisionnel (3 ans)

**Année 1 — Mai 2026 à Avril 2027**

| Poste | Montant |
|---|---|
| Revenus abonnements Premium (6 mois x ~30 abonnés x 4,99€) | 900 € |
| Revenus B2B Salles Partenaires | 0 € |
| **Total revenus** | **~900 €** |
| Hébergement & infra (12 mois x 150€) | 1 800 € |
| Marketing & contenu (12 mois x 150€) | 1 800 € |
| Frais juridiques (CGU, RGPD, one-shot) | 1 000 € |
| Outils SaaS (email, monitoring, etc.) | 600 € |
| **Total charges** | **~5 200 €** |
| **Résultat net** | **-4 300 €** |

**Année 2 — Mai 2027 à Avril 2028**

| Poste | Montant |
|---|---|
| Revenus abonnements Premium (moy. 150 abonnés x 4,99€ x 12) | 8 982 € |
| Revenus B2B Salles Partenaires (5 x 149€ x 6 mois) | 4 470 € |
| **Total revenus** | **~13 450 €** |
| Hébergement & infra (12 mois x 300€) | 3 600 € |
| Marketing & acquisition (12 mois x 400€) | 4 800 € |
| Outils SaaS | 1 200 € |
| Frais divers | 1 000 € |
| **Total charges** | **~10 600 €** |
| **Résultat net** | **+2 850 €** |

**Année 3 — Mai 2028 à Avril 2029**

| Poste | Montant |
|---|---|
| Revenus abonnements Premium (moy. 1 000 abonnés x 4,99€ x 12) | 59 880 € |
| Revenus B2B Salles Partenaires (20 x 199€ x 12) | 47 760 € |
| Commission matchs payants (estimatif) | 5 000 € |
| **Total revenus** | **~112 640 €** |
| Hébergement & infra | 7 200 € |
| Marketing & acquisition | 15 000 € |
| Premier recrutement partiel (freelance/CDI partiel) | 30 000 € |
| Outils SaaS & frais généraux | 5 000 € |
| **Total charges** | **~57 200 €** |
| **Résultat net** | **+55 440 €** |

### 9.3 Seuil de rentabilité

Le seuil de rentabilité mensuel, en couvrant uniquement les charges fixes d'infrastructure (150 euros/mois en phase 1), est atteint dès 31 abonnés Premium actifs (150 / 4,99 = 30,06). Ce seuil très bas est un avantage structurel de teams-up.fit : l'entreprise peut être rentable avec un volume d'utilisateurs payants modeste.

Le seuil de rentabilité global (incluant le marketing et les frais généraux) est atteint en milieu d'année 2, soit environ 18 mois après le lancement. Ce calendrier est réaliste et ne nécessite pas de financement externe significatif si l'équipe peut absorber le déficit de l'année 1 sur fonds propres.

### 9.4 Besoin de financement

Dans le scénario de base (croissance organique, pas de recrutement avant l'année 3), le besoin de financement externe est limité. Le déficit de l'année 1 est d'environ 4 300 euros — un montant absorbable sur fonds propres même avec des ressources modestes.

Si l'équipe souhaite accélérer la croissance (marketing plus agressif, recrutement d'un profil business/marketing dès l'année 2, développement d'une application mobile native), un financement de 30 000 à 80 000 euros permettrait d'atteindre les objectifs de l'année 2 en 12 mois plutôt que 18. Ce financement pourrait provenir d'un incubateur (BPI Emergence, programme French Tech), d'une aide à l'innovation (Aide à la Création d'Entreprises de Technologies Innovantes — ACETI), ou d'un premier tour de love money / business angels.

---

## 10. RISQUES ET FACTEURS CLÉS DE SUCCÈS

### Risques principaux

Le principal risque d'une plateforme de matchmaking est le problème de l'œuf et de la poule : sans matchs, pas de joueurs ; sans joueurs, pas de matchs. La stratégie de lancement local concentré à Bordeaux est conçue précisément pour franchir ce seuil critique sur un périmètre géographique restreint avant de s'étendre.

Le risque de monétisation — la question de savoir si les utilisateurs accepteront de payer pour un service initialement gratuit — est atténué par la nature de l'abonnement Capitaine Premium, qui cible spécifiquement les organisateurs réguliers (et non tous les utilisateurs), et par la valeur tangible apportée (mise en avant, statistiques, créations illimitées).

Le risque réglementaire est limité mais réel : la plateforme collecte des données personnelles et doit être en conformité RGPD. Un travail juridique sera réalisé avant le lancement pour couvrir les obligations légales essentielles.

### Facteurs clés de succès

Le succès de teams-up.fit repose sur trois facteurs. En premier lieu, atteindre rapidement un volume de matchs suffisant à Bordeaux pour que chaque utilisateur trouve un match pertinent à rejoindre — sans cela, la plateforme perd de sa valeur. En deuxième lieu, la qualité de l'expérience utilisateur et la fiabilité technique : une seule mauvaise expérience (inscription longue, match annulé sans prévenir, bug visible) peut décourager un early adopter et nuire au bouche-à-oreille. En troisième lieu, la cohérence de l'animation communautaire : les premières semaines après le lancement sont déterminantes pour construire un noyau d'utilisateurs engagés qui deviendront les ambassadeurs naturels de la plateforme.

---

## 11. CONCLUSION

teams-up.fit adresse un problème réel, quotidien et largement répandu parmi les millions de sportifs amateurs français. Le produit est techniquement abouti, différencié et prêt à être mis entre les mains des utilisateurs. Le marché est en croissance structurelle, porté notamment par l'explosion du padel et la digitalisation des pratiques sportives. Le modèle économique est sain, avec un seuil de rentabilité atteignable sans financement externe significatif.

L'enjeu des prochains mois est celui de l'exécution : valider le product-market fit à Bordeaux, construire une communauté engagée, activer le modèle de revenus freemium et préparer une extension nationale méthodique. L'équipe a démontré sa capacité à concevoir et développer un produit complexe et de qualité. La prochaine étape est de démontrer la même rigueur dans la conquête des utilisateurs.

---

*Document confidentiel — teams-up.fit — Avril 2026*  
*Estimations financières à titre indicatif. Données marché issues de sources publiques (INJEP, Ministère des Sports, Eurobaromètre 2022, Grand View Research, Statista) et d'extrapolations signalées comme telles. À actualiser avec les données réelles post-lancement.*

---

## ANNEXE — Business Model Canvas (synthèse)

Voir fichier `tasks/business_model_canvas.md`
