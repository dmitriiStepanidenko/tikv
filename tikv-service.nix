# Inspired by: https://twey.io/nix-patterns/inputs-and-outputs/#user-defined-instances
# tikv-service.nix
{
  config,
  lib,
  tikvPackage,
  craneLib,
  pkgs,
  ...
}: let
  toml = pkgs.formats.toml {};
in {
  options.services.tikv = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({
      name,
      config,
      ...
    }: {
      options = {
        enable = lib.mkEnableOption "TiKV service";

        addr = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1:20160";
          description = "The address that the TiKV server monitors";
        };

        advertiseAddr = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "The server advertise address for client traffic from outside";
        };

        statusAddr = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1:20180";
          description = "The port through which the TiKV service status is listened";
        };

        advertiseStatusAddr = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "The address through which TiKV accesses service status from outside";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/tikv/${name}";
          description = "The path to the data directory";
        };

        capacity = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "The store capacity";
        };

        logLevel = lib.mkOption {
          type = lib.types.str;
          default = "info";
          description = "The log level";
        };

        logFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "The log file";
        };

        pd = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "The address list of PD servers";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "tikv-${name}";
          description = "User under which TiKV service runs";
        };

        config = lib.mkOption {
          type = lib.types.nullOr toml.type;
          default = null;
          description = "Config file parameters";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "tikv-${name}";
          description = "Group under which TiKV service runs";
        };
      };
    }));
    default = {};
    description = "TiKV service instances";
  };

  config = let
    enabledInstances = lib.filterAttrs (name: cfg: cfg.enable) config.services.tikv;
  in
    lib.mkIf (enabledInstances != {}) {
      systemd.services =
        lib.mapAttrs' (
          name: cfg: let
            configFile =
              if cfg.config != null
              then craneLib.writeTOML "tikv-${name}.toml" cfg.config
              else null;
          in
            lib.nameValuePair "tikv-${name}" {
              description = "TiKV Distributed Key-Value Database (${name})";
              after = ["network.target"];
              wantedBy = ["multi-user.target"];

              serviceConfig = {
                Type = "simple";
                ExecStart = lib.concatStringsSep " " ([
                    "${tikvPackage}/bin/tikv-server"
                    "--addr"
                    cfg.addr
                    "--status-addr"
                    cfg.statusAddr
                    "--data-dir"
                    cfg.dataDir
                    "-L"
                    cfg.logLevel
                  ]
                  ++ lib.optional (cfg.advertiseAddr != null) "--advertise-addr ${cfg.advertiseAddr}"
                  ++ lib.optional (cfg.advertiseStatusAddr != null) "--advertise-status-addr ${cfg.advertiseStatusAddr}"
                  ++ lib.optional (cfg.capacity != null) "--capacity ${cfg.capacity}"
                  ++ lib.optional (cfg.logFile != null) "--log-file ${cfg.logFile}"
                  ++ lib.optional (cfg.pd != []) "--pd ${lib.concatStringsSep "," cfg.pd}"
                  ++ lib.optional (configFile != null) "--config ${configFile}");

                Restart = "on-failure";
                RestartSec = "10s";
                User = cfg.user;
                Group = cfg.group;
                RuntimeDirectory = "tikv-${name}";
                StateDirectory = "tikv-${name}";
              };

              environment = {
                RUST_BACKTRACE = "full";
              };
            }
        )
        enabledInstances;

      users.users =
        lib.mapAttrs' (
          name: cfg:
            lib.nameValuePair "tikv-${name}" {
              isSystemUser = true;
              group = cfg.group;
              home = cfg.dataDir;
              createHome = true;
            }
        )
        enabledInstances;

      users.groups =
        lib.mapAttrs' (
          name: cfg:
            lib.nameValuePair "tikv-${name}" {}
        )
        enabledInstances;
    };
}
