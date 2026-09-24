# Guide matériel

*English version: [hardware.md](hardware.md)*

Aucun réglage de Windows ne rattrape un matériel mal configuré ou usé. Classés par impact réel, du plus gros gain au plus fin :

## 1. Un SSD NVMe comme disque système

De loin le plus gros gain de réactivité : démarrage, lancement des applis, chargement des projets.

- **SSD SATA → NVMe :** un SSD SATA plafonne vers 550 Mo/s. Un NVMe PCIe 3.0 fait environ 3 500 Mo/s, un PCIe 4.0 environ 7 000 Mo/s.
- **Disque dur → n'importe quel SSD :** le jour et la nuit.
- Avant d'acheter : un emplacement **M.2** libre, et sa **génération PCIe**. Sur beaucoup de cartes, un emplacement M.2 partage ses lignes avec des ports SATA et en désactive certains : le manuel indique lesquels.

`Check.cmd` affiche le type de ton disque système.

## 2. La RAM à sa fréquence prévue (XMP / EXPO)

Le réglage gratuit le plus oublié. Sans son profil, la RAM tourne à sa fréquence de base (2133 MHz en DDR4) au lieu de celle écrite sur la boîte. Ça se voit sur les 1 % low en jeu.

- BIOS → active **XMP** (Intel) ou **EXPO/DOCP** (AMD). **Chaque mise à jour du BIOS le désactive.**
- Vérification : *Gestionnaire des tâches → Performance → Mémoire → Vitesse*, ou `Check.cmd`.

## 3. Resizable BAR

Permet au processeur d'accéder à toute la mémoire de la carte graphique d'un coup, au lieu de fenêtres de 256 Mo. Quelques pourcents dans certains jeux, rien dans d'autres. Il faut **Above 4G decoding**, **Re-Size BAR** et le **CSM coupé** dans le BIOS (voir le [guide BIOS](bios.fr.md)), et une carte mère et un BIOS qui le proposent. `Check.cmd` le lit pour les cartes NVIDIA.

## 4. L'écran à sa vraie fréquence

Windows laisse souvent un écran 144 Hz à 60 Hz. *Paramètres → Système → Écran → Affichage avancé* → choisis la fréquence la plus haute. `Check.cmd` prévient quand une fréquence plus haute est proposée.

- **G-Sync / FreeSync :** active-le, en **DisplayPort**.
- **Fréquences overclockées** (« OC 180 Hz » sur une dalle 144 Hz) : essaie, mais regarde de près. Sur beaucoup de dalles, surtout les TN, l'overdrive n'est pas réglé pour la fréquence overclockée : halos clairs derrière les objets en mouvement, couleurs délavées. La fréquence native donne souvent la meilleure image.

## 5. Tirer parti de la carte graphique en 1080p

Avec une carte puissante en 1080p, c'est souvent le processeur qui limite, pas la carte graphique. Utilise la marge pour la qualité d'image :

- **DLDSR** (Panneau NVIDIA → *Gérer les paramètres 3D → DSR - Facteurs → 2.25x DL*) : les jeux calculent l'image en 2880×1620, puis la réduisent à ton écran. Image nettement plus fine, pour presque les mêmes FPS quand le processeur limite. Choisis cette résolution dans le jeu, en plein écran.
- **DLDSR 2.25x + DLSS Qualité :** le jeu calcule en interne en 1080p, puis affiche en 2880×1620. Meilleure image qu'en 1080p natif, pour à peu près le même coût.
- **DSR - Lissage :** 33 % par défaut. Monte vers 50 % si l'image paraît trop accentuée, surtout avec DLSS.
- **Jeux compétitifs :** reste en résolution native, avec **NVIDIA Reflex** activé, pour le maximum de FPS et la latence la plus basse.

## 6. Santé des disques

Outil gratuit : **CrystalDiskInfo**. Ce qu'il faut lire :

| Champ | Signification |
|---|---|
| Pourcentage de santé | Durée de vie restante d'un SSD. Prévoir le remplacement quand il passe sous 20 % environ |
| **Total écriture hôte** | À comparer à l'endurance garantie par le fabricant (TBW, par exemple 150 To pour un Samsung 860 EVO de 250 Go). Un disque système qui écrit plusieurs Go par heure a généralement un coupable : Replay instantané NVIDIA en continu, caches de montage vidéo, disques de WSL/Docker |
| Secteurs réalloués (05), en attente (C5), erreurs incorrigibles | Doivent rester à 0. S'ils augmentent, sauvegarde et remplace le disque |
| **Erreurs CRC UDMA (C7)** | Erreurs de transmission entre le disque et la carte mère : presque toujours **le câble SATA ou son port**, pas le disque. Change le câble et vérifie que le compteur n'augmente plus |

