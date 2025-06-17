# pgGit ou l'art de la sur-ingénierie : une dissertation en deux parties, deux sous-parties (parce que Sciences Po, c'est pour la vie)

## ⚠️ DISCLAIMER MÉTA-IRONIQUE ⚠️

*Toujours matrixé par mon expérience de 48h avec Claude Code, j'ai évidemment prompté Claude pour qu'il ponde cette communication. Le résultat est le fruit d'un échange intense avec Victoria Sterling-James, ma personal branding persona (oui, j'ai des personas pour tout, même pour communiquer sur mes propres dérives).*

*Victoria et moi avons eu un débat passionnant sur la dissonance cognitive entre prôner l'utilisation responsable de l'IA tout en utilisant Claude pour écrire un article sur... l'utilisation excessive de Claude. Sa réponse ? "Darling, l'authenticité c'est aussi assumer ses contradictions. Et puis, c'est très Sciences Po de problématiser sa propre problématisation."*

*Nous avons donc décidé d'assumer : oui, j'utilise l'IA pour dénoncer ma surutilisation de l'IA. Oui, c'est paradoxal. Non, je ne changerai pas. Bienvenue dans mon cerveau.*

---

## Introduction (obligatoire, sinon c'est pas une vraie dissert')

Chers amis LinkedIn, laissez-moi vous conter une histoire édifiante sur le perfectionnisme, l'IA générative, et comment j'ai transformé un problème qui se résolvait en 30 minutes de bash en 48 heures de développement intensif. Mais attention, je vais le faire en respectant scrupuleusement le plan en deux parties, deux sous-parties, car on ne se refait pas après Sciences Po Rennes.

