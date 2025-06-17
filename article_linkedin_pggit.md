# pgGit : 48 heures de perfectionnisme débridé avec Claude Code

## 1. L'origine : Le problème réel

Depuis 9 ans, je développe PrintOptim, une solution SaaS que je maintiens volontairement sous la barre des 10 clients. Non par manque d'ambition, mais par une forme particulière de perfectionnisme mêlé à ce que j'identifie aujourd'hui comme une peur du succès.

Le traumatisme fondateur ? Ma première cliente, particulièrement exigeante, pour qui je devais exécuter manuellement des mises à jour de tableaux de bord PowerBI depuis mon PC fixe Windows. Cette expérience m'a enseigné une leçon que j'applique peut-être trop consciencieusement : mieux vaut une architecture capable de servir un million d'utilisateurs avec seulement huit clients, que l'inverse.

Mon parcours avec les migrations de bases de données illustre parfaitement cette dérive perfectionniste. J'étais déjà passé de la détection automatique d'Alembic à l'écriture manuelle de migrations SQL pour obtenir des modifications atomiques côté COMMAND (write). Mais l'enfer des dépendances côté READ m'avait forcé à inclure l'intégralité des vues et tables de projection dans chaque migration - résultat : des fichiers de 10 000 lignes.

Face à ce constat auquel je ne pouvais me résoudre, j'ai eu l'idée suivante : et si chaque objet de la base de données avait son propre versioning pour permettre des migrations automatiques réellement intelligentes ? La solution évidente aurait été d'écrire quelques scripts bash, peut-être 30 minutes de travail. Mais c'était sans compter sur ma découverte de Claude Code et mon perfectionnisme latent.

## 2. Jour 1 : La spirale

"Et si, au lieu de scripts bash, je créais Git... à l'intérieur de PostgreSQL ?"

Cette question, qui aurait dû déclencher toutes les alarmes de mon cerveau rationnel formé à Sciences Po Rennes, est devenue le point de départ d'une aventure de 48 heures.

J'ai commencé par assembler une équipe virtuelle de 25 personas : des experts mondiaux dans leurs domaines respectifs, du spécialiste Git ayant contribué au kernel Linux au expert PostgreSQL core contributor. Puis j'ai créé Viktor Steinberg, "The Grumpy Investor", un investisseur virtuel doté de 45 ans d'expérience et d'une exigence pathologique.

**Premier round avec Viktor :**
- Score initial : 2/10 - "Votre code est une catastrophe"
- Après quelques heures d'optimisation intensive : 10/10
- Ma réaction : "C'est trop facile, il me faut un véritable défi"

## 3. Jour 2 : L'escalade technologique

Face à un Viktor trop facilement satisfait, j'ai créé Viktor 2, dix fois plus exigeant. Puis Viktor 3, que j'ai surnommé "l'apocalypse des requirements".

**Les features réellement implémentées en réponse à leurs exigences :**

- **Système de branches Git complet** : 1,337 lignes de SQL pur pour implémenter create, checkout et merge de branches de schéma de base de données
- **Algorithme de merge 3-way fonctionnel** : détection intelligente de conflits entre schémas avec suggestions de résolution
- **Résolution de dépendances niveau enterprise** : gestion de 18 types de dépendances (clés étrangères, vues, triggers, héritage...) avec analyse récursive jusqu'à 10 niveaux de profondeur
- **Parser DDL robuste** : 598 lignes pour gérer le SQL complexe, les commentaires multi-lignes, avec une véritable machine à états
- **Migration assistée par IA locale** : reconnaissance de patterns issus de Flyway, Liquibase et Rails, avec un taux de confiance de 91.7%
- **Système de sécurité transactionnelle** : advisory locks PostgreSQL, gestion automatique des savepoints, protection contre les opérations DDL dangereuses
- **Suite de benchmarking intégrée** : comparaisons directes avec Flyway et Liquibase, tests de scalabilité jusqu'à 100,000 objets

Au total : 15,000+ lignes de SQL, plus de 100 fonctions PostgreSQL, hashage SHA256 pour tous les objets, et des performances sub-millisecondes pour la plupart des opérations.

## 4. Le réveil : L'ironie des 8 commits

