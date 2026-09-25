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

Le prochain chantier doit utiliser une chaîne vérifiée `unpack_bootimg` + `mkbootimg` + `avbtool`, adaptée au header v2 et à la politique AVB de l’appareil. Le script `scripts/repack_bootimg.py` présent ici refuse explicitement l’ancien chemin manuel.

Ne flashez pas directement `Image` comme s’il s’agissait d’un `boot.img`. Conservez une image boot officielle de restauration correspondant exactement à la version LineageOS installée.
