# Guide BIOS

*English version: [bios.md](bios.md)*

Aucun script ne peut changer les réglages du BIOS. Cette page est la liste de contrôle, y compris ce qu'il faut refaire **après chaque mise à jour du BIOS**, qui remet tout à zéro. Les chemins sont ceux du BIOS MSI (Click BIOS 5) en mode avancé (F7). Les autres marques utilisent des noms proches, rangés ailleurs.

`Check.cmd` indique depuis Windows si la plupart de ces réglages ont bien pris.

## Avant une mise à jour du BIOS

- **BitLocker :** s'il est actif, suspends-le d'abord (*Panneau de configuration → BitLocker → Interrompre la protection*) et garde ta clé de récupération sous la main. La mise à jour efface le TPM, et BitLocker demanderait sinon la clé au démarrage.
- **Note tes réglages.** Sur MSI, **F12** enregistre une capture de la page affichée sur une clé USB en FAT32.
- Utilise l'outil de flash intégré à la carte mère (M-Flash, Q-Flash, EZ Flash…) depuis une clé USB en FAT32. Ne coupe pas le courant pendant le flash.

**À quoi ça sert ?** Surtout à la sécurité : correctifs du microcode du processeur et des failles du firmware. Ça apporte rarement des FPS en soi, sauf quand ça débloque une fonction comme Resizable BAR.

## Ce qu'une mise à jour du BIOS remet à zéro

Constaté sur une vraie mise à jour :

