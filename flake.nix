{
  description = "Linquebot's nix flake";

  nixConfig = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://beiyanyunyi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "beiyanyunyi.cachix.org-1:iCC1rwPPRGilc/0OS7Im2mP6karfpptTCnqn9sPtwls="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crate2nix = {
      url = "github:nix-community/crate2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      rust-overlay,
      crate2nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [
          (import rust-overlay)
        ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        buildRustCrateForPkgs =
          crate:
          pkgs.buildRustCrate.override {
            rustc = (pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.minimal));
            cargo = (pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.minimal));
          };
        generatedCargoNix = crate2nix.tools.${system}.generatedCargoNix {
          name = "rustNix";
          src = ./.;
        };
        cargoNix = import generatedCargoNix {
          inherit pkgs buildRustCrateForPkgs;
        };
      in
      rec {
        devShells.default =
          with pkgs;
          mkShell {
            buildInputs = [
              openssl
              graphviz
              (rust-bin.selectLatestNightlyWith (
                toolchain:
                toolchain.default.override {
                  extensions = [ "rust-src" ];
                }
              ))
            ];
          };
        packages.default =
          with pkgs;
          cargoNix.rootCrate.build.overrideAttrs (
            final: prev: {
              buildInputs = prev.buildInputs ++ [ openssl ];
              nativeBuildInputs = prev.nativeBuildInputs ++ [ makeWrapper ];
              postInstall = ''
                wrapProgram $out/bin/linquebot_rs --prefix PATH : ${lib.makeBinPath [ graphviz ]}
              '';
              meta.mainProgram = "linquebot_rs";
            }
          );
        packages.dockerSupports =
          with pkgs;
          let
            fonts-conf = makeFontsConf {
              fontDirectories = [
                twemoji-color-font
                noto-fonts-cjk-sans
                noto-fonts
              ];
            };
          in
          stdenvNoCC.mkDerivation {
            name = "linquebot_rs-docker-supports";
            dontUnpack = true;
            buildInputs = [
              fontconfig
            ];
            installPhase = ''
              runHook preInstall
              mkdir -p $out/etc/fonts/conf.d $out/var
              mkdir -m 1777 $out/tmp
              cp ${fonts-conf} $out/etc/fonts/conf.d/99-nix.conf
              runHook postInstall
            '';
          };
        packages.dockerImage =
          with pkgs;
          dockerTools.buildLayeredImage {
            name = "ghcr.io/lhcfl/linquebot_rs";
            tag = "latest";
            contents = [
              # coreutils
              dockerTools.caCertificates
              dockerTools.usrBinEnv
              # dockerTools.binSh
              # strace
              packages.dockerSupports
            ];
            config = {
              Cmd = [
                "${lib.meta.getExe packages.default}"
              ];
              WorkingDir = "/app";
            };
            created = "now";
          };
      }
    );
}
