# pc-tuning

[![CI](https://github.com/slayerfx/pc-tuning/actions/workflows/ci.yml/badge.svg)](https://github.com/slayerfx/pc-tuning/actions/workflows/ci.yml)
[![Licence : MIT](https://img.shields.io/badge/Licence-MIT-green.svg)](LICENSE)
[![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE.svg)](#prérequis)
[![Windows 10 | 11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4.svg)](#prérequis)

**Réglages de Windows, du BIOS et du matériel pour un PC de bureau de jeu et de création. Chaque réglage Windows peut être vérifié, réappliqué et annulé.**

*English version: [README.md](README.md)*

La plupart des « optimiseurs » appliquent une pile de réglages une fois pour toutes, puis te laissent deviner ce qu'il en reste. `pc-tuning` tient une liste de réglages qu'il sait **vérifier** à tout moment. C'est important, car Windows Update, les installations de pilotes et certaines applis remettent des réglages en place sans prévenir. `Check.cmd` montre exactement ce qui a bougé, et `Apply.cmd` ne corrige que ça.

Le BIOS et le matériel ne se règlent pas par script : chacun a son guide, [BIOS](docs/bios.fr.md) et [matériel](docs/hardware.fr.md).

## Démarrage rapide

1. Télécharge le projet (**Code → Download ZIP**) et décompresse-le où tu veux, par exemple dans `Documents\pc-tuning`.
   Si Windows bloque les fichiers : clic droit sur le ZIP → **Propriétés** → coche **Débloquer** avant de décompresser.
2. *Facultatif :* copie `config.example.json` en `config.json` et active les options que tu veux (voir [Configuration](#configuration)).
3. Double-clique sur **`Check.cmd`**. Il liste chaque réglage et l'état de ton matériel, sans rien modifier.
4. Double-clique sur **`Apply.cmd`** et accepte la demande de droits administrateur. Il crée un point de restauration, note l'état actuel, corrige ce qui doit l'être, puis propose de redémarrer.
5. Tu changes d'avis ? **`Undo.cmd`** remet l'état noté lors du dernier Apply.

Relance `Check.cmd` après les grosses mises à jour de Windows ou une installation de pilote. Les messages s'affichent en français ou en anglais, selon la langue de Windows.

## Ce qu'il gère

Activé par défaut :

| Groupe | Réglages | Pourquoi |
|---|---|---|
| Télémétrie | Services DiagTrack, informations d'utilisation et cartes hors connexion désactivés. 15 tâches planifiées de télémétrie, plus les dossiers SoftLanding et GoogleUserPEH. Télémétrie au minimum, pas de Bing ni de suggestions web dans Démarrer, pas d'installation silencieuse d'applis promues, pas de contenu sponsorisé, pas d'identifiant publicitaire | Moins d'activité en fond, moins de publicité |
| Services | Suivi des données (`DusmSvc`) et inventaire (`InventorySvc`) en manuel | Démarrés seulement quand il faut |
| Applications | 14 applis promotionnelles : Bing Actualités/Météo, Solitaire, Clipchamp, Obtenir de l'aide, Hub de commentaires, To Do, Dev Home, Power Automate, Widgets, Teams perso… | Xbox, OneDrive, Mobile connecté et Lecteur multimédia sont conservés : ajoute-les à `extraApps` si tu ne t'en sers pas |
| Jeu et performances | Game DVR coupé, planification GPU accélérée (indispensable pour la génération d'images DLSS), plan « Performances optimales », pas d'économie d'énergie PCI Express ni USB, pas d'horodatage du dernier accès NTFS | Moins de pics de latence et d'écritures en fond |
| Interface et souris | Menus sans délai, pas d'animations de la barre des tâches, accélération de la souris coupée | Bureau plus vif, visée constante |
| Démarrage | Entrée « Teams » orpheline retirée | Laissée derrière elle quand la nouvelle appli Teams est désinstallée |
| Wallpaper Engine | En pause quand un jeu est en plein écran ou en fenêtre maximisée (jeux sans bordure) | Évite un second moteur 3D qui tourne pendant les parties |
| Réseau | Économies d'énergie de la carte filaire coupées (Ethernet économe en énergie et assimilés, Intel et Realtek), bridage réseau multimédia désactivé | Une mise à jour du pilote les réactive souvent |

Désactivé par défaut, parce que ce sont des compromis ou des goûts personnels :

| Option | Ce qu'elle fait | Contrepartie |
|---|---|---|
| `disableMemoryIntegrity` | Coupe l'intégrité de la mémoire (HVCI) et la VBS, et verrouille ce choix par stratégie pour que Windows ne la réactive pas. L'hyperviseur reste, donc WSL et Docker continuent de marcher | **Moins de protection contre les pilotes malveillants.** Le gain est réel sur les processeurs Intel d'avant la 10e génération (pas de MBEC, HVCI est émulé), faible sur les récents. Certains anti-triches l'exigent : `Undo.cmd` si un jeu refuse de démarrer |
| `removeNahimic` | Retire la couche audio Nahimic (MSI et d'autres) et bloque ses identifiants matériels pour que Windows Update ne la remette pas | Source connue de latence audio et de saccades en jeu, mais certains aiment ses effets |
| `disableHibernation` | `powercfg /hibernate off` | Libère sur C: un fichier de la taille de ta RAM, mais plus de veille prolongée ni de démarrage rapide (PC de bureau uniquement) |
| `disableTransparency` | Pas d'effets de transparence | Question de goût |
| `disableChromeAutostart` | Empêche Chrome de se lancer avec Windows, comme le fait le Gestionnaire des tâches | Question de goût |
| `defender.excludeSteamLibraries`, `defender.extraExclusions` | Exclusions Defender pour les bibliothèques de jeux et les médias générés (caches vidéo, enregistrements) | **Les dossiers exclus ne sont pas analysés.** N'exclus jamais tes sources de code ni tes téléchargements |
| `network.dnsServers` | Fixe les serveurs DNS de la carte filaire, par exemple ta box puis [Quad9](https://quad9.net) (`9.9.9.9`) | Laisse vide pour garder ceux de ta box |

## Ce que Check signale en plus

Ce qu'aucun script ne devrait changer à ta place, avec une piste quand quelque chose cloche :

- intégrité de la mémoire vraiment arrêtée (après redémarrage), hyperviseur chargé
- version du BIOS (comparée à `checks.latestBiosVersion` si tu la renseignes), Secure Boot et ses certificats 2023, temps de démarrage du BIOS (Fast Boot)
- RAM à sa fréquence prévue (profil XMP/EXPO)
- type de disque système (SATA ou NVMe)
- écran principal à la fréquence maximale qu'il propose
- Resizable BAR (NVIDIA)
- âge des pilotes réseau et Intel Management Engine
- vitesse de la liaison filaire (un câble abîmé fait retomber le Gigabit à 100 Mbps)

## Configuration

Tout fonctionne sans configuration. Pour personnaliser, copie `config.example.json` en `config.json` (à côté du script, ignoré par git) ou passe `-Config chemin\du\fichier.json`. Les clés inconnues sont signalées, pour qu'une faute de frappe ne passe pas inaperçue.

| Clé | Par défaut | Rôle |
|---|---|---|
| `disableMemoryIntegrity` | `false` | Voir plus haut |
| `removeNahimic` | `false` | Voir plus haut |
| `disableTelemetry` | `true` | Services, tâches et réglages de télémétrie |
| `removeApps` | 14 applis | Applis à retirer (noms de paquets, tels que les affiche `Get-AppxPackage`) |
| `extraApps` | aucune | Applis supplémentaires à retirer, par exemple `"Microsoft.GamingApp"`, `"Microsoft.OneDriveSync"`, `"Microsoft.OutlookForWindows"` |
| `manualServices` | `DusmSvc`, `InventorySvc` | Services en démarrage manuel. Les services absents sont ignorés |
| `disableGameDvr` | `true` | Enregistrement Game DVR |
| `hardwareGpuScheduling` | `true` | HAGS |
| `desktopPowerPlan` | `true` | Plan « Performances optimales », pas d'économie d'énergie PCIe ni USB. **À désactiver sur un portable** |
| `disableHibernation` | `false` | Voir plus haut |
| `snappierInterface` | `true` | Délai des menus et animations de la barre des tâches |
| `disableTransparency` | `false` | Voir plus haut |
| `disableMouseAcceleration` | `true` | « Améliorer la précision du pointeur » décoché |
| `disableChromeAutostart` | `false` | Voir plus haut |
| `wallpaperEnginePause` | `true` | Seulement si Wallpaper Engine est installé |
| `network.adapter` | `""` | Nom de la carte (`Get-NetAdapter`). Vide : la première carte filaire connectée |
| `network.dnsServers` | aucun | Voir plus haut |
| `network.disablePowerSaving` | `true` | Économies d'énergie de la carte |
| `network.disableThrottling` | `true` | `NetworkThrottlingIndex` |
| `defender.excludeSteamLibraries` | `false` | Toutes les bibliothèques Steam, lues dans la liste de Steam |
| `defender.extraExclusions` | aucun | Dossiers à exclure. Variables d'environnement acceptées : `"%USERPROFILE%\\Videos"` |
| `checks.latestBiosVersion` | `""` | Dernière version du BIOS de ta carte mère, telle que Windows l'affiche (`1.D0` pour la « 1D » de MSI) |
| `checks.minLinkSpeedMbps` | `1000` | Vitesse de liaison en dessous de laquelle Check prévient |

## Après une mise à jour du BIOS

Une mise à jour du BIOS remet tout à zéro, y compris ce que Windows avait modifié : profil XMP, clés Secure Boot, certificats Secure Boot 2023 de Microsoft, et elle efface le TPM. Suis le [guide BIOS](docs/bios.fr.md). **`SecureBoot.cmd`** remet les certificats 2023 avec la [procédure de Microsoft](https://support.microsoft.com/en-us/topic/registry-key-updates-for-secure-boot-windows-devices-with-it-managed-updates-a7be69c9-4634-42e1-9ca1-df06f43f360d), pour réactiver Secure Boot sans écran « Secure Boot Violation ».

## Sécurité

- **Point de restauration** avant chaque Apply (`rstrui.exe` pour y revenir).
- **État d'avant** de chaque réglage modifié, noté dans `backups\state-before-*.json` : c'est ce que `Undo.cmd` remet.
- **Journal** de chaque Apply, Undo et SecureBoot dans `logs\`.
- **Non réversible par Undo :** les applis retirées (elles se réinstallent depuis le Microsoft Store) et les pilotes Nahimic retirés (réinstalle le pack audio de ta carte mère, après que `Undo.cmd` a levé le blocage).
- Essaie d'abord `Apply.cmd -DryRun` pour voir ce qui changerait.

## Écarté délibérément

Beaucoup de réglages populaires sont neutres, au mieux :

- **Désactiver SysMain** : un conseil de l'époque des disques durs. Sur SSD avec 16 Go ou plus, il aide.
- **`Win32PrioritySeparation`, `SystemResponsiveness`, priorités MMCSS** : les valeurs par défaut de Windows sont déjà les bonnes pour un PC de bureau.
- **Supprimer le fichier d'échange** : plantages dans les logiciels de montage, certains jeux refusent de démarrer.
- **Vider `C:\Windows\Installer`** : casse la réparation et la désinstallation des programmes MSI.
- **`DISM /ResetBase`** : les mises à jour Windows deviennent impossibles à désinstaller.
- **Défragmenter les SSD** : TRIM fait déjà le travail.
- **Désactiver Defender**, les « optimiseurs » tiers et les nettoyeurs de registre.
- **PcaPatchDbTask** : Windows la réactive à chaque démarrage.

## En ligne de commande

```powershell
powershell -ExecutionPolicy Bypass -File .\pc-tuning.ps1 -Mode Check
powershell -ExecutionPolicy Bypass -File .\pc-tuning.ps1 -Mode Apply -DryRun -Config D:\ma-config.json -Language fr
```

| Paramètre | Rôle |
|---|---|
| `-Mode Check\|Apply\|Undo\|SecureBoot` | Ce qu'il faut faire (par défaut : `Check`) |
| `-DryRun` | Dérouler Apply, Undo ou SecureBoot sans rien modifier |
| `-Config <fichier>` | Utiliser un fichier de configuration JSON |
| `-Language fr\|en` | Forcer la langue (par défaut : langue d'affichage de Windows) |
| `-StateFile <fichier>` | Fichier d'état à écrire (Apply) ou à remettre (Undo) à la place du plus récent dans `backups\` |
| `-NoPause` | Ne pas attendre Entrée à la fin |

## Prérequis

Windows 10 ou 11 avec Windows PowerShell 5.1 (intégré), sur un PC de bureau. Droits administrateur pour Apply, Undo et SecureBoot : le script les demande. Check s'en passe, sauf pour la ligne des exclusions Defender.

Conçu et testé sur un Intel Core i9-9900K, une MSI MPG Z390 Gaming Pro Carbon, une NVIDIA RTX 4070 Ti et Windows 11 25H2.

## Avertissement

Fourni tel quel, sans garantie. Lis ce que signalent `Check.cmd` et `Apply.cmd -DryRun` avant d'appliquer.

## Licence

[MIT](LICENSE)
