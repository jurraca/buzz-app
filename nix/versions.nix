{
  # Vendored cargo dependencies for the buzz-app workspace (root Cargo.lock).
  # Regenerate after Cargo.lock changes by replacing the hash with
  # lib.fakeHash in nix/buzz-app.nix and building the affected package.
  cargoHash = "sha256-yYpqaWYUHZa61tdoyEU0P7OHbVrcR50X/PAA/+lHzBI=";

  # pnpm store for the frontend (pnpm-lock.yaml, lockfile v9, fetcherVersion 4).
  # Regenerate after package.json / pnpm-lock.yaml changes the same way.
  pnpmHash = "sha256-Y1iFdum87ALHYnpHqkaCjPoNWx6K1u8a2BlUrZgtI4Y=";

  # fetchFromGitHub hash for the pinned block/buzz revision that
  # scripts/build-buzz-cli.mjs builds the bundled `buzz` CLI from (the
  # buzz-audio-client git rev in src-tauri/Cargo.toml).
  buzzCliSrcHash = "sha256-609SAjEWOGMVj33K7Ay/azjlafiscopIpLtSO1soNfk=";

  # Vendored cargo dependencies for that pinned block/buzz checkout.
  buzzCliCargoHash = "sha256-pYCis8LXLUKU3iPaUkeR/hH3XmBljCjVZQ7EDD2cqrs=";
}
