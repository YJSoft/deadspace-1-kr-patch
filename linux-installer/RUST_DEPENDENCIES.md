# Linux installer Rust dependencies

The AppImage GUI is based in part on the work of the FLTK project
(https://www.fltk.org) through fltk-rs. Exact versions are locked in
`Cargo.lock`.

Runtime crates use the following declared licenses:

- anyhow, bitflags, block-buffer, cfg-if, cpufeatures, crc32fast,
  crossbeam-channel, crossbeam-utils, crypto-common, digest, libc, once_cell,
  proc-macro2, quote, serde, serde_core, serde_derive, serde_json, sha2, syn,
  ttf-parser, typenum: MIT OR Apache-2.0
- fltk, fltk-sys, generic-array, itoa, md5, memchr, minipaste, shlex,
  version_check, zmij: MIT-compatible or dual MIT/Apache-2.0 terms as declared
  in each crate package
- unicode-ident: (MIT OR Apache-2.0) AND Unicode-3.0
- FLTK native library: GNU Library GPL 2.0 with the FLTK static-linking
  exceptions

The complete package metadata and upstream source URLs can be regenerated
with `cargo metadata --manifest-path linux-installer/Cargo.toml --locked`.
The fltk-rs MIT notice and FLTK exception notice are distributed in
`third_party/licenses` and inside the AppImage.
