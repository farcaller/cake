{ config, lib, pkgs, ... }:
with lib;
let
  metadataOpts = { name, config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
      };
      namespace = mkOption {
        type = types.str;
      };
      labels = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
    };
  };
  applicationResourcesOpts = { name, config, ... }: {
    options = {
      apiVersion = mkOption {
        type = types.str;
        default = "argoproj.io/v1alpha1";
      };
      kind = mkOption {
        type = types.str;
        default = "Application";
      };
      metadata = mkOption {
        default = { };
        type = types.submodule metadataOpts;
      };
      spec = mkOption {
        type = types.attrsOf types.anything;
        default = { };
      };
    };
  };

  appProjectResourcesOpts = { name, config, ... }: {
    options = {
      apiVersion = mkOption {
        type = types.str;
        default = "argoproj.io/v1alpha1";
      };
      kind = mkOption {
        type = types.str;
        default = "AppProject";
      };
      metadata = mkOption {
        default = { };
        type = types.submodule metadataOpts;
      };
      spec = mkOption {
        type = types.attrsOf types.anything;
        default = { };
      };
    };
  };

  resourcesOpts = { name, config, ... }: {
    options = {
      applications = mkOption {
        default = { };
        type = with types; attrsOf (submodule applicationResourcesOpts);
      };
      appProjects = mkOption {
        default = { };
        type = with types; attrsOf (submodule appProjectResourcesOpts);
      };
    };
  };
in
{
  options = {
    nixAppResolver = mkOption {
      default = null;
      type = types.nullOr types.raw;
    };
    resources = mkOption {
      default = { };
      type = types.submodule resourcesOpts;
    };
  };

  config =
    let
      inherit (builtins) attrNames attrValues;
      clusterNames = attrNames config.clusters;

      mkPerClusterApps = cluster:
        let
          clusterApps = lib.filterAttrs (name: value: value.enable == true) config.clusters.${cluster}.apps;
          mkSingleApp = name: appSpec:
            let
              baseAppSpec = config.apps.${appSpec.app};
              syncOptions =
                [ "ServerSideApply=true" ]
                ++ (if appSpec.createNamespace then [ "CreateNamespace=true" ] else [ ]);
              projectName = if (builtins.length appSpec.namespaces) == 1 then "${cluster}-${appSpec.namespace}" else "${cluster}-app-${name}";

              mergedSpec = lib.recursiveUpdate (lib.recursiveUpdate { } baseAppSpec) appSpec;

              source =
                let
                  needsValues = ((attrNames appSpec.values) != [ ] || baseAppSpec.valuesGenerator != null);
                  isImpure = baseAppSpec.impure == true;
                  resolvedValues = lib.recursiveUpdate baseAppSpec.values appSpec.values;
                  finalValues =
                    if baseAppSpec.valuesGenerator != null
                    then
                      baseAppSpec.valuesGenerator
                        {
                          clusterName = cluster;
                          cluster = config.clusters.${cluster};
                          values = resolvedValues;
                          inherit config;
                        }
                    else resolvedValues;
                in
                if baseAppSpec.kind == "nix"
                then
                  let
                    params = [ ]
                      ++ (if needsValues then [{ name = "values"; string = builtins.readFile ((pkgs.formats.json { }).generate "values.json" finalValues); }] else [ ])
                      ++ (if isImpure then [{ name = "impure"; string = "true"; }] else [ ]);
                    baseSource =
                      if baseAppSpec.source != null
                      then baseAppSpec.source
                      else
                        assert lib.assertMsg (config.nixAppResolver != null) "nixAppResolver is null, but no source defined for ${name}";
                        config.nixAppResolver {
                          inherit name appSpec baseAppSpec;
                        };
                  in
                  lib.recursiveUpdate
                    baseSource
                    (lib.optionalAttrs (builtins.length params > 0) {
                      plugin. parameters = params;
                    })
                else
                  (lib.recursiveUpdate
                    {
                      chart = appSpec.release.chart;
                      repoURL = appSpec.release.repo;
                      targetRevision = appSpec.release.version;
                      helm.releaseName = name;
                    }
                    (lib.optionalAttrs needsValues {
                      helm.values = builtins.readFile ((pkgs.formats.yaml { }).generate "values.yaml" finalValues);
                    }
                    ));
            in
            assert lib.assertMsg
              (
                (baseAppSpec.kind == "helm" && appSpec.release != null && appSpec.source == null)
                || (baseAppSpec.kind != "helm" && appSpec.release == null)
              ) "apps.${name} must have a release set iff it's a helm app";
            {
              metadata.name = "${cluster}-${name}";
              metadata.namespace = "argocd";
              metadata.labels.cluster = cluster;
              metadata.labels.environment = config.clusters.${cluster}.environment;
              spec = (lib.recursiveUpdate
                {
                  inherit source;
                  destination = {
                    name = cluster;
                    namespace = appSpec.namespace;
                  };
                  project = projectName;
                  syncPolicy = { inherit syncOptions; };
                }
                (lib.optionalAttrs ((builtins.length mergedSpec.ignoreDifferences) > 0) {
                  inherit (mergedSpec) ignoreDifferences;
                }
                ));
            };
        in
        lib.pipe clusterApps [
          (builtins.mapAttrs (name: value: {
            name = "${cluster}/${name}";
            value = mkSingleApp name value;
          }))
          attrValues
          builtins.listToAttrs
        ];

      mkPerClusterAppProjects = cluster:
        let
          clusterApps = lib.filterAttrs (name: value: value.enable == true) config.clusters.${cluster}.apps;

          allProjects = builtins.mapAttrs
            (name: appSpec:
              let
                projectName = if (builtins.length appSpec.namespaces) == 1 then "${cluster}-${appSpec.namespace}" else "${cluster}-app-${name}";
              in
              {
                name = projectName;
                value = { inherit appSpec; inherit cluster; };
              });

          mkSingleAppProject = (name: { appSpec, cluster, ... }:
            {
              metadata.name = name;
              metadata.namespace = "argocd";
              metadata.labels.cluster = cluster;
              spec = {
                clusterResourceWhitelist = [{ group = "*"; kind = "*"; }];
                destinations = (map (namespace: { name = cluster; inherit namespace; }) appSpec.namespaces);
                orphanedResources.ignore = [ ];
                orphanedResources.warn = true;
                sourceRepos = [ "*" ];
              };
            });
        in
        lib.pipe clusterApps [
          allProjects
          builtins.attrValues
          builtins.listToAttrs
          (builtins.mapAttrs (name: value: { name = "${cluster}/${name}"; value = mkSingleAppProject name value; }))
          attrValues
          builtins.listToAttrs
        ];
    in
    {
      resources.applications = builtins.foldl' (acc: name: acc // (mkPerClusterApps name)) { } clusterNames;
      resources.appProjects = builtins.foldl' (acc: name: acc // (mkPerClusterAppProjects name)) { } clusterNames;
    };
}
