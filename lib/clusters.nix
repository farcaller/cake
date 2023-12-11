{ config, lib, ... }:
with lib;
let
  topLevelConfig = config;

  clusterAppsOpts = [
    ({ name, config, ... }: {
      options = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        app = mkOption {
          type = types.str;
          default = name;
        };
      };
    })
    ({ name, config, ... }: {
      options =
        let
          baseAppName = if config.app == null then name else config.app;
          baseApp = topLevelConfig.apps.${baseAppName};
        in
        {
          release = mkOption {
            type = types.nullOr (types.attrsOf types.anything);
            default = baseApp.release;
          };
          values = mkOption {
            type =
              if baseApp.valuesSchema != null
              then types.submodule ({ ... }: { options = baseApp.valuesSchema; })
              else types.attrsOf types.anything;
            default = baseApp.values;
          };
          createNamespace = mkOption {
            type = types.bool;
            default = baseApp.createNamespace;
          };
          namespace = mkOption {
            type = types.nullOr types.str;
            default = baseApp.namespace;
          };
          namespaces = mkOption {
            type = types.listOf types.str;
            default = baseApp.namespaces;
          };
        };
    })
  ];

  clusterOpts = { name, config, ... }: {
    options = {
      apps = mkOption {
        default = { };
        type = types.attrsOf (types.submodule clusterAppsOpts);
      };
      environment = mkOption {
        type = types.str;
      };
      _resources = mkOption {
        default = { };
        type = types.attrsOf types.anything;
      };
    };
  };
in
{
  options = {
    clusterImports = mkOption {
      default = [];
      type = types.listOf types.path;
    };

    clusters = mkOption {
      default = { };
      type = with types; attrsOf (submodule ([ clusterOpts ] ++ (map import config.clusterImports)));
    };
  };

  config = {
    resources = builtins.foldl'
      (acc: clusterConfig: lib.recursiveUpdate acc clusterConfig._resources)
      { }
      (builtins.attrValues config.clusters);
  };
}
