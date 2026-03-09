# Team Up - CLAUDE.md

Ce fichier contient des informations sur le projet pour Claude Code.

## Description du projet

Application Ruby on Rails bootstrappée avec le template Devise de lewagon.

## Stack technique

- **Framework** : Ruby on Rails
- **Authentification** : Devise
- **Base de données** : (à préciser)

## Conventions

- (à compléter)

## Commandes utiles

```bash
# Lancer le serveur
rails server

# Lancer les migrations
rails db:migrate

# Lancer les tests
rails test
```
Orchestration des flux de travail

Je travail sur rails et je suis junior ne fait pas du code trop compliqué, commente toujours tous le code pour m'aider a lire le code. On utilisera rails, stimulus, html/scss, bootstrap, JavaScript.

Mode Planification par défaut

• Activez le mode planification pour toute tâche complexe (3 étapes ou plus, ou décisions architecturales).

• En cas d'imprévu, arrêtez-vous et repensez immédiatement votre planification – n'insistez pas.

• Utilisez le mode planification pour les étapes de vérification, et pas seulement pour la construction.

• Rédigez des spécifications détaillées en amont pour éviter toute ambiguïté.

Stratégie des sous-agents

• Utilisez les sous-agents de manière judicieuse pour désencombrer la fenêtre principale.

• Confiez la recherche, l'exploration et l'analyse parallèle aux sous-agents.

• Pour les problèmes complexes, allouez davantage de ressources de calcul via les sous-agents.

• Une tâche par sous-agent pour une exécution ciblée.

Boucle d'amélioration continue

• Après toute correction de l'utilisateur : mettez à jour le fichier tasks/lessons.md avec le modèle.

• Définissez des règles pour éviter de reproduire la même erreur.

• Itérez sans relâche sur ces leçons jusqu'à réduire le taux d'erreurs.

• Consultez les leçons au début de chaque session pour chaque projet.

Vérification avant finalisation • Ne jamais marquer une tâche comme terminée sans avoir prouvé son bon fonctionnement.

• Comparer le comportement du code principal et de vos modifications, le cas échéant.

• Se demander : « Un ingénieur senior approuverait-il cela ? »

• Exécuter les tests, vérifier les journaux, démontrer la correction.

Exiger l'élégance (Équilibré)

• Pour les modifications importantes : faire une pause et se demander : « Existe-t-il une solution plus élégante ? »

• Si une correction semble peu élégante : « Avec le recul, implémenter la solution élégante. »

• Ignorer cette étape pour les corrections simples et évidentes ; ne pas sur-ingénierie.

• Remettre en question son propre travail avant de le présenter.

Correction autonome des bogues

• Lorsqu'un rapport de bogue est reçu : le corriger, tout simplement. Ne demandez pas d'assistance constante.

• Indiquez les journaux, les erreurs et les tests en échec, puis résolvez-les.
• L'utilisateur n'a pas besoin de changer de contexte.

• Corrigez les tests d'intégration continue en échec sans qu'on vous dise comment faire.

Gestion des tâches

Planifiez d'abord : Rédigez un plan dans tasks/todo.md avec des éléments cochables.

Vérifiez le plan : Enregistrez-le avant de commencer l'implémentation.

Suivez la progression : Marquez les éléments comme terminés au fur et à mesure.

Expliquez les changements : Rédigez un résumé à chaque étape.

Documentez les résultats : Ajoutez une section de révision à tasks/todo.md.

Capturez les enseignements : Mettez à jour tasks/lessons.md après les corrections.

Principes fondamentaux

• La simplicité avant tout : Simplifiez au maximum chaque changement. Impactez le moins de code possible.

• Pas de paresse : Trouvez les causes profondes. Pas de solutions temporaires. Respectez les normes des développeurs expérimentés.

• Impact minimal : Les changements ne doivent toucher que le nécessaire. Évitez d'introduire des bogues.
