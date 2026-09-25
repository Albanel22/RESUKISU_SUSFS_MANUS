# Build GitHub Actions — kiev / ReSukiSU + SUSFS

Ce kit construit le kernel LineageOS pour kiev à partir de commits figés, puis génère un `boot.img` avec le kernel `Image.gz`, le ramdisk de référence et les modules compilés.

## Installation dans le dépôt GitHub

Copier le contenu de ce dossier à la racine du dépôt GitHub :

```text
.github/workflows/build-kiev-kernel.yml
integration/
scripts/
README.md
```

Le workflow est lancé automatiquement lorsqu’un de ces fichiers change, ou manuellement depuis **Actions → Build kiev ReSukiSU SUSFS kernel → Run workflow**.

## Versions reproductibles

| Élément | Valeur |
|---|---|
| Kernel | `LineageOS/android_kernel_motorola_sm8250` |
| Commit kernel | `c21b90c6860eeade8da37ea1212aa6135cf99e1f` |
| ReSukiSU | `90b4a4c70f70c835b01c2be6deac58ee3c0cb4c2` |
| Image boot de référence | `https://mirrorbits.lineageos.org/full/kiev/20260920/boot.img` |
| Image dtbo de référence | `https://mirrorbits.lineageos.org/full/kiev/20260920/dtbo.img` |
| Defconfig | `vendor/lito-perf_defconfig` |
| Architecture | `arm64` |

Les URLs et commits sont visibles dans le workflow afin que chaque exécution soit auditable.

## Artefacts produits

Le job téléverse :

- `boot-resukisu-susfs-kiev-20260920.img` : image boot finale, de taille normalement égale à la partition de référence ;
- `dtbo.img` : image DTBO de référence ;
- `Image.gz` : kernel compressé séparément ;
- `boot.img` original et `build.log` pour diagnostic.

Le workflow ne flashe aucune image et ne modifie aucun appareil.

## Exécution locale équivalente

Depuis la racine du kit :

```bash
ROOT="$PWD/work" KERNEL_DIR="$PWD/work/kernel" \
  bash scripts/prepare.sh

ROOT="$PWD/work" KERNEL_DIR="$PWD/work/kernel" JOBS=2 \
  bash scripts/build.sh

ROOT="$PWD/work" \
REFERENCE_BOOT="$PWD/work/reference/boot.img" \
KERNEL_IMAGE="$PWD/work/kernel/out/arch/arm64/boot/Image.gz" \
MODULE_ROOT="$PWD/work/kernel/out" \
OUTPUT_BOOT="$PWD/work/boot-resukisu-susfs-kiev-20260920.img" \
  python3 scripts/repack_bootimg.py
```

La compilation demande plusieurs gigaoctets d’espace disque et peut dépasser une heure sur un runner partagé. Le workflow limite volontairement la parallélisation à deux jobs pour réduire le risque d’épuisement mémoire.

## Vérifications importantes

Avant tout flash, vérifier la somme SHA-256 de l’artefact, confirmer que `file boot-resukisu-susfs-kiev-20260920.img` identifie une Android boot image, et comparer la taille à la partition `boot` réelle du téléphone. La génération de l’image ne constitue pas une validation de démarrage sur matériel.
