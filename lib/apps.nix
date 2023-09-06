{ lib, ... }:
with lib;
let
  appsOpts = [
    ({ name, config, ... }: {
      options = {
        kind = mkOption {
          description = lib.mdDoc "Application kind. `nix` is a nix source application, `helm` is a helm application.";
          type = types.enum [ "nix" "helm" ];
        };
      };
    })
    ({ name, config, ... }: {
      options = {
        source = mkOption {
          description = lib.mdDoc ''
            ArgoCD Application source block for `nix` application kind. Does nothing for helm applications.
            
            If it's not defined, the evaluated application is passed to config.nixAppResolver to resolve the source.
          '';
          default = null;
          type = types.nullOr (types.submodule {
            options = {
              path = mkOption {
                type = types.str;
                default = "";
              };
              repoURL = mkOption {
                type = types.str;
              };
              targetRevision = mkOption {
                type = types.str;
                default = "HEAD";
              };
            };
          });
        };
        release = mkOption {
          description = lib.mdDoc "Helm release details.";
          type = types.nullOr (types.submodule {
            options = {
              chart = mkOption {
                type = types.str;
              };
              repo = mkOption {
                type = types.str;
              };
              version = mkOption {
                type = types.str;
              };
            };
          });
          default = null;
        };
      };
    })
    ({ name, config, ... }: {
      options = {
        createNamespace = mkOption {
          description = lib.mdDoc "If true, a namespace will be automatically created for this application.";
          type = types.bool;
          default = false;
        };
        namespace = mkOption {
          description = lib.mdDoc "The default namespace name for this application.";
          type = types.nullOr types.str;
          default = name;
        };
        namespaces = mkOption {
          description = lib.mdDoc "Any extra namespaces this application should be allowed to access.";
          type = types.listOf types.str;
          default = [ config.namespace ];
        };
        values = mkOption {
          description = lib.mdDoc "Value to pass to the application.";
          type = types.attrsOf types.anything;
          default = { };
        };
        valuesGenerator = mkOption {
          description = lib.mdDoc "A generator function for the values.";
          type = types.nullOr types.raw;
          default = null;
        };
        valuesSchema = mkOption {
          description = lib.mdDoc "Attrset containing the options definitions for the values.";
          type = types.nullOr types.raw;
          default = null;
        };
        ignoreDifferences = mkOption {
          description = lib.mdDoc "Differences to ignore while diffing. See https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/#application-level-configuration.";
          type = types.listOf types.anything;
          default = [ ];
        };
        impure = mkOption {
          description = lib.mdDoc "If true, the nix application will be evaluated as an impure flake.";
          type = types.bool;
          default = false;
        };
      };
    })
  ];
in
{
  options = {
    apps = mkOption {
      default = { };
      type = with types; attrsOf (submodule appsOpts);
    };
  };
}