| Quoi | Conséquence | Correction |
|---|---|---|
| Profil XMP / EXPO | La RAM retombe à sa fréquence de base (2133 MHz en DDR4) | Le réactiver. `Check.cmd` prévient |
| Secure Boot | Désactivé, et plus aucune clé (« System Mode : Setup ») | Voir [Secure Boot](#secure-boot-après-une-mise-à-jour-du-bios) |
| Certificats Secure Boot 2023 de Microsoft | Disparus du firmware, alors que Windows démarre déjà avec le gestionnaire signé 2023 | `SecureBoot.cmd` |
| TPM | Effacé | Code PIN Windows Hello à recréer s'il est refusé, clés d'accès (passkeys) enregistrées dans Windows Hello perdues, clé de récupération BitLocker demandée s'il n'était pas suspendu |
| CSM, Above 4G, Resizable BAR, Fast Boot, courbes des ventilateurs | Valeurs d'usine | Cette liste |

## Liste de contrôle

| Réglage | Où (MSI) | Valeur | Pourquoi |
|---|---|---|---|
| **XMP / EXPO** | bouton en haut à gauche | Profil 1 | RAM à sa fréquence prévue |
| Memory Fast Boot | OC, réglages mémoire | Enabled | Pas de réentraînement de la RAM à chaque démarrage |
| Virtualisation du processeur (Intel VT-x / AMD SVM) | OC → CPU Features | Enabled | WSL, Docker, Bac à sable Windows |
| TPM (Intel PTT / AMD fTPM) | Settings → Security → Trusted Computing | Enabled | Windows 11, Windows Hello |
| **CSM coupé** | Settings → Advanced → Windows OS Configuration → *Windows 10 WHQL Support* | UEFI | Requis pour Secure Boot et Resizable BAR. Seulement si Windows est installé en mode UEFI (`msinfo32` : « Mode BIOS : UEFI ») |
| Above 4G decoding | Settings → Advanced → PCIe/PCI Sub-system Settings | Enabled | Requis pour Resizable BAR |
| **Re-Size BAR Support** | même menu | Enabled | Quelques pourcents dans certains jeux. Pas proposé par toutes les cartes ni tous les BIOS |
| **Fast Boot** | Settings → Advanced → Windows OS Configuration | Fast Boot activé, *MSI Fast Boot* désactivé | Des secondes gagnées à chaque démarrage. MSI Fast Boot saute aussi l'initialisation USB, ce qui rend le BIOS difficile d'accès |
| Ordre de démarrage | Settings → Boot | Windows Boot Manager en premier, démarrage réseau coupé | Rien à chercher au démarrage. Les autres périphériques restent accessibles par le menu de démarrage (F11 sur MSI) |
| **Secure Boot** | Settings → Advanced → Windows OS Configuration → Secure Boot | Enabled, mode Standard | Sécurité, et exigé par certains anti-triches (Battlefield 6, Valorant, Call of Duty…) |

Avec Fast Boot, le clavier peut ne pas être lu à temps pour entrer dans le BIOS. Passe alors par Windows : *Paramètres → Système → Récupération → Démarrage avancé → Redémarrer maintenant → Dépannage → Options avancées → Paramètres du microprogramme UEFI*.

## Secure Boot après une mise à jour du BIOS

Windows démarre désormais avec un gestionnaire de démarrage signé par le certificat 2023 de Microsoft. Les clés d'usine remises par une mise à jour du BIOS ne contiennent pas forcément ce certificat. Activer Secure Boot risque alors un écran « Secure Boot Violation ». Dans l'ordre :

1. BIOS : vérifie que des clés sont installées. Secure Boot en mode **Standard** installe les clés d'usine au démarrage suivant. Sur certaines cartes : *Secure Boot Mode : Custom → Key Management → Restore Factory Keys*.
2. Windows : lance **`SecureBoot.cmd`**. Il s'arrête si le firmware n'a aucune clé. Il faut parfois deux passages, avec un redémarrage entre les deux.
3. `Check.cmd` doit afficher « Secure Boot désactivé (certificats 2023 en place : à activer dans le BIOS) », ou « Secure Boot actif » s'il l'est déjà.
4. BIOS : **Secure Boot → Enabled**, mode Standard.

Si le PC affiche une erreur Secure Boot au démarrage : remets Secure Boot sur **Disabled**, et Windows démarre normalement. Rien n'est cassé, les certificats n'étaient simplement pas encore en place. Lance `SecureBoot.cmd`, puis réessaie.

Une fois `SecureBoot.cmd` passé, **n'utilise plus « Restore Factory Keys »** : ça effacerait à nouveau les certificats 2023.

## À ne pas toucher

- **C-states, SpeedStep/EIST, tensions, Load-Line Calibration** : les valeurs par défaut sont bonnes. Vérifie que le processeur tient son turbo sur tous les cœurs sous charge (HWMonitor, ou les outils de test du [guide matériel](hardware.fr.md)). S'il ne baisse pas, il n'y a rien à corriger.
- **Game Boost et autres overclockings en un clic** : ils montent la tension bien plus que nécessaire.

## Turbo sur tous les cœurs : à toi de voir

« Enhanced Turbo » chez MSI, « MultiCore Enhancement » chez ASUS, « Enhanced Multi-Core Performance » chez Gigabyte : tous les cœurs tournent à la fréquence turbo d'un seul cœur. Sur un i9-9900K, ça donne 5,0 GHz au lieu de 4,7 GHz sur tous les cœurs.

- **Gain :** environ +6 % en rendu, compilation ou export vidéo. En jeu, 0 à 3 % : les jeux chargent rarement tous les cœurs à fond.
- **Coût :** 40 à 50 W de plus sous charge, et beaucoup plus de chaleur.

À n'activer qu'avec un gros ventirad ou un watercooling, en vérifiant que le processeur reste sous 85-90 °C en jeu. Sinon, laisse-le désactivé.

## Facultatif : baisser la tension

Sur les cartes MSI, **CPU Lite Load** (Auto par défaut) baisse la tension du processeur cran par cran : températures plus basses, et parfois un turbo plus stable. Chaque cran doit être testé sous charge (Cinebench en boucle, OCCT) : trop bas, et le PC plante sous charge. Ça ne vaut le coup que si le processeur chauffe.