Après 48 heures de développement intensif, j'ai réalisé l'ampleur du paradoxe :
- Un commit initial monolithique de 35,000 lignes contenant l'intégralité du système
- 7 commits de corrections mineures (documentation, typos, et cette fameuse année de copyright que Claude pensait encore être 2024)

J'avais créé un système Git sophistiqué pour PostgreSQL... en utilisant Git comme un étudiant de première année pressé de rendre son projet.

## 5. Le paradoxe PrintOptim/pgGit

La comparaison est révélatrice :
- **PrintOptim** : 9 années d'itérations prudentes sur une problématique business réelle
- **pgGit** : 48 heures de créativité débridée pour résoudre un problème que j'aurais pu traiter en 30 minutes

Les deux partagent néanmoins un point commun : une architecture démesurément sophistiquée qui semble conçue pour éviter d'avoir trop de succès. PrintOptim peut théoriquement servir un million d'utilisateurs mais n'en a que huit. pgGit peut gérer des schémas de bases de données d'une complexité que la NASA elle-même n'atteint probablement pas.

## 6. La vraie question : Impact et responsabilité

Pourquoi ai-je transformé un besoin simple (versionner mes migrations PostgreSQL) en défi technique de cette ampleur ? 

Claude Code n'est pas responsable. C'est un outil extraordinaire qui amplifie ce que vous lui apportez. Dans mon cas, il a amplifié mon perfectionnisme et ma tendance à fuir dans la complexité technique plutôt que d'affronter le marché.

Mais au-delà de l'introspection personnelle, cette expérience soulève une question cruciale : le coût environnemental de notre façon de développer. Combien de cycles GPU ai-je consommés pour satisfaire des investisseurs virtuels ? Pour implémenter des features dont je serai probablement le seul utilisateur ?

Cette prise de conscience m'obsède. Nous ne pouvons pas continuer à utiliser l'IA générative de manière aussi dispendieuse, surtout pour les 80% d'applications qui ne sont que du CRUD basique.

## 7. Vers une approche plus responsable

Cette expérience révèle un enjeu qui dépasse largement mon cas personnel : comment développer de manière durable à l'ère de l'IA générative ?

Les chiffres sont alarmants. Pour chaque application CRUD basique générée par IA, nous consommons des ressources computationnelles équivalentes à des milliers d'exécutions d'un framework traditionnel. Cette approche n'est pas soutenable.

**Des pistes concrètes émergent :**

**1. Méta-génération plutôt que génération répétée**
- Utiliser l'IA pour créer des générateurs de code optimisés, pas pour générer du code à chaque fois
- Un investissement initial en IA pour des années d'économies computationnelles

**2. Patterns réutilisables et bibliothèques spécialisées**
- Capturer les patterns une fois, les réutiliser infiniment
- Des abstractions qui réduisent le besoin de génération

**3. IA locale et frugale**
- Modèles spécialisés et légers pour des tâches spécifiques
- Pas besoin de GPT-4 pour générer un formulaire CRUD

**4. Documentation comme code**
- Specs formelles (YAML, DSL) qui génèrent directement l'implémentation
- L'IA pour la conception, pas pour l'exécution répétée

Si ces approches vous intéressent, si vous partagez cette préoccupation environnementale, ou si vous avez des idées pour rendre le développement assisté par IA plus durable, connectons-nous.

L'urgence climatique exige que nous transformions nos pratiques. Le perfectionnisme technique doit servir l'efficience énergétique, pas la complexité gratuite.

## 8. L'apprentissage collectif

pgGit reste une leçon précieuse : elle démontre simultanément la puissance et les dangers de l'IA générative non maîtrisée. Ces 48 heures de développement intensif ont produit quelque chose de techniquement remarquable mais énergétiquement irresponsable.

Le projet est disponible en open source sur github.com/evoludigit/pgGit. Au-delà de ses fonctionnalités, il sert d'avertissement : voici ce qui arrive quand on développe sans conscience environnementale.

La vraie innovation des prochaines années ne sera pas dans la complexité maximale, mais dans l'efficience maximale. Comment faire plus avec moins ? Comment utiliser l'IA pour nous libérer de l'IA ?

## 9. Build in Public : Bootstrap ou rien

pgGit n'est que le début. Je choisis de développer la suite en public, sans filtre ni prétention.