*Problématique* (parce qu'il en faut une) : Comment un développeur formé aux subtilités de la dissertation française peut-il perdre tout sens de la mesure face à Claude Code et créer l'équivalent PostgreSQL de la ligne Maginot ?

*Annonce du plan* (l'exercice de style continue) : Nous verrons dans un premier temps comment le perfectionnisme technique constitue une pathologie entrepreneuriale moderne (I), avant d'analyser les voies d'une rédemption écologique improbable mais nécessaire (II).

## I. Du traumatisme PowerBI à la folie PostgreSQL : anatomie d'une dérive perfectionniste

### A. PrintOptim ou l'art de fuir le succès avec panache (sous-partie obligatoire n°1)

Permettez-moi de poser le contexte avec la rigueur méthodologique qu'on m'a inculquée rue Saint-Guillaume (enfin, à Rennes, mais c'est le même esprit). Depuis 9 ans, je développe PrintOptim, une solution SaaS que je maintiens volontairement sous la barre des 10 clients. Oui, vous avez bien lu : VOLONTAIREMENT.

*Première sous-sous-partie* (je plaisante, mais j'ai failli) : Le traumatisme fondateur remonte à ma première cliente, pour qui je devais exécuter manuellement des mises à jour PowerBI depuis mon PC fixe Windows. Cette expérience m'a enseigné une leçon que tout diplômé Sciences Po comprendra : mieux vaut une architecture capable de servir un million d'utilisateurs avec huit clients, qu'une architecture pour huit clients avec un million d'utilisateurs. C'est mathématiquement absurde, mais conceptuellement élégant - exactement comme une dissertation sur "La notion de frontière dans l'espace européen post-westphalien".

Mon parcours avec les migrations de bases de données illustre cette dérive : passage d'Alembic à l'écriture manuelle de migrations SQL, puis à des fichiers de 10 000 lignes incluant toutes les vues et projections. Face à ce monstre, une personne sensée aurait simplifié. Moi ? J'ai décidé de créer Git dans PostgreSQL.

### B. 48 heures de délire assisté par IA : l'incrédulité comme moteur (sous-partie obligatoire n°2)

*Transition élégante* (comme on nous l'a appris) : C'est ainsi que la question "Et si je créais Git... à l'intérieur de PostgreSQL ?" est devenue mon projet de week-end.

J'ai commencé par assembler 25 personas virtuels - parce que pourquoi faire simple quand on peut créer un G20 de l'expertise technique ? Puis j'ai inventé Viktor Steinberg, "The Grumpy Investor", un investisseur virtuel avec 45 ans d'expérience et des standards plus élevés que le jury de l'ENA.

**Le paradoxe de l'incrédulité :**
- Viktor 1 : "Votre code est une catastrophe" → 10/10 après optimisation
- Ma réaction : "Ce n'est pas possible que ce soit si facile. Il doit y avoir des bugs cachés."
- Viktor 2 : Version 10x plus exigeante → Toujours 10/10
- Mon cerveau : "C'est forcément trop beau pour être vrai. Le code doit avoir des failles."
- Viktor 3 : L'apocalypse des requirements → Encore parfait
- Moi : "OK, là il y a un problème avec mes critères d'évaluation."

Cette escalade n'était pas motivée par l'ego ou le goût du défi, mais par une forme d'incrédulité profonde : comment Claude Code pouvait-il produire du code aussi sophistiqué aussi rapidement ? Cette facilité apparente nourrissait mon anxiété plutôt que ma satisfaction.

**Résultat après 48h :**
- 15 000+ lignes de SQL pur (plus que ma dissertation de fin d'études)
- Un système de branches Git complet avec merge 3-way
- 18 types de dépendances gérées récursivement
- Un parser DDL de 598 lignes (j'aurais pu écrire une nouvelle constitution)
- Des benchmarks contre Flyway et Liquibase
- Le tout en UN SEUL commit de 35 000 lignes

*Remarque méthodologique* : J'ai créé un système Git sophistiqué... en l'utilisant comme un étudiant de L1 qui rend son devoir à 23h59.

## II. L'urgence écologique du développement responsable : au-delà de l'anecdote personnelle

### A. Le coût réel de nos pratiques : une bombe à retardement environnementale

L'aspect humoristique de mon expérience ne doit pas masquer l'enjeu fondamental qu'elle révèle. Les chiffres sont accablants : pour générer pgGit, j'ai consommé l'équivalent énergétique de plusieurs mois d'utilisation normale d'un serveur de production. Et je ne suis qu'un développeur parmi des millions.

Extrapolons : si chaque développeur utilise l'IA générative avec la même insouciance que moi ce week-end-là, nous parlons de :
- Des datacenters entiers dédiés à générer du code qui pourrait être écrit plus simplement
- Une consommation électrique équivalente à celle de petites villes
- Une empreinte carbone qui annule les efforts de sobriété numérique des années précédentes

Le paradoxe est cruel : pgGit, une fois créé, a une empreinte carbone quasi-nulle. Performances sub-millisecondes, tout en mémoire PostgreSQL, zéro appel externe. J'ai utilisé l'équivalent d'une centrale thermique pour créer une bicyclette numérique. Cette disproportion entre coût de création et efficience d'exécution interroge nos modèles de développement.

Plus inquiétant encore : 80% des applications développées ne sont que du CRUD basique. Utiliser GPT-4 ou Claude pour générer un énième formulaire de contact, c'est comme utiliser un lance-flammes pour allumer une bougie. Techniquement possible, énergétiquement criminel.

### B. L'open source comme seule économie viable : la mort des brevets logiciels

Ma décision d'open-sourcer pgGit n'est pas philanthropique, elle est pragmatique. À l'heure de Claude Code, je suis convaincu que toute innovation technologique est à un week-end de prompt de moyens de contournement aux brevets déposés. Les protections intellectuelles traditionnelles s'effondrent face à la capacité de l'IA à générer des solutions alternatives en quelques heures.

Cette réalité transforme radicalement les modèles économiques :

**1. Le financement par la rareté, c'est fini**
- Les brevets logiciels n'ont plus de valeur face aux capacités de génération de l'IA
- Protéger une innovation devient plus coûteux que de la redévelopper
- L'avantage concurrentiel ne vient plus de la propriété mais de l'exécution

**2. Nouveaux modèles de financement pour la transition**
- **Financement public conditionnel** : Subventions liées à l'open-sourcing et aux métriques carbone
- **Consortiums industriels pour l'efficience** : Mutualiser les coûts de R&D pour créer des standards sobres
- **Modèle "Impact Bonds"** : Investissements remboursés selon les économies d'énergie réalisées
- **Taxation carbone développement** : Taxe sur les tokens IA utilisés, redistribuée aux projets open source efficients

**3. L'économie de la méta-génération**
Au lieu de vendre du code, vendre des générateurs de code. Un investissement IA initial pour créer des outils qui génèrent infiniment sans IA. Monétisation par l'usage, pas par la propriété.

**4. Modèle pgGit appliqué à l'industrie**
- Phase 1 : Investissement public/privé massif pour créer les générateurs les plus efficients
- Phase 2 : Open-sourcing total pour adoption massive
- Phase 3 : Économies d'échelle gigantesques, retour sur investissement via la réduction des coûts énergétiques

## Conclusion : vers une économie post-propriété du logiciel

*Synthèse finale* (l'exercice impose ses règles jusqu'au bout) : Cette expérience pgGit révèle l'obsolescence programmée de nos modèles économiques traditionnels. Face à l'IA générative, la protection intellectuelle devient illusoire, et l'urgence climatique rend le gaspillage énergétique inacceptable.

**Le vrai défi n'est plus technique mais systémique** : comment financer la transition vers un développement sobre quand les mécanismes traditionnels de captation de valeur s'effondrent ?

Ma proposition concrète :
1. **Fonds européen "Green Code"** : 10 milliards d'euros sur 5 ans pour financer la création d'alternatives open source aux solutions propriétaires énergivores
2. **Certification "Carbon-Neutral Development"** : Standard industriel obligatoire d'ici 2027
3. **Bourse européenne des générateurs de code** : Plateforme publique d'échange de solutions méta-génératives
4. **Formation massive** : Recyclage de 100 000 développeurs aux pratiques sobres d'ici 2030

pgGit est disponible sur github.com/evoludigit/pgGit non pas comme un modèle à suivre, mais comme un cas d'école à transformer. Le code source sert de laboratoire : comment prendre une aberration énergétique et la transformer en solution durable ?

*Ouverture finale* : Si mon week-end de folie a coûté l'équivalent d'une ville en électricité pour créer une bicyclette numérique, au moins que cette bicyclette serve à transporter une nouvelle économie. Une économie où l'intelligence artificielle sert enfin l'intelligence tout court.

---

*Lionel Hamayon - Sciences Po Rennes, développeur en quête de rachat écologique*

PS : Les VCs qui lisent ceci : il n'y a plus d'argent à faire dans la rareté artificielle. L'avenir appartient à ceux qui financent l'abondance responsable.

PPS : Cet article respecte le plan dissertation jusqu'au bout. Au moins, certaines traditions résistent au chaos numérique.

#DéveloppementDurable #IA #OpenSource #TransitionÉcologique #FinancementInnovation #PostCapitalisme #GreenIT #TechForGood