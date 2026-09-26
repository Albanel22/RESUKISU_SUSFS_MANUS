# Kit GitHub Actions corrigé — kiev / ReSukiSU + SUSFS

Ce kit lance une compilation **fail-closed** du noyau `kiev` et téléverse uniquement les artefacts sûrs de compilation :

- `Image` ARM64 brut ;
- `.config` effectivement utilisé ;
- `KERNELRELEASE` ;
- archive des modules ;
- sommes SHA-256 et journal de build.

Il **ne produit pas de `boot.img` flashable**. Le repacker précédent était incompatible avec le boot Android v2 et le footer AVB de l’image `kiev` de référence. Refuser l’image est plus sûr que publier un artefact qui peut provoquer un boot failure ou un kernel panic.

## Installation dans GitHub

Copier le contenu de ce dossier à la racine d’un dépôt GitHub dédié :

```text
.github/workflows/build-kiev-kernel.yml
integration/
scripts/build.sh
scripts/prepare.sh
scripts/inspect_bootimg.py
scripts/repack_bootimg.py
README.md
```

Les fichiers `*.orig` éventuels sont des copies de comparaison et ne sont pas nécessaires.

Puis :

1. créer un commit sur une branche de test ;
2. pousser vers GitHub ;
3. ouvrir **Actions → Build kiev ReSukiSU SUSFS kernel (safe)** ;
4. lancer **Run workflow** ;
5. vérifier l’artefact `Image`, `kernel.config`, `KERNELRELEASE`, `modules.tar.gz`, `SHA256SUMS` et `build.log`.

## Pins utilisés

| Élément | Valeur |
|---|---|
| Kernel | `LineageOS/android_kernel_motorola_sm8250` |
| Commit kernel | `c21b90c6860eeade8da37ea1212aa6135cf99e1f` |
| ReSukiSU | `90b4a4c70f70c835b01c2be6deac58ee3c0cb4c2` |
| Defconfig | `vendor/lito-perf_defconfig` |
| Architecture | `arm64` |

## Conditions d’échec volontaires

Le workflow s’arrête si :

- le patch `integration/kernel-adaptations.patch` ne s’applique pas proprement ;
- un fichier `.rej` ou `.orig` existe ;
- `CONFIG_KSU_SUSFS` n’est pas conservé après `olddefconfig` ;
- `CONFIG_KSU_MANUAL_HOOK` reste actif ;
- les prototypes SUSFS `struct filename **` sont absents ;
- un ancien hook incompatible est présent ;
- le kernel produit est `Image.gz` ou n’est pas identifié comme un `Image` ARM64 brut ;
- aucun module n’est compilé.

Le patch fourni dans l’archive initiale échoue actuellement sur `fs/Makefile` avec le commit kernel épinglé. Le workflow doit donc échouer jusqu’à ce que ce patch soit réellement corrigé pour ce commit ; il ne doit pas être contourné avec `|| true` ou suppression des `.rej`.

## À propos du boot.img

Le workflow utilise une chaîne vérifiée `unpack_bootimg` + `mkbootimg`, adaptée au header v2 de kiev. Le script `scripts/repack_bootimg.py` présent ici refuse explicitement l’ancien chemin manuel.

Ne flashez pas directement `Image` comme s’il s’agissait d’un `boot.img`. Conservez une image boot officielle de restauration correspondant exactement à la version LineageOS installée.

## Validation locale réussie

- Kernel: `LineageOS/android_kernel_motorola_sm8250`
- Kernel commit: `c21b90c6860eeade8da37ea1212aa6135cf99e1f`
- ReSukiSU commit testé: `0e4698951b8e0e1cb997e46f2049c691869a4f45` (`main`)
- Mode: `CONFIG_KSU_MANUAL_HOOK=y`
- SUSFS: désactivé
- Résultat: compilation complète réussie
- Kernel release: `4.19.325-cip136-st20-perf-gc21b90c6860e-dirty`
- Image SHA-256: `26050b844189f543fd99f8e6027faea51229febb8332fbe8bc7f74974dfa52b9`

Attention: cette validation utilise ReSukiSU `main`, car le commit historique `0e4698951b8e0e1cb997e46f2049c691869a4f45` n'est plus récupérable depuis les références publiques GitHub.

## Artefacts de boot

Le workflow télécharge et vérifie les images officielles kiev du 20 septembre 2026 : `boot.img` et `dtbo.img`. Il remplace le kernel dans le conteneur boot v2 et produit `boot-unsigned.img`. Le `dtb` intégré au boot v2 est conservé ; `dtbo.img` est une partition séparée et est publié séparément.

Le workflow ne demande aucune clé ni aucun secret AVB. Les artefacts publiés sont : `boot-unsigned.img`, `dtbo.img`, `Image`, `kernel.config`, `KERNELRELEASE`, `modules.tar.gz`, `SHA256SUMS` et `build.log`.