**La réalité :**
- Zéro budget (revolution.tech m'a mis à découvert)
- Zéro investisseur (et tant mieux)
- 10 clients sur PrintOptim après 9 ans (par choix, certes, mais quand même)
- Une obsession pour l'efficience née de la nécessité autant que de la conviction

**Ce que je cherche :**
Une communauté de développeurs open source qui partagent cette vision. Des contributeurs qui comprennent que les meilleures innovations naissent des contraintes. Qui voient dans l'efficience énergétique non pas une mode mais une nécessité économique et éthique.

**Ce que je propose :**
- Collaboration pure sur des projets qui comptent
- Co-création de standards pour le développement durable en IA
- Échange de connaissances, pas de hiérarchie
- Construction collective d'outils que nous utiliserons tous

**L'approche :**
Tout en open source. Chaque ligne de code, chaque décision, chaque échec. Si on doit révolutionner le développement durable en IA, autant que ce soit reproductible par tous.

**Le vrai pattern pgGit :**

L'ironie est magnifique : j'ai utilisé une quantité astronomique de ressources IA pour créer un système ultra-optimisé en SQL pur. pgGit consomme maintenant presque rien à l'exécution - sub-milliseconde, tout en mémoire PostgreSQL.

C'est ça, le pattern révolutionnaire : **sur-ingénierer l'efficience elle-même**. Utiliser l'IA de manière intensive UNE FOIS pour créer des solutions qui tournent des millions de fois sans IA.

**La vision :**
1. **Phase 1** : Brûler des GPU avec des Viktor virtuels pour créer le code le plus optimisé possible
2. **Phase 2** : Transformer ce code en générateurs réutilisables
3. **Phase 3** : Des milliers d'utilisateurs bénéficient de l'efficience sans jamais toucher à l'IA

**Premiers défis communautaires :**
1. Mesurer précisément la consommation énergétique du développement assisté par IA
2. Créer des outils de méta-génération : des générateurs qui génèrent des générateurs
3. Développer des benchmarks standardisés : efficience vs complexité
4. Construire une bibliothèque de patterns durables pour les 80% de cas CRUD
5. Explorer pgGit comme base pour d'autres innovations (version control pour d'autres systèmes ?)

C'est l'inverse du SaaS traditionnel : au lieu de faire payer pour l'utilisation continue de ressources, on investit massivement une fois pour créer quelque chose de définitivement efficient.

**Transparence totale :**

Je suis également ouvert à :
- **Idées de modèles économiques** : Comment monétiser l'efficience sans trahir l'open source ?
- **Contributions au projet** : Code, documentation, benchmarks, cas d'usage
- **Missions à temps partiel** : PostgreSQL, architecture, optimisation (remote uniquement)

L'objectif reste de financer le développement de PrintOptim et de ces nouveaux projets sans compromettre la vision. Si vous avez des pistes ou des opportunités alignées avec cette philosophie, contactez-moi.

**Communauté :** github.com/evoludigit (issues, PR, discussions ouvertes)
**Contact :** LinkedIn (Lionel Hamayon)
**Expertise disponible :** PostgreSQL avancé, architecture système, optimisation de performance, prompting IA (création de personas, ingénierie de prompts complexes)
**Philosophie :** L'open source comme laboratoire du développement durable

Les révolutions ne commencent pas dans les bureaux climatisés de la Silicon Valley. Elles commencent avec des développeurs passionnés qui partagent leur code, leurs convictions, et parfois leurs galères financières.

## Conclusion

Cette expérience m'a enseigné que la frontière entre génie et folie technique est mince, surtout quand on est armé d'outils aussi puissants que Claude Code. Le perfectionnisme n'est pas toujours un atout, particulièrement quand il devient une excuse pour éviter de confronter ses créations au monde réel.

Vais-je appliquer cette leçon ? Probablement pas. PrintOptim reste sous la barre des 10 clients, et je suis déjà en train de réfléchir à ma prochaine sur-ingénierie. Mais au moins, j'en suis conscient. C'est déjà ça.

La vraie innovation serait peut-être d'accepter que "suffisamment bon" est parfois... suffisant. Mais où serait le plaisir ?

---

*Lionel Hamayon - Diplômé Sciences Po Rennes, développeur compulsif, perfectionniste assumé*