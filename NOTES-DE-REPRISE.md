# Notes de reprise

J'ai d'abord analysé les deux fichiers avec Claude Code : valeurs distinctes
par colonne, cellules vides, valeurs qui ne ressemblent pas aux autres. Puis
j'ai lu le schéma, les modèles et l'API publique de Baqio. Mon principe :
quand le fichier ne tranche pas, je suis la structure existante de Baqio
plutôt que d'en inventer une.

Le plus gros écart est le type de tiers. CaveGest a quatre types (client,
fournisseur, prospect, revendeur). Dans Baqio, un client n'a pas de type,
seulement une `customer_category`. En attendant la confirmation du client,
j'ai donc choisi de reprendre les revendeurs comme clients, et je le signale
dans le rapport pour que le client le voie.

Je garde le schéma tant qu'il tient, et je ne le change que là où les données
le demandent, en dernier. Par exemple, j'ai d'abord terminé le code métier
demandé par le test, puis seulement ensuite revu la structure des tarifs, des
sections et des couleurs selon les données réelles.

Ma façon de faire : d'abord faire fonctionner le code, puis l'améliorer, avec
des tests. Pendant l'import, quand je trouve une règle générale, je
l'applique de façon stricte, par exemple pour les codes postaux et les
téléphones. Ce qui est illisible n'est pas importé, ce qui est lisible mais
douteux est importé et signalé. Je préfère garder la donnée du client plutôt
que la corriger moi-même. Dans un vrai projet, ces choix passeraient d'abord
par un collègue qui connaît le métier.

À confirmer avec le client, par exemple :

- Le type client / fournisseur / prospect leur sert-il, ou la catégorie
  suffit-elle ?
- « Carton 6 », « 6 x 75 » : comment calculer le volume en ml ?
- Doublons : trois produits de même nom et contenance, six références
  utilisées par deux produits, trois enseignes à la même adresse, un numéro
  de TVA sur deux clients. Est-ce une erreur ?
- 989 clients sont sans pays, dont 469 avec un numéro de TVA français qui
  donne le pays. Peut-on considérer que les clients sont français par défaut ?
- GDCPT a 5 clients et aucun tarif, SALON 51 tarifs et aucun client : sont-
  elles encore utilisées ?
- Mes nettoyages leur conviennent-ils ? Téléphones au format international,
  codes postaux complétés, noms en majuscules, numéros de TVA, etc.
