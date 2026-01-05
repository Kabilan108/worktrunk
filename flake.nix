{
  description = "Worktrunk CLI flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
    }:
    let
      systemOutputs = flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
          lib = pkgs.lib;
          rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          rustPlatform = pkgs.makeRustPlatform {
            cargo = rustToolchain;
            rustc = rustToolchain;
          };
          cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
          worktrunk = rustPlatform.buildRustPackage {
            pname = "worktrunk";
            version = cargoToml.package.version;
            src = ./.;
            cargoLock = {
              lockFile = ./Cargo.lock;
            };
            doCheck = false;
            nativeBuildInputs = [
              pkgs.makeWrapper
              pkgs.git
            ];
            buildInputs = lib.optionals pkgs.stdenv.isDarwin [ pkgs.libiconv ];

            postInstall = ''
              install -d \
                $out/share/bash-completion/completions \
                $out/share/zsh/site-functions \
                $out/share/fish/vendor_completions.d
              COMPLETE=bash $out/bin/wt > $out/share/bash-completion/completions/wt
              COMPLETE=zsh $out/bin/wt > $out/share/zsh/site-functions/_wt
              COMPLETE=fish $out/bin/wt > $out/share/fish/vendor_completions.d/wt.fish
            '';

            postFixup = ''
              wrapProgram $out/bin/wt --prefix PATH : ${lib.makeBinPath [ pkgs.git ]}
            '';

            meta = with lib; {
              description = "A CLI for Git worktree management, designed for parallel AI agent workflows";
              homepage = "https://worktrunk.dev";
              license = with licenses; [
                mit
                asl20
              ];
              mainProgram = "wt";
            };
          };
        in
        {
          packages = {
            inherit worktrunk;
            default = worktrunk;
          };
          apps.default = {
            type = "app";
            program = "${worktrunk}/bin/wt";
          };
          devShells.default = pkgs.mkShell {
            packages = [
              rustToolchain
              pkgs.git
              pkgs.lychee
              pkgs.cargo-insta
              pkgs.cargo-nextest
            ];
          };
        }
      );
    in
    systemOutputs
    // {
      overlays.default = final: _prev: {
        worktrunk = self.packages.${final.system}.worktrunk;
      };

      homeManagerModules.worktrunk =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.worktrunk;
          tomlFormat = pkgs.formats.toml { };
          defaultSettings = {
            "worktree-path" = "../{{ main_worktree }}.{{ branch | sanitize }}";
          };
        in
        {
          options.programs.worktrunk = {
            enable = lib.mkEnableOption "Worktrunk CLI";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.worktrunk;
              defaultText = "worktrunk package from this flake";
              description = "Worktrunk package to install.";
            };
            settings = lib.mkOption {
              type = tomlFormat.type;
              default = defaultSettings;
              description = "Worktrunk configuration written to the XDG config file.";
            };
            enableBashIntegration = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to enable Bash shell integration.";
            };
            enableZshIntegration = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to enable Zsh shell integration.";
            };
            enableFishIntegration = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to enable Fish shell integration.";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];
            xdg.configFile."worktrunk/config.toml".source =
              tomlFormat.generate "worktrunk-config.toml" cfg.settings;

            programs.bash.initExtra = lib.mkIf cfg.enableBashIntegration ''
              if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init bash)"; fi
            '';

            programs.zsh.initExtra = lib.mkIf cfg.enableZshIntegration ''
              if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi
            '';

            programs.fish.interactiveShellInit = lib.mkIf cfg.enableFishIntegration ''
              if type -q wt; command wt config shell init fish | source; end
            '';
          };
        };

    };
}