## 7. Réseau filaire à 1 Gbps

Presque tous les ports Ethernet sont Gigabit. Le Gigabit utilise les 4 paires du câble, alors que le 100 Mbps n'en a besoin que de 2. Une paire abîmée ou un connecteur mal enfoncé fait retomber la liaison à 100 Mbps, ce qui plafonne Internet vers 95 Mbit/s quel que soit ton abonnement. `Check.cmd` affiche la vitesse de liaison. S'il indique 100 Mbps :

1. Débranche et rebranche le câble **des deux côtés**, jusqu'au clic.
2. Essaie **un autre port** de la box.
3. Change le câble : **Cat 5e minimum, Cat 6 idéalement**, sans pli, languette intacte.

Ne force pas « Vitesse et duplex » sur 1 Gbps dans les propriétés de la carte : sans négociation automatique, la liaison peut ne plus s'établir du tout.

## 8. Températures et poussière

Un processeur ou une carte graphique qui chauffe trop ralentit tout seul. Outils gratuits : **HWMonitor** ou **HWiNFO**. Sous charge, garde le processeur sous 90 °C environ et la carte graphique sous 83 °C environ.

- Dépoussière le boîtier, les radiateurs et les filtres. Flux d'air : entrée devant et en bas, sortie derrière et en haut.
- Sur une machine ancienne, refaire la pâte thermique du processeur peut regagner des centaines de MHz en charge prolongée.

## 9. Pilotes

Pilotes du chipset, du réseau et d'Intel Management Engine : chez Intel ou AMD, ou sur la page support de ta carte mère. `Check.cmd` signale les pilotes réseau et Management Engine de plus de 2 ans.

Pour une installation propre, sans logiciel en plus : décompresse le paquet, puis *Gestionnaire de périphériques → clic droit sur le périphérique → Mettre à jour le pilote → Parcourir mon poste de travail* → le dossier décompressé, sous-dossiers inclus. Fais le pilote réseau en dernier : la connexion coupe quelques secondes. Évite les logiciels de « mise à jour de pilotes ».

## Mesurer les performances

Teste un composant à la fois, toujours dans les mêmes conditions, et note les scores : c'est comme ça qu'on voit l'effet d'un changement.

| Quoi | Outil gratuit | Mesure |
|---|---|---|
| Processeur | **Cinebench 2024** | score sur un cœur et sur tous les cœurs |
| Jeu (carte graphique + processeur) | **3DMark** (démo gratuite sur Steam), test **Time Spy** | score graphique et score processeur, comparés à des PC identiques |
| Carte graphique seule | **Unigine Superposition** | FPS dans une scène 3D fixe |
| Disques | **CrystalDiskMark** | vitesses de lecture et d'écriture, séquentielles et aléatoires |
| Tes vrais jeux | **CapFrameX** | FPS moyens et **1 % low**, la fluidité réelle |
| Températures | **HWMonitor** | à surveiller pendant les tests |

Méthode :

1. Ferme tout : messageries, navigateur, fond d'écran animé, launchers.
2. Lance chaque test 3 fois et garde le score du milieu. Le premier passage est souvent plus faible.
3. Garde HWMonitor ouvert. Au-delà des températures de la section 8, le matériel ralentit et les scores baissent.
4. Note les scores avec la date et ce qui a changé depuis la dernière mesure.

**UserBenchmark :** les mesures brutes sont exploitables, les classements non. Son test graphique est si léger (300 à 400 FPS) que c'est le processeur qui limite : une carte puissante avec un processeur plus ancien obtient un mauvais classement sans que rien ne cloche. Ses pourcentages de disques comparent des disques système occupés par Windows à des disques au repos.

## Ce qui ne sert à rien

- **« Boosters » et nettoyeurs de RAM** : du placebo.
- **Défragmenter un SSD** : inutile, TRIM s'en charge.
- **Overclocking extrême sans refroidissement adapté** : de l'instabilité pour un gain marginal.
