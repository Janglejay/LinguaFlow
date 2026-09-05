# Third-party notices

LinguaFlow's own source code is MIT licensed. The following components retain their own licenses and copyright notices.

## librime

- Project: <https://github.com/rime/librime>
- License: BSD 3-Clause
- Version used by the Apple Silicon release build: 1.17.0
- Embedded in distributable application bundles together with its required dynamic-library dependencies.

## Embedded runtime dependencies

The Apple Silicon installer currently embeds the following unmodified libraries required by librime:

| Component | Version | License |
| --- | --- | --- |
| gflags | 2.3.1 | BSD 3-Clause |
| glog | 0.7.1 | BSD 3-Clause |
| LevelDB | 1.23 | BSD 3-Clause |
| marisa-trie | 0.3.1 | BSD 2-Clause or LGPL 2.1+ |
| OpenCC | 1.4.2 | Apache 2.0 |
| Snappy | 1.2.2 | BSD 3-Clause |
| yaml-cpp | 0.9.0 | MIT |

The complete upstream license texts used for packaging are kept in
`installer/ThirdPartyLicenses/` and copied into each distributable application
bundle under `Contents/Resources/ThirdPartyLicenses/`.

## Rime Prelude

- Project: <https://github.com/rime/rime-prelude>
- License: GNU LGPL 3.0
- Included as the `Vendor/rime-prelude` Git submodule.

## Luna Pinyin

- Project: <https://github.com/rime/rime-luna-pinyin>
- License: GNU LGPL 3.0
- Included as the `Vendor/rime-luna-pinyin` Git submodule.

## Rime Essay

- Project: <https://github.com/rime/rime-essay>
- License: GNU LGPL 3.0
- Included as the `Vendor/rime-essay` Git submodule.

The build copies unmodified Rime YAML and dictionary data into the Chinese input-method bundle. See the `LICENSE` and `AUTHORS` files in each submodule for the full terms and attribution.
